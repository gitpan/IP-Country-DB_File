
use strict;
use warnings;



use ExtUtils::MakeMaker;

WriteMakefile(
  DISTNAME  => 'IP-Country-DB_File',
  NAME      => 'IP::Country::DB_File',
  AUTHOR    => "Nick\ Wellnhofer\ \<wellnhofer\@aevum\.de\>",
  ABSTRACT  => "IP\ to\ country\ translation\ based\ on\ DB_File",
  VERSION   => '2.00',
  EXE_FILES => [ qw() ],
  (eval { ExtUtils::MakeMaker->VERSION(6.31) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM    => {
    "DB_File" => '0',
  },
  test => {TESTS => 't/*.t'}
);

