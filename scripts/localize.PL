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
#
# MiniVend localizer
#
# $Id: localize,v 1.3 2000/03/02 10:34:31 mike Exp $
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

$Global::ErrorFile = "$Global::VendRoot/error.log";

### END CONFIGURABLE VARIABLES

sub dontwarn { $FindBin::RealBin; }

use Vend::Util qw(readfile escape_chars);
require Vend::Config;
use Getopt::Std;

use vars qw($opt_c $opt_d $opt_l $opt_M $opt_m $opt_o $opt_t $USAGE);
use strict;

$USAGE = <<EOF;
$0 -- produce localization file from set of pages

usage:    localize -l lg_CC [-d lg_CC] [-m file|-t] file [file2 file3 ...]

OPTIONS

    -c         Rewrite [L] sections with [LC]text[do_DO]text[/do_dO],
               adjust file and data -- mutually exclusive with -o
    -d lg_CC   Create default domain file with Locale lg_CC as prefix
    -l lg_CC   Create file with Locale lg_CC as prefix
    -m <file>  Read existing information to merge from <file>
    -M         When in -c mode, prefix MM_ to make minimate_compatible; 
               when in regular mode, strip MM_ from [LC] defs
    -o         Rewrite [L] sections with [L msgNNNN], adjust file and data
               -- mutually exclusive with -c
    -t         Two page mode, mutually exclusive with -m

lg_CC refers to the POSIX norm of specifying two-letter
language and country codes to refer to a locale.
    
Two-page mode requires two files (one for each language) to compare and
merge into one locale definition.

The merge file for the -m option should use the Perl reference form --
see the MiniVend documentation for more information.

If [L msg_key]default text[/L] keys are found, will produce a comment
with the default text for reference.

A backup file (filename.html.bak) is saved if -o is used, but only
one level. Subsequent .bak files will be overwritten.

EOF

getopts('cd:l:Mm:ot') or die "$USAGE\n";

die "$USAGE\n" if $@;
die "$USAGE\n" unless $opt_l;
die "$USAGE\n" if $opt_d && $opt_l eq $opt_d;

my $def = $opt_d || 'default';

my $Mpre = '';
if($opt_M) {
	$Mpre = 'MM_';
}

my $Uneval;

if($Data::Dumper::Version) {
	$Uneval = \&Data::Dumper::Dumper;
	$Data::Dumper::Useqq = 1;
}
else {
	$Uneval = \&Vend::Util::uneval_it;
}

my $C = {};

Vend::Config::setcat($C);

if(! $opt_m) {
	# do nothing
}
elsif ( open(CONFIG, $opt_m) ) {
	my $value;
	while (<CONFIG>) {
		chomp;
		next unless s/^\s*locale\s+//i;
		$value = $_;
        if ($value =~ /^(.*)<<(\w+)\s*/) {                  # "here" value
            my $begin  = $1 || '';
            $begin .= "\n" if $begin;
            my $mark = $2;
            my $startline = $.;
            $value = $begin . Vend::Config::read_here(\*CONFIG, $mark);
            unless (defined $value) {
                die (sprintf('%d: %s', $startline,
                    qq#no end marker ("$mark") found#));
            }
        }
		Vend::Config::parse_locale('Locale', $value);
	}
}
else {
	warn "Couldn't read merge file $opt_m, continuing without.\n";
}

$C->{Locale_repository} = {} unless $C->{Locale_repository};

my $Locale = $C->{Locale_repository};

my $one_text;
my $two_text;
my $one;
my $two;

if($opt_t) {
	$one = shift;
	$two = shift || die "$USAGE\n";
	my @one;
	my @two;
	my @comment;

	$one_text = readfile($one) or die "file $one not present or empty.\n";
	$two_text = readfile($two) or die "file $two not present or empty.\n";

	while ($one_text =~ m:\[L(\s+[\w+]\s*)?\](.*?)\[/L\]:) {
			if($1) {
				push (@one, $1);
				push (@comment, $2);
			}
			else {
				push (@one, $2);
				push (@comment, '');
			}
	}
	$two_text =~ s:\[L\](.*?)\[/L\]:push (@two, $1):eg;

	print "Locale $opt_l <<EOF\n";
	print "{\n";
	my $i;
	for($i = 0; $i < @one; $i++) {
		print "'";
		$one[$i] =~ s/'/\\'/g;
		print $one[$i];
		print "',\n";
		if ($comment[$i]) {
			$comment[$i] =~ s/\n/\n# /g;
			print "# $comment[$i]\n";
		}
		print "'";
		$two[$i] =~ s/'/\\'/g;
		print $two[$i];
		print "',\n\n";
	}
	print "\n}\nEOF\n";
	exit;
}

my %Comment;
my $Key = 'msg0001';

sub getkey {
	$Key++ until ! defined $Locale->{$def}->{$Key};
	return $Key;
}

sub write_structure {
	my($key, $default) = @_;
	if($key) {
		$Locale->{$def}->{$key} = $default;
		$Comment{$key} = $default;
		$Comment{$key} =~ s/\n/\n# /g;
	}
	else {
		$Locale->{$def}->{$default} = $default;
	}
}

sub substitute_lc {
	my($default) = @_;
	my $loc = {};
	while($default =~ s:\s*\[(\w+)\]\s*(.*)\[/\1\]::s) {
		my $l = $1;
		my $val = $2;
		$val =~ s/\s+$//;
		$l =~ s/^MM_// if $opt_M;
		$loc->{$l} = $val;
	}
	$default =~ s/^\s+//;
	$default =~ s/\s+$//;
	for(keys %$loc) {
		$Locale->{$_}->{$default} = $loc->{$_};
		$Comment{$default} = $default;
		$Comment{$default} =~ s/\n/\n# /g;
	}
	$Locale->{$def}->{$default} = $default;
	my $out = "$default\n";
	for(keys %$Locale) {
		next unless defined $Locale->{$_}{$default};
		next if $_ eq 'default';
		$out .= "[$Mpre$_]" . $Locale->{$_}{$default} . "[/$Mpre$_]\n";
	}
	return $out;
}

my $data;
my $key;
my $file;

foreach $file (@ARGV) {
	unless ($data = readfile($file)) {
		warn "file $file non-existent or empty, skipping.\n";
		next;
	}

	if($opt_c) {
		rename($file, "$file.bak") or die "Couldn't rename $file: $!\n";
		$data =~ s!\[L(?:\s+\w+\s*)?\](.*?)\[/L\]!
					'[LC]' . substitute_lc($1) . '[/LC]'!ge
	}
	elsif($opt_o) {
		rename($file, "$file.bak") or die "Couldn't rename $file: $!\n";
		while ($data =~ s:\[L\](.*?)(\[/L\]):
					'[L ' . ($key = getkey()) . ']' . $1. $2:e) {
				write_structure($key, $1);
		}
	}
	if(! $opt_c) {
		while ($data =~ m:\[L(\s+(\w+)\s*)?\](.*?)\[/L\]:sg) {
					write_structure($2 || undef, $3);
		}
		while ($data =~ m!\[LC\](.*?)\[/LC\]!gs) {
print STDERR ".";
					substitute_lc($1);
		}
	}

	if($opt_c || $opt_o) {
		Vend::Util::writefile($file, $data);
	}
}

my $loc_text = "Locale $opt_l <<EOF\n{\n";
my $def_text = "Locale $def <<EOF\n{\n";

my $d = $Locale->{$def};
my $l = $Locale->{$opt_l};

my($text, $dat, $cmt);

foreach $key (sort keys %$d) {

		$dat = ($Comment{$key} || '') and
			$dat =~ s/\n/\n# /g;

		$def_text .= "# $dat\n" if $dat;

		if ($dat) {
			$cmt = $dat;
		}
		else {
			$cmt = $key;
			$cmt =~ s/\n/\n# /g;
		}
		$loc_text .= "# $cmt\n";

		$text = &$Uneval($key);
		$loc_text .= "$text,\n";
		#$loc_text .= &$Uneval ($l->{$key} || '');
		# Change to put undef on length 0
		$loc_text .= (defined $l->{$key} && length($l->{$key})) 
					 ?	$Uneval->($l->{$key})
					 :  'undef';
		$loc_text .= ",\n\n";

		next unless $Comment{$key};
		$def_text .= "$text,\n";
		$def_text .= &$Uneval($Comment{$key});
		$def_text .= ",\n\n";
	

}

$def_text .= "\n}\nEOF\n";
$loc_text .= "\n}\nEOF\n\n";

print $loc_text;
print $def_text;

=head1 NAME

localize -- produce MiniVend localization file from set of pages

=head1 VERSION

$Id: localize,v 1.3 2000/03/02 10:34:31 mike Exp $

=head1 SYNOPSIS

C<localize -l lg_CC [-d lg_CC] [-m file|-t] file [file2 file3 ...]>

=head1 DESCRIPTION

Helps manage Minivend pages by finding, adding, and merging localization strings.

=head1 OPTIONS

=over 4

=item C<-c>

Rewrite [L] sections with [LC]text[do_DO]text[/do_dO], adjust file and
data -- mutually exclusive with C<-o>.

=item C<-d lg_CC>

Create default domain file with Locale lg_CC as prefix

=item C<-l lg_CC>

Create file with Locale lg_CC as prefix. This is mandatory unless in
-c mode with C<-m> option.

=item C<-m file>

Read existing information to merge from <file>. Can contain multiple locales.

=item C<-M>

When in C<-c> mode, prefix MM_ to make minimate_compatible; 
when in regular mode, strip MM_ from [LC] defs

=item C<-o>

Rewrite [L] sections with [L msgNNNN], adjust file and data.
Mutually exclusive with C<-c>.

=item C<-t>

Two page mode, mutually exclusive with C<-m.>

=back

lg_CC refers to the POSIX norm of specifying two-letter
language and country codes to refer to a locale.
    
Two-page mode requires two files (one for each language) to compare and
merge into one locale definition.

The merge file for the C<-m> option should use the Perl reference form --
see the MiniVend documentation for more information.

If [L msg_key]default text[/L] keys are found, will produce a comment
with the default text for reference.

A backup file (filename.html.bak) is saved if C<-o> is used, but only
one level. Subsequent .bak files will be overwritten.

=head1 SEE ALSO

mvdocs(8), http://www.minivend.com

=head1 AUTHOR

Mike Heins, <mikeh@minivend.com>. Valuable contributions made by Stefan Hornburg,
<racke@linuxia.net>.
=cut

_EoP_
	s{.*\n(#(.*)~_~(\w+)~_~(.*))}{$2 . doit($3) . "$4\n$1"}eg;
	my $file = $0;
	$file =~ s/\.PL$//;
	open(OUT, ">$file") 
		or die "Create $file: $!\n";
	print OUT $_;
}
