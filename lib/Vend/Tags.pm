#!/usr/bin/perl
# Tags.pm - Interpret MiniVend tags for Safe
# 
# $Id: Tags.pm,v 1.4 2000/03/02 10:33:39 mike Exp $
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

package Vend::Tags;

require Exporter;
require AutoLoader;

use vars qw($AUTOLOAD @ISA);
@ISA = qw(Exporter);

sub new {
	return bless {}, shift;
}

sub DESTROY {
	1;
}

sub AUTOLOAD {
	shift;
	my $routine = $AUTOLOAD;
	$routine =~ s/.*:://;
	if(ref($_[0]) =~ /HASH/) {
		@_ = Vend::Parse::resolve_args($routine, @_);
	}
	return Vend::Parse::do_tag($routine, @_);
}

1;

__END__
