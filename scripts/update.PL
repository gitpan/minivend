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
# update - MiniVend database updater
#
# $Id: update,v 1.4 2000/03/02 10:35:09 mike Exp $
#
# Copyright 1996-2000 by Michael J. Heins <mikeh@minivend.com>
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

    eval {
        require 5.004;
        require FindBin;
        1 and $Global::VendRoot = "$FindBin::RealBin";
        1 and $Global::VendRoot =~ s/.bin$//;
    };
	($Global::VendRoot = $ENV{MINIVEND_ROOT})
		if defined $ENV{MINIVEND_ROOT};
	$Global::VendRoot = $Global::VendRoot || '/usr/local/minivend';
#	$Global::VendRoot = $Global::VendRoot || '~_~INSTALLARCHLIB~_~';
}
### END CONFIGURABLE VARIABLES

sub dontwarn { $FindBin::RealBin; }

$Global::ConfigFile = 'minivend.cfg';
$Global::ErrorFile = "$Global::VendRoot/error.log";
$Vend::ExternalProgram = 1;

my $DEBUG = 0;

use strict;
use Fcntl;

#select a DBM

BEGIN {
	$Global::GDBM = $Global::DB_File = 0;
    AUTO: {
        last AUTO if
            (defined $ENV{MINIVEND_DBFILE} and $Global::DB_File = 1);
        last AUTO if
			(defined $ENV{MINIVEND_NODBM});
        eval {require GDBM_File and $Global::GDBM = 1};
        eval {require DB_File and $Global::DB_File = 1};
    }
	if($Global::GDBM) {
		require Vend::Table::GDBM;
		import GDBM_File;
		$Global::GDBM = 1;
		$Global::Default_database = 'GDBM';
	}
	if($Global::DB_File) {
		require Vend::Table::DB_File;
		import DB_File;
		$Global::DB_File = 1;
		$Global::Default_database = 'DB_FILE'
			unless defined $Global::Default_database;
	}
	if(! $Global::GDBM and ! $Global::DB_File) {
		die "No DBM defined! Update not designed to work with DBI or memory databases.\n";
	}
}

use Vend::Config;
use Vend::Data;
use Vend::Util;

$Vend::Cfg = {};

my $Name = 'products';
my $Directory;

my $USAGE = <<EOF;
usage: update -c catalog [-n name] \\
            -f field [-f field1 -f field2 ...] -k key value [value1 value2 ...]
    or

usage: update -c catalog -i inputfile [-n name]

Options:

  -c catalog    Catalog name as defined in minivend.cfg.
  -f field      Field name(s) in database. If multiple fields are specified,
                multiple corresponding values must be supplied.  Use '' to
                set to the empty string.
  -i file       Input file to add entries to an existing database. (Must
                be in same format/order as existing database.)
  -k key        Key (item code) to be updated.
  -n name       Database name as defined in catalog.cfg (default products).

If specifying a subcatalog database, make sure it is defined in the
subcatalog definition.  If it is in the base catalog, use that catalog
as the parameter for the -c directive.
EOF

my ($Inputfile, $Key, @Fields, @Values);
my ($Catalog,$delimiter,$db);

GETOPT: {

	if($ARGV[0] eq '-c') {
		shift(@ARGV);
		$Catalog = shift(@ARGV);
		redo GETOPT;
	}
	elsif($ARGV[0] eq '-d') {
		shift(@ARGV);
		$Directory = shift(@ARGV);
		redo GETOPT;
	}
	elsif($ARGV[0] eq '-n') {
		shift(@ARGV);
		$Name = shift(@ARGV);
		redo GETOPT;
	}
	elsif($ARGV[0] eq '-k') {
		shift(@ARGV);
		$Key = shift(@ARGV);
		redo GETOPT;
	}
	elsif($ARGV[0] eq '-i') {
		shift(@ARGV);
		$Inputfile = shift(@ARGV);
		redo GETOPT;
	}
	elsif($ARGV[0] eq '-f') {
		shift(@ARGV);
		push(@Fields, shift @ARGV); 
		redo GETOPT;
	}

} # END GETOPT

die $USAGE unless defined $Catalog;

push @Values, @ARGV;

if(@Fields and ! @Values) {
	die $USAGE . "\n";
}
elsif (scalar(@Fields) != scalar(@Values) ) {
	die "Number of fields and number of values don't match.\n" . $USAGE . "\n";
}
elsif ((@Fields or @Values) and defined $Inputfile) {
	die "No field or value arguments accepted when inputting from a file.\n" .
	$USAGE . "\n";
}
elsif (@Fields and ! $Key) {
	die $USAGE . "\n";
}
elsif (!defined $Inputfile and ! @Fields and !@Values) {
	die $USAGE . "\n";
}

my($name,$dir,$param,$subcat,$subconfig);
chdir $Global::VendRoot;
open(GLOBAL, $Global::ConfigFile) or
    die "No global configuration file? Aborting.\n";
while(<GLOBAL>) {
    next unless /^\s*(sub)?catalog\s+$Catalog\s+/i;
    $subcat = $1 || '';
    chomp;
    s/^\s+//;
    unless($subcat) {
        (undef,$name,$dir,$param) = split /\s+/, $_, 4;
    }
    else {
        (undef,$name,$subconfig,$dir,$param) = split /\s+/, $_, 5;
    }
    last;

}
close GLOBAL;

global_config();

chdir $dir or die "Couldn't change directory to $dir: $!\n";

$Vend::Cfg = config($name, $dir, "$dir/etc", ($subconfig || undef));
$::Variable = $Vend::Cfg->{Variable};

die "Problems with config.\n" unless defined $Vend::Cfg;

$Vend::Cfg->{ProductDir} = $Directory
	if defined $Directory;

die "Bad data directory $Vend::Cfg->{ProductDir} -- doesn't exist.\n$USAGE\n"
	unless -d $Vend::Cfg->{ProductDir};

open_database(1);

$Vend::WriteDatabase{$Name} = 1;

die "Bad database $Name -- doesn't exist.\n\n$USAGE\n"
	unless $db = database_exists_ref($Name);

my $ref;
eval {
	$ref = $db->ref();
};

die "Bad open of database $Name from catalog $Catalog ($!): $@\n"
	unless $ref and ! $@;

unless($ref->record_exists($Key)) {
	die "Key $Key not found in database $Name.\n";
}

my ($key,$field,@fields);

my $key_col = $Vend::Table::Common::KEY_IDX;

if (! defined $Inputfile ) {
	foreach $field (@Fields) {
		unless ( defined $ref->test_column($field) ) {
			die "$field is not a column in the database.\n";
		}
		my $val = shift @Values;
print "setting ${Name}::${field}::$Key=$val\n";
		$ref->set_field($Key, $field, $val);
	}
}
else {
	open INPUT, $Inputfile or die "Couldn't open input file $Inputfile: $!\n";
	while(<INPUT>) {
		chomp;
		s/[\r\cZ]+//;
		(@fields) = split /\t/, $_;
		$key = $fields[$key_col];
		$ref->set_row($key, @fields);
	}
	close INPUT;
}

close_database();

=head1 NAME

update -- command line setting of Minivend databases

=head1 VERSION

1.0

=head1 SYNOPSIS

   update -c catalog [-f field -k key [-t table] value]

=head1 DESCRIPTION

Minivend's C<update> is a rudimentary method of directly setting the
DBM files (not the ASCII files) of a MiniVend DBM database.

NOTE: This command DOES NOT APPLY TO SQL databases. They have their own
command line monitors that are more flexible.

=head1 OPTIONS

=over 4

=item -c name

Sets the catalog for which C<update> operates. It reads the
catalog.cfg file to retrieve database settings. 

=item -f field

The name of the field to set.

=item -n name

The name of the table to set. If the table is not a DBM database the
C<update> program will terminate with an error.

=back

=head1 SEE ALSO

http://www.minivend.com

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
