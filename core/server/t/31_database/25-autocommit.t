package OpenXPKI::Server::Database::Driver::MySQLTest;
use Moose;
extends 'OpenXPKI::Server::Database::Driver::MySQL';

around 'dbi_dsn' => sub {
    my $orig = shift;
    my $self = shift;
    return $self->$orig(@_) . ";mysql_read_timeout=1";
};


package main;

use strict;
use warnings;
use English;
use Test::More;
use Test::Exception;

#use OpenXPKI::Debug; $OpenXPKI::Debug::LEVEL{'OpenXPKI::Server::Database.*'} = 100;

plan skip_all => "No MySQL database found / OXI_TEST_DB_MYSQL_NAME not set" unless $ENV{OXI_TEST_DB_MYSQL_NAME};

#
# setup
#
sub get_log {
    my $appender = Log::Log4perl->appender_by_name("Everything")
        or BAIL_OUT("Could not access Log4perl appender");
    my $messages = $appender->string;
    $appender->string("");
    return $messages;
}

use_ok "OpenXPKI::Server::Database";
use_ok "OpenXPKI::Server::Log";
my $log = OpenXPKI::Server::Log->new(
    CONFIG => \"
# Catch-all root logger
log4perl.rootLogger = DEBUG, Everything

log4perl.appender.Everything          = Log::Log4perl::Appender::String
log4perl.appender.Everything.layout   = Log::Log4perl::Layout::PatternLayout
log4perl.appender.Everything.layout.ConversionPattern = %d %c.%p %m%n
"
);

my $db_params = {
    type => "MySQLTest",
    host => "127.0.0.1", # if not specified, the driver tries socket connection
    name => $ENV{OXI_TEST_DB_MYSQL_NAME},
    user => $ENV{OXI_TEST_DB_MYSQL_USER},
    passwd => $ENV{OXI_TEST_DB_MYSQL_PASSWORD},
};

my $db_alice = OpenXPKI::Server::Database->new(log => $log, db_params => $db_params, autocommit => 1);
my $db_bob   = OpenXPKI::Server::Database->new(log => $log, db_params => $db_params);

# Checks if db handle "bob" sees the given data in table "test"
sub bob_sees {
    my ($id, $text, $message) = @_;
    my $data;
    lives_and {
        $data = $db_bob->select_one(from => "test", columns => [ "id", "text" ], where => { id => $id });
        is_deeply $data, ($text ? { id => $id, text => $text } : undef);
    } $message;
}

#
# create test table
#
eval { $db_alice->run("DROP TABLE test") };
$db_alice->run("CREATE TABLE test (id INTEGER PRIMARY KEY, text VARCHAR(100))");
$db_alice->insert(into => "test", values => { id => 1, text => "Litfasssaeule" });

#
# Tests
#
my $data;

lives_and {
    $db_alice->start_txn;
    like get_log(), qr/autocommit.*start_txn/i;
} "Warn about useless start_txn()";

lives_and {
    $db_alice->commit;
    like get_log(), qr/autocommit.*commit/i;
} "Warn about useless commit()";

lives_and {
    $db_alice->rollback;
    like get_log(), qr/autocommit.*rollback/i;
} "Warn about useless rollback()";

# Writing and reading
lives_ok {
    $db_alice->update(table => "test", set => { text => "LED-Panel" }, where => { id => 1 });
} "Alice updates data without commit";

bob_sees 1, "LED-Panel", "Bob sees new data";

$db_bob->commit; # to be able to drop database
$db_alice->run("DROP TABLE test");

done_testing(7);
