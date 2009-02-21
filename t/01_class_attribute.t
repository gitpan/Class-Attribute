#!/usr/bin/perl

package MyDateTime;

use overload '""' => \&stringify;

sub now { bless [ time ], shift }
sub stringify { return shift->[0] }

package Employee;
use Class::Attribute;

attribute 'id',      is_int, protected, public_accessor, default => 1;
attribute 'name',    is_string(10, 40, 'a name of 10 - 40 chars');
attribute 'sex',     is_in( ['M', 'F'], 'sex (M/F)' ), private;
attribute 'age',     is_int, default => 18;
attribute 'email',   is_email, predicate => 'has_email';
attribute 'dob',     is_date;
attribute 'updated', isa => 'MyDateTime', default => sub { MyDateTime->now };

sub public_set_sex {
    shift->set_sex(shift);
}

package Manager;
use base qw(Employee);
use Class::Attribute;

attribute 'dept', readonly, default => 'accounts';
attribute 'security_code', is_string(6, 6, '6 digit pin'), default => '000000', protected;

sub set_id                 { shift->SUPER::set_id(shift)  }
sub set_sex                { shift->SUPER::set_sex(shift) }
sub get_all_attributes     { shift->_get_all_attributes   }


package main;

use strict;
use warnings;

use Test::More tests => 22;
use Test::NoWarnings;
use Test::Exception;

isa_ok(my $emp = Employee->new, 'Employee');
isa_ok(my $mgr = Manager->new, 'Manager');

is($emp->get_id, 1, 'default for id = 1');
is($emp->get_age, 18, 'default for age = 18');
isa_ok($emp->get_updated, 'MyDateTime');

## should fail, id is protected.
throws_ok
    { $emp->set_id(1) }
    qr/Called a protected mutator/i,
    'set_id is protected';

## should fail, not a valid email.
check_validation(
    sub { $emp->set_email('a@f.com.a'); $emp },
    qr/email = a\@f\.com\.a is not an email address/i,
    'barfs on invalid email address'
);

# should be atleast 10c.
check_validation(
    sub { $emp->set_name('bharanee'); $emp },
    qr/name = bharanee is not a name of 10 - 40 chars/i,
    'barfs on invalid name'
);

# works.
ok($emp->set_dob('1978-01-17'), 'set dob');
ok($emp->set_updated(MyDateTime->now), 'set updated');

# private mutators.
throws_ok
    { $mgr->set_sex('M') }
    qr/Called a private mutator 'Employee::set_sex' from Manager/,
    'private method is really private, can only be called inside Employee';

throws_ok
    { $mgr->set_dept('hr') }
    qr/Called a private mutator 'Manager::set_dept' from main/,
    'readonly defines private mutators';

lives_ok
    { $emp->public_set_sex('M') }
    'private method can be called through a public interface';

is($mgr->get_dept, 'accounts', 'readonly has public accessor');
is ($mgr->has_email, 0, 'no email address yet');

ok($mgr->set_id(2), 'Manager::set_id works');
ok($mgr->set_email('mgr@example.com'), 'Manager::set_email works on valid email');
ok($mgr->set_name('firstname lastname'), 'Manager::set_name works on name > 10c long');

is ($mgr->has_email, 1, 'email address set');

my $updated = $mgr->get_updated;
my %attributes = $mgr->get_all_attributes;

isa_ok($updated, 'MyDateTime', 'updated time');
is_deeply(
    \%attributes,
    {
        id      => 2,
        email   => 'mgr@example.com',
        name    => 'firstname lastname',
        sex     => undef,
        age     => 18,
        dob     => undef,
        updated => $updated,
        dept    => 'accounts',
        security_code => '000000',
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
        0.5,
        sub {
            $baz->email('emp@mgr.com');
            $baz->email;
            $baz->id
        }
    )->iters * 2;
    my $count2 = Benchmark::countit(
        0.5,
        sub {
            $emp->set_email('emp@mgr.com');
            $emp->get_email;
            $emp->get_id; # protected_method
        }
    )->iters * 2;

    TODO: {
        local $TODO = 'make performance test pass on all platforms';
        ok(
            $count1 <= $count2,
            "faster! Class::Attribute $count2/s vs Class::Accessor::Faster $count1/s"
        );
    }
}

__DATA__
package Baz;
use base qw(Class::Accessor::Faster);
__PACKAGE__->mk_accessors(qw(id name sex age email dob updated));
