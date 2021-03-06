#!/usr/bin/perl
use strict;
use warnings;

# Core modules
use English;
use FindBin qw( $Bin );

# CPAN modules
use Test::More;

use lib "$Bin/../lib";

plan tests => 7;

my $maxage = 60*60*24;  # 1 day

sub get_utc_time {
    my $t = shift || time;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
        gmtime($t);
    $year += 1900;
    $mon++;
    my $time;
    my $microseconds = 0;
    eval { # if Time::HiRes is available, use it to get microseconds
        use Time::HiRes qw( gettimeofday );
        my ($seconds, $micro) = gettimeofday();
        $microseconds = $micro;
    };
    $time = sprintf("%04d%02d%02d%02d%02d%02d%06d", $year, $mon, $mday, $hour, $min, $sec, $microseconds);

    return $time;
}

use OpenXPKI::Debug;
$OpenXPKI::Debug::LEVEL{'.*'} = $ENV{DEBUG_LEVEL} if $ENV{DEBUG_LEVEL};

sub is_logentry_count {
    my ($wf_id, $count) = @_;

    my $result = CTX('dbi')->select(
        from => 'application_log',
        columns => [ '*' ],
        where => {
            category => 'openxpki.application',
            workflow_id => $wf_id,
        }
    )->fetchall_arrayref({});

    is scalar @{$result}, $count, "$count log entries found via workflow id";
}

#
# Setup test context
#
use OpenXPKI::Test;
OpenXPKI::Test->new->setup_env;

my $dbi = CTX('dbi');
my $log = CTX('log');

#
# Tests
#

# Setup workflow ID which is part of the logged informations
my $wf_id = int(rand(10000000));
OpenXPKI::Server::Context::setcontext({
    workflow_id => $wf_id
});

# Insert and validate test message via API
my $msg = sprintf "DBI Log Workflow Test %01d", $wf_id;

ok $log->info($msg, "application"), 'log test message to be kept'
    or diag "ERROR: log=$log";

my $result = $dbi->select(
    from => 'application_log',
    columns => [ '*' ],
    where => {
        category => 'openxpki.application',
        message => { -like => "%$msg" },
    }
)->fetchall_arrayref({});
is scalar @{$result}, 1, "1 log entry found via string search";

# Insert test message #1 via database
ok $dbi->insert(
    into => 'application_log',
    values => {
        application_log_id  => $dbi->next_id('application_log'),
        logtimestamp        => get_utc_time( time - $maxage + 5), # should be kept when calling 'purge'
        workflow_id         => $wf_id,
        category            => 'openxpki.application',
        priority            => 'info',
        message             => "Blah",
    },
), "insert old test message to be kept";

# Insert test message #2 via database
ok $dbi->insert(
    into => 'application_log',
    values => {
        application_log_id  => $dbi->next_id('application_log'),
        logtimestamp        => get_utc_time( time - $maxage - 5), # should be deleted when calling 'purge'
        workflow_id         => $wf_id,
        category            => 'openxpki.application',
        priority            => 'info',
        message             => "Blah",
    },
), "insert old test message to be purged";

is_logentry_count $wf_id, 3;

# API call to purge records
my $maxutc = get_utc_time( time - $maxage );
ok CTX('api')->purge_application_log( { MAXAGE => $maxage } ), "call 'purge_application_log' with MAXAGE";

is_logentry_count $wf_id, 2;

1;
