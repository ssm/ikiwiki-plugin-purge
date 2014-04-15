#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'IkiWiki::Plugin::purge' ) || print "Bail out!\n";
}

diag( "Testing IkiWiki::Plugin::purge $IkiWiki::Plugin::purge::VERSION, Perl $], $^X" );
