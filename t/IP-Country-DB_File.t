use Test::More tests => 38;
BEGIN { use_ok('IP::Country::DB_File') };

my $filename = 't/ipcc.db';
unlink($filename);

my $ipcc = IP::Country::DB_File->new($filename, 1);
ok(defined($ipcc), 'new');

local *FILE;
ok(open(FILE, '<', 't/delegated-test'), 'open source file');
ok($ipcc->importFile(*FILE) == 81, 'import file');
close(FILE);

undef($ipcc);

ok(-e $filename, 'create db');

$ipcc = IP::Country::DB_File->new($filename);

ok(abs($ipcc->db_time() - time()) < 24 * 3600, 'db_time');

my @tests = qw(
    0.0.0.0         ?
    0.0.0.1         ?
    0.0.1.0         ?
    0.1.0.0         ?
    1.2.3.4         ?
    24.131.255.255  ?
    24.132.0.0      NL
    24.132.127.255  NL
    24.132.128.0    NL
    24.132.255.255  NL
    24.133.0.0      ?
    24.255.255.255  ?
    25.0.0.0        GB
    25.50.100.200   GB
    25.255.255.255  GB
    26.0.0.0        ?
    33.177.178.99   ?
    61.1.255.255    ?
    62.12.95.255    CY
    62.12.96.0      ?
    62.12.127.255   ?
    62.12.128.0     CH
    217.198.128.241 UA
    217.255.255.255 DE
    218.0.0.0       ?
    218.0.0.1       ?
    218.0.0.111     ?
    218.0.111.111   ?
    218.111.111.111 ?
    224.111.111.111 ?
    254.111.111.111 ?
    255.255.255.255 ?
);

for(my $i=0; $i<@tests; $i+=2) {
    my ($ip, $testCC) = ($tests[$i], $tests[$i+1]);
    #print STDERR ("\n*** $ip $cc ", $ipcc->inet_atocc($ip));
    my $cc = $ipcc->inet_atocc($ip);
    $cc = '?' unless defined($cc);
    ok($cc eq $testCC, "lookup $ip");
}

unlink($filename);
