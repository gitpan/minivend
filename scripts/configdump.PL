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
# MiniVend configuration dumper (version see POD documentation)
#
# Copyright 1999, 2000 by Stefan Hornburg <racke@linuxia.de>
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
}

### END CONFIGURABLE VARIABLES

# dummy function used by Config.pm
sub debug { return undef }

$Global::ConfigFile = 'minivend.cfg';
$Vend::ExternalProgram = 1;

use lib $Global::VendRoot;
use lib "$Global::VendRoot/lib";

use strict;
use Vend::Config;
use Vend::Util;

my $USAGE = <<EOF;
usage: configdump catalog
EOF

# check commandline parameters
unless ($#ARGV == 0) {
    print $USAGE;
    exit 1;
}
    
my ($catalog, $name);

$Vend::Cfg = {};

$catalog = shift;

my($name,$dir,$param,$subcat,$subconfig,$junk);
chdir $Global::VendRoot;

if ($catalog) {
    open(GLOBAL, $Global::ConfigFile) or
        die "No global configuration file? Aborting.\n";
    while(<GLOBAL>) {
        next unless /^\s*(sub)?catalog\s+$catalog\s+/i;
        $subcat = $1 || '';
        chomp;
        s/^\s+//;
        unless($subcat) {
            ($junk,$name,$dir,$param) = split /\s+/, $_, 4;
        } else {
            ($junk,$name,$subconfig,$dir,$param) = split /\s+/, $_, 5;
        }
        last;
    }
    close GLOBAL;

    # send some required values
    $Global::SendMailLocation = 'none';
	$Global::SysLog = '';
	$Global::ErrorFile = '/dev/null';
}
global_config();
chdir $dir or die "Couldn't change directory to $dir: $!\n";

if ($catalog) {
    $Vend::Cfg = config($name, $dir, 'config', $subconfig || undef);
}

my $value;

foreach (sort (keys (%$Vend::Cfg))) {
    $value = $$Vend::Cfg{$_};
    print_values ($value, $_, 1);
}

sub print_values {
    my ($value, $prefix, $level) = @_;

    if (ref($value) eq 'HASH') {
        foreach my $subkey (sort (keys (%$value))) {
            if (ref($$value{$subkey}) eq '') {
                print "$prefix $subkey ", $$value{$subkey}, "\n";
            } else {
                print_values ($$value{$subkey}, "$prefix $subkey",
                              $level + 1);
            }
        }
    } elsif (ref($value) eq 'ARRAY') {
        for (my $i = 0; $i <= $#$value; $i++) {
            if (ref($$value[$i]) eq '') {
                print "$prefix #", $i + 1, ' ', $$value[$i], "\n";
            } else {
                print_values ($$value[$i], "$prefix #" . $i + 1, $level + 1);
            }
        }
    } else {
        print "$prefix $value\n";
    }
}

=head1 NAME

configdump - MiniVend configuration dumper

=head1 SYNOPSIS

configdump catalog

=head1 VERSION

1.0

=head1 DESCRIPTION

C<configdump> writes the configuration directives for the given catalog
to standard output. This includes the default settings too.

=head1 SEE ALSO

mvdocs(8), dump(1), makecat(1), minivend(1)

=head1 LICENSE

MiniVend comes with ABSOLUTELY NO WARRANTY.  This is free software, and
you are welcome to redistribute and modify it under the terms of the
GNU General Public License.

=head1 COPYRIGHT

Copyright 1999-2000, Stefan Hornburg. All rights reserved except as in the
license.

=head1 AUTHOR

Stefan Hornburg, <racke@linuxia.de>

=cut

_EoP_
	s{.*\n(#(.*)~_~(\w+)~_~(.*))}{$2 . doit($3) . "$4\n$1"}eg;
	my $file = $0;
	$file =~ s/\.PL$//;
	open(OUT, ">$file") 
		or die "Create $file: $!\n";
	print OUT $_;
}
