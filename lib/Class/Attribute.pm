package Class::Attribute;

use warnings;
use strict;

use Carp;
use Scalar::Util qw(blessed);
use List::Util   qw(first);

our $METHOD_DELIM = '_';

use constant ATTR_PUBLIC    => 'pu';
use constant ATTR_PROTECTED => 'pr';
use constant ATTR_PRIVATE   => 'pv';

our %owner;

=head1 NAME

Class::Attribute - A fast and light weight alternative for defining class attributes.

=head1 VERSION

Version 0.025

=cut

our $VERSION = '0.025';

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

2. Has a very simple and extensible attribute validation mechanism using
   regular expressions.

3. Can set default values for attributes.


    # example

    package MyUser;

    use DateTime;
    use YAML;
    # exports symbols into the MyUser namespace and then
    # pushes itself into @MyUser::ISA.
    use Class::Attribute;

    attribute 'id',      is_int, protected, public_accessor, default => 1;
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

attribute, public, private, protected, readonly, public_accessor, protected_accessor, private_accessor, public_mutator, protected_mutator, private_mutator, is_int, is_float, is_email, is_boolean, is_string, is_date, is_datetime, is_in

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
        readonly public private protected
        public_accessor protected_accessor private_accessor
        public_mutator protected_mutator private_mutator
        is_int is_float
        is_email is_boolean
        is_string is_in
        is_date is_datetime
    ) {
        *{"$class:\:$func"} = *$func;
    }

    # avoid repeated inheritence and re-using slots.
    if (!$class->can('_init_class_config')) {
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
    my $slots = $class->_slots;
    for my $attr (keys %$defaults) {
        my $value = $defaults->{$attr};
        $value = &$value() if ref $value eq 'CODE';
        $self->[$slots->{$attr}] = $value;
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

1. Attribute Permission. This can be defined for accessors and mutators as I<public (default), private, protected or readonly> or for finer grain control separately as I<public_accessor, public_mutator, protected_accessor, protected_mutator, private_accessor or private_mutator>.

 # e.g.  attribute 'id1', public;
 # e.g.  attribute 'id2', private, protected_accessor;
 # e.g.  attribute 'id3', protected;
 # e.g.  attribute 'id4', readonly;


I<CAVEATS>

The readonly attribute definition will result in a public accessor and private mutator.

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

    my ($perm_read, $perm_write) = delete @attrs{qw(perm_read perm_write)};
    if (!$perm_read && !$perm_write) {
        $perm_read  = ATTR_PUBLIC;
        $perm_write = ATTR_PUBLIC;
    }

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
    if ($perm_read) {
        if ($perm_read eq ATTR_PUBLIC) {
            __PACKAGE__->_make_accessor("$class\::get$METHOD_DELIM$name", $slot);
        }
        elsif ($perm_read eq ATTR_PROTECTED) {
            __PACKAGE__->_make_protected_accessor("$class\::get$METHOD_DELIM$name", $slot);
        }
        else {
            $owner{$class}{$slot} = $name;
            $class->_method_owner->[$slot][0] = "$class\::get$METHOD_DELIM$name";
            __PACKAGE__->_make_private_accessor("$class\::get$METHOD_DELIM$name", $slot);
        }
    }

    if ($perm_write) {
        if ($perm_write eq ATTR_PUBLIC) {
            __PACKAGE__->_make_mutator ("$class\::set$METHOD_DELIM$name", $slot);
        }
        elsif ($perm_write eq ATTR_PROTECTED) {
            __PACKAGE__->_make_protected_mutator ("$class\::set$METHOD_DELIM$name", $slot);
        }
        else {
            $owner{$class}{$slot} = $name;
            $class->_method_owner->[$slot][1] = "$class\::set$METHOD_DELIM$name";
            __PACKAGE__->_make_private_mutator ("$class\::set$METHOD_DELIM$name", $slot);
        }
    }

    if ($predicate) {
        __PACKAGE__->_make_predicate("$class\::$predicate", $slot);
    }

    if ($isa) {
        $class->_validator->{$name} = $isa;
    }
    elsif ($validates) {
        $class->_validator->{$name} = $validates;
    }
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
    _define_hash_variable($class, $_) for qw(_slots _slot_count _defaults _validator);
    _define_array_variable($class, $_) for qw(_method_owner);
}

sub _define_hash_variable {
    croak 'Cannot access private method _define_hash_variable' unless caller eq __PACKAGE__;
    my ($class, $var) = @_;

    no strict 'refs';
    ${"$class\::$var"} ||= {};
    *{"$class\::$var"} = sub {
        no strict 'refs'; ${"$class\::$var"}
    };
    return ${"$class\::$var"};
}

sub _define_array_variable {
    croak 'Cannot access private method _define_array_variable' unless caller eq __PACKAGE__;
    my ($class, $var) = @_;

    no strict 'refs';
    ${"$class\::$var"} ||= [];
    *{"$class\::$var"} = sub {
        no strict 'refs';
        if (@_ == 2) {
            return ${"$class\::$var"}->[$_[1]];
        }
        if (@_ == 3) {
            return ${"$class\::$var"}->[$_[1]]->[$_[2]];
        }
        else {
            return ${"$class\::$var"};
        }
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
use constant readonly  =>  perm_read => ATTR_PUBLIC,    perm_write => ATTR_PRIVATE;
use constant public    =>  perm_read => ATTR_PUBLIC,    perm_write => ATTR_PUBLIC;
use constant protected =>  perm_read => ATTR_PROTECTED, perm_write => ATTR_PROTECTED;
use constant private   =>  perm_read => ATTR_PRIVATE,   perm_write => ATTR_PRIVATE;

use constant public_accessor    => perm_read => ATTR_PUBLIC;
use constant protected_accessor => perm_read => ATTR_PROTECTED;
use constant private_accessor   => perm_read => ATTR_PRIVATE;

use constant public_mutator     => perm_write => ATTR_PUBLIC;
use constant protected_mutator  => perm_write => ATTR_PROTECTED;
use constant private_mutator    => perm_write => ATTR_PRIVATE;


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
