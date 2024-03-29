# Util.pm - Minivend utility functions
#
# $Id: Util.pm,v 1.10 2000/03/09 13:33:40 mike Exp mike $
# 
# Copyright 1996-2000 by Michael J. Heins <mikeh@minivend.com>
#
# This program was originally based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# Portions from Vend 0.3
# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
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

package Vend::Util;
require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(

	catfile
	check_security
	copyref
	currency
	dump_structure
	errmsg
	escape_chars
	evalr
	file_modification_time
	file_name_is_absolute
	find_special_page
	format_log_msg
	generate_key
	get_option_hash
	is_no
	is_yes
	lockfile
	logData
	logDebug
	logError
	logGlobal
	logtime
	random_string
	readfile
	readin
	secure_vendUrl
	send_mail
	setup_escape_chars
	tag_nitems
	uneval
	uneval_fast
	unlockfile
	vendUrl

);

use strict;
use Config;
use Fcntl;
use subs qw(logError logGlobal);
use vars qw($VERSION @EXPORT @EXPORT_OK);
$VERSION = substr(q$Revision: 1.10 $, 10);

BEGIN {
	eval {
		require 5.004;
	};
}

my $Eval_routine;
my $Eval_routine_file;
my $Pretty_uneval;
my $Fast_uneval;
my $Fast_uneval_file;

### END CONFIGURABLE MODULES

## ESCAPE_CHARS

$ESCAPE_CHARS::ok_in_filename =
		'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .
		'abcdefghijklmnopqrstuvwxyz' .
		'0123456789'				 .
		'-:_.$/'
	;

sub setup_escape_chars {
    my($ok, $i, $a, $t);

    foreach $i (0..255) {
        $a = chr($i);
        if (index($ESCAPE_CHARS::ok_in_filename,$a) == -1) {
			$t = '%' . sprintf( "%02X", $i );
        }
		else {
			$t = $a;
        }
        $ESCAPE_CHARS::translate[$i] = $t;
    }
}

# Replace any characters that might not be safe in a filename (especially
# shell metacharacters) with the %HH notation.

sub escape_chars {
    my($in) = @_;
    my($c, $r);

    $r = '';
    foreach $c (split(//, $in)) {
		$r .= $ESCAPE_CHARS::translate[ord($c)];
    }

    # safe now
    $r =~ /(.*)/;
    $r = $1;
    return $r;
}

# Returns its arguments as a string of tab-separated fields.  Tabs in the
# argument values are converted to spaces.

sub tabbed {        
    return join("\t", map { $_ = '' unless defined $_;
                            s/\t/ /g;
                            $_;
                          } @_);
}

# Finds common-log-style offset
# Unproven, authoratative code welcome
my $Offset;
FINDOFFSET: {
    my $now = time;
    my ($gm,$gh,$gd,$gy) = (gmtime($now))[1,2,5,7];
    my ($lm,$lh,$ld,$ly) = (localtime($now))[1,2,5,7];
    if($gy != $ly) {
        $gy < $ly ? $lh += 24 : $gh += 24;
    }
    elsif($gd != $ld) {
        $gd < $ld ? $lh += 24 : $gh += 24;
    }
    $gh *= 100;
    $lh *= 100;
    $gh += $gm;
    $lh += $lm;
    $Offset = sprintf("%05d", $lh - $gh);
    $Offset =~ s/0(\d\d\d\d)/+$1/;
}

# Returns time in HTTP common log format
sub logtime {
    return POSIX::strftime("[%d/%B/%Y:%H:%M:%S $Offset]", localtime());
}

sub format_log_msg {
	my($msg) = @_;
	my(@params);

	# IP, Session, REMOTE_USER (if any) and time
    push @params, ($CGI::remote_host || $CGI::remote_addr || '-');
	push @params, ($Vend::SessionName || '-');
	push @params, ($CGI::user || '-');
	push @params, logtime();

	# Catalog name
	my $string = ! defined $Vend::Cfg ? '-' : ($Vend::Cfg->{CatalogName} || '-');
	push @params, $string;

	# Path info and script
	$string = $CGI::script_name || '-';
	$string .= $CGI::path_info || '';
	push @params, $string;

	# Message, quote newlined area
	$msg =~ s/\n/\n> /g;
	push @params, $msg;
	return join " ", @params;
}

sub round_to_frac_digits {
	my ($num, $digits) = @_;
	if (defined $digits) {
		# use what we were given
	}
	elsif ( $Vend::Cfg->{Locale} ) {
		$digits = $Vend::Cfg->{Locale}{frac_digits} || 2;
	}
	else {
		$digits = 2;
	}
	my @frac;
	$num =~ /^(\d*)\.(\d+)$/
		or return $num;
	my $int = $1;
	@frac = split //, $2;
	local($^W) = 0;
	my $frac = join "", @frac[0 .. $digits - 1];
	if($frac[$digits] > 4) {
		$frac++;
	}
	if(length($frac) > $digits) {
		$int++;
		$frac = 0 x $digits;
	}
	return "$int.$frac";
}

# Return AMOUNT formatted as currency.
sub commify {
    local($_) = shift;
	my $sep = shift || ',';
    1 while s/^(-?\d+)(\d{3})/$1$sep$2/;
    return $_;
}

sub picture_format {
	my($amount, $pic, $sep, $point) = @_;
    $pic	= reverse $pic;
	$point	= '.' unless defined $point;
	$sep	= ',' unless defined $sep;
	$pic =~ /(#+)\Q$point/;
	my $len = length($1);
	$amount = sprintf('%.' . $len . 'f', $amount);
	$amount =~ tr/0-9//cd;
	my (@dig) = split //, $amount;
	$pic =~ s/#/pop(@dig)/eg;
	$pic =~ s/\Q$sep\E+(?!\d)//;
	$pic =~ s/\d/*/g if @dig;
	$amount = reverse $pic;
	return $amount;
}

sub setlocale {
    my ($locale, $currency, $opt) = @_;
    $locale = $::Scratch->{mv_locale} unless defined $locale;

    if ( $locale and not defined $Vend::Cfg->{Locale_repository}{$locale}) {
        ::logError( "attempt to set non-existant locale '%s'" , $locale );
        return '';
    }

    if ( $currency and not defined $Vend::Cfg->{Locale_repository}{$currency}) {
        ::logError("attempt to set non-existant currency '%s'" , $currency);
        return '';
    }

    if($locale) {
        my $loc = $Vend::Cfg->{Locale} = $Vend::Cfg->{Locale_repository}{$locale};

        for(@Vend::Config::Locale_directives_scalar) {
            $Vend::Cfg->{$_} = $loc->{$_}
                if defined $loc->{$_};
        }

        for(@Vend::Config::Locale_directives_ary) {
            @{$Vend::Cfg->{$_}} = split (/\s+/, $loc->{$_})
                if $loc->{$_};
        }
		no strict 'refs';
		for(qw/LC_COLLATE LC_CTYPE LC_TIME/) {
			next unless $loc->{$_};
			POSIX::setlocale(&{"POSIX::$_"}, $loc->{$_});
		}
    }

    if ($currency) {
        my $curr = $Vend::Cfg->{Locale_repository}{$currency};

        for(@Vend::Config::Locale_directives_currency) {
            $Vend::Cfg->{$_} = $curr->{$_}
                if defined $curr->{$_};
        }
        @{$Vend::Cfg->{Locale}}{@Vend::Config::Locale_keys_currency} =
                @{$curr}{@Vend::Config::Locale_keys_currency};
    }

    $::Scratch->{mv_locale}   = $locale    if $opt->{persist} and $locale;
    $::Scratch->{mv_currency} = $currency  if $opt->{persist} and $currency;
    return '';
}


sub currency {
	my($amount, $noformat, $convert, $opt) = @_;
#::logDebug("currency called: amount=$amount no=$noformat convert=$convert");
	$opt = {} unless $opt;
	$amount = $amount / $Vend::Cfg->{PriceDivide} if $convert;
	return $amount if $noformat;
	my $loc;
	my $sep;
	my $dec;
	my $fmt;
	my $precede = '';
	my $succede = '';
	if ($loc = $opt->{locale} || $Vend::Cfg->{Locale}) {
		$sep = $loc->{mon_thousands_sep} || $loc->{thousands_sep} || ',';
		$dec = $loc->{mon_decimal_point} || $loc->{decimal_point} || '.';
		return picture_format($amount, $loc->{price_picture}, $sep, $dec)
			if defined $loc->{price_picture};
		$fmt = "%." . $loc->{frac_digits} .  "f";
		my $cs;
		if($cs = ($loc->{currency_symbol} ||$loc->{currency_symbol} || '') ) {
			if($loc->{p_cs_precedes}) {
				$precede = $cs;
				$precede = "$precede " if $loc->{p_sep_by_space};
			}
			else {
				$succede = $cs;
				$succede = " $succede" if $loc->{p_sep_by_space};
			}
		}
	}
	else {
		$fmt = "%.2f";
	}

	$amount = sprintf $fmt, $amount;
	$amount =~ s/\./$dec/ if defined $dec;
	$amount = commify($amount, $sep || undef)
		if $Vend::Cfg->{PriceCommas};
	return "$precede$amount$succede";
}

## random_string

# leaving out 0, O and 1, l
my $random_chars = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

# Return a string of random characters.

sub random_string {
    my ($len) = @_;
    $len = 8 unless $len;
    my ($r, $i);

    $r = '';
    for ($i = 0;  $i < $len;  ++$i) {
	$r .= substr($random_chars, int(rand(length($random_chars))), 1);
    }
    $r;
}

# To generate a unique key for caching
# Not very good without MD5
#
my $Md;
my $Keysub;

eval {require Digest::MD5 };

if(! $@) {
	$Md = new Digest::MD5;
	$Keysub = sub {
#::logDebug("key gen args: '@_'");
					@_ = time() unless @_;
					$Md->reset();
					$Md->add(@_);
					$Md->hexdigest();
				};
}
else {
	$Keysub = sub {
		my $out = '';
		@_ = time() unless @_;
		for(@_) {
			$out .= unpack "%32c*", $_;
			$out .= unpack "%32c*", substr($_,5);
			$out .= unpack "%32c*", substr($_,-1,5);
		}
		$out;
	};
}

sub generate_key { &$Keysub(@_) }

sub hexify {
    my $string = shift;
    $string =~ s/(\W)/sprintf '%%%02x', ord($1)/ge;
    return $string;
}

sub unhexify {
    my $s = shift;
    $s =~ s/%(..)/chr(hex($1))/ge;
    return $s;
}

## UNEVAL

# Returns a string representation of an anonymous array, hash, or scaler
# that can be eval'ed to produce the same value.
# uneval([1, 2, 3, [4, 5]]) -> '[1,2,3,[4,5,],]'
# Uses either Storable::freeze or Data::Dumper::DumperX or uneval 
# in 

sub uneval_it {
    my($o) = @_;		# recursive
    my($r, $s, $i, $key, $value);

	local($^W) = 0;
    $r = ref $o;
    if (!$r) {
	$o =~ s/([\\"\$@])/\\$1/g;
	$s = '"' . $o . '"';
    } elsif ($r eq 'ARRAY') {
	$s = "[";
	foreach $i (0 .. $#$o) {
	    $s .= uneval_it($o->[$i]) . ",";
	}
	$s .= "]";
    } elsif ($r eq 'HASH') {
	$s = "{";
	while (($key, $value) = each %$o) {
	    $s .= "'$key' => " . uneval_it($value) . ",";
	}
	$s .= "}";
    } else {
	$s = "'something else'";
    }

    $s;
}

use subs 'uneval_fast';

sub uneval_it_file {
	my ($ref, $fn) = @_;
	open(UNEV, ">$fn") 
		or die "Can't create $fn: $!\n";
	print UNEV uneval_fast($ref);
	close UNEV;
}

sub eval_it_file {
	my ($fn) = @_;
	local($/) = undef;
	open(UNEV, $fn) or return undef;
	my $ref = evalr(<UNEV>);
	close UNEV;
	return $ref;
}

# See if we have Storable and the user has OKed its use
# If so, session storage/write will be about 5x faster
eval {
	die unless $ENV{MINIVEND_STORABLE};
	require Storable;
	import Storable 'freeze';
	$Fast_uneval     = \&Storable::freeze;
	$Fast_uneval_file  = \&Storable::store;
	$Eval_routine    = \&Storable::thaw;
	$Eval_routine_file = \&Storable::retrieve;
};

# See if Data::Dumper is installed with XSUB
# If it is, session writes will be about 25-30% faster
eval {
		require Data::Dumper;
		import Data::Dumper 'DumperX';
		$Data::Dumper::Indent = 1;
		$Data::Dumper::Terse = 1;
		$Pretty_uneval = \&Data::Dumper::DumperX;
		$Fast_uneval = \&Data::Dumper::DumperX
			unless defined $Fast_uneval;
};

*uneval_fast = defined $Fast_uneval       ? $Fast_uneval       : \&uneval_it;
*evalr       = defined $Eval_routine      ? $Eval_routine      : sub { eval shift };
*eval_file   = defined $Eval_routine_file ? $Eval_routine_file : \&eval_it_file;
*uneval_file = defined $Fast_uneval_file  ? $Fast_uneval_file  : \&uneval_it_file;
*uneval      = defined $Pretty_uneval     ? $Pretty_uneval     : \&uneval_it;

sub writefile {
    my($file, $data) = @_;

	$file = ">>$file" unless $file =~ /^[|>]/;

    eval {
		unless($file =~ s/^[|]\s*//) {
			open(MVLOGDATA, "$file") or die "open\n";
			lockfile(\*MVLOGDATA, 1, 1) or die "lock\n";
			seek(MVLOGDATA, 0, 2) or die "seek\n";
			if(ref $data) {
				print(MVLOGDATA $$data) or die "write to\n";
			}
			else {
				print(MVLOGDATA $data) or die "write to\n";
			}
			unlockfile(\*MVLOGDATA) or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, Text::ParseWords::shellwords($file);
			open(MVLOGDATA, "|-") || exec @args;
			if(ref $data) {
				print(MVLOGDATA $$data) or die "pipe to\n";
			}
			else {
				print(MVLOGDATA $data) or die "pipe to\n";
			}
		}
		close(MVLOGDATA) or die "close\n";
    };
    if ($@) {
		::logError ("Could not %s file '%s': %s\nto write this data:\n%s",
				$@,
				$file,
				$!,
				$data,
				);
		return 0;
    }
	1;
}


# Log data fields to a data file.

sub logData {
    my($file,@msg) = @_;
    my $prefix = '';

	$file = ">>$file" unless $file =~ /^[|>]/;

	my $msg = tabbed @msg;

    eval {
		unless($file =~ s/^[|]\s*//) {
			open(MVLOGDATA, "$file")	or die "open\n";
			lockfile(\*MVLOGDATA, 1, 1)	or die "lock\n";
			seek(MVLOGDATA, 0, 2)		or die "seek\n";
			print(MVLOGDATA "$msg\n")	or die "write to\n";
			unlockfile(\*MVLOGDATA)		or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, Text::ParseWords::shellwords($file);
			open(MVLOGDATA, "|-") || exec @args;
			print(MVLOGDATA "$msg\n") or die "pipe to\n";
		}
		close(MVLOGDATA) or die "close\n";
    };
    if ($@) {
		::logError ("Could not %s log file '%s': %s\nto log this data:\n%s",
				$@,
				$file,
				$!,
				$msg,
				);
		return 0;
    }
	1;
}


sub file_modification_time {
    my ($fn) = @_;
    my @s = stat($fn) or die "Can't stat '$fn': $!\n";
    return $s[9];
}

sub quoted_comma_string {
	my ($text) = @_;
	my (@fields);
	push(@fields, $+) while $text =~ m{
   "([^\"\\]*(?:\\.[^\"\\]*)*)"[\s,]?  ## std quoted string, w/possible space-comma
   | ([^\s,]+)[\s,]?                   ## anything else, w/possible space-comma
   | [,\s]+                            ## any comma or whitespace
        }gx;
    @fields;
}

# Modified from old, old module called Ref.pm
sub copyref {
    my($x,$r) = @_; 

    my($z, $y);

    my $rt = ref $x;

    if ($rt =~ /SCALAR/) {
        # Would \$$x work?
        $z = $$x;
        return \$z;
    } elsif ($rt =~ /HASH/) {
        $r = {} unless defined $r;
        for $y (sort keys %$x) {
            $r->{$y} = &copyref($x->{$y}, $r->{$y});
        }
        return $r;
    } elsif ($rt =~ /ARRAY/) {
        $r = [] unless defined $r;
        for ($y = 0; $y <= $#{$x}; $y++) {
            $r->[$y] = &copyref($x->[$y]);
        }
        return $r;
    } elsif ($rt =~ /REF/) {
        $z = &copyref($x);
        return \$z;
    } elsif (! $rt) {
        return $x;
    } else {
        die "do not know how to copy $x";
    }
}

sub check_gate {
	my($f, $gatedir) = @_;

	my $gate;
	if ($gate = readfile("$gatedir/.access_gate") ) {
#::logDebug("found access_gate");
		$f =~ s:.*/::;
		$gate = Vend::Interpolate::interpolate_html($gate);
#::logDebug("f=$f gate=$gate");
		if($gate =~ m!^$f(?:\.html?)?[ \t]*:!m ) {
			$gate =~ s!.*(\n|^)$f(?:\.html?)?[ \t]*:!!s;
#::logDebug("gate=$gate");
			$gate =~ s/\n[\S].*//s;
			$gate =~ s/^\s+//;
		}
		elsif($gate =~ m{^\*(?:\.html?)?[: \t]+(.*)}m) {
			$gate = $1;
		}
		else {
			undef $gate;
		}
	}
	return $gate;
}

sub get_option_hash {
	return $_[0] if ref $_[0];
	return {} unless $_[0] =~ /\S/;
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	if($string =~ /^{/ and $string =~ /}/) {
		return $Vend::Interpolate::ready_safe->reval($string);
	}
	my @opts = split /\s*,\s*/, $string;
	my %hash;
	for(@opts) {
		my ($k, $v) = split /[\s=]+/, $_, 2;
		$hash{$k} = $v;
	}
	return \%hash;
}

## READIN

my $Lang;

sub find_locale_bit {
	my $text = shift;
	$Lang = $::Scratch->{mv_locale} unless defined $Lang;
#::logDebug("find_locale: $Lang");
	$text =~ m{\[$Lang\](.*)\[/$Lang\]}s
		and return $1;
	$text =~ s{\[(\w+)\].*\[/\1\].*}{}s;
	return $text;
}

# Reads in a page from the page directory with the name FILE and ".html"
# appended. If the HTMLsuffix configuration has changed (because of setting in
# catalog.cfg or Locale definitions) it will substitute that. Returns the
# entire contents of the page, or undef if the file could not be read.
# Substitutes Locale bits as necessary.

sub readin {
    my($file, $only) = @_;
    my($fn, $contents, $gate, $pathdir, $dir, $level);
    local($/);

	$Global::Variable->{MV_PREV_PAGE} = $Global::Variable->{MV_PAGE}
		if defined $Global::Variable->{MV_PAGE};
	$Global::Variable->{MV_PAGE} = $file;

	$file =~ s#\.html?$##;
	if($file =~ m{\.\.} and $file =~ /\.\..*\.\./) {
		::logError( "Too many .. in file path '%s' for security.", $file );
		$file = find_special_page('violation');
	}
	($pathdir = $file) =~ s#/[^/]*$##;
	$pathdir =~ s:^/+::;
	my $try;
	my $suffix = $Vend::Cfg->{HTMLsuffix};
  FINDPAGE: {
	foreach $try (
					$Vend::Cfg->{PageDir},
					@{$Vend::Cfg->{TemplateDir}},
					@{$Global::TemplateDir}          )
	{
		$dir = $try . "/" . $pathdir;
		if (-f "$dir/.access") {
			if (-s _) {
				$level = 3;
			}
			else {
				$level = '';
			}
			$gate = check_gate($file,$dir);
		}

		if( defined $level and ! check_security($file, $level, $gate) ){
			my $realm = $::Variable->{COMPANY} || $Vend::Cfg->{CatalogName};
			$Vend::StatusLine = <<EOF if $Vend::InternalHTTP;
HTTP/1.0 401 Unauthorized
WWW-Authenticate: Basic realm="$realm"
EOF
			if(-f "$try/violation.$suffix") {
				$fn = "$try/violation.$suffix";
			}
			else {
				$file = find_special_page('violation');
				$fn = $try . "/" . escape_chars($file) . $suffix;
			}
		}
		else {
			$fn = $try . "/" . escape_chars($file) . $suffix;
		}

		if (open(MVIN, $fn)) {
			binmode(MVIN) if $Global::Windows;
			undef $/;
			$contents = <MVIN>;
			close(MVIN);
			last;
		}
		last if defined $only;
	}
	if(! defined $contents) {
		last FINDPAGE if $suffix eq '.html';
		$suffix = '.html';
		redo FINDPAGE;
	}
	elsif($Vend::Cfg->{Locale}) {
		my $key;
		$contents =~ s~\[L(\s+([^\]]+))?\]([\000-\377]*?)\[/L\]~
						$key = $2 || $3;		
						defined $Vend::Cfg->{Locale}{$key}
						?  ($Vend::Cfg->{Locale}{$key})	: $3 ~eg;
		$contents =~ s~\[LC\]([\000-\377]*?)\[/LC\]~
						find_locale_bit($1) ~eg;
		undef $Lang;
	}
	else {
		$contents =~ s~\[L(?:\s+[^\]]+)?\]([\000-\377]*?)\[/L\]~$1~g;
	}
  }
  if($Vend::Cfg->{HTMLmirror}) {
  	my $mir = $fn;
  	$mir =~ s:([^/]+)$:.$1:;
#::logDebug("mirror $mir");
  	if	(
			-f $mir
				and 
			file_modification_time($fn) <= file_modification_time($mir)
		)
	{
		return $contents;
	}
	else {
		# We want to work anyway
		open (MIR, ">$mir")
			or return $contents;
		Vend::Interpolate::vars_and_comments(\$contents, 1);
		print MIR $contents;
		close MIR;
	}
  }
  $contents;
}

# Reads in an arbitrary file.  Returns the entire contents,
# or undef if the file could not be read.
# Careful, needs the full path, or will be read relative to
# VendRoot..and will return binary. Should be tested by
# the user.
#
# To ensure security in multiple catalog setups, leading
# / is not allowed unless $Global::NoAbsolute is set.
#
sub readfile {
    my($file, $no) = @_;
    my($contents);
    local($/);
	$Global::Variable->{MV_FILE} = $file;

	if($no and ($file =~ m:^\s*/: or $file =~ m#\.\./.*\.\.#)) {
		::logError("Can't read file '%s' with NoAbsolute set" , $file);
		::logGlobal({}, "Can't read file '%s' with NoAbsolute set" , $file );
		return undef;
	}

    return undef if ! open(READIN, $file);

	binmode(READIN) if $Global::Windows;
	undef $/;
	$contents = <READIN>;
	close(READIN);

	if ($Vend::Cfg->{Locale} and $Vend::Cfg->{Locale}->{readfile}) {
		my $key;
		$contents =~ s~\[L(\s+([^\]]+))?\]([\000-\377]*?)\[/L\]~
						$key = $2 || $3;		
						defined $Vend::Cfg->{Locale}->{$key}
						?  ($Vend::Cfg->{Locale}->{$key})	: $3 ~eg;
	}
    $contents || '';
}

sub is_yes {
    return( defined($_[$[]) && ($_[$[] =~ /^[yYtT1]/));
}

sub is_no {
	return( !defined($_[$[]) || ($_[$[] =~ /^[nNfF0]/));
}

# Returns a URL which will run the ordering system again.  Each URL
# contains the session ID as well as a unique integer to avoid caching
# of pages by the browser.

sub vendUrl {
    my($path, $arguments, $r) = @_;
    $r = $Vend::Cfg->{VendURL}
		unless defined $r;

	my @parms;

	if(defined $Vend::Cfg->{AlwaysSecure}{$path}) {
		$r = $Vend::Cfg->{SecureURL};
	}

	my($id, $ct);
	$id = $Vend::SessionID
		unless $CGI::cookie && $::Scratch->{mv_no_session_id};
	$ct = ++$Vend::Session->{pageCount}
		unless $::Scratch->{mv_no_count};

    $r .= '/' . $path;
	$r .= '.html' if $::Scratch->{mv_add_dot_html};
	push @parms, "$::VN->{mv_session_id}=$id"			 	if defined $id;
	push @parms, "$::VN->{mv_arg}=" . hexify($arguments)	if defined $arguments;
	push @parms, "$::VN->{mv_pc}=$ct"                 	if defined $ct;
	push @parms, "$::VN->{mv_cat}=$Vend::Cfg->{CatalogName}"
														if defined $Vend::VirtualCat;
	return $r unless @parms;
    return $r . '?' . join("&", @parms);
} 

sub secure_vendUrl {
	return vendUrl($_[0], $_[1], $Vend::Cfg->{SecureURL});
}

my $use = undef;

### flock locking

# sys/file.h:
my $flock_LOCK_SH = 1;          # Shared lock
my $flock_LOCK_EX = 2;          # Exclusive lock
my $flock_LOCK_NB = 4;          # Don't block when locking
my $flock_LOCK_UN = 8;          # Unlock

sub flock_lock {
    my ($fh, $excl, $wait) = @_;
    my $flag = $excl ? $flock_LOCK_EX : $flock_LOCK_SH;

    if ($wait) {
        flock($fh, $flag) or die "Could not lock file: $!\n";
        return 1;
    }
    else {
        if (! flock($fh, $flag | $flock_LOCK_NB)) {
            if ($! =~ m/^Try again/
                or $! =~ m/^Resource temporarily unavailable/
                or $! =~ m/^Operation would block/) {
                return 0;
            }
            else {
                die "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub flock_unlock {
    my ($fh) = @_;
    flock($fh, $flock_LOCK_UN) or die "Could not unlock file: $!\n";
}


### Select based on os, vestigial

my $lock_function;
my $unlock_function;

unless (defined $use) {
    my $os = $Vend::Util::Config{'osname'};
	$use = 'flock';
	if ($os =~ /win32/i) {
        $use = 'none';
	}
}
        
if ($use eq 'none') {
    print "using NO locking\n";
    $lock_function = sub {1};
    $unlock_function = sub {1};
}
else {
    $lock_function = \&flock_lock;
    $unlock_function = \&flock_unlock;
}
    
sub lockfile {
    &$lock_function(@_);
}

sub unlockfile {
    &$unlock_function(@_);
}

# Returns the total number of items ordered.
# Uses the current cart if none specified.

sub tag_nitems {
	my($ref, $opt) = @_;
    my($cart, $total, $item);
	
	if($ref) {
		 $cart = $::Carts->{$ref}
		 	or return 0;
	}
	else {
		$cart = $Vend::Items;
	}

	my ($attr, $sub);
	if($opt->{qualifier}) {
		$attr = $opt->{qualifier};
		my $qr;
		$qr = qr{$opt->{compare}}
			if $opt->{compare};
		if($opt->{compare}) {
			$sub = sub { 
							$_[0] =~ $qr;
						};
		}
		else {
			$sub = sub { return $_[0] };
		}
	}

    $total = 0;
    foreach $item (@$cart) {
		next if $attr and ! $sub->($item->{$attr});
		$total += $item->{'quantity'};
    }
    $total;
}

sub dump_structure {
	my ($ref, $name) = @_;
	my $save;
	$name =~ s/\.cfg$//;
	$name .= '.structure';
	open(UNEV, ">$name") or die "Couldn't write structure $name: $!\n";
	if(defined $Data::Dumper::Indent) {
		$save = $Data::Dumper::Indent;
		$Data::Dumper::Indent = 2;
	}
	print UNEV uneval($ref);
	close UNEV;
	$Data::Dumper::Indent = $save if defined $save;
}

# Do an internal HTTP authorization check
sub check_authorization {
	my($auth, $pwinfo) = @_;

	$auth =~ s/^\s*basic\s+//i or return undef;
	my ($user, $pw) = split(
						":",
						MIME::Base64::decode_base64($auth),
						2,
						);
	my $cmp_pw;
	my $use_crypt = 1;
	if(!defined $Vend::Cfg) {
		$pwinfo = $Global::AdminUser;
		$pwinfo =~ s/^\s+//;
		$pwinfo =~ s/\s+$//;
		my (%compare) = split /[\s:]+/, $pwinfo;
		return undef unless $compare{$user};
		$cmp_pw = $compare{$user};
		undef $use_crypt if $Global::Variable->{MV_NO_CRYPT};
	}
	elsif(	$user eq $Vend::Cfg->{RemoteUser}	and
			$Vend::Cfg->{Password}					)
	{
		$cmp_pw = $Vend::Cfg->{Password};
		undef $use_crypt if $::Variable->{MV_NO_CRYPT};
	}
	else {
		$pwinfo = $Vend::Cfg->{UserDatabase} unless $pwinfo;
		undef $use_crypt unless $::Variable->{MV_USE_CRYPT};
		$cmp_pw = Vend::Interpolate::tag_data($pwinfo, 'password', $user)
			if defined $Vend::Cfg->{Database}{$pwinfo};
	}

	return undef unless $cmp_pw;

	if(! $use_crypt) {
		return $user if $pw eq $cmp_pw;
	}
	else {
		my $test = crypt($pw, $cmp_pw);
		return $user
			if $test eq $cmp_pw;
	}
	return undef;
}

# Check that the user is authorized by one or all of the
# configured security checks
sub check_security {
	my($item, $reconfig, $gate) = @_;

	my $msg;
	if(! $reconfig) {
# If using the new USERDB access control you may want to remove this next line
# for anyone with an HTTP basic auth will have access to everything
		#return 1 if $CGI::user and ! $Global::Variable->{MV_USERDB};
		if($gate) {
			$gate =~ s/\s+//g;
			return 1 if is_yes($gate);
		}
		elsif($Vend::Session->{logged_in}) {
			return 1 if $::Variable->{MV_USERDB_REMOTE_USER};
			my $db;
			my $field;
			if ($db = $::Variable->{MV_USERDB_ACL_TABLE}) {
				$field = $::Variable->{MV_USERDB_ACL_COLUMN};
				my $access = Vend::Data::database_field(
								$db,
								$Vend::Session->{username},
								$field,
								);
				return 1 if $access =~ m{(^|\s)$item(\s|$)};
			}
		}
		if($Vend::Cfg->{UserDB} and $Vend::Cfg->{UserDB}{log_failed}) {
			my $besthost = $CGI::remote_host || $CGI::remote_addr;
			::logError("auth error host=%s ip=%s script=%s page=%s",
							$besthost,
							$CGI::remote_addr,
							$CGI::script_name,
							$CGI::path_info,
							);
		}
        return '';  
	}
	elsif($reconfig eq '1') {
		$msg = 'reconfigure catalog';
	}
	elsif ($reconfig eq '2') {
		$msg = "access protected database $item";
#::logDebug("passed gate of $gate");
		return 1 if is_yes($gate);
	}
	elsif ($reconfig eq '3') {
		$msg = "access administrative function $item";
	}

	# Check if host IP is correct when MasterHost is set to something
	if (	$Vend::Cfg->{MasterHost}
				and
		(	$CGI::remote_host !~ /^($Vend::Cfg->{MasterHost})$/
				and
			$CGI::remote_addr !~ /^($Vend::Cfg->{MasterHost})$/	)	)
	{
			my $fmt = <<'EOF';
ALERT: Attempt to %s at %s from:

	REMOTE_ADDR  %s
	REMOTE_USER  %s
	USER_AGENT   %s
	SCRIPT_NAME  %s
	PATH_INFO    %s
EOF
		logGlobal ({}, $fmt,
						$msg,
						$CGI::script_name,
						$CGI::host,
						$CGI::user,
						$CGI::useragent,
						$CGI::script_name,
						$CGI::path_info,
						);
		return '';
	}

	# Check to see if password enabled, then check
	if (
		$reconfig eq '1'		and
		!$CGI::user				and
		$Vend::Cfg->{Password}	and
		crypt($CGI::reconfigure_catalog, $Vend::Cfg->{Password})
		ne  $Vend::Cfg->{Password})
	{
		::logGlobal(
				{},
				"ALERT: Password mismatch, attempt to %s at %s from %s",
				$msg,
				$CGI::script_name,
				$CGI::host,
				);
			return '';
	}

	# Finally check to see if remote_user match enabled, then check
	if ($Vend::Cfg->{RemoteUser} and
		$CGI::user ne $Vend::Cfg->{RemoteUser})
	{
		my $fmt = <<'EOF';
ALERT: Attempt to %s %s per user name:

	REMOTE_HOST  %s
	REMOTE_ADDR  %s
	REMOTE_USER  %s
	USER_AGENT   %s
	SCRIPT_NAME  %s
	PATH_INFO    %s
EOF

		::logGlobal($fmt,
			$CGI::script_name,
			$msg,
			$CGI::remote_host,
			$CGI::remote_addr,
			$CGI::user,
			$CGI::useragent,
			$CGI::script_name,
			$CGI::path_info,
		);
		return '';
	}

	# Don't allow random reconfigures without one of the three checks
	unless ($Vend::Cfg->{MasterHost} or
			$Vend::Cfg->{Password}   or
			$Vend::Cfg->{RemoteUser})
	{
		my $fmt = <<'EOF';
Attempt to %s on %s, secure operations disabled.

	REMOTE_ADDR  %s
	REMOTE_USER  %s
	USER_AGENT   %s
	SCRIPT_NAME  %s
	PATH_INFO    %s
EOF
		::logGlobal ($fmt,
				$msg,
				$CGI::script_name,
				$CGI::host,
				$CGI::user,
				$CGI::useragent,
				$CGI::script_name,
				$CGI::path_info,
				);
			return '';

	}

	# Authorized if got here
	return 1;
}

# Replace the escape notation %HH with the actual characters.
#
sub unescape_chars {
    my($in) = @_;

    $in =~ s/%(..)/chr(hex($1))/ge;
    $in;
}


# Checks the Locale for a special page definintion mv_special_$key and
# returns it if found, otherwise goes to the default Vend::Cfg->{Special} array
sub find_special_page {
    my $key = shift;
	my $dir = '';
	$dir = "../$Vend::Cfg->{SpecialPageDir}/"
		if $Vend::Cfg->{SpecialPageDir};
    return $Vend::Cfg->{Special}{$key} || "$dir$key";
}

## ERROR

# Log the error MSG to the error file.

sub logDebug {
	return unless $Global::DebugFile;
	print caller() . ':debug: ', @_, "\n";
}

sub errmsg {
	my($fmt, @strings) = @_;
	my $location;
	if($Vend::Cfg->{Locale} and defined $Vend::Cfg->{Locale}{$fmt}) {
	 	$location = $Vend::Cfg->{Locale};
	}
	elsif($Global::Locale and defined $Global::Locale->{$fmt}) {
	 	$location = $Global::Locale;
	}
	return sprintf $fmt, @strings if ! $location;
	if(ref $location->{$fmt}) {
		$fmt = $location->{$fmt}[0];
		@strings = @strings[ @{ $location->{$fmt}[1] } ];
	}
	else {
		$fmt = $location->{$fmt};
	}
	return sprintf $fmt, @strings;
}

sub logGlobal {
    my($msg) = shift;
	my $opt;
	if(ref $msg) {
		$opt = $msg;
		$msg = shift;
	}
	if(@_) {
		$msg = errmsg($msg, @_);
	}
	my $nolock;

	my $fn = $Global::ErrorFile;
	my $flags;
	if($opt and $Global::SysLog) {
		$fn = "|" . ($Global::SysLog->{command} || 'logger');

		my $leveled;
		if($opt->{level} and defined $Global::SysLog->{$opt->{level}}) {
			$fn .= " -p $Global::SysLog->{$opt->{level}}";
			$leveled = 1;
		}

		my $tag = '';
		if($Global::SysLog->{tag}) {
			$tag = " -t $Global::SysLog->{tag}"
				unless "\L$Global::Syslog->{tag}" eq 'none';
		}
		else {
			$tag = " -t minivend";
		}
		$tag .= ".$opt->{level}" if $tag and ! $leveled;

		$fn .= $tag;

		if($opt->{socket}) {
			$fn .= " -u $opt->{socket}";
		}
	}

	print "$msg\n" if $Vend::Foreground and ! $Vend::Log_suppress && ! $Vend::Quiet;

	$fn =~ s/^([^|>])/>>$1/
		or $nolock = 1;
#::logDebug("logging with $fn");
    $msg = format_log_msg($msg) if ! $nolock;

	$Vend::Errors .= $msg if $Global::DisplayErrors;

    eval {
		open(MVERROR, $fn) or die "open\n";
		if(! $nolock) {
			lockfile(\*MVERROR, 1, 1) or die "lock\n";
			seek(MVERROR, 0, 2) or die "seek\n";
		}
		print(MVERROR $msg, "\n") or die "write to\n";
		if(! $nolock) {
			unlockfile(\*MVERROR) or die "unlock\n";
		}
		close(MVERROR) or die "close\n";
    };
    if ($@) {
		chomp $@;
		print "\nCould not $@ error file '";
		print $Global::ErrorFile, "':\n$!\n";
		print "to report this error:\n", $msg;
		exit 1;
    }
}


# Log the error MSG to the error file.

sub logError {
    my $msg = shift;
	return unless defined $Vend::Cfg;
	if(@_) {
		$msg = errmsg($msg, @_);
	}

	print "$msg\n" if $Vend::Foreground and ! $Vend::Log_suppress && ! $Vend::Quiet;

	$Vend::Session->{last_error} = $msg;

    $msg = format_log_msg($msg) unless $msg =~ s/^\\//;

	$Vend::Errors .= $msg if ($Vend::Cfg->{DisplayErrors} ||
							  $Global::DisplayErrors);

    eval {
		open(MVERROR, ">>$Vend::Cfg->{ErrorFile}")
											or die "open\n";
		lockfile(\*MVERROR, 1, 1)		or die "lock\n";
		seek(MVERROR, 0, 2)				or die "seek\n";
		print(MVERROR $msg, "\n")		or die "write to\n";
		unlockfile(\*MVERROR)			or die "unlock\n";
		close(MVERROR)					or die "close\n";
    };
    if ($@) {
		chomp $@;
		logGlobal ("Could not %s error file %s: %s\nto report this error: %s",
					$@,
					$Vend::Cfg->{ErrorFile},
					$!,
					$msg,
				);
    }
}

# Here for convenience in calls
sub set_cookie {
    my ($name, $value, $expire) = @_;
    $::Instance->{Cookies} = []
        if ! $::Instance->{Cookies};
    @{$::Instance->{Cookies}} = [$name, $value, $expire];
    return;
}

# Here for convenience in calls
sub read_cookie {
	my ($lookfor, $string) = @_;
	$string = $CGI::cookie
		unless defined $string;
	return undef unless $string =~ /\b$lookfor=([^\s;]+)/i;
 	return unescape_chars($1);
}

# Return a quasi-hashed directory/file combo, creating if necessary
sub exists_filename {
    my ($file,$levels,$chars, $dir) = @_;
	my $i;
	$levels = 1 unless defined $levels;
	$chars = 1 unless defined $chars;
	$dir = $Vend::Cfg->{ScratchDir} unless $dir;
    for($i = 0; $i < $levels; $i++) {
		$dir .= "/";
		$dir .= substr($file, $i * $chars, $chars);
		return 0 unless -d $dir;
	}
	return -f "$dir/$file" ? 1 : 0;
}

# Return a quasi-hashed directory/file combo, creating if necessary
sub get_filename {
    my ($file,$levels,$chars, $dir) = @_;
	my $i;
	$levels = 1 unless defined $levels;
	$chars = 1 unless defined $chars;
	$dir = $Vend::Cfg->{ScratchDir} unless $dir;
    for($i = 0; $i < $levels; $i++) {
		$dir .= "/";
		$dir .= substr($file, $i * $chars, $chars);
		mkdir $dir, 0777 unless -d $dir;
	}
    die "Couldn't make directory $dir (or parents): $!\n"
		unless -d $dir;
    return "$dir/$file";
}

# These were stolen from File::Spec
# Can't use that because it INSISTS on object
# calls without returning a blessed object

my $abspat = $^O =~ /win32/i ? '^([a-z]:)?[\\\\/]' : '^/';

sub file_name_is_absolute {
    my($file) = @_;
    $file =~ m{$abspat}oi ;
}

sub win_catfile {
    my $file = pop @_;
    return $file unless @_;
    my $dir = catdir(@_);
    $dir =~ s/(\\\.)$//;
    $dir .= "\\" unless substr($dir,length($dir)-1,1) eq "\\";
    return $dir.$file;
}

sub unix_catfile {
    my $file = pop @_;
    return $file unless @_;
    my $dir = catdir(@_);
    for ($dir) {
	$_ .= "/" unless substr($_,length($_)-1,1) eq "/";
    }
    return $dir.$file;
}

sub unix_path {
    my $path_sep = ":";
    my $path = $ENV{PATH};
    my @path = split $path_sep, $path;
    foreach(@path) { $_ = '.' if $_ eq '' }
    @path;
}

sub win_path {
    local $^W = 1;
    my $path = $ENV{PATH} || $ENV{Path} || $ENV{'path'};
    my @path = split(';',$path);
    foreach(@path) { $_ = '.' if $_ eq '' }
    @path;
}

sub win_catdir {
    my @args = @_;
    for (@args) {
	# append a slash to each argument unless it has one there
	$_ .= "\\" if $_ eq '' or substr($_,-1) ne "\\";
    }
    my $result = canonpath(join('', @args));
    $result;
}

sub win_canonpath {
    my($path) = @_;
    $path =~ s/^([a-z]:)/\u$1/;
    $path =~ s|/|\\|g;
    $path =~ s|\\+|\\|g ;                          # xx////xx  -> xx/xx
    $path =~ s|(\\\.)+\\|\\|g ;                    # xx/././xx -> xx/xx
    $path =~ s|^(\.\\)+|| unless $path eq ".\\";   # ./xx      -> xx
    $path =~ s|\\$|| 
             unless $path =~ m#^([a-z]:)?\\#;      # xx/       -> xx
    $path .= '.' if $path =~ m#\\$#;
    $path;
}

sub unix_canonpath {
    my($path) = @_;
    $path =~ s|/+|/|g ;                            # xx////xx  -> xx/xx
    $path =~ s|(/\.)+/|/|g ;                       # xx/././xx -> xx/xx
    $path =~ s|^(\./)+|| unless $path eq "./";     # ./xx      -> xx
    $path =~ s|/$|| unless $path eq "/";           # xx/       -> xx
    $path;
}

sub unix_catdir {
    my @args = @_;
    for (@args) {
	# append a slash to each argument unless it has one there
	$_ .= "/" if $_ eq '' or substr($_,-1) ne "/";
    }
    my $result = join('', @args);
    # remove a trailing slash unless we are root
    substr($result,-1) = ""
	if length($result) > 1 && substr($result,-1) eq "/";
    $result;
}


my $catdir_routine;
my $canonpath_routine;
my $catfile_routine;
my $path_routine;

if($^O =~ /win32/i) {
	$catdir_routine = \&win_catdir;
	$catfile_routine = \&win_catfile;
	$path_routine = \&win_path;
	$canonpath_routine = \&win_canonpath;
}
else {
	$catdir_routine = \&unix_catdir;
	$catfile_routine = \&unix_catfile;
	$path_routine = \&unix_path;
	$canonpath_routine = \&unix_canonpath;
}

sub path {
	return &{$path_routine}(@_);
}

sub catfile {
	return &{$catfile_routine}(@_);
}

sub catdir {
	return &{$catdir_routine}(@_);
}

sub canonpath {
	return &{$canonpath_routine}(@_);
}

*send_mail = \&Vend::Order::send_mail;

#print "catfile a b c --> " . catfile('a', 'b', 'c') . "\n";
#print "catdir a b c --> " . catdir('a', 'b', 'c') . "\n";
#print "canonpath a/b//../../c --> " . canonpath('a/b/../../c') . "\n";
#print "file_name_is_absolute a/b/c --> " . file_name_is_absolute('a/b/c') . "\n";
#print "file_name_is_absolute a:b/c --> " . file_name_is_absolute('a:b/c') . "\n";
#print "file_name_is_absolute /a/b/c --> " . file_name_is_absolute('/a/b/c') . "\n";

1;
__END__
