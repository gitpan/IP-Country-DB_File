use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'IP::Country::DB_File',
    DISTNAME          => 'IP-Country-DB_File',
    VERSION_FROM      => 'lib/IP/Country/DB_File.pm',
    PREREQ_PM         => {
        DB_File => undef
    },
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'lib/IP/Country/DB_File.pm',
       AUTHOR         => 'Nick Wellnhofer <wellnhofer@aevum.de>') : ()),
);
