#!/usr/bin/perl
# Simple HTTP logging server

use strict;
use IO::Handle;
use HTTP::Daemon;
use HTTP::Status;
use POSIX qw(strftime);

$|=1;

my $logfile="server.log";
my $d = HTTP::Daemon->new(
        LocalAddr => '10.1.220.8',
        LocalPort => 80
        ) or die "cannot bind: $!";

open (FLOG,">>$logfile") or die "cannot open log file: $!";

print "Please contact me at: <URL:", $d->url, ">\n";
while (my $c = $d->accept) {
        while (my $r = $c->get_request) {
                my $now_string = strftime "%a %b %e %H:%M:%S %Y", localtime;
                my $str=$c->peerhost."= $now_string:\n";
                $str=$str.$r->as_string."\n";
                print FLOG $str;
                FLOG->flush;
                print $str;
                $c->send_status_line;
                $c->send_response("OK");
        }
        $c->close;
        undef($c);
}

close (FLOG);
