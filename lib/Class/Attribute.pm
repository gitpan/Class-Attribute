package Class::Attribute;

use warnings;
use strict;

use Carp;
use Scalar::Util qw(blessed);
use List::Util   qw(first);

our $METHOD_DELIM = '_';

use constant ATTR_RW        => 'rw';
use constant ATTR_RO        => 'ro';
use constant ATTR_PROTECTED => 'pr';
use constant ATTR_PRIVATE   => 'pv';
use constant ATTR_META      => 'mt';

=head1 NAME

Class::Attribute - Another way to define class attributes!!!

=head1 VERSION

Version 0.022

=cut

our $VERSION = '0.022';

require XSLoader;
XSLoader::load('Class::Attribute', $VERSION);

=head1 SYNOPSIS

This is a very light weight and fast implementation for defining
attributes without having to resort to full blown use of Moose.

The module tries to fill in gaps found in several other similar implementations
found on CPAN; Class::Accessor, Class::InsideOut, Object::InsideOut, Moose and Mouse.

Class::Attribute,

1. Allows definition of attributes of the following type/permissions.
    a. public
    b. private
    c. protected
    d. readonly
    e. meta

2. Has a very simple and extensible attribute validation mechanism using
   regular expressions.

3. Can set default values for attributes.

and thats it.


    # example

    package MyUser;

    use DateTime;
    use YAML;
    # exports symbols into the MyUser namespace and then
    # pushes itself into @MyUser::ISA.
    use Class::Attribute;

    attribute 'id',      is_int, protected, default => 1;
    attribute 'name',    is_string(10, 40, 'a name of 10 - 40 chars');
    attribute 'sex',     is_in( ['M', 'F'], 'sex (M/F)' ), private;
    attribute 'age',     is_int, default => 18;
    attribute 'email',   is_email, predicate => 'has_email';
    attribute 'dob',     is_date;
    attribute 'updated', isa => 'DateTime', default => sub { DateTime->now };

    sub new {
        my $self = shift->SUPER::new(@_);
        my %args = @_;
        $self->set_sex($args{sex}) if exists $args{sex};

        return $self;
    }

    sub serialize {
        my ($self) = @_;
        if ($self->is_updated) {
            $self->set_id(time) unless defined $self->get_id;
            $self->set_updated(DateTime->now);
            my %attrs = $self->_get_all_attributes;
            return Dump(\%attrs);
        }
    }

    1;

    # and now in your script ...

    use MyUser;
    my $user = MyUser->new(sex => 'M');

    # should return FALSE.
    print $user->has_email;

    $user->set_name('foo bar baz');
    $user->set_email('foo@bar.com');

    # should return TRUE.
    print $user->has_email;

    # should return 18.
    print $user->get_age, "\n";

    $user->set_age('2008-123-1');
    # returns validation errors.
    my @errors = $user->validate;

    # should throw a permission error.
    $user->set_id(1);

    # should serialize the fields including ones set by default.
    print $user->serialize, "\n";


=head1 EXPORT

attribute, public, private, protected, readonly, meta, is_int, is_float, is_email,
is_boolean, is_string, is_date, is_datetime, is_in

=head1 FUNCTIONS


=head2 import

This is where all the initial compile time work happens. All this does is pushes some of the useful symbols to the
caller namespace. Read EXPORT section for the list of exported symbols.

=cut

sub import {
    my $class = caller;

    no warnings 'redefine';
    no strict 'refs';
    for my $func qw(
        attribute
        readonly public private protected meta
        is_int is_float
        is_email is_boolean
        is_string is_in
        is_date is_datetime
    ) {
        *{"$class:\:$func"} = *$func;
    }

    # avoid repeated inheritence and re-using slots.
    if (!first { $_ eq __PACKAGE__ } @{"$class:\:ISA"}) {
        push @{"$class:\:ISA"}, __PACKAGE__;
        $class->_init_class_config;
    }
}

=head2 new

The default constructor. It calls _new() which sets the default values and
returns a blessed reference. Override this in your class if you want the
constructor to do more with the provided arguments like setting protected
attributes etc.

=cut

sub new {
    my ($class, %attrs) = @_;
    my $self = $class->_new;
    return $self;
}

=head2 _new

Sets the default values as defined.

=cut

sub _new {
    my ($class, %args) = @_;

    my $self = bless [], $class;
    my $defaults = $class->_defaults;
    for my $attr (keys %$defaults) {
        my $value = $defaults->{$attr};
        $value = &$value() if ref $value eq 'CODE';
        no strict 'refs'; my $mutator = "set_$attr";
        $self->$mutator($value);
    }
    return $self;
}

=head2 attr

Same as attribute(), read below.

=cut

=head2 attribute

This basically does the grunt work of parsing the attribute definitions, defaults etc
and setting up appropriate methods in the caller namespace.

The possible attribute definitions are explained below.

1. Attribute Permission - public (default), private, protected, readonly or meta.

 # e.g.  attribute 'id1', public;
 # e.g.  attribute 'id2', private;
 # e.g.  attribute 'id3', protected;
 # e.g.  attribute 'id4', readonly;
 # e.g.  attribute 'id4', meta;


I<CAVEATS>

The following matrix illustrates the types of accessors and mutators that
will be created given the attribute type/permission.

            |    accessor    |    mutator
 -----------|----------------|--------------
 public     |    public      |    pubic
 private    |    public      |    private
 protected  |    public      |    protected
 readonly   |    public      |    N/A
 meta       |    protected   |    protected

The readonly attribute definition will result in no accessor being created.
The meta attribute has only a private accessor and mutator.

2. Attribute ISA - Checks the value in the validator if it is an instance of a particular class.

 # e.g.  attribute 'dob', public, isa => 'DateTime';

3. Attribute Default - Any scalar value or CODEREF that will be assigned by default in the constructor.

 # e.g.  attribute 'age', public, default => 18;

4. Attribute Validation - A reference to an array with 2 elements. The first one should be
a regular expression and the second an explanation what the validation does.

 # e.g.  attribute 'dob', public, like => [qr/^\d{4}-\d\d-\d\d$/, 'a date of the form YYYY-MM-DD'];

The following validators are exported as functions into the caller namespace.

 is_int, is_float, is_boolean, is_email, is_string, is_in, is_date, is_datetime

5. Attribute Predicate - A method name that is created to check if the attribute value
has been set or instantiated.

 # e.g.  attribute 'email', public, predicate => 'has_email';

=cut

sub attribute {
    my $class = caller;

    my $name  = shift @_;
    my %attrs = @_;

    my $perm      = delete $attrs{perms} || ATTR_RW;
    my $validates = delete $attrs{like};
    my $default   = delete $attrs{default};
    my $isa       = delete $attrs{isa};
    my $predicate = delete $attrs{predicate};

    no warnings 'redefine';
    no strict 'refs';

    if (defined $default) {
        $class->_defaults->{$name} = $default;
    }

    ## inspired by Class::Accessor::Faster
    my $slot_count = $class->_slot_count;
    $slot_count->{value} ||= 0;

    my $slot = $slot_count->{value}++;
    $class->_slots->{$name} = $slot;

    my $package = __PACKAGE__;
    # meta types default to private accessors.

    if ($perm eq ATTR_META) {
        __PACKAGE__->_make_protected_accessor("$class\::get$METHOD_DELIM$name", $slot);
        __PACKAGE__->_make_protected_mutator ("$class\::set$METHOD_DELIM$name", $slot);
    }
    elsif ($perm eq ATTR_PROTECTED) {
        __PACKAGE__->_make_accessor("$class\::get$METHOD_DELIM$name", $slot);
        __PACKAGE__->_make_protected_mutator ("$class\::set$METHOD_DELIM$name", $slot);
    }
    elsif ($perm eq ATTR_PRIVATE) {
        __PACKAGE__->_make_accessor("$class\::get$METHOD_DELIM$name", $slot);
        __PACKAGE__->_make_private_mutator ("$class\::set$METHOD_DELIM$name", $slot);
    }
    elsif ($perm eq ATTR_RO) {
        __PACKAGE__->_make_accessor("$class\::get$METHOD_DELIM$name", $slot);
    }
    elsif ($perm eq ATTR_RW) {
        __PACKAGE__->_make_accessor("$class\::get$METHOD_DELIM$name", $slot);
        __PACKAGE__->_make_mutator ("$class\::set$METHOD_DELIM$name", $slot);
    }

    if ($predicate) {
        *{"$class\::$predicate"} = eval "sub { !!shift->get$METHOD_DELIM$name }";
        croak $@ if $@;
    }

    if ($isa) {
        $class->_validator->{$name} = $isa;
    }
    elsif ($validates) {
        $class->_validator->{$name} = $validates;
    }
}

# TODO XSify this.
sub _make_protected_accessor {
    my ($class, $method, $slot) = @_;

    (my $realmethod = rand()) =~ s/\./_/;
    $realmethod = $method . $realmethod;
    $class->_make_accessor($realmethod, $slot);

    no strict 'refs';
    *$method = sub {
        my ($self) = @_;
        my ($caller, $subroutine) = (caller(0))[0, 3];
        (my $class) = $subroutine =~ m/^(.*)::/;

        if ($caller eq $class or $caller eq __PACKAGE__ or $caller->isa($class)) {
            goto &$realmethod;
        }
        else {
            croak("Called a protected accessor $method");
        }
    };
}

# TODO XSify this.
sub _make_private_accessor {
    my ($class, $method, $slot) = @_;

    (my $realmethod = rand()) =~ s/\./_/;
    $realmethod = $method . $realmethod;
    $class->_make_accessor($realmethod, $slot);

    no strict 'refs';
    *$method = sub {
        my ($self) = @_;
        my ($caller, $subroutine) = (caller(0))[0, 3];
        (my $class) = $subroutine =~ m/^(.*)::/;

        if ($caller eq $class or $caller eq __PACKAGE__) {
            goto &$realmethod;
        }
        else {
            croak("Called a private accessor $method");
        }
    };
}

# TODO XSify this.
sub _make_protected_mutator {
    my ($class, $method, $slot) = @_;

    (my $realmethod = rand()) =~ s/\./_/;
    $realmethod = $method . $realmethod;
    $class->_make_mutator($realmethod, $slot);

    no strict 'refs';
    *$method = sub {
        my ($self, $value) = @_;
        my ($caller, $subroutine) = (caller(0))[0, 3];
        (my $class) = $subroutine =~ m/^(.*)::/;

        if ($caller eq $class or $caller eq __PACKAGE__ or $caller->isa($class)) {
            goto &$realmethod;
        }
        else {
            croak("Called a protected mutator $method");
        }
    };
}

# TODO XSify this.
sub _make_private_mutator {
    my ($class, $method, $slot) = @_;

    (my $realmethod = rand()) =~ s/\./_/;
    $realmethod = $method . $realmethod;
    $class->_make_mutator($realmethod, $slot);

    no strict 'refs';
    *$method = sub {
        my ($self, $value) = @_;
        my ($caller, $subroutine) = (caller(0))[0, 3];
        (my $class) = $subroutine =~ m/^(.*)::/;

        if ($caller eq $class or $caller eq __PACKAGE__) {
            goto &$realmethod;
        }
        else {
            croak("Called a private mutator $method");
        }
    };
}

=head2 validate

validates the attributes against any specified validators and returns
failures if any.

=cut

sub validate {
    my ($self) = @_;
    my $class = ref $self;
    my @errors;

    for my $attr (keys %{$class->_slots}) {
        my $validator = $class->_validator->{$attr};
        my $value = $self->[$class->_slots->{$attr}];
        next unless $validator && defined $value;
        if (ref $validator) {
            if($value !~ m/$validator->[0]/) {
                push @errors, sprintf '%s = %s is not %s',
                    $attr, $value, $validator->[1];
            }
        }
        elsif (!blessed($value) || !$value->isa($validator)) {
            push @errors, sprintf '%s = %s is not %s',
                $attr, $value, $validator->[1];
        }
    }

    return @errors;
}

sub _init_class_config {
    croak 'Cannot access private method _init_class_config' unless caller eq __PACKAGE__;
    my ($class) = @_;
    _define_config_attribute($class, $_) for qw(_slots _slot_count _defaults _validator);
}

sub _define_config_attribute {
    croak 'Cannot access private method _define_config_attribute' unless caller eq __PACKAGE__;
    my ($class, $var) = @_;

    no strict 'refs';
    ${"$class\::$var"} ||= {};
    *{"$class\::$var"} = sub {
        no strict 'refs'; ${"$class\::$var"}
    };
    return ${"$class\::$var"};
}

=head2 _get_all_attributes

This is a private method that returns a hash of attribute names and their values.

=cut

sub _get_all_attributes {
    my ($self) = @_;
    croak 'Cannot call private method _get_all_attributes'
        unless caller eq ref $self or caller eq __PACKAGE__;

    my %slotmap = %{$self->_slots};
    return map { $_ => $self->[$slotmap{$_}] } keys %slotmap;
}


# some constants and default validators.

use constant readonly  =>  'perms' , ATTR_RO;
use constant public    =>  'perms' , ATTR_RW;
use constant protected =>  'perms' , ATTR_PROTECTED;
use constant private   =>  'perms' , ATTR_PRIVATE;
use constant meta      =>  'perms' , ATTR_META;

# numeric
use constant INT       => qr/^\d+$/;
use constant FLOAT     => qr/^\d+(?:.\d+)?$/;

# subset of RFC2822.
use constant EMAIL     =>
        qr/^
            \w+[\w\-+!]*@
            (?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+
            (?:[A-Z]{2}|com|org|net|gov|mil|biz|info|mobi|name|aero|jobs|museum)
        $/xoi;

use constant BOOLEAN   => qr/^[01]$/;

use constant DATE      => qr/^\d{4}-\d{1,2}-\d{1,2}$/;
use constant DATETIME  => qr/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/;

# simple validator defaults.
use constant is_int      => 'like', [INT,      'an Integer'       ];
use constant is_float    => 'like', [FLOAT,    'a Float'          ];
use constant is_email    => 'like', [EMAIL,    'an Email Address' ];
use constant is_boolean  => 'like', [BOOLEAN,  'a Boolean Value'  ];
use constant is_date     => 'like', [DATE,     'a date'           ];
use constant is_datetime => 'like', [DATETIME, 'a datetime value' ];

=head2 is_string($min_len, $max_len, $comment)

A validator that accepts 3 arguments (min length, max length, comment)
and returns a hash that Class::Attribute likes. All parameters are optional.

=cut

sub is_string {
    my ($min, $max, $comment) = @_;
    $min ||= 0;
    $max ||= '';
    $comment ||= "a string of length > $min chars";
    my $regex = qr/^.{$min,$max}/;
    return 'like', [ $regex, $comment ];
}

=head2 is_in($list_ref, $comment)

A validator that checks if an attribute is an element of a provided
set of values.

=cut

sub is_in {
    my ($list, $comment) = @_;
    croak "Argument 1 to is_in() should be a non-empty ARRAYREF"
        unless (ref $list || '') eq 'ARRAY' && @$list;
    $comment ||= 'one of ' . join ',', @$list;
    my $elements = join '|', @$list;
    my $regex = qr/^(?:$elements)$/;
    return 'like', [ $regex, $comment ];
}

=head1 AUTHOR

Bharanee Rathna, C<< <deepfryed a la gmail> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-class-attribute at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-Attribute>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Class::Attribute


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Class-Attribute>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Class-Attribute>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Class-Attribute>

=item * Search CPAN

L<http://search.cpan.org/dist/Class-Attribute>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to Class::Accessor for all the pain it's saved me from in the past.
Thanks to Moose for doing what should have been in Perl CORE looooooong back.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Bharanee Rathna, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Class::Attribute
