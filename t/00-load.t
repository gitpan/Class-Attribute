#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Class::Attribute' );
}

diag( "Testing Class::Attribute $Class::Attribute::VERSION, Perl $], $^X" );
