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
# MiniVend link program configurator
#
# $Id: compile_link,v 1.4 2000/03/02 10:34:12 mike Exp $
#
# Copyright 1996-2000 by Michael J. Heins <mikeh@minivend.com>
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

use Getopt::Long;
use Config;

my $Self = {
	LINK_HOST      => 'localhost',
	LINK_PORT      => 7786,
	LINK_TIMEOUT   => 30,
	LINK_FILE      => '/usr/local/minivend/etc/socket',
#	LINK_FILE      => '~_~INSTALLARCHLIB~_~/etc/socket',
	SRC_DIR        => '/usr/local/minivend/src',
#	SRC_DIR        => '~_~INSTALLARCHLIB~_~/src',
	INSTALLPRIVLIB => '/usr/local/minivend/lib',
#	INSTALLPRIVLIB => '~_~INSTALLPRIVLIB~_~',
	INSTALLARCHLIB => '/usr/local/minivend',
#	INSTALLARCHLIB => '~_~INSTALLARCHLIB~_~',
	INSTALLMAN1DIR => '/usr/local/minivend/doc',
#	INSTALLMAN1DIR => '~_~INSTALLMAN1DIR~_~',
	INSTALLSCRIPT => '/usr/local/minivend/bin',
#	INSTALLSCRIPT => '~_~INSTALLARCHLIB~_~/bin',
	INSTALLBIN => '/usr/local/minivend/bin',
#	INSTALLBIN => '~_~INSTALLBIN~_~',
};


my $prog = $0;
$prog =~ s:.*/::;
my $USAGE = <<EOF;
usage: $prog [-t tcp_port] [-s sockfile] [-h host] [-w secs] \
             [--perl] [-o outputfile] [--suid]

Configures a Minivend link program.

options:

  -b dir, --build=dir   Alternate build directory
                         (default $Self->{SRC_DIR})
  -f, --force           Force compile even if already there
  -h host, --host=host  Name of host the TCP link should contact
                         (default $Self->{LINK_HOST})
  -i, --inetmode        Copy the tlink file to outputfile
  -n, --nostrip         Don't try and strip(1) the executable files
  -o cgifile,           Write it to a specific file as well as the
     --output=cgifile    link catalog directory
  -s socketfile,        Location of UNIX socket (default
      --socket=file      $Self->{INSTALLARCHLIB}/etc/socket)
  -t port, --port=port  Port number to use (default $Self->{LINK_PORT})
  -w N, --timeout=N     Number of seconds before timeout (default $Self->{LINK_TIMEOUT})
  -u, --unixmode        Copy the vlink file to outputfile (default)
  --nosuid              Don't change mode to suid for vlink (CGIWRAP)
  --perl                Use Perl tlink program
  --source              Alterate source dir (default $Self->{SRC_DIR})
EOF

Getopt::Long::config(qw/permute/);

my $Output;
my $Force;
my @Flags;
my $Inet;
my $Unix;
my $NoSUID;
my $Nostrip;
my $Perl_tlink;
my $Build_dir;

my %optctl = (

    'port'          => \ $Self->{LINK_PORT},
    'timeout'       => \ $Self->{LINK_TIMEOUT},
    'host'          => \ $Self->{LINK_HOST},
    'socket'        => \ $Self->{LINK_FILE},
    'build'         => \ $Build_dir,
    'source'        => \ $Self->{SRC_DIR},
    'inetmode'      => \ $Inet,
    'unixmode'      => \ $Unix,
    'nosuid'        => \ $NoSUID,
    'nostrip'       => \ $Nostrip,
    'perl'          => \ $Perl_tlink,
    'force'         => \ $Force,
    'outputfile'    => \ $Output,
	'<>'			=> sub {
							push @Flags, shift;
						},
);

my @options = ( qw/

    port|p=i
    timeout|w=i
    host|h=s
	socket|s=s
	inetmode|i
	unixmode|u
	nostrip|n
	perl
	force|f
    build|b=s
    source=s
	outputfile|o=s
    <>

/ );

GetOptions(\%optctl, @options)			or die "\n$USAGE\n";

sub doit {
	my ($self, $orig, $template, $preamble, $key, $postamble) = @_;
	my $replace =  $Self->{$key} || $Config{$key};
#warn <<EOF;
#orig=$orig
#template=$template
#key=$key
#replace=$replace
#EOF
	return "$orig$template" unless defined $replace;
	return "$preamble$replace$postamble$template";
}

use File::Copy;

if($Build_dir) {
	if (-e $Build_dir and (! -d _ or ! -w _)) {
		die "Cannot use $Build_dir for build directory.\n";
	}
	elsif (! -d $Build_dir) {
		mkdir $Build_dir, 0777
			or die "Could not make directory $Build_dir: $!\n";
	}
	my @files = glob("$Self->{SRC_DIR}/*");
	for(@files) {
		next unless -f $_;
		File::Copy::copy($_, $Build_dir)
			or die "copy $_ to $Build_dir: $!\n";
	}
	chdir $Build_dir
		or die "Couldn't change to build directory: $!\n";
}
else {
	chdir $Self->{SRC_DIR}
		or die "Couldn't change to source directory: $!\n";
}

if(! $Perl_tlink and ! -f "config.h" || ! -f "syscfg") {
	system "./configure";
	if($?) {
		die "Couldn't run configure; probably no C compiler.\n";
	}
}

my @edit_files = qw/config.h tlink.pl vlink.pl/;

foreach my $targ (@edit_files) {
	my $src = "$targ.tmp";
	rename $targ, $src
		or die "Couldn't rename $targ to $src: $!\n";
	open (IN, $src)
		or die "Couldn't read $src: $!\n";
	open (OUT, ">$targ")
		or die "Couldn't write $targ: $!\n";
	local($/);
	$_ = <IN>;
	close IN;
	s{(~@~(\w+)~@~)}{doit($Self, $1, '', '', $2, '')}eg;
	s{(.*)(\n[ 	]*#(.*)~_~(\w+)~_~(.*))}{doit($Self, $1, $2, $3, $4, $5)}eg;
	s{(.*)(\n[ 	]*/\*(.*)~_~(\w+)~_~(.*)\*/)}{doit($Self, $1, $2, $3, $4, $5)}eg;
	print OUT $_;
	close OUT or die "close $targ: $!\n";
	unlink $src;
}

my $Intermediate;

COMPILE: {

	use vars qw/$CC $DEFS $LIBS $CFLAGS/;

	if($Perl_tlink) {
		$Intermediate = 'tlink.pl.$Self->{LINK_HOST}.$Self->{LINK_PORT}';
		$Intermediate =~ s/\W/./g;
		File::Copy::copy('tlink.pl', $Intermediate)
			or die "Cannot write intermediate file $Intermediate: $!\n";
		File::Copy::copy('tlink.pl', 'tlink')
			or die "Cannot write tlink: $!\n";
		chmod 0755, 'tlink';
		undef $Unix;
		$Inet = 1;
		last COMPILE;
	}
	elsif($Inet) {
		undef $Unix;
	}

	# Compile

	my $vlink_file = $Self->{LINK_FILE};
	$vlink_file =~ s/[^A-Za-z0-9.]/_/g;
	$vlink_file = "vlink.$vlink_file";

	my $tlink_file = "tlink.$Self->{LINK_HOST}.$Self->{LINK_PORT}";
	$tlink_file =~ s/\W/./g;

	$Intermediate = $Inet ? $tlink_file : $vlink_file;

	unlink $Intermediate if $Force;

	do "syscfg";
	if(! -f $vlink_file) {
		system "$CC $CFLAGS $DEFS $LIBS vlink.c -o $vlink_file";
		if($?) {
			warn "Problem compiling $vlink_file.\n";
		}
		else {
			system "strip $vlink_file"
				unless $Nostrip;
			File::Copy::copy($vlink_file, 'vlink');
			chmod 0755, 'vlink';
		}
	}
	else {
		print "Skipping compile of $vlink_file, already done.\n";
		File::Copy::copy($vlink_file, 'vlink');
		chmod 0755, 'vlink';
	}
	if(! -f $tlink_file) {
		system "$CC $CFLAGS $DEFS $LIBS tlink.c -o $tlink_file";
		if($?) {
			warn "Problem compiling $tlink_file.\n";
		}
		else {
			system "strip $tlink_file"
				unless $Nostrip;
			File::Copy::copy($tlink_file, 'tlink');
			chmod 0755, 'tlink';
		}
	}
	else {
		print "Skipping compile of $tlink_file, already done.\n";
		File::Copy::copy($tlink_file, 'tlink');
		chmod 0755, 'tlink';
	}

	if(! -f $Intermediate) {
		die "Couldn't compile your choice of link '$Intermediate'\n";
	}
}

if($Output) {
	if (-e $Output and ! $Force) {
		my $ans;
		print "Output file $Output exists. Overwrite? [y/N] ";
		$ans = <>;
		exit unless $ans =~ /^\s*y/i;
	}
	if(! -w $Output) {
		print "Output file $Output not writable. Overwrite? [y/N] ";
		
	}
	File::Copy::copy($Intermediate, $Output)
		or die "Cannot write output file $Output: $!\n";
	if($Unix and ! $NoSUID) {
		chmod 04755, $Output
			or die "couldn't make $Output SUID: $!\n";
	}
}

=head1 NAME

compile_link -- compile and copy MiniVend link CGI

=head1 VERSION

1.0

=head1 SYNOPSIS

   compile_link [-p NNNN] [-s sfile] [-h host] [-w N] \\
	        [--perl] [-nf] [-o outputfile] [-b dir] [-s dir]

=head1 DESCRIPTION

The C<compile_link> program configures (including compilation if
necessary) a link CGI for talking to the MiniVend server daemon.

If the --perl option is given, it will not compile but instead use the
tlink.pl program, setting its variables as needed.

Designed to be used in conjunction with MiniVend's makecat.

=head1 OPTIONS

=over 4

=item -b dir, --build=dir

Sets the directory where the build files will be made. Default is C<src> in
the Minivend software directory.

=item -h hostname, --host=hostname

Sets the host address or host name that should be compiled into the
TCP-based link program.  This sets the default, which still can be
overridden by C<MINIVEND_HOST> in the environment of the executing process.

=item -p NNNN, --port=NNNN

Sets the port number that should be compiled into the TCP-based link program.
This sets the default, which still can be overridden by C<MINIVEND_PORT> in the
environment of the executing process. The port must be higher than 1024.

=item -s sfile, --socket=sfile

The name of the UNIX-domain socket file which should be compiled into the
UNIX-domain link program. This sets the default, which still can be
overridden by C<MINIVEND_SOCKET> in the environment of the executing process. 

=item --source=dir

Sets the directory containing the source files. Default is C<src> in
the Minivend software directory.

=item -w N, --timeout=N

The number of seconds the link program should wait for a connection before
sending its timeout page.


=back

=head1 SEE ALSO

makecat(1), http://www.minivend.com

=head1 AUTHOR

Mike Heins, <mikeh@minivend.com>


_EoP_
	s{.*\n(#(.*)~_~(\w+)~_~(.*))}{$2 . doit($3) . "$4\n$1"}eg;
	my $file = $0;
	$file =~ s/\.PL$//;
	open(OUT, ">$file") 
		or die "Create $file: $!\n";
	print OUT $_;
}
