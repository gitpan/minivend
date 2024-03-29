# Table/DBI.pm: access a table stored in an DBI/DBD Database
#
# $Id: DBI.pm,v 1.7 2000/03/02 10:33:53 mike Exp $
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

package Vend::Table::DBI;
$VERSION = substr(q$Revision: 1.7 $, 10);

use strict;

# 0: dummy open object
# 1: table name
# 2: key name
# 3: Configuration hash
# 4: Array of column names
# 5: database object
# 6: each reference (transitory)

use vars qw/
			$CONFIG
			$TABLE
			$KEY
			$NAME
			$TYPE
			$DBI
			$EACH
			$TIE_HASH
			$Set_handle
            %DBI_connect_cache
            %DBI_connect_count
		 /;

($CONFIG, $TABLE, $KEY, $NAME, $TYPE, $DBI, $EACH) = (0 .. 6);

$TIE_HASH = $DBI;

my %Cattr = ( qw(
					PRINTERROR     	PrintError
					AUTOCOMMIT     	AutoCommit
				) );

my %Dattr = ( qw(
					WARN			Warn
					CHOPBLANKS		ChopBlanks	
					COMPATMODE		CompatMode	
					INACTIVEDESTROY	InactiveDestroy	
					PRINTERROR     	PrintError
					RAISEERROR     	RaiseError
					AUTOCOMMIT     	AutoCommit
					LONGTRUNCOK    	LongTruncOk
					LONGREADLEN    	LongReadLen
				) );

sub find_dsn {
	my ($config) = @_;
	my($param, $value, $cattr, $dattr, @out);
	my($user,$pass,$dsn,$driver);
	my $i = 0;
	foreach $param (qw! DSN USER PASS !) {
		$out[$i++] = $config->{ $param } || undef;
	}
	foreach $param (keys %$config) {
		if(defined $Dattr{$param}) {
			$dattr = { AutoCommit => 1, PrintError => 1 }
				unless defined $dattr;
			$dattr->{$Dattr{$param}} = $config->{$param};
		}
		next unless defined $Cattr{$param};
		$cattr = {} unless defined $cattr;
		$cattr->{$Cattr{$param}} = $config->{$param};
	}
	$out[3] = $cattr || undef;
	$out[4] = $dattr || undef;
	@out;
}

sub config {
	my ($s, $key, $value) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	return $s->[$CONFIG]{$key} unless defined $value;
	$s->[$CONFIG]{$key} = $value;
}

sub import_db {
	my($s) = @_;
	my $db = Vend::Data::import_database($s->[0], 1);
	return undef if ! $db;
	$Vend::Database{$s->[0]{name}} = $db;
	Vend::Data::update_productbase($s->[0]{name});
	return $db;
}

my $Info;

sub create {
    my ($class, $config, $columns, $tablename) = @_;

	my @call = find_dsn($config);
	my $dattr = pop @call;
	my $db = DBI->connect( @call )
		or die "DBI connect failed: $DBI::errstr\n";

	if($config->{HANDLE_ONLY}) {
		return bless [$config, $tablename, undef, undef, undef, $db], $class;
	}

    die "columns argument $columns is not an array ref\n"
        unless CORE::ref($columns) eq 'ARRAY';

	if(defined $dattr) {
		for(keys %$dattr) {
			$db->{$_} = $dattr->{$_};
		}
	}

    my ($i, $key, $keycol);
	my(@cols);

	$key = $config->{KEY} || $columns->[0];

#::logDebug("columns coming in: @{$columns}");
    for ($i = 0;  $i < @$columns;  $i++) {
        $cols[$i] = $$columns[$i];
#::logDebug("checking column '$cols[$i]'");
		if(defined $key) {
			$keycol = $i if $cols[$i] eq $key;
		}
		if(defined $config->{COLUMN_DEF}->{$cols[$i]}) {
			$cols[$i] .= " " . $config->{COLUMN_DEF}->{$cols[$i]};
		}
		else {
			$cols[$i] .= " char(128)";
		}
		$$columns[$i] = $cols[$i];
		$$columns[$i] =~ s/\s+.*//;
    }

	$keycol = 0 unless defined $keycol;
	$config->{KEY_INDEX} = $keycol;
	$config->{KEY} = $key;

	$cols[$keycol] =~ s/\s+.*/ char(16) NOT NULL/
			unless defined $config->{COLUMN_DEF}->{$key};

	my $query = "create table $tablename ( \n";
	$query .= join ",\n", @cols;
	$query .= "\n)\n";

	# test creation of table
	TESTIT: {
		my $q = $query;
		eval {
			$db->do("drop table mv_test_create")
		};
		$q =~ s/create\s+table\s+(\S+)/create table mv_test_create/;
		if(!  $db->do($q) ) {
			::logError(
						"bad table creation statement:\n%s\n\nError: %s",
						$query,
						$DBI::errstr,
			);
			warn "$DBI::errstr\n";
			return undef;
		}
		$db->do("drop table mv_test_create")
	}

	$db->do("drop table $tablename")
		or warn "$DBI::errstr\n";
	
	$db->do($query)
		or warn "DBI: Create table '$tablename' failed: $DBI::errstr\n";
	::logError("table %s created: %s" , $tablename, $query );

	$db->do("create index ${tablename}_${key} on $tablename ($key)")
		or ::logError("table %s index failed: %s" , $tablename, $DBI::errstr);

	$config->{NAME} = $columns;

    my $s = [$config, $tablename, $key, $columns, undef, $db];
    bless $s, $class;
}

sub new {
	my ($class, $obj) = @_;
	bless [$obj], $class;
}

sub open_table {
    my ($class, $config, $tablename) = @_;
	
    my @call = find_dsn($config);
    my $dattr = pop @call;
    my $db;

	unless($config->{dsn_id}) {
		$config->{dsn_id} = join "_", @call;
    	if($Global::HotDBI->{$Vend::Cfg->{CatalogName}}) {
			$config->{hot_dbi} = 1;
			$DBI_connect_count{$config->{dsn_id}}++;
		}
	}
#::logDebug("db_file: $config->{db_file}");
#::logDebug("db_file_extended: $config->{db_file_extended}");
	unless ($db = $DBI_connect_cache{ $config->{dsn_id} }) {
		$db = DBI->connect( @call );
		$DBI_connect_cache{$config->{dsn_id}} = $db;
#::logDebug("connected to $config->{dsn_id}");
	}

#	if(! $Info and ($Info = $db->table_info()) ) {
#::logDebug("$tablename table_info: " . ::uneval($Info->fetchall_arrayref()));
#	}

    unless ($config->{hot_dbi}) {
		$DBI_connect_count{$config->{dsn_id}}++;
	}
#::logDebug("connect count open: " . $DBI_connect_count{$config->{dsn_id}});

	die "$tablename: $DBI::errstr" unless $db;

	if($config->{HANDLE_ONLY}) {
		return bless [$config, $tablename, undef, undef, undef, $db], $class;
	}
	my $key;
	my $columns;

	if(defined $dattr) {
		for(keys %$dattr) {
			$db->{$_} = $dattr->{$_};
		}
	}

	$config->{NAME} = list_fields($db, $tablename)
		if ! $config->{NAME};
	$config->{COLUMN_INDEX} = fields_index($config->{NAME})
		if ! $config->{COLUMN_INDEX};

	$config->{NUMERIC} = {} unless $config->{NUMERIC};

	die "DBI: no column names returned for $tablename\n"
			unless defined $config->{NAME}[1];

	# Check if we have a non-first-column key
	if($config->{KEY}) {
		$key = $config->{KEY};
	}
	else {
		$key = $config->{KEY} = $config->{NAME}[0];
	}
	$config->{KEY_INDEX} = $config->{COLUMN_INDEX}{lc $key}
		if ! $config->{KEY_INDEX};
	die ::errmsg("Bad key specification: %s"  .
					::uneval($config->{NAME}) .
					::uneval($config->{COLUMN_INDEX}),
					$key
		)
		if ! defined $config->{KEY_INDEX};

    my $s = [$config, $tablename, $key, $config->{NAME}, undef, $db];
	bless $s, $class;
}

sub close_table {
	my $s = shift;
	return 1 if ! defined $s->[$DBI];
	undef $s->[$CONFIG]{_Insert_h};
	undef $s->[$CONFIG]{Update_handle};
    undef $s->[$CONFIG]{Exists_handle};
    return 1 if $s->[$CONFIG]{hot_dbi};
#::logDebug("connect count close: " . ($DBI_connect_count{$s->[$CONFIG]->{dsn_id}} - 1));
	return 1 if --$DBI_connect_count{$s->[$CONFIG]->{dsn_id}} > 0;
	undef $DBI_connect_cache{$s->[$CONFIG]->{dsn_id}};
	$s->[$DBI]->disconnect();
}

sub columns {
	my ($s) = shift;
	$s = $s->import_db() if ! defined $s->[$DBI];
    return @{$s->[$NAME]};
}

sub test_column {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	return $s->[$CONFIG]->{COLUMN_INDEX}{lc $column};
}

sub quote {
	my($s, $value, $field) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	return $s->[$DBI]->quote($value)
		unless $field and $s->numeric($field);
	return $value;
}

sub numeric {
	return exists $_[0]->[$CONFIG]->{NUMERIC}->{$_[1]};
}

sub filter {
	my ($s, $ary, $col, $filter) = @_;
	my $column;
	for(keys %$filter) {
		next unless defined ($column = $col->{$_});
		$ary->[$column] = Vend::Interpolate::filter_value(
								$filter->{$_},
								$ary->[$column],
								$_,
						  );
	}
}

sub inc_field {
    my ($s, $key, $column, $value) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
    my $sth = $s->[$DBI]->prepare(
		"select $column from $s->[$TABLE] where $s->[$KEY] = $key");
    die "inc_field: $DBI::errstr\n" unless defined $sth;
    $sth->execute();
    $value += ($sth->fetchrow_array)[0];
	$value = $s->[$DBI]->quote($value)
		unless exists $s->[$CONFIG]{NUMERIC}{$column};
    $sth = $s->[$DBI]->do("update $s->[$TABLE] SET $column=$value where $s->[$KEY] = $key");
    $value;
}

sub column_index {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	return $s->[$CONFIG]{COLUMN_INDEX}{lc $column};
}

sub column_exists {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	return defined($s->[$CONFIG]{COLUMN_INDEX}{lc $column});
}

sub field_accessor {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
    return sub {
        my ($key) = @_;
		$key = $s->[$DBI]->quote($key)
			unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
        my $sth = $s->[$DBI]->prepare
			("select $column from $s->[$TABLE] where $s->[$KEY] = $key")
				or die $DBI::errstr;
		($sth->fetchrow)[0];
    };
}

sub bind_entire_row {
	my($s, $sth, $key, @fields) = @_;
#::logDebug("bind_entire_row=" . ::uneval(\@_));
	my $i;
	my $numeric = $s->[$CONFIG]->{NUMERIC};
	my $name = $s->[$NAME];
	my $j = 1;
	for($i = 0; $i < scalar @$name; $i++, $j++) {
#::logDebug("bind $j=$fields[$i]");
		$sth->bind_param(
			$j,
			$fields[$i],
			(! exists $numeric->{$name->[$i]} ? undef : DBI::SQL_INTEGER),
			);
	}
	$sth->bind_param(
			$j,
			$key,
			(! exists $numeric->{$name->[$i]} ? undef : DBI::SQL_INTEGER),
			)
		if $key;
	return;
}

sub set_row {
    my ($s, @fields) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	my $cfg = $s->[$CONFIG];
	$s->filter(\@fields, $s->[$CONFIG]{COLUMN_INDEX}, $s->[$CONFIG]{FILTER_TO})
		if $s->[$CONFIG]{FILTER_TO};
	if(! $cfg->{_Insert_h}) {
		my (@ins_mark);
		my $i = 0;
		for(@{$s->[$NAME]}) {
			push @ins_mark, '?';
			$cfg->{_Key_column} = $i if $s->[$KEY] eq $_;
			$i++;
		}
		die "set_row init for $s->[$TABLE]: No key column found."
			unless defined $cfg->{_Key_column};
		my $ins_string = join ", ",  @ins_mark;
		my $query = "INSERT INTO $s->[$TABLE] VALUES ($ins_string)";
#::logDebug("set_row query=$query");
		$cfg->{_Insert_h} = $s->[$DBI]->prepare($query);
		die "$DBI::errstr\n" if ! defined $cfg->{_Insert_h};
	}

	eval {
		my $val = $s->quote($fields[$cfg->{_Key_column}], $s->[$KEY]);
		$s->[$DBI]->do("delete from $s->[$TABLE] where $s->[$KEY] = $val");
	};
    $s->bind_entire_row($cfg->{_Insert_h}, undef, @fields);
	$cfg->{_Insert_h}->execute()
		or die "$DBI::errstr\n";
}

sub row_hash {
    my ($s, $key) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
    my $sth = $s->[$DBI]->prepare(
		"select * from $s->[$TABLE] where $s->[$KEY] = $key");
    $sth->execute()
		or die("execute error: $DBI::errstr");
	return $sth->fetchrow_hashref()
		unless $s->[$CONFIG]{FILTER_FROM};
}

sub field_settor {
    my ($s, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
    return sub {
        my ($key, $value) = @_;
		$value = $s->[$DBI]->quote($value)
			unless exists $s->[$CONFIG]->{NUMERIC}->{$column};
		$key = $s->[$DBI]->quote($key)
			unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
        $s->[$DBI]->do("update $s->[$TABLE] SET $column=$value where $s->[$KEY] = $key");
    };
}

sub field {
    my ($s, $key, $column) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
	my $query = "select $column from $s->[$TABLE] where $s->[$KEY] = $key";
#::logDebug("DBI field: key=$key column=$column query=$query");
    my $sth = $s->[$DBI]->prepare(
		"select $column from $s->[$TABLE] where $s->[$KEY] = $key");
    $sth->execute()
		or die("execute error: $DBI::errstr");
	my $data = ($sth->fetchrow_array())[0];
	return '' unless $data =~ /\S/;
	$data;
}

sub set_field {
    my ($s, $key, $column, $value) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];
    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to set %s in read-only table",
					"$s->[$CONFIG]{name}::${column}::$key",
					);
		return undef;
	}
	my $rawkey = $key;
	my $rawval = $value;
	$key   = $s->quote($key, $s->[$KEY]);
	$value = $s->quote($value, $column);
	my $query;
	if($s->record_exists($rawkey)) {
		$query = <<EOF;
update $s->[$TABLE] SET $column = $value where $s->[$KEY] = $key
EOF
	}
	else {
		$query = <<EOF;
insert into $s->[$TABLE] ($s->[$KEY], $column) VALUES ($key, $value)
EOF
	}
	$s->[$DBI]->do($query)
		or die "$DBI::errstr\n";
	return $rawval;
}

sub ref {
	return $_[0] if defined $_[0]->[$DBI];
	return $_[0]->import_db();
}

sub test_record {
	1;
}

sub record_exists {
    my ($s, $key) = @_;
    $s = $s->import_db() if ! defined $s->[$DBI];
    my $query;
    $query = $s->[$CONFIG]{Exists_handle}
        or
	    $query = $s->[$DBI]->prepare(
				"select $s->[$KEY] from $s->[$TABLE] where $s->[$KEY] = ?"
			)
        and
		$s->[$CONFIG]{Exists_handle} = $query;
    my $status;
    eval {
        $status = defined $s->[$DBI]->selectrow_array($query, undef, $key);
    };
    return undef if $@;
    return $status;
}

sub delete_record {
    my ($s, $key) = @_;
	$s = $s->import_db() if ! defined $s->[$DBI];

    if($s->[$CONFIG]{Read_only}) {
		::logError("Attempt to delete record '%s' from read-only database %s",
						$key,
						$s->[$CONFIG]{name},
						);
		return undef;
	}
	$key = $s->[$DBI]->quote($key)
		unless exists $s->[$CONFIG]{NUMERIC}{$s->[$KEY]};
    $s->[$DBI]->do("delete from $s->[$TABLE] where $s->[$KEY] = $key");
}

sub fields_index {
	my($fields) = @_;
	my %idx;
	for( my $i = 0; $i < @$fields; $i++) {
		$idx{lc $fields->[$i]} = $i;
	}
	return \%idx;
}

sub list_fields {
	my($db, $name) = @_;
	my @fld;

	my $sth = $db->prepare("select * from $name")
		or die $DBI::errstr;

	# Wish we didn't have to do this, but we cache the columns
	$sth->execute()		or die "$DBI::errstr\n";

	@fld = @{$sth->{NAME}};
	return \@fld;
}

# OLDSQL

# END OLDSQL

sub touch {
	return ''
}

# Now supported, including qualification
sub each_record {
    my ($s, $qual) = @_;
#::logDebug("qual=$qual");
	$s = $s->import_db() if ! defined $s->[$DBI];
    my ($table, $db, $each) = @{$s}[$TABLE,$DBI,$EACH];
    unless(defined $each) {
		my $query = $db->prepare("select * from $table " . ($qual || '') )
            or die $DBI::errstr;
		$query->execute();
		my $idx = $s->[$CONFIG]{KEY_INDEX};
		$each = sub {
			my $ref = $query->fetchrow_arrayref()
				or return undef;
			return ($ref->[$idx], $ref);
		};
        push @$s, $each;
    }
	my ($key, $return) = $each->();
	if(! defined $key) {
		pop @$s;
		return ();
	}
    return ($key, @$return);
}

# Now supported, including qualification
sub each_nokey {
    my ($s, $qual) = @_;
#::logDebug("qual=$qual");
	$s = $s->import_db() if ! defined $s->[$DBI];
    my ($table, $db, $each) = @{$s}[$TABLE,$DBI,$EACH];
    unless(defined $each) {
		my $query = $db->prepare("select * from $table " . ($qual || '') )
            or die $DBI::errstr;
		$query->execute();
		my $idx = $s->[$CONFIG]{KEY_INDEX};
		$each = sub {
			my $ref = $query->fetchrow_arrayref()
				or return undef;
			return ($ref);
		};
        push @$s, $each;
    }
	my ($return) = $each->();
	if(! defined $return->[0]) {
		pop @$s;
		return ();
	}
    return (@$return);
}

sub sprintf_substitute {
	my ($s, $query, $fields, $cols) = @_;
	my ($tmp, $arg);
	my $i;
	if(defined $cols->[0]) {
		for($i = 0; $i <= $#$fields; $i++) {
			$fields->[$i] = $s->quote($fields->[$i], $cols->[$i])
				if defined $cols->[0];
		}
	}
	return sprintf $query, @$fields;
}

sub query {
    my($s, $opt, $text, @arg) = @_;

    if(! ref $opt) {
        unshift @arg, $text;
        $text = $opt;
        $opt = {};
    }

	$s = $s->import_db() if ! defined $s->[$DBI];
	$opt->{query} = $opt->{sql} || $text if ! $opt->{query};

#::logDebug("\$db->query=$opt->{query}");
	if(defined $opt->{values}) {
		# do nothing
		@arg = $opt->{values} =~ /['"]/
				? ( Text::ParseWords::shellwords($opt->{values})  )
				: (grep /\S/, split /\s+/, $opt->{values});
		@arg = @{$::Values}{@arg};
	}

	my $query;
    $query = ! scalar @arg
			? $opt->{query}
			: sprintf_substitute ($s, $opt->{query}, \@arg);

	my $codename = $s->[$CONFIG]{KEY};
	my $ref;
	my $relocate;
	my $return;
	my $spec;
	my $stmt;
	my $sth;
	my $update;
	my $rc;
	my %nh;
	my @na;
	my @out;
	my $db = $s->[$DBI];

    if ( 0 and "\L$opt->{st}" eq 'db') {
		eval {
			($spec, $stmt) = Vend::Scan::sql_statement($query, $ref);
		};
		if(! CORE::ref $spec) {
			::logError("Bad SQL, query was: %s", $query);
			return ($opt->{failure} || undef);
		}
		my @additions = grep length($_) == 2, keys %$opt;
		if(@additions) {
			@{$spec}{@additions} = @{$opt}{@additions};
		}
	}
	else {
		$update = 1 if $query !~ /^\s*select\s+/i;

		eval {
			if($update and $s->[$CONFIG]{Read_only}) {
				my $msg = errmsg(
							"Attempt to do update on read-only table.\nquery: %s",
							$query,
						  );
				::logError($msg);
				die "$msg\n";
			}
			$opt->{row_count} = 1 if $update;
			$sth = $db->prepare($query);
			$rc = $sth->execute();
			
			if ($opt->{hashref}) {
				my @ary;
				while ( defined ($_ = $sth->fetchrow_hashref) ) {
					push @ary, $_;
				}
				die $DBI::errstr if $sth->err();
				$ref = $Vend::Interpolate::Tmp->{$opt->{hashref}} = \@ary;
			}
			else {
				my $i = 0;
				@na = @{$sth->{NAME} || []};
				%nh = map { (lc $_, $i++) } @na;
				$ref = $Vend::Interpolate::Tmp->{$opt->{arrayref}}
					= $sth->fetchall_arrayref()
					 or die $DBI::errstr;
			}
		};
		if($@) {
			if(! $sth) {
				# query failed, probably because no table
				# Do nothing and fall through to MVSEARCH
			}
			else {
				::logError("SQL query failed: %s\nquery was: %s", $@, $query);
				$return = $opt->{failure} || undef;
			}
		}
	}

MVSEARCH: {
	last MVSEARCH if defined $ref;

	my @tabs = @{$spec->{fi}};
	for (@tabs) {
		s/\..*//;
	}
	if (! defined $s || $tabs[0] ne $s->[$CONFIG]{name}) {
		unless ($s = $Vend::Database{$tabs[0]}) {
			::logError("Table %s not found in databases", $tabs[0]);
			return $opt->{failure} || undef;
		}
#::logDebug("rerouting to $tabs[0]");
		$opt->{STATEMENT} = $stmt;
		$opt->{SPEC} = $spec;
		return $s->query($opt, $text);
	}

eval {

	if($stmt->command() ne 'SELECT') {
		if(defined $s and $s->[$CONFIG]{Read_only}) {
			die ("Attempt to write read-only database $s->[$CONFIG]{name}");
		}
		$update = $stmt->command();
	}
	my @vals = $stmt->row_values();
	
	@na = @{$spec->{rf}}     if $spec->{rf};

	$spec->{fn} = [$s->columns];
	if(! @na) {
		@na = ! $update || $update eq 'INSERT' ? '*' : $codename;
	}
	@na = @{$spec->{fn}}       if $na[0] eq '*';
	$spec->{rf} = [@na];
	
#::logDebug("tabs='@tabs' columns='@na' vals='@vals'"); 

    my $search;
	$opt->{bd} = $tabs[0];
	$search = new Vend::DbSearch;

	my %fh;
	my $i = 0;
	%nh = map { (lc $_, $i++) } @na;
	$i = 0;
	%fh = map { ($_, $i++) } @{$spec->{fn}};

#::logDebug("field hash: " . Vend::Util::uneval(\%fh)); 
	for ( qw/rf sf/ ) {
		next unless defined $spec->{$_};
		map { $_ = $fh{$_} } @{$spec->{$_}};
	}

	if($update) {
		die "DBI tables must be updated natively.\n";
	}
	elsif ($opt->{hashref}) {
		$ref = $Vend::Interplate::Tmp->{$opt->{hashref}} = $search->hash($spec);
	}
	else {
		$ref = $Vend::Interplate::Tmp->{$opt->{arrayref}} = $search->array($spec);
	}
};
#::logDebug("search spec: " . Vend::Util::uneval($spec));
#::logDebug("name hash: " . Vend::Util::uneval(\%nh));
#::logDebug("ref returned: " . Vend::Util::uneval($ref));
#::logDebug("opt is: " . Vend::Util::uneval($opt));
	if($@) {
		::logError("MVSQL query failed for %s: %s\nquery was: %s",
					$opt->{table},
					$@,
					$query,
					);
		$return = $opt->{failure} || undef;
	}
} # MVSEARCH
#::logDebug("finished query, rc=$rc ref=$ref arrayref=$opt->{arrayref} Tmp=$Vend::Interpolate::Tmp->{$opt->{arrayref}}");
	return $rc
		if $opt->{row_count};
	return Vend::Interpolate::tag_sql_list($text, $ref, \%nh, $opt)
		if $opt->{list};
	return Vend::Interpolate::html_table($opt, $ref, \@na)
		if $opt->{html};
	return Vend::Util::uneval($ref)
		if $opt->{textref};
	return wantarray ? ($ref, \%nh, \@na) : $ref;
}

1;

__END__
