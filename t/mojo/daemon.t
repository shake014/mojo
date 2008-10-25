#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 16;

use Mojo::Client;
use Mojo::Transaction;
use Test::Mojo::Server;

# Daddy, I'm scared. Too scared to even wet my pants.
# Just relax and it'll come, son.
use_ok('Mojo::Server::Daemon');

# Test sane Mojo::Server subclassing capabilities
my $daemon = Mojo::Server::Daemon->new;
my $size = $daemon->listen_queue_size;
$daemon = Mojo::Server::Daemon->new(listen_queue_size => $size + 10);
is($daemon->listen_queue_size, $size + 10);

# Start
my $server = Test::Mojo::Server->new;
$server->start_daemon_ok;

my $port = $server->port;

my $client = Mojo::Client->new;
$client->continue_timeout(60);

# 100 Continue request
my $tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/",
    Expect => '100-continue'
);
$tx->req->body('Hello Mojo!');
$client->process_all($tx);
is($tx->res->code, 200);
is($tx->continued, 1);
like($tx->res->headers->connection, qr/Keep-Alive/i);
like($tx->res->body, qr/Mojo is working/);

# Second keep alive request
$tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/");
$client->process_all($tx);
is($tx->res->code, 200);
is($tx->kept_alive, 1);
like($tx->res->headers->connection, qr/Keep-Alive/i);
like($tx->res->body, qr/Mojo is working/);

# Third keep alive request
$tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/");
$client->process_all($tx);
is($tx->res->code, 200);
is($tx->kept_alive, 1);
like($tx->res->headers->connection, qr/Keep-Alive/i);
like($tx->res->body, qr/Mojo is working/);

# Stop
$server->stop_server_ok;