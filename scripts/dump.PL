#$self = {
#	INSTALLPRIVLIB => '/usr/local/minivend/lib',
#	INSTALLARCHLIB => '/usr/local/minivend',
#};

use Config;
require 'scripts/initp.pl';

sub doit {
	my ($key) = @_;
	my $val;
	if ($MV::Self->{RPMBUILDDIR} and $val = $MV::Self->{$key}) {
		$val =~ s!^$MV::Self->{RPMBUILDDIR}/!/!; 
		return $val;
	}
	return $MV::Self->{$key} unless $key =~ /[a-z]/;
	return $Config{$key};
}

DOIT: {
	local ($/);
	local($_) = <<'_EoP_';
#!/usr/bin/perl
##!~_~perlpath~_~
#
# MiniVend session dumper
#
# $Id: dump,v 1.4 2000/03/02 10:34:28 mike Exp $
#
# Copyright 1996-2000 by Michael J. Heins <mikeh@minivend.com>
#
# This program was originally based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# See the file 'Changes' for information.
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
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA.

use lib '/usr/local/minivend/lib';
#use lib '~_~INSTALLPRIVLIB~_~';
use lib '/usr/local/minivend';
#use lib '~_~INSTALLARCHLIB~_~';

BEGIN {

	($Global::VendRoot = $ENV{MINIVEND_ROOT})
		if defined $ENV{MINIVEND_ROOT};

$Global::VendRoot = $Global::VendRoot || '/usr/local/minivend';
#$Global::VendRoot = $Global::VendRoot || '~_~INSTALLARCHLIB~_~';
	$Global::ErrorFile = "$Global::VendRoot/error.log";
	$ENV{MINIVEND_STORABLE} = 1
		if -f "$Global::VendRoot/_session_storable";
	$ENV{MINIVEND_STORABLE_DB} = 1
		if -f "$Global::VendRoot/_db_storable";
}

### END CONFIGURABLE VARIABLES

sub debug { return undef }
sub dontwarn { $FindBin::RealBin; }

$Global::ConfigFile = 'minivend.cfg';
$Global::HammerLock = 20;
$Vend::ExternalProgram = 1;

$Vend::SessionID = 'dumpprog';

use strict;
use Fcntl;

#select a DBM

# Will be set if GDBM or DB_File

my $Extension;

BEGIN {
	$Global::GDBM = $Global::DB_File = $Global::NDBM = 0;
	$Extension = '';
    AUTO: {
        eval {require GDBM_File and $Global::GDBM = 1};
        eval {require DB_File and $Global::DB_File = 1};
    }
	if($Global::GDBM) {
		require Vend::Table::GDBM;
		import GDBM_File;
		$Global::GDBM = 1;
		$Extension = '.gdbm';
	}
	if($Global::DB_File) {
		require Vend::Table::DB_File;
		import DB_File;
		$Global::DB_File = 1;
		$Extension = '.db';
	}
	else {
		die "No DBM defined! (File sessions can be viewed without this program.)\n";
	}
}

use Vend::Session;
use Vend::Util;
use Vend::Config;

my $USAGE = <<EOF;
usage: dump -c catalog [-n session_id]
           or
       dump sessionfile [sessionfile.lock]

If specifying a subcatalog database, make sure SessionFile and
SessionLockFile are defined in the subcatalog configuration
file.  If it is in the base catalog, use that catalog as the
parameter for the -c directive.
EOF

my ($catalog, $name);

$Vend::Cfg = { ErrorFile => '/dev/null' };

GETOPT: {

if($ARGV[0] eq '-c') {
	shift(@ARGV);
	$catalog = shift(@ARGV);
	redo GETOPT;
}
elsif($ARGV[0] eq '-n') {
	shift(@ARGV);
	$name = shift(@ARGV);
	redo GETOPT;
}
elsif(! defined $ARGV[0]) {
	last GETOPT;
}
else {
	$Vend::Cfg->{SessionDatabase} = shift
		|| die $USAGE;
	$Vend::Cfg->{SessionDatabase} =~ s/\.(gdbm|db)$//;
	warn "Session Database: $Vend::Cfg->{SessionDatabase}\n";
	$Vend::Cfg->{SessionLockFile} = shift;
	if (defined $Vend::Cfg->{SessionLockFile}) { 
		die <<EOF unless -f $Vend::Cfg->{SessionLockFile};
Session lock file '$Vend::Cfg->{SessionLockFile}' doesn't exist.
Create one if you are sure the MiniVend server is down, then try
again.
EOF
	}
	elsif (-f "$Vend::Cfg->{SessionDatabase}.lock") {
		$Vend::Cfg->{SessionLockFile} = 
				"$Vend::Cfg->{SessionDatabase}.lock";
	}
	else {
		my $dir = $Vend::Cfg->{SessionDatabase};
		my $file;
		$dir =~ s:/?([^/]+)$::;
		$dir = '.' unless $dir;
		$file = $1;
		die "Aborting, no lock files found, even in $dir/etc/$file.lock!\n"
			unless -f "$dir/etc/$file.lock";
		$Vend::Cfg->{SessionLockFile} ="$dir/etc/$file.lock";
	}

	last GETOPT;

}

} # END GETOPT

die "too many args, aborting.\n" 
		if @ARGV;

if(defined $catalog) {
	my($name,$dir,$param,$subcat,$subconfig,$junk);
	chdir $Global::VendRoot;
	open(GLOBAL, $Global::ConfigFile) or
		die "No global configuration file? Aborting.\n";
	while(<GLOBAL>) {
		next unless /^\s*(sub)?catalog\s+$catalog\s+/i;
		$subcat = $1 || '';
		chomp;
		s/^\s+//;
		unless($subcat) {
			($junk,$name,$dir,$param) = split /\s+/, $_, 4;
		}
		else {
			($junk,$name,$subconfig,$dir,$param) = split /\s+/, $_, 5;
		}
		last;

	}
	close GLOBAL;

	$Global::SendMailLocation = 'none';
	$Global::SysLog = '';
	$Global::ErrorFile = '/dev/null';
	global_config();

	chdir $dir or die "Couldn't change directory to $dir: $!\n";

	$Vend::Cfg = config($name, $dir, 'config', $subconfig || undef);

}

CHECKEXIST: {
	my $sessfile = $Vend::Cfg->{SessionDatabase} . $Extension;
	die "No session database $sessfile to dump.\n" unless -f $sessfile;
	die $USAGE unless defined $Vend::Cfg->{SessionLockFile};
}


Vend::Util::setup_escape_chars();
$CGI::user = 'DUMP';
$CGI::host = 'LOCAL';
$Vend::SessionName = session_name();
Vend::Session::open_session();
Vend::Session::dump_sessions($name || undef);
Vend::Session::close_session();

=head1 NAME

dump -- MiniVend session dumper

=head1 VERSION

$Id: dump,v 1.4 2000/03/02 10:34:28 mike Exp $

=head1 SEE ALSO

mvdocs(8), configdump(1), makecat(1), minivend(1)


=head1 DESCRIPTION

Skeleton POD to avoid make errors.

=cut
_EoP_
	s{.*\n(#(.*)~_~(\w+)~_~(.*))}{$2 . doit($3) . "$4\n$1"}eg;
	my $file = $0;
	$file =~ s/\.PL$//;
	open(OUT, ">$file") 
		or die "Create $file: $!\n";
	print OUT $_;
}
