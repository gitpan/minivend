# Table/InMemory.pm: store a table in memory
#
# $Id: InMemory.pm,v 1.4 2000/03/02 10:34:01 mike Exp $
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

package Vend::Table::InMemory;
use Vend::Table::Common;
@ISA = qw/Vend::Table::Common/;
$VERSION = substr(q$Revision: 1.4 $, 10);
use strict;

# 0: column names
# 1: column index
# 2: tie hash
# 3: configuration

use vars qw($FILENAME
			$COLUMN_NAMES
			$COLUMN_INDEX
			$KEY_INDEX
			$TIE_HASH
			$DBM
			$CONFIG
			$EACH
			);
(
	$CONFIG,
	$FILENAME,
	$COLUMN_NAMES,
	$COLUMN_INDEX,
	$KEY_INDEX,
	$TIE_HASH,
	$DBM,
	$EACH
	) = (0 .. 7);

sub config {
	my ($self, $key, $value) = @_;
	return $self->[$CONFIG]{$key} unless defined $value;
	$self->[$CONFIG]{$key} = $value;
}

sub import_db {
	return shift;
}

sub create {
    my ($class, $config, $columns) = @_;

    $config = {} unless defined $config;

    die "columns argument $columns is not an array ref\n"
        unless CORE::ref($columns) eq 'ARRAY';

    my $column_index = Vend::Table::Common::create_columns($columns, $config);

    my $tie = {};
    my $s = [
				$config,
				undef,
				$columns,
				$column_index,
				$config->{KEY_INDEX},
				$tie,
				1
			];
#::logDebug("Create database $config->{name}: " . ::uneval($s));
    bless $s, $class;
}

sub new {
	my ($class, $obj) = @_;
	bless [$obj], $class;
}

sub close_table {
	1;
}

sub row {
    my ($s, $key) = @_;
    my $a = $s->[$TIE_HASH]{$key};
    die "There is no row with index '$key'" unless defined $a;
    return @$a;
}

sub row_hash {
    my ($s, $key) = @_;
    my $a = $s->[$TIE_HASH]{$key};
#::logDebug("here is row $key: " . ::uneval($a));
    die "There is no row with index '$key'" unless defined $a;
	my %row;
	@row{ @{$s->[$COLUMN_NAMES]} } = @$a;
    return \%row;
}

*row_array = \&row;

sub columns {
    my ($s) = @_;
    return @{$s->[$COLUMN_NAMES]};
}


sub field_settor {
    my ($s, $column) = @_;
    my $index = $s->column_index($column);
    return sub {
        my ($key, $value) = @_;
        my $a = $s->[$TIE_HASH]{$key};
        $a = $s->[$TIE_HASH]{$key} = [] unless defined $a;
        $a->[$index] = $value;
        return undef;
    };
}

sub set_row {
    my ($s, @fields) = @_;
	my $key = $fields[$s->[$KEY_INDEX]];
    $s->[$TIE_HASH]{$key} = [@fields];
}

sub inc_field {
    my ($s, $key, $column, $adder) = @_;
    my $a = $s->[$TIE_HASH]{$key};
    $a = $s->[$TIE_HASH]{$key} = [] unless defined $a;
    $a->[$s->column_index($column)] += $adder;
}

sub each_record {
    my ($s) = @_;
    my $key;

#::logDebug("reached each_record InMemory");
	return $s->each_sorted() if defined $s->[$EACH];
    for (;;) {
        $key = each %{$s->[$TIE_HASH]};
		return () unless defined $key;
		return ($key, $s->row($key));
    }
}

sub each_nokey {
    my ($s) = @_;
#::logDebug("reached each_nokey InMemory");
	$s = $s->import_db() if ! defined $s->[$TIE_HASH];
    my $key;

    for (;;) {
        $key = each %{$s->[$TIE_HASH]};
		return () unless defined $key;
		return ($s->row($key));
    }
}


#sub each_record {
#    my ($s) = @_;
#    my @e = each %{$s->[$TIE_HASH]};
#    if (@e) {
#        return ($e[0], @{$e[1]});
#    }
#    else {
#        return ();
#    }
#}

sub record_exists {
    my ($s, $key) = @_;
#::logDebug("$key exist test");
    return exists($s->[$TIE_HASH]{$key});
}

*test_record = \&record_exists;

sub delete_record {
    my ($s, $key) = @_;
    delete($s->[$TIE_HASH]{$key});
}

sub clear_table {
    my ($s) = @_;
    %{$s->[$TIE_HASH]} = ();
}

sub touch {
	1
}

sub ref {
	return $_[0];
}

# Unfortunate hack need for Safe searches
*column_index	= \&Vend::Table::Common::column_index;
*field			= \&Vend::Table::Common::field;
*numeric		= \&Vend::Table::Common::numeric;
*row_hash		= \&Vend::Table::Common::row_hash;
*set_field		= \&Vend::Table::Common::set_field;

1;
