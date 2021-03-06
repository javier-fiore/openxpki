package OpenXPKI::Server::Log::Appender::DBI;

use strict;
use warnings;

use OpenXPKI::Debug;
use OpenXPKI::Server::Context qw( CTX );
use Data::Dumper;
use English;
use Log::Log4perl::Level;
use Carp;
use OpenXPKI::Server::Database; # we must import "auto_id" 

my %LOGLEVELS = (
    ALL     => 0,
    TRACE   => 5000,
    DEBUG   => 10000,
    INFO    => 20000,
    WARN    => 30000,
    ERROR   => 40000,
    FATAL   => 50000,
    OFF     => (2 ** 31) - 1,
);


sub new {
    ##! 1: 'start'
    my($proto, %p) = @_;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class; 
    ##! 1: 'end'
    return $self;
}

sub log {
    ##! 1:  'start'
    my $self    = shift;
    my $arg_ref = { @_ };

    ##! 128: 'arg_ref: ' . Dumper $arg_ref

    my $timestamp = $self->__get_current_utc_time();
    ##! 64: 'timestamp: ' . $timestamp
    my $category  = $arg_ref->{'log4p_category'};
    ##! 64: 'category: ' . $category
    my $loglevel  = $arg_ref->{'log4p_level'};
    ##! 64: 'loglevel: ' . $loglevel
    my $message   = $arg_ref->{'message'}->[0];
    ##! 64: 'message: ' . $message

    my $dbi;

    eval {
        $dbi = CTX('dbi_log');
    };
    if ($EVAL_ERROR || ! defined $dbi) {
        ##! 16: 'dbi_log unavailable!'
        print STDERR "dbi_log unavailable! (tried to log: $timestamp, $category, $loglevel, $message)\n";
        return;
    }

    # TODO: If category IS '*.audit', write to the audittrail. Otherwise,
    #       write to application_log and also put workflow_id into its
    #       own column instead of in the message.
    if ( $category =~ m{\.audit$} ) {
        # do NOT catch DBI errors here as we want to fail if audit 
        # is not working
        $dbi->insert(
            into => 'audittrail',
            values  => {
                audittrail_key => AUTO_ID,
                logtimestamp   => $timestamp,
                loglevel       => $loglevel,
                category       => $category,
                message        => $message,
            },    
        );
    } else {
        my $serial;
        my $wf_id = 0;
        if (OpenXPKI::Server::Context::hascontext('workflow_id')) {
            $wf_id = CTX('workflow_id');
        }

        my $loglevel_int = 0;
        if ( exists $LOGLEVELS{$loglevel} ) {
            $loglevel_int = $LOGLEVELS{$loglevel};
        }
        $dbi->insert(
            into => 'application_log',
            values  => {
                application_log_id => AUTO_ID,
                logtimestamp       => $timestamp,
                workflow_id        => $wf_id,
                priority           => $loglevel,
                category           => $category,
                message            => $message,
            },    
        );
        
        if (my $exc = OpenXPKI::Exception->caught()) {
            ##! 16: 'exception caught'
            if ($exc->message() eq 'I18N_OPENXPKI_SERVER_DBI_DBH_DO_QUERY_NOT_CONNECTED') {
                ##! 16: 'dbi_log not connected'
                print STDERR "dbi_log not connected! (tried to log: $timestamp, $category, $loglevel, $wf_id, $message)\n";
                return; 
            }
            else {
                $exc->rethrow();
            }
        }
    }

    ##! 1: 'end'
    return 1;
}

sub __get_current_utc_time {
    my $self = shift;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
        gmtime(time);
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

1;
__END__

=head1 Name

OpenXPKI::Server::Log::Appender::DBI

=head1 Description

This is a special log appender for Log::Log4perl. It uses the dbi_log
handle generated during server init to write to the audittrail and
application_log tables. 

 
