use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME               => 'IkiWiki::Plugin::purge',
    AUTHOR             => q{Stig Sandbeck Mathisen <ssm@fnord.no>},
    VERSION_FROM       => 'lib/IkiWiki/Plugin/purge.pm',
    ABSTRACT_FROM      => 'lib/IkiWiki/Plugin/purge.pm',
    LICENSE            => 'gpl',
    PL_FILES           => {},
    MIN_PERL_VERSION   => 5.006,
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => 0, },
    BUILD_REQUIRES     => {
        'Test::More'          => 0,
        'Test::Pod::Coverage' => 0,
    },
    PREREQ_PM => { 'IkiWiki' => '3.00', },
    dist      => { COMPRESS  => 'gzip -9f', SUFFIX => 'gz', },
    clean     => { FILES     => 'IkiWiki-Plugin-purge-*' },
);
