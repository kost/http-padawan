#!/usr/bin/perl
# HTTP proxy for UA change. Copyright (C) Kost. Distributed under GPL. 

use strict;
use IO::Socket::SSL;
use HTTP::Proxy;
use HTTP::Proxy::HeaderFilter::simple;
use Getopt::Long;

my $configfile="$ENV{HOME}/.proxy-ua";
my %config;
$config{'agent'} = 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)';
$config{'port'} = 3128;
$config{'verbose'}=0;
$config{'listen'}="0.0.0.0";
$config{'max_clients'}=64;
$config{'sslmitm'}=1;

my $uashortcuts = { 
	gbotmozilla => 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
	googlebot => 'Googlebot/2.1 (+http://www.googlebot.com/bot.html',
	gbot => 'Googlebot/2.1 (+http://www.google.com/bot.html)'
};

my ($key, $cert);


if (-e $configfile) {
        open(CONFIG,"<$configfile") or next;
        while (<CONFIG>) {
            chomp;                  # no newline
            s/#.*//;                # no comments
            s/^\s+//;               # no leading white
            s/\s+$//;               # no trailing white
            next unless length;     # anything left?
            my ($var, $value) = split(/\s*=\s*/, $_, 2);
            $config{$var} = $value;
        }
        close(CONFIG);
}

Getopt::Long::Configure ("bundling");

my $result = GetOptions (
	"l|listen" => \$config{'listen'},
	"n|maxclients" => \$config{'max_clients'},
	"k|sslkey" => \$config{'$sslkey'},
	"c|sslcert" => \$config{'$sslcert'},
	"a|agent" => \$config{'agent'},
        "p|port=i" => \$config{'port'},
        "s|verifyssl!" => \$config{'verifyssl'},
        "v|verbose+"  => \$config{'verbose'},
        "h|help" => \&help
);

# Monkeypatch HTTP::Proxy to handle CONNECT as I want to.
if ($config{'sslmitm'}) {

sub _handle_CONNECT {
    my ($self, $served) = @_;
    my $last = 0;
    my $conn = $self->client_socket;    
    my $req  = $self->request;
    my $upstream = IO::Socket::INET->new( PeerAddr => $req->uri->host_port );
    unless( $upstream and $upstream->connected ) {
	# 502 Bad Gateway / 504 Gateway Timeout
	# Note to implementors: some deployed proxies are known to
	# return 400 or 500 when DNS lookups time out.
	my $response = HTTP::Response->new( 200 );
	$response->content_type( "text/plain" );
	$self->response($response);
	return $last;
    }

    # send the response headers (FIXME more headers required?)
    my $response = HTTP::Response->new(200);
    $self->response($response);
    $self->{$_}{response}->select_filters( $response ) for qw( headers body );

    $self->_send_response_headers( $served );

    # we now have a TCP connection to the upstream host
    $last = 1;
    my $class = ref($conn);
    { no strict 'refs'; unshift(@{$class . "::ISA"}, 'IO::Socket::SSL'); } # Forcibly change classes the socket inherits from
    $class->start_SSL($conn, 
	SSL_server => 1, 
	SSL_key_file => $config{'sslkey'},
	SSL_cert_file => $config{'sslcert'}, # Turn our client socket into SSL.
    ) or warn("Could not start SSL");
    ${*$conn}{'httpd_nomore'} = 0; # Pay no attention to the Connection: close header behind the curtain.
    {   # Build a method to fiddle with the request object we get from the client, as it needs to http->https
	my $old_setrequest_method = \&HTTP::Proxy::request;
	my $new_request_method = sub {
	    my ($self, $new_req) = @_;
	    if ($new_req) {
		use Data::Dumper;
		if (!$new_req->uri->scheme or $new_req->uri->scheme eq 'http') {
		    $new_req->uri->scheme('https');
		    $new_req->uri->host($new_req->header('Host'));
		}
	    }
	    $old_setrequest_method->($self, $new_req);
	};
	# And monkeypatch it into HTTP proxy, using local to restrict it by lexical scope
	# so that it goes away once we exit the block (i.e. the CONNECT method finishes).
	no warnings qw[once redefine];
	local *HTTP::Proxy::request = $new_request_method;
	use warnings qw[once redefine];
	$self->serve_connections($conn);
    }
    $conn->stop_SSL($conn);
    return $last;
}
{
    no warnings qw(once redefine);
    *HTTP::Proxy::_handle_CONNECT = \&_handle_CONNECT;
}
}

my $proxy = HTTP::Proxy->new;
$proxy->host( $config{'listen'} );
$proxy->port( $config{'port'} ); 
$proxy->max_clients($config{'max_clients'});

my $filter = HTTP::Proxy::HeaderFilter::simple->new(
      sub { 
	$_[1]->remove_header(qw( User-Agent ));
	$_[1]->push_header( User_Agent => $config{'agent'} ); 
	}
    );

$proxy->push_filter( request => $filter );

if ($config{'verbose'}>5) {
	$proxy->logmask( HTTP::Proxy::ALL );
}

print STDERR "[i] Starting proxy server at $config{'listen'}:$config{'port'}\n";

$proxy->start;

print STDERR "[i] Stopping proxy server at $config{'listen'}:$config{'port'}\n";
