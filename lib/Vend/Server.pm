# Server.pm:  listen for cgi requests as a background server
#
# $Id: Server.pm,v 1.36 1998/03/14 23:47:56 mike Exp $
#
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
# Copyright 1996-1998 by Michael J. Heins <mikeh@iac.net>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Vend::Http::Server;
require Vend::Http;
@ISA = qw(Vend::Http::CGI);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.36 $, 10);

use Vend::Util qw(strftime);
use POSIX qw(setsid);
use strict;

my $Pidfile;

sub new {
    my ($class, $fh, $env, $entity) = @_;
    my $http = new Vend::Http::CGI;
    $http->populate($env);
    $http->{fh} = $fh;
    $http->{entity} = $entity;
    bless $http, $class;
}

sub read_entity_body {
    my ($s) = @_;
    $s->{entity};
}

sub create_cookie {
	my($domain,$path) = @_;
	my $out = "Set-Cookie: MV_SESSION_ID=" . $Vend::SessionName . ";";
	$out .= " path=$path;";
	$out .= " domain=" . $domain . ";" if $domain;
	$out .= " expires=" .
					strftime "%a, %d-%b-%y %H:%M:%S GMT ", gmtime($Vend::Expire)
			 if $Vend::Expire;
	$out .= "\r\n";
}

sub respond {

    my ($s, $content_type, $body) = @_;
    my $fh = $s->{fh};

	# Fix for SunOS, Ultrix, Digital UNIX
	my($oldfh) = select($fh);
	$| = 1;
	select($oldfh);

	if($s->{response_made}) {
		print $fh $body;
		return 1;
	}

	if ($CGI::script_name =~ m:/nph-[^/]+$:) {
		if(defined $Vend::StatusLine) {
			print $fh $Vend::StatusLine;
			undef $Vend::StatusLine;
		}
		else { print $fh "HTTP/1.0 200 OK\r\n"; }
	}

	if ((defined $Vend::Expire or ! $CGI::cookie) and $Vend::Cfg->{'Cookies'}) {

		my @domains;
		@domains = ('');
		if ($Vend::Cfg->{CookieDomain}) {
			@domains = split /\s+/, $Vend::Cfg->{CookieDomain};
		}

		my @paths;
		@paths = ('/');
		if($Global::Mall) {
			my $ref = $Global::Catalog{$Vend::Cfg->{CatalogName}};
			@paths = ($ref->{'script'});
			push (@paths, @{$ref->{'alias'}}) if defined $ref->{'alias'};
			if ($Global::FullUrl) {
				# remove domain from script
				for (@paths) { s:^[^/]+/:/: ; }
			}
		}

		my ($d, $p);
		foreach $d (@domains) {
			foreach $p (@paths) {
				print $fh create_cookie($d, $p);
			}
		}
    }

    if (defined $Vend::StatusLine) {
		print $fh "$Vend::StatusLine\r\n";
	}
	else {
		print $fh "Content-type: $content_type\r\n";
	}

	if ($Vend::Session->{frames} and $CGI::values{mv_change_frame}) {
# DEBUG
#Vend::Util::logDebug
#("Changed Frame: Window-target: " . $CGI::values{mv_change_frame} . "\r\n")
#	if ::debug(0x40);
# END DEBUG
		print $fh "Window-target: " . $CGI::values{mv_change_frame} . "\r\n";
    }

    print $fh "\r\n";
    print $fh $body;
    $s->{'response_made'} = 1;
}

package Vend::Server;
require Exporter;
@Vend::Server::ISA = qw(Exporter);
@Vend::Server::EXPORT = qw(run_server);

use Fcntl;
use Config;
use Socket;
use strict;
use Vend::Util;
use POSIX qw(setsid);

my $LINK_FILE = "$Global::ConfDir/socket";

sub _read {
    my ($in) = @_;
    my ($r);
    
    do {
        $r = sysread(Vend::Server::MESSAGE, $$in, 512, length($$in));
    } while (!defined $r and $! =~ m/^Interrupted/);
    die "read: $!" unless defined $r;
    die "read: closed" unless $r > 0;
}

sub _find {
    my ($in, $char) = @_;
    my ($x);

    _read($in) while (($x = index($$in, $char)) == -1);
    my $before = substr($$in, 0, $x);
    substr($$in, 0, $x + 1) = '';
    $before;
}

sub _string {
    my ($in) = @_;
    my $len = _find($in, " ");
    _read($in) while (length($$in) < $len + 1);
    my $str = substr($$in, 0, $len);
    substr($$in, 0, $len + 1) = '';
    $str;
}

sub read_cgi_data {
    my ($argv, $env, $entity) = @_;
    my ($in, $block, $n, $i, $e, $key, $value);
    $in = '';

    for (;;) {
        $block = _find(\$in, "\n");
        if (($n) = ($block =~ m/^arg (\d+)$/)) {
            $#$argv = $n - 1;
            foreach $i (0 .. $n - 1) {
                $$argv[$i] = _string(\$in);
            }
        } elsif (($n) = ($block =~ m/^env (\d+)$/)) {
            foreach $i (0 .. $n - 1) {
                $e = _string(\$in);
                if (($key, $value) = ($e =~ m/^([^=]+)=(.*)$/s)) {
                    $$env{$key} = $value;
                }
            }
        } elsif ($block =~ m/^entity$/) {
            $$entity = _string(\$in);
        } elsif ($block =~ m/^end$/) {
            last;
        } else {
            die "Unrecognized block: $block\n";
        }
    }
}

sub connection {
    my (@argv, %env, $entity);
    read_cgi_data(\@argv, \%env, \$entity);

    my $http = new Vend::Http::Server \*Vend::Server::MESSAGE, \%env, $entity;

    ::dispatch($http);
}

## Signals

my $Signal_Terminate;
my $Signal_Debug;
my $Signal_Restart;
my %orig_signal;
my @trapped_signals = qw(HUP INT TERM USR1 USR2);
$Vend::Server::Num_servers = 0;

# might also trap: QUIT

my ($Routine_USR1, $Routine_USR2, $Routine_HUP, $Routine_TERM, $Routine_INT);
my ($Sig_inc, $Sig_dec, $Counter);

$Routine_USR1 = sub { $SIG{USR1} = $Routine_USR1; $Vend::Server::Num_servers++};
$Routine_USR2 = sub { $SIG{USR2} = $Routine_USR2; $Vend::Server::Num_servers--};
$Routine_HUP  = sub { $SIG{HUP} = $Routine_HUP; $Signal_Restart = 1};
$Routine_TERM = sub { $SIG{TERM} = $Routine_TERM; $Signal_Terminate = 1 };
$Routine_INT  = sub { $SIG{INT} = $Routine_INT; $Signal_Terminate = 1 };

sub setup_signals {
    @orig_signal{@trapped_signals} =
        map(defined $_ ? $_ : 'DEFAULT', @SIG{@trapped_signals});
    $Signal_Terminate = $Signal_Debug = '';
    $SIG{'HUP'}  = 'IGNORE';
    $SIG{'PIPE'} = 'IGNORE';

	if($Config{'osname'} eq 'irix' or ! $Config{d_sigaction}) {
		$SIG{'INT'}  = $Routine_INT;
		$SIG{'TERM'} = $Routine_TERM;
		$SIG{'USR1'} = $Routine_USR1;
		$SIG{'USR2'} = $Routine_USR2;
	}

	else {
		$SIG{'INT'}  = sub { $Signal_Terminate = 1; };
		$SIG{'TERM'} = sub { $Signal_Terminate = 1; };
		$SIG{'HUP'}  = sub { $Signal_Restart = 1; };
		$SIG{'USR1'} = sub { $Vend::Server::Num_servers++; };
		$SIG{'USR2'} = sub { $Vend::Server::Num_servers--; };
	}

    if(! $Global::SafeSignals or $Config{'osname'} =~ /bsd/) {
        require File::CounterFile;
        my $filename = "$Global::ConfDir/process.counter";
        unlink $filename;
        $Counter = new File::CounterFile $filename;
        $Sig_inc = sub { $Vend::Server::Num_servers = $Counter->inc(); };
        $Sig_dec = sub { $Vend::Server::Num_servers = $Counter->dec(); };
    }
    else {
        $Sig_inc = sub { kill "USR1", $Vend::MasterProcess; };
        $Sig_dec = sub { kill "USR2", $Vend::MasterProcess; };
    }

}

sub restore_signals {
    @SIG{@trapped_signals} = @orig_signal{@trapped_signals};
}

my $Last_housekeeping = 0;

# Reconfigure any catalogs that have requested it, and 
# check to make sure we haven't too many running servers
sub housekeeping {
	my ($tick) = @_;
	my $now = time;
	rand();

	# Always do it if called without argument, otherwise
	# only after $tick seconds
	if (defined $tick) {
		return if ($now - $Last_housekeeping < $tick);
	}

	$Last_housekeeping = $now;

	my ($c, $num,$reconfig, $restart, @files);

		opendir(Vend::Server::CHECKRUN, $Global::ConfDir)
			or die "opendir $Global::ConfDir: $!\n";
		@files = readdir Vend::Server::CHECKRUN;
		closedir(Vend::Server::CHECKRUN)
			or die "closedir $Global::ConfDir: $!\n";
		($reconfig) = grep $_ eq 'reconfig', @files;
		($restart) = grep $_ eq 'restart', @files
			if $Signal_Restart;
		if (defined $restart) {
			$Signal_Restart = 0;
			open(Vend::Server::RESTART, "+<$Global::ConfDir/restart")
				or die "open $Global::ConfDir/restart: $!\n";
			lockfile(\*Vend::Server::RESTART, 1, 1)
				or die "lock $Global::ConfDir/restart: $!\n";
			while(<Vend::Server::RESTART>) {
				chomp;
				my ($directive,$value) = split /\s+/, $_, 2;
				if($value =~ /<<(.*)/) {
					my $mark = $1;
					$value = Vend::Config::read_here(\*Vend::Server::RESTART, $mark);
					unless (defined $value) {
						logGlobal(<<EOF);
Global reconfig ERROR
Can't find string terminator "$mark" anywhere before EOF.
EOF
						last;
					}
					chomp $value;
				}
				eval {
					if($directive =~ /^\s*(sub)?catalog$/i) {
						::add_catalog("$directive $value");
					}
					elsif($directive =~ /^remove\s+catalog\s+(\S+)$/i) {
						::remove_catalog($1);
					}
					else {
						::change_global_directive($directive, $value);
					}
				};
				if($@) {
					logGlobal(@_);
					last;
				}
			}
			unlockfile(\*Vend::Server::RESTART)
				or die "unlock $Global::ConfDir/restart: $!\n";
			close(Vend::Server::RESTART)
				or die "close $Global::ConfDir/restart: $!\n";
			unlink "$Global::ConfDir/restart"
				or die "unlink $Global::ConfDir/restart: $!\n";
		}
		if (defined $reconfig) {
			open(Vend::Server::RECONFIG, "+<$Global::ConfDir/reconfig")
				or die "open $Global::ConfDir/reconfig: $!\n";
			lockfile(\*Vend::Server::RECONFIG, 1, 1)
				or die "lock $Global::ConfDir/reconfig: $!\n";
			while(<Vend::Server::RECONFIG>) {
				chomp;
				my ($script_name,$build) = split /\s+/, $_;
                my $cat = $Global::Selector{$script_name};
                unless (defined $cat) {
                    logGlobal(<<EOF);
Bad script name '$script_name' for reconfig.
EOF
                    next;
                }
                $c = ::config_named_catalog($cat->{'CatalogName'},
                                    "from running server ($$)", $build);
				if (defined $c) {
					$Global::Selector{$script_name} = $c;
					for(sort keys %Global::SelectorAlias) {
						next unless $Global::SelectorAlias{$_} eq $script_name;
						$Global::Selector{$_} = $c;
					}
					logGlobal "Reconfig of $c->{CatalogName} successful, build=$build.";
				}
				else {
					logGlobal <<EOF;
Error reconfiguring catalog $script_name from running server ($$):
$@
EOF
				}
			}
			unlockfile(\*Vend::Server::RECONFIG)
				or die "unlock $Global::ConfDir/reconfig: $!\n";
			close(Vend::Server::RECONFIG)
				or die "close $Global::ConfDir/reconfig: $!\n";
			unlink "$Global::ConfDir/reconfig"
				or die "unlink $Global::ConfDir/reconfig: $!\n";
		}

}

# The servers for both are now combined
# Can have both INET and UNIX on same system
sub server_both {
    my ($socket_filename) = @_;
    my ($n, $rin, $rout, $pid, $tick, $max_servers);

	$Vend::MasterProcess = $$;

	$max_servers = $Global::MaxServers   || 4;
	$tick        = $Global::HouseKeeping || 60;

    setup_signals();


	my $port = $Global::TcpPort || 7786;
	my $host = $Global::TcpHost || '127.0.0.1';
	my $proto = getprotobyname('tcp');

# DEBUG
#Vend::Util::logDebug
#("Starting server socket file='$socket_filename' tcpport=$port hosts='$host'\n")
#	if ::debug($Global::DHASH{SERVER});
# END DEBUG
	unlink $socket_filename;

	my $vector = '';
	my $spawn;

	my $so_max;
	if(defined &SOMAXCONN) {
		$so_max = SOMAXCONN;
	}
	else {
		$so_max = 128;
	}

	unlink "$Global::ConfDir/mode.inet", "$Global::ConfDir/mode.unix";

	if($Global::Unix_Mode) {
		socket(Vend::Server::USOCKET, AF_UNIX, SOCK_STREAM, 0) || die "socket: $!";

		setsockopt(Vend::Server::USOCKET, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));

		bind(Vend::Server::USOCKET, pack("S", AF_UNIX) . $socket_filename . chr(0))
			or die "Could not bind (open as a socket) '$socket_filename':\n$!\n";
		listen(Vend::Server::USOCKET,$so_max) or die "listen: $!";

		$rin = '';
		vec($rin, fileno(Vend::Server::USOCKET), 1) = 1;
		$vector |= $rin;
		open(Vend::Server::INET_MODE_INDICATOR, ">$Global::ConfDir/mode.unix")
			or die "creat mode.inet: $!";
		close(Vend::Server::INET_MODE_INDICATOR);

		chmod 0600, $socket_filename;

		#DEBUG or very insecure installations with no sensitive data
		chmod 0666, $socket_filename if $ENV{MINIVEND_INSECURE};

	}

	if($Global::Inet_Mode) {
		eval {
			socket(Vend::Server::ISOCKET, PF_INET, SOCK_STREAM, $proto)
					|| die "socket: $!";
			setsockopt(Vend::Server::ISOCKET, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
					|| die "setsockopt: $!";
			bind(Vend::Server::ISOCKET, sockaddr_in($port, INADDR_ANY))
					|| die "bind: $!";
			listen(Vend::Server::ISOCKET,$so_max)
					|| die "listen: $!";
		};

		if (! $@) {
			$rin = '';
			vec($rin, fileno(Vend::Server::ISOCKET), 1) = 1;
			$vector |= $rin;
			open(Vend::Server::INET_MODE_INDICATOR, ">$Global::ConfDir/mode.inet")
				or die "creat mode.inet: $!";
			close(Vend::Server::INET_MODE_INDICATOR);
		}
		elsif ($Global::Unix_Mode) {
			logGlobal "INET mode error: $@\n\nContinuing in UNIX MODE ONLY\n";
		}
		else {
			logGlobal "INET mode server failed to start: $@\n";
			logGlobal "SERVER TERMINATING";
			exit 1;
		}
	}

	my $no_fork;

	if($Global::Windows or ::debug(0x1000) ) {
# DEBUG
#print
#("Running in foreground, OS=$, debug=$Global::DEBUG\n")
#	if ::debug(0xFFFF);
# END DEBUG
		$no_fork = 1;
	}

    for (;;) {

# DEBUG
#$Global::DEBUG = $Global::DebugMode;
# END DEBUG

	  eval {
        $rin = $vector;
		undef $spawn;
        $n = select($rout = $rin, undef, undef, $tick);

        if ($n == -1) {
            if ($! =~ m/^Interrupted/) {
                # if ($Signal_Debug) {
                #    $Signal_Debug = 0;
                #    debug();
                # }
                # elsif
                if ($Signal_Terminate) {
                    last;
                }
            }
            else {
				my $msg = $!;
				logGlobal("error '$msg' from select.");
                die "select: $msg\n";
            }
        }

        elsif (	$Global::Inet_Mode && vec($rout, fileno(Vend::Server::ISOCKET), 1) ) {
            my $ok = accept(Vend::Server::MESSAGE, Vend::Server::ISOCKET);
            die "accept: $!" unless defined $ok;
			$spawn = 1;
		}
        elsif (	$Global::Unix_Mode && vec($rout, fileno(Vend::Server::USOCKET), 1) ) {
            my $ok = accept(Vend::Server::MESSAGE, Vend::Server::USOCKET);
            die "accept: $!" unless defined $ok;
			$spawn = 1;
		}
		elsif($n == 0) {
			housekeeping();
		}
        else {
            die "Why did select return with $n?";
        }
	  };
	  logGlobal("Died in select, retrying: $@") if $@;


	  eval {
		SPAWN: {
			last SPAWN unless defined $spawn;
# DEBUG
#Vend::Util::logDebug
#("Spawning connection, " .
#	($no_fork ? 'no fork, ' : 'forked, ') .  scalar localtime() . "\n")
#	if ::debug($Global::DHASH{SERVER});
# END DEBUG
			if(defined $no_fork) {
				$Vend::NoFork = {};
				connection();
				undef $Vend::NoFork;
			}
			elsif(! defined ($pid = fork) ) {
				logGlobal ("Can't fork: $!");
				die ("Can't fork: $!");
			}
			elsif (! $pid) {
				#fork again
				unless ($pid = fork) {

					eval { 
						&$Sig_inc;
						connection();
					};
					if ($@) {
						my $msg = $@;
						logGlobal("Runtime error: $msg");
						logError("Runtime error: $msg")
					}

					select(undef,undef,undef,0.050) until getppid == 1;
					&$Sig_dec;
					exit(0);
				}
				exit(0);
			}
			close Vend::Server::MESSAGE;
			last SPAWN if $no_fork;
			wait;
		}
	  };

		# clean up dies during spawn
		if ($@) {
			logGlobal("Died in server spawn: $@\n") if $@;

			# Below only happens with Windows or foreground debugs.
			# Prevent corruption of changed $Vend::Cfg entries
			# (only VendURL/SecureURL at this point).
			if($Vend::Save and $Vend::Cfg) {
				Vend::Util::copyref($Vend::Save, $Vend::Cfg);
				undef $Vend::Save;
				undef $Vend::Cfg;
			}
		}

		last if $Signal_Terminate || $Signal_Debug;

	  eval {
        for(;;) {
		   housekeeping($tick);
           last if $Vend::Server::Num_servers < $max_servers;
           select(undef,undef,undef,0.300);
           last if $Signal_Terminate || $Signal_Debug;
        }

	  };
	  logGlobal("Died in housekeeping, retry.\n") if $@;


    }

    close(Vend::Server::SOCKET);
    restore_signals();

   	if ($Signal_Terminate) {
       	logGlobal("STOP server ($$) on signal TERM");
       	return 'terminate';
   	}

    return '';
}

 sub debug {
     my ($x, $y);
     for (;;) {
         print "> ";
         $x = <STDIN>;
         return if $x eq "\n";
         $y = eval $x;
         if ($@) {
             print $@, "\n";
         }
         else {
             print "$y\n";
         }
     }
 }


sub grab_pid {
    my $ok = lockfile(\*Vend::Server::Pid, 1, 0);
    if (not $ok) {
        chomp(my $pid = <Vend::Server::Pid>);
        return $pid;
    }
    {
        no strict 'subs';
        truncate(Vend::Server::Pid, 0) or die "Couldn't truncate pid file: $!\n";
    }
    print Vend::Server::Pid $$, "\n";
    return 0;
}



sub open_pid {

	$Pidfile = $Global::ConfDir . "/minivend.pid";
    open(Vend::Server::Pid, "+>>$Pidfile")
        or die "Couldn't open '$Pidfile': $!\n";
    seek(Vend::Server::Pid, 0, 0);
    my $o = select(Vend::Server::Pid);
    $| = 1;
    {
        no strict 'refs';
        select($o);
    }
}

sub run_server {
    my $next;
    my $pid;
	my $silent = 0;
	
    open_pid();

	unless($Global::Inet_Mode || $Global::Unix_Mode || $Global::Windows) {
		$Global::Inet_Mode = $Global::Unix_Mode = 1;
	}
	elsif ( $Global::Windows ) {
		$Global::Inet_Mode = 1;
	}

	my @types;
	push (@types, 'INET') if $Global::Inet_Mode;
	push (@types, 'UNIX') if $Global::Unix_Mode;
	my $server_type = join(" and ", @types);

    if ($Global::Windows || ::debug(4096) ) {
        $pid = grab_pid();
        if ($pid) {
            print "The MiniVend server is already running ".
                "(process id $pid)\n";
            exit 1;
        }

        print "MiniVend server started ($$) ($server_type)\n";
		$next = server_both($LINK_FILE);
    }

    else {

        fcntl(Vend::Server::Pid, F_SETFD, 0)
            or die "Can't fcntl close-on-exec flag for '$Pidfile': $!\n";
        my ($pid1, $pid2);
        if ($pid1 = fork) {
            # parent
            wait;
            exit 0;
        }
        elsif (not defined $pid1) {
            # fork error
            print "Can't fork: $!\n";
            exit 1;
        }
        else {
            # child 1
            if ($pid2 = fork) {
                # still child 1
                exit 0;
            }
            elsif (not defined $pid2) {
                print "child 1 can't fork: $!\n";
                exit 1;
            }
            else {
                # child 2
                sleep 1 until getppid == 1;

                $pid = grab_pid();
                if ($pid) {
                    print "The MiniVend server is already running ".
                        "(process id $pid)\n"
						unless $silent;
                    exit 1;
                }
                print "MiniVend server started in $server_type mode(s) (process id $$)\n"
					unless $silent;

                close(STDIN);
                close(STDOUT);
                close(STDERR);

				if($Global::DEBUG & 2048) {
					$Global::DEBUG = $Global::DEBUG || 255;
					open(Vend::DEBUG, ">>$Global::ConfDir/mvdebug");
					select Vend::DEBUG;
					print "Start DEBUG at " . localtime() . "\n";
					$| =1;
				}
				elsif (!$Global::DEBUG) {
					# May as well turn warnings off, not going anywhere
					$ = 0;
				}

                open(STDOUT, ">&Vend::DEBUG");
				select(STDOUT);
                $| = 1;
                open(STDERR, ">&Vend::DEBUG");
                select(STDERR); $| = 1; select(STDOUT);

                logGlobal("START server ($$) ($server_type)");

                setsid();

                fcntl(Vend::Server::Pid, F_SETFD, 1)
                    or die "Can't fcntl close-on-exec flag for '$Pidfile': $!\n";

				$next = server_both($LINK_FILE);

				unlockfile(\*Vend::Server::Pid);
				opendir(CONFDIR, $Global::ConfDir) 
					or die "Couldn't open directory $Global::ConfDir: $!\n";
				my @running = grep /^mvrunning/, readdir CONFDIR;
				for(@running) {
					unlink "$Global::ConfDir/$_" or die
						"Couldn't unlink status file $Global::ConfDir/$_: $!\n";
				}
				unlink $Pidfile;
                exit 0;
            }
        }
    }                
}

1;
__END__
