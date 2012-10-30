#!/usr/bin/perl
# Port scanner through proxy. (C) Kost. Distributed under GPL. 

$|=1;

use strict;
use IO::Socket;
use IO::Socket::SSL;
use Getopt::Long;

my $reftable={
	"Connection refused" => 'SQUID: Connection refused.',
	"Access Denied"	=> 'SQUID: Access denied.',
	"Unsupported Request Method and Protocol" => 'SQUID: Unsupported method.',
	"Connection timed out" => 'SQUID: Connection timed out.',
	"Zero Sized Reply" => 'SQUID: Zero sized reply.',
	"Error Code: 403 Forbidden." => 'IIS: forbidden'
	};

Getopt::Long::Configure ("bundling");

my @aports=(21,70,80,210,280,443,488,563,591,777,901,8080,9080,9060,8000);
my @ahosts;

my $proxyhost="127.0.0.1";
my $proxyport="8080";
my $alternate;
my $method = "GET";
my $scheme="http";
my $hosts;
my $ports;
my $verbose;
my $http1;
my $ssl;
my $uri="/";

my $result = GetOptions (
        "I|proxyhost=s" => \$proxyhost,
	"P|proxyport=i" => \$proxyport,
        "i|ip=s" => \$hosts,
	"p|port=s" => \$ports,
	"m|method=s" => \$method,
	"e|scheme=s" => \$scheme,
	"s|ssl" => \$ssl,
	"u|uri" => \$uri,
	"a|alternate" => \$alternate,
	"1|http1" => \$http1,
        "v|verbose+"  => \$verbose,
        "h|help" => \&help
);

if ($ports) {
	@aports=();
	my @items=split(",",$ports);
	foreach my $item (@items) {
		if ($item =~ /-/) {
			my ($begport,$endport)=split("-",$item);
			for (my $p=$begport; $p<=$endport; $p++) {
				push @aports, $p;
			}
		} else {
			push @aports, $item;
		}	
	}
}
if ($verbose>2) {
	print STDERR "[i] Ports to scan: ";
	foreach my $p (@aports) { print $p.","; }
	print STDERR "\n";
}

if ($hosts) {
	my @items=split(",",$hosts);
	foreach my $item (@items) {
		if ($item =~ /[A-Za-z]/) {
			push @ahosts,$item;
		}
		elsif ($item =~ /-/) {
			my @ipp=split(/\./,$item);
			my ($beg,$end)=split("-",$ipp[3]);
			for (my $p=$beg; $p<=$end; $p++) {
				push @ahosts, "$ipp[0].$ipp[1].$ipp[2].$p";
			}
		} else {
			push @ahosts, $item;
		}	
	}
} else {
	help();
}
if ($verbose>2) {
	print STDERR "[i] Hosts to scan: ";
	foreach my $p (@ahosts) { print $p.","; }
	print STDERR "\n";

}

my $httpversion;
if ($http1) {
	$httpversion="HTTP/1.1";
} else {
	$httpversion="HTTP/1.0";
}
if ($verbose>2) {
	print STDERR "[i] Using $httpversion\n";
}

foreach my $host (@ahosts) {
	foreach my $port (@aports) {
		print "$host;$port;";
		my $sock;
		if ($ssl) {
			print STDERR "[i] Using SSL\n" if ($verbose>2);
			$sock = IO::Socket::SSL->new(PeerAddr => $proxyhost,
					    PeerPort => $proxyport);
		} else {
			print STDERR "[i] Using plain socket\n" if ($verbose>2);
			$sock = IO::Socket::INET->new(PeerAddr => $proxyhost,
					    PeerPort => $proxyport,
					    Proto    => 'tcp');
		}
		if (!$sock) {
			print STDERR "Cannot connect to Proxy $proxyhost:$proxyport : $!\n";
			next;
		}

		my $req;
		if ($alternate) {
			$req = "$method host:$port $httpversion\r\n";
		} else {
			$req = "$method $scheme://$host:$port$uri $httpversion\r\n";
		}
		if ($http1) {
			$req=$req."Host: $host:$port\r\n";
		}
		$req=$req."\r\n";
		print STDERR "[i] Request:\n".$req."\n[i]End Req\n" if ($verbose>5);
		print $sock $req;
			
		my $output;
		while (<$sock>) {
			$output=$output.$_;	
		}
		print $output."\n" if ($verbose>5);

		my $foundkey=0;
		foreach my $key ( keys %{$reftable} ) {
			if ($output =~ /$key/) {
				$foundkey=1;
				print $reftable->{$key};
				print "\n";
			}
		}
						
		if ($foundkey == 0) {
			print "Unknown\n";
			print $output;
			print "\n";
		}
	}
}

sub help {
        print "$0: Enumerate hosts and ports through proxy\n";
        print "Copyright (C) Vlatko Kosturjak, Kost. Distributed under GPL.\n\n";
        print "Usage: $0 -I proxy.host -P 80 -i 192.168.1.1-254 -p 80,8080-8090\n\n";
        print " -a      try alternate proxy usage (useful for CONNECT)\n";
        print " -I      proxy host\n";
        print " -P      proxy port\n";
	print " -i      hosts to enumerate\n";
	print " -p      ports to enumerate\n";
	print " -e      scheme to enumerate (useful: http, https, ftp, gopher, ...)\n";
	print " -m      method to enumerate (useful: GET*, HEAD, POST, PUT, CONNECT, ...)\n";
	print " -s	use SSL\n";
        print " -1      use HTTP/1.1\n";
        print " -v      verbose\n";
        print " -h      this help message\n";
        exit (0);
}
