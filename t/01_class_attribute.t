#!/usr/bin/perl

package MyDateTime;

use overload '""' => \&stringify;

sub now { bless [ time ], shift }
sub stringify { return shift->[0] }

package Foo;
use Class::Attribute;

attribute 'id',      is_int, protected, default => 1;
attribute 'name',    is_string(10, 40, 'a name of 10 - 40 chars');
attribute 'sex',     is_in( ['M', 'F'], 'sex (M/F)' ), private;
attribute 'age',     is_int, default => 18;
attribute 'email',   is_email;
attribute 'dob',     is_date;
attribute 'updated', isa => 'MyDateTime', default => sub { MyDateTime->now };

package Bar;
use base qw(Foo);

sub set_id                 { shift->SUPER::set_id(shift)  }
sub set_sex                { shift->SUPER::set_sex(shift) }
sub get_all_attributes     { shift->_get_all_attributes   }

package main;

use strict;
use warnings;

use Test::More tests => 18;
use Test::NoWarnings;
use Test::Exception;

isa_ok(my $foo = Foo->new, 'Foo');
isa_ok(my $bar = Bar->new, 'Bar');

is($foo->get_id, 1, 'default for id = 1');
is($foo->get_age, 18, 'default for age = 18');
isa_ok($foo->get_updated, 'MyDateTime');

## should fail, id is protected.
throws_ok
    { $foo->set_id(1) }
    qr/Called a protected mutator/i,
    'set_id is protected';

## should fail, not a valid email.
check_validation(
    sub { $foo->set_email('a@f.com.a'); $foo },
    qr/email = a\@f\.com\.a is not an email address/i,
    'barfs on invalid email address'
);

# should be atleast 10c.
check_validation(
    sub { $foo->set_name('bharanee'); $foo },
    qr/name = bharanee is not a name of 10 - 40 chars/i,
    'barfs on invalid name'
);

# works.
ok($foo->set_dob('1978-01-17'), 'set dob');
ok($foo->set_updated(MyDateTime->now), 'set updated');

# set_sex is private.
throws_ok
    { $bar->set_sex('M') }
    qr/Called a private mutator Foo::set_sex/,
    'private method is really private, can only be called inside Foo';

ok($bar->set_id(2), 'Bar::set_id works');
ok($bar->set_email('foo@bar.com.au'), 'Bar::set_email works on valid email');
ok($bar->set_name('foo bar baz'), 'Bar::set_name works on name > 10c long');

my $updated = $bar->get_updated;
my %attributes = $bar->get_all_attributes;

isa_ok($updated, 'MyDateTime', 'updated time');
is_deeply(
    \%attributes,
    {
        id      => 2,
        email   => 'foo@bar.com.au',
        name    => 'foo bar baz',
        sex     => undef,
        age     => 18,
        dob     => undef,
        updated => $updated,
    },
    'attributes set correctly'
);

sub check_validation {
    my ($code, $regex, $comment) = @_;

    my $obj = &$code();
    like(
        join ('', $obj->validate),
        $regex,
        $comment
    );
}

SKIP: {
    # should benchmarks be tests ? :-)
    my $code = do { local $/; <DATA> };
    eval "$code";
    skip 'Class::Accessor not installed ?', 1 if $@;
    eval { require Benchmark };
    skip 'Benchmark not installed ?', 1 if $@;

    my $baz = Baz->new;

    my $count1  = Benchmark::countit(
        0.5, sub { $baz->email('foo@bar.com'); $baz->email }
    )->iters * 2;
    my $count2 = Benchmark::countit(
        0.5, sub { $foo->set_email('foo@bar.com'); $foo->get_email }
    )->iters * 2;

    ok(
        $count1 < $count2,
        "faster! Class::Attribute $count2/s vs Class::Accessor::Faster $count1/s"
    );
}

__DATA__
package Baz;
use base qw(Class::Accessor::Faster);
__PACKAGE__->mk_accessors(qw(id name sex age email dob updated));
