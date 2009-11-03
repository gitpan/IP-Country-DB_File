#!/usr/bin/perl
use strict;

package IP::Country::DB_File;

use DB_File ();
use Fcntl ();
use Socket ();

use vars qw($VERSION @rirs);

BEGIN {
    $VERSION = '1.03';

    # Regional Internet Registries
    @rirs = (
        { name=>'arin',    server=>'ftp.arin.net'    },
        { name=>'ripencc', server=>'ftp.ripe.net'    },
        { name=>'afrinic', server=>'ftp.afrinic.net' },
        { name=>'apnic',   server=>'ftp.apnic.net'   },
        { name=>'lacnic',  server=>'ftp.lacnic.net'  },
    );
}

sub new {
    my ($class, $dbFile, $writeAccess) = @_;
    $dbFile = 'ipcc.db' unless defined($dbFile);

    my $this = {};

    my %db;
    my $flags = $writeAccess ?
        Fcntl::O_RDWR|Fcntl::O_CREAT|Fcntl::O_TRUNC :
        Fcntl::O_RDONLY;
    $this->{db} = tie(%db, 'DB_File', $dbFile, $flags, 0666,
                      $DB_File::DB_BTREE)
        or die("Can't open database $dbFile: $!");
    
    return bless($this, $class);
}

sub importFile {
    my ($this, $file) = @_;
    my $db = $this->{db};
    
    my ($count, $lastStart, $lastEnd, $lastCC, $seenHeader) = (0, 0, 0, '');

    while(my $line = readline($file)) {
        next if $line =~ /^#/ or $line !~ /\S/;

        unless($seenHeader) {
            $seenHeader = 1;
            next;
        }

        my ($registry, $cc, $type, $start, $value, $date, $status) =
            split(/\|/, $line);

        next unless $type eq 'ipv4' && $start ne '*';

        # TODO (paranoid): validate $cc, $start and $value

        my $ipNum = unpack('N', pack('C4', split(/\./, $start)));

        die("IP addresses not sorted (line $.)")
            if $ipNum < $lastEnd;

        if($ipNum == $lastEnd && $lastCC eq $cc) {
            # optimization: concat ranges of same country
            $lastEnd += $value;
        }
        else {
            if($lastCC) {
                my $key = pack('N', $lastEnd - 1);
                my $data = pack('Na2', $lastStart, $lastCC);
                $db->put($key, $data) >= 0 or die("dbput: $!");
            }

            ($lastStart, $lastEnd, $lastCC) = ($ipNum, $ipNum + $value, $cc);
            ++$count;
        }
    }

    if($lastCC) {
        my $key = pack('N', $lastEnd - 1);
        my $data = pack('Na2', $lastStart, $lastCC);
        $db->put($key, $data) >= 0 or die("dbput: $!");
    }
    
    $db->sync() >= 0 or die("dbsync: $!");
    
    return $count;
}

sub build {
    my ($this, $dir) = @_;
    $dir = '.' unless defined($dir);

    local *FILE;

    for my $rir (@rirs) {
        my $filename = "$dir/delegated-$rir->{name}";
        CORE::open(FILE, '<', $filename)
            or die("Can't open $filename: $!, " .
                   "maybe you have to fetch files first");

        eval {
            $this->importFile(*FILE);
        };

        my $error = $@;

        close(FILE);

        die($error) if $@;
    }
}

sub inet_ntocc {
    my ($this, $addr) = @_;
    
    my $db = $this->{db};
    my ($key, $data);
    $db->seq($key = $addr, $data, DB_File::R_CURSOR()) and return undef;
    my ($start, $cc) = unpack('a4a2', $data);
    
    return $addr ge $start ? $cc : undef;
}

sub inet_atocc {
    my ($this, $ip) = @_;
    
    my $addr = Socket::inet_aton($ip);
    return undef unless defined($addr);
    
    my $db = $this->{db};
    my ($key, $data);
    $db->seq($key = $addr, $data, DB_File::R_CURSOR()) and return undef;
    my ($start, $cc) = unpack('a4a2', $data);
    
    return $addr ge $start ? $cc : undef;
}

sub db_time {
    my $this = shift;
    
    local *FILE;
    my $fd = $this->{db}->fd();
    open(FILE, "<&$fd")
        or die("Can't dup DB file descriptor: $!\n");
    my @stat = stat(FILE)
        or die("Can't stat DB file descriptor: $!\n");
    close(FILE);
    
    return $stat[9]; # mtime
}

# functions

sub fetchFiles {
    my $dir = shift;
    $dir = '.' unless defined($dir);

    require Net::FTP;

    for my $rir (@rirs) {
        my $server = $rir->{server};

        my $ftp = Net::FTP->new($server)
            or die("Can't connect to FTP server $server: $@");

        $ftp->login('anonymous', '-anonymous@')
            or die("Can't login to FTP server $server: " . $ftp->message());

        my $name = $rir->{name};

        my $ftpDir = "/pub/stats/$name";
        $ftp->cwd($ftpDir)
            or die("Can't find directory $ftpDir on FTP server $server: " .
                   $ftp->message());

        my $filename = "delegated-$name-latest";
        $ftp->get($filename, "$dir/delegated-$name")
            or die("Get $filename from FTP server $server failed: " .
                   $ftp->message());

        $ftp->quit();
    }
}

sub removeFiles {
    my $dir = shift;
    $dir = '.' unless defined($dir);

    for my $rir (@rirs) {
        my $name = $rir->{name};
        unlink("$dir/delegated-$name");
    }
}

sub update {
    require Getopt::Std;
    
    my %opts;
    Getopt::Std::getopts('fbrd:', \%opts) or exit(1);
    
    die("extraneous arguments\n") if @ARGV > 1;
    
    my $dir = $opts{d};
    
    fetchFiles($dir) if $opts{f};
    
    if($opts{b}) {
        my $ipcc = __PACKAGE__->new($ARGV[0], 1);
        $ipcc->build($dir);
    }
    
    removeFiles($dir) if $opts{r};
}

1;

__END__

=head1 NAME

IP::Country::DB_File - IP to country translation based on DB_File

=head1 SYNOPSIS

    perl -MIP::Country::DB_File -e IP::Country::DB_File::update -- \
        -f -b -r
    
    my $ipcc = IP::Country::DB_File->new();
    $ipcc->inet_atocc('1.2.3.4');
    $ipcc->inet_atocc('host.example.com');

    my $ipcc = IP::Country::DB_File->new('ipcc.db', 1);
    IP::Country::DB_File::fetchFiles();
    $ipcc->build();
    IP::Country::DB_File::removeFiles();

=head1 DESCRIPTION

IP::Country::DB_File is a light-weight module for fast IP address to country
translation based on L<DB_File>. The country code database is stored in a
Berkeley DB file.

The database is built from the publically available statistics files of the
Regional Internet Registries. Currently, the files are downloaded from the
following hard-coded locations:

    ftp://ftp.arin.net/pub/stats/arin/delegated-arin-latest
    ftp://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-latest
    ftp://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-latest
    ftp://ftp.apnic.net/pub/stats/apnic/delegated-apnic-latest
    ftp://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-latest

You have to build the database before you can lookup country codes. This can be
done directly in Perl, or by calling the update subroutine from the command
line. Since the country code data changes constantly, you should consider
updating the database from time to time. It should be no problem to use a
database built on a different machine as long as the I<libdb> versions are
compatible.

This module tries to be API compatible with the other L<IP::Country> modules.
The installation of L<IP::Country> is not required.

=head1 CONSTRUCTOR

=head2 new

my $ipcc = IP::Country::DB_File->new([ I<$dbFile> ], [ I<$writeAccess> ]);

Creates a new object and opens the database file I<$dbFile>. I<$dbFile>
defaults to F<ipcc.db>.

I<$writeAccess> is a boolean that should be true if you plan to build or modify
the database. If you only make lookups you should pass a false value.
I<$writeAccess> defaults to false.

=head1 OBJECT METHODS

=head2 build

$ipcc->build([ I<$dir> ]);

Builds a database from geo IP source files in directory I<$dir>. I<$dir>
defaults to the current directory. This method creates or overwrites the
database file.

=head2 inet_atocc

$ipcc->inet_atocc(I<$string>);

Looks up the country code of host I<$string>. I<$string> can either be an IP
address in dotted quad notation or a hostname. Returns a country code as
defined in the geo IP source files. This code consists of two uppercase
letters. In most cases it is an ISO-3166-1 alpha-2 country code, but
there are also codes like 'EU' for Europe.

Returns undef if there's no country code listed for the IP address.

=head2 inet_ntocc

$ipcc->inet_ntocc(I<$string>);

Like I<inet_atocc> but works with a stringified numeric IP address.

=head2 db_time

$ipcc->db_time();

Returns the mtime of the DB file.

=head1 FUNCTIONS

=head2 fetchFiles

IP::Country::DB_File::fetchFiles([ I<$dir> ]);

Fetches geo IP source files from the FTP servers of the RIR and stores them in
I<$dir>. I<$dir> defaults to the current directory. This method requires
L<Net::FTP>.

This method only fetches files and doesn't build the database yet.

=head2 removeFiles

IP::Country::DB_File::removeFiles([ I<$dir> ]);

Deletes the previously fetched geo IP source files in I<$dir>. I<$dir> defaults
to the current directory.

=head2 update

You can call this subroutine from the command line to update the country code
database like this:

    perl -MIP::Country::DB_File -e IP::Country::DB_File::update -- \
        [options] [dbfile]

I<dbfile> is the database file and defaults to F<ipcc.db>. Options include

=head3 -f

fetch files

=head3 -b

build database

=head3 -r

remove files

=head3 -d [dir]

set directory for geo IP source files

You should provide at least one of the I<-f>, I<-b> or I<-r> options, otherwise
this routine does nothing.

=head1 SEE ALSO

L<IP::Country>

=head1 AUTHOR

Nick Wellnhofer <wellnhofer@aevum.de>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Nick Wellnhofer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
