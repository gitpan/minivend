# Vend/Scan.pm:  Prepare searches for MiniVend
#
# $Id: Scan.pm,v 1.10 2000/03/02 10:33:04 mike Exp $
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

package Vend::Scan;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(
			create_last_search
			finish_search
			find_search_params
			perform_search
			);

$VERSION = substr(q$Revision: 1.10 $, 10);

use strict;
use Vend::Util;
use Vend::Interpolate;
use Vend::Data qw(product_code_exists_ref column_index);

my @Order = ( qw(
					mv_dict_look
					mv_searchspec
					mv_search_file
					mv_base_directory
					mv_field_names
                    mv_field_file
					mv_verbatim_columns
					mv_range_look
					mv_cache_key
					mv_profile
					mv_case
					mv_negate
					mv_numeric
                    mv_column_op
					mv_begin_string
					mv_coordinate
					mv_nextpage
					mv_dict_end
					mv_dict_fold
					mv_dict_limit
					mv_dict_order
					mv_failpage
					mv_first_match
					mv_all_chars
					mv_return_all
					mv_exact_match
					mv_head_skip
					mv_index_delim
					mv_list_only
					mv_matchlimit
                    mv_more_decade
					mv_min_string
					mv_max_matches
					mv_orsearch
					mv_range_min
					mv_range_max
					mv_range_alpha
					mv_record_delim
					mv_return_delim
					mv_return_fields
					mv_return_file_name
					mv_return_reference
					mv_substring_match
					mv_return_spec
					mv_spelling_errors
					mv_search_field
					mv_search_group
					mv_search_label
					mv_search_page
					mv_search_relate
					mv_sort_field
					mv_sort_option
					mv_searchtype
					mv_unique
					mv_more_matches
					mv_value
					prefix

));

my %Scan = ( qw(

                    ac  mv_all_chars
                    bd  mv_base_directory
                    bs  mv_begin_string
                    ck  mv_cache_key
                    co  mv_coordinate
                    cs  mv_case
                    cv  mv_verbatim_columns
                    de  mv_dict_end
                    df  mv_dict_fold
                    di  mv_dict_limit
                    dl  mv_dict_look
                    DL  mv_raw_dict_look
                    do  mv_dict_order
                    dr  mv_record_delim
                    em  mv_exact_match
                    er  mv_spelling_errors
                    ff  mv_field_file
                    fi  mv_search_file
                    fm  mv_first_match
                    fn  mv_field_names
                    hs  mv_head_skip
                    ix  mv_index_delim
                    lb  mv_search_label
                    lo  mv_list_only
                    lr  mv_search_line_return
                    md  mv_more_decade
                    ml  mv_matchlimit
                    mm  mv_max_matches
                    MM  mv_more_matches
                    mp  mv_profile
                    ms  mv_min_string
                    ne  mv_negate
                    ng  mv_negate
                    np  mv_nextpage
                    nu  mv_numeric
                    op  mv_column_op
                    os  mv_orsearch
					pf  prefix
                    ra  mv_return_all
                    rd  mv_return_delim
                    rf  mv_return_fields
                    rg  mv_range_alpha
                    rl  mv_range_look
                    rm  mv_range_min
                    rn  mv_return_file_name
                    rr  mv_return_reference
                    rs  mv_return_spec
                    rx  mv_range_max
                    SE  mv_raw_searchspec
                    se  mv_searchspec
                    sf  mv_search_field
                    sg  mv_search_group
                    si  mv_search_immediate
                    sp  mv_search_page
                    sq  mv_sql_query
                    sr  mv_search_relate
                    st  mv_searchtype
                    su  mv_substring_match
                    td  mv_table_cell
                    tf  mv_sort_field
                    th  mv_table_header
                    to  mv_sort_option
                    tr  mv_table_row
                    un  mv_unique
                    va  mv_value

				) );

my @ScanKeys = keys %Scan;
my %RevScan;
%RevScan = reverse %Scan;

my %Parse = (

    mv_search_group         =>  \&_array,
    mv_search_field         =>  \&_array,
    mv_all_chars            =>  \&_yes_array,
    mv_begin_string         =>  \&_yes_array,
    mv_case                 =>  \&_yes_array,
    mv_negate               =>  \&_yes_array,
    mv_numeric              =>  \&_yes_array,
    mv_orsearch             =>  \&_yes_array,
    mv_substring_match      =>  \&_yes_array,
    mv_column_op            =>  \&_array,
    mv_coordinate           =>  \&_yes,

	mv_field_names          =>	\&_array,
	mv_spelling_errors      => 	sub { my $n = int($_[1]); $n < 8 ? $n : 1; },
    mv_dict_limit           =>  \&_dict_limit,
    mv_exact_match          =>  \&_yes,
    mv_head_skip            =>  \&_number,
    mv_matchlimit           =>  sub { $_[1] =~ /(\d+)/ ? $1 : 50 },
    mv_max_matches          =>  sub { $_[1] =~ /(\d+)/ ? $1 : 2000 },
    mv_min_string           =>  sub { $_[1] =~ /(\d+)/ ? $1 : 1 },
    mv_profile              =>  \&parse_profile,
    mv_range_alpha          =>  \&_array,
    mv_range_look           =>  \&_array,
    mv_range_max            =>  \&_array,
    mv_range_min            =>  \&_array,
    mv_return_all           =>  \&_yes,
    mv_return_fields        =>  \&_array,
    mv_return_file_name     =>  \&_yes,
    mv_save_context         =>  \&_array,
    mv_searchspec           =>  \&_verbatim_array,
    mv_sort_field           =>  \&_array,
    mv_sort_option          =>  \&_opt,
    mv_unique               =>  \&_yes,
    mv_value                =>  \&_value,
	mv_sql_query			=>  sub {
								my($ref, $val) = @_;
								my $p = Vend::Interpolate::escape_scan($val, $ref);
								find_search_params($ref, $p);
								return $val;
							},
	#base_directory      => 	\&_file_security_scalar,
	mv_field_file          => 	\&_file_security_scalar,
	mv_search_file         => 	\&_file_security,

);

sub create_last_search {
	my ($ref) = @_;
	my @out;
	my @val;
	my ($key, $val);
	while( ($key, $val) = each %$ref) {
		next unless defined $RevScan{$key};
		@val = split /\0/, $val;
		for(@val) {
			s!/!__SLASH__!g;
			s!(\W)!sprintf '%%%02x', ord($1)!eg;
			s!__SLASH__!::!g;
			push @out, "$RevScan{$key}=$_";
		}
	}
	$Vend::Session->{last_search} = join "/", 'scan', @out;
}

sub find_search_params {
	my($c,$param) = @_;
	my(@args);
	if(! $param) {
		$c = \%CGI::values;
	}
	else {
		$param =~ s/__NULL__/\0/g;
		@args = split m:/:, $param;
	}

	my($var,$val);

	for(@args) {
		($var,$val) = split /=/, $_, 2;
		next unless defined $Scan{$var};
		$val =~ s!::!/!g;
		$val =~ s/%([A-Fa-f0-9][A-Fa-f0-9])/chr(hex($1))/ge;
		$c->{$Scan{$var}} = defined $c->{$Scan{$var}}
							? ($c->{$Scan{$var}} . "\0$val" )
							: $val;
	}
#::logDebug("find_search_params: " . ::uneval($c));
	return $c;
}

my %Save;

sub parse_map {
	my($ref,$map) = @_;
	$map = delete $ref->{mv_search_map} unless $map;
	use strict;
	return undef unless defined $map;
	my($params);
	if(index($map, "\n") != -1) {
		$params = $map;
	}
    elsif(defined $Vend::Cfg->{SearchProfileName}->{$map}) {
        $map = $Vend::Cfg->{SearchProfileName}->{$map};
        $params = $Vend::Cfg->{SearchProfile}->[$map];
    }
    elsif($map =~ /^\d+$/) {
        $params = $Vend::Cfg->{SearchProfile}->[$map];
    }
    elsif(defined $::Scratch->{$map}) {
        $params = $::Scratch->{$map};
    }
	
	return undef unless $params;

	if ( $params =~ m{\[} or $params =~ /__/) {
		$params = interpolate_html($params);
	}

	my($ary, $var,$source, $i);

	$params =~ s/^\s+//mg;
	$params =~ s/\s+$//mg;
	my(@param) = grep $_, split /[\r\n]+/, $params;
	for(@param) {
		($var,$source) = split /[\s=]+/, $_, 2;
		$ref->{$var} = [] unless defined $ref->{$var};
		$ref->{$source} = '' if ! defined $ref->{$source};
		$ref->{$source} =~ s/\0/|/g;
		push @{$ref->{$var}}, ($ref->{$source});
	}
	return 1;
}

sub parse_profile_ref {
    my ($ref, $profile) = @_;
    my ($var, $p);
    foreach $p (keys %$profile) {
		next unless
			$var = $Scan{$p}
					or
			(defined $RevScan{$p} and $var = $p);
		$ref->{$var} = $profile->{$p}, next
			if ref $profile->{$p} || ! defined $Parse{$var};
		$ref->{$var} = &{$Parse{$var}}($ref,$profile->{$p});
    }
    return;
}

sub parse_profile {
	my($ref,$profile) = @_;
	return undef unless defined $profile;
	my($params);
    if(defined $Vend::Cfg->{SearchProfileName}->{$profile}) {
        $profile = $Vend::Cfg->{SearchProfileName}->{$profile};
        $params = $Vend::Cfg->{SearchProfile}->[$profile];
    }
    elsif($profile =~ /^\d+$/) {
        $params = $Vend::Cfg->{SearchProfile}->[$profile];
    }
    elsif(defined $::Scratch->{$profile}) {
        $params = $::Scratch->{$profile};
    }
	
	return undef unless $params;

	if ( index($params, '[') != -1 or index($params, '__') != -1) {
		$params = interpolate_html($params);
	}

	my($p, $var,$val);
	my $status = $profile;
	undef %Save;
	$params =~ s/^\s+//mg;
	$params =~ s/\s+$//mg;
	my(@param) = grep $_, split /[\r\n]+/, $params;
	for(@param) {
		($var,$val) = split /[\s=]+/, $_, 2;
		$status = -1 if $var eq 'mv_last';
		next unless defined $RevScan{$var} or $var = $Scan{$var};
		$val =~ s/&#(\d+);/chr($1)/ge;
		$Save{$p} = $val;
		$val = &{$Parse{$var}}($ref,$val,$ref->{$var} || undef)
				if defined $Parse{$var};
		$ref->{$var} = $val if defined $val;
	}

	return $status;
}

sub finish_search {
    my($q) = @_;
#::logDebug("finishing up search spec=" . ::uneval($q));
    my $matches = $q->{'matches'};
    $::Values->{mv_search_match_count}    = $matches;
	delete $::Values->{mv_search_error};
	$::Values->{mv_search_error} = $q->{mv_search_error}
		if $q->{mv_search_error};
    $::Values->{mv_matchlimit}     = $q->{mv_matchlimit};
    $::Values->{mv_first_match}    = $q->{mv_first_match}
			if defined $q->{mv_first_match};
    $::Values->{mv_searchspec} 	   = $q->{mv_searchspec};
    $::Values->{mv_raw_searchspec} = $q->{mv_raw_searchspec} || undef;
    $::Values->{mv_raw_dict_look}  = $q->{mv_raw_dict_look}  || undef;
    $::Values->{mv_dict_look}      = $q->{mv_dict_look} || undef;
}

# Search for an item with glimpse or text engine
sub perform_search {
    my($c,$more_matches,$pre_made) = @_;

	if (!$c) {
		return undef unless $Vend::Session->{search_params};
		($c, $more_matches) = @{$Vend::Session->{search_params}};
		unless($c->{mv_cache_key}) {
			Vend::Scan::create_last_search($c);
			$c->{mv_cache_key} = generate_key($Vend::Session->{last_search});
		}
	}
	elsif ($c->{mv_search_immediate}) {
        unless($c->{mv_cache_key}) {
            undef $c->{mv_search_immediate};
            Vend::Scan::create_last_search($c);
            $c->{mv_cache_key} = generate_key($Vend::Session->{last_search});
        }
	}

	my($v) = $::Values;
    my($param);
	my(@fields);
	my(@specs);
	my($out);
	my ($p, $q, $matches);

	my %options;
	$options{mv_session_id} = $c->{mv_session_id} || $Vend::SessionID;
	if($c->{mv_more_matches}) {
		@options{qw/mv_cache_key mv_next_pointer mv_last_pointer mv_matchlimit/}
			= split /:/, $c->{mv_more_matches};
		my $s = new Vend::Search %options;
		$q = $s->more_matches();
		finish_search($q);
		return $q;
	}


	# A text or glimpse search from here

	parse_map($c) if defined $c->{mv_search_map};

	if(defined $c->{mv_sql_query}) {
		my $params = Vend::Interpolate::escape_scan(delete $c->{mv_sql_query}, $c);
		find_search_params($c, $params);
	}

	if($pre_made) {
		parse_profile_ref(\%options,$c);
	}
	else {
		foreach $p ( grep defined $c->{$_}, @ScanKeys) {
			$c->{$Scan{$p}} = $c->{$p}
				if ! defined $c->{$Scan{$p}};
		}
		foreach $p ( grep defined $c->{$_}, @Order) {
#::logDebug("Parsing $p");
			if(defined $Parse{$p}) {
				$options{$p} = &{$Parse{$p}}(\%options, $c->{$p})
			}
			else {
				$options{$p} = $c->{$p};
			}
			last if $options{$p} eq '-1' and $p eq 'mv_profile';
		}
	}

#::logDebug("Cache key: $options{mv_cache_key}");
	if(! $options{mv_cache_key}) {
		$options{mv_cache_key} = $c->{mv_search_label} ||
								 generate_key(
									@{$options{mv_searchspec}},
									@{$options{mv_search_field}},
									@{$options{mv_search_file}},
								);
#::logDebug("generated cache key: $options{mv_cache_key}");
	}

#::logDebug("Options after parse: " . ::uneval(\%options));

# GLIMPSE
 	if (defined $options{mv_searchtype} && $options{mv_searchtype} eq 'glimpse') {
		undef $options{mv_searchtype} if ! $Vend::Cfg->{Glimpse};
	}
# END GLIMPSE

  SEARCH: {

		$options{mv_return_all} = 1
			if $options{mv_dict_look} and ! $options{mv_searchspec};
	
		if (defined $pre_made) {
			$q = $pre_made;
			@{$q}{keys %options} = (values %options);
		}
		elsif (! defined $options{mv_searchtype} or $options{mv_searchtype} eq 'text') {
			$q = new Vend::TextSearch %options;
		}
		elsif ( $options{mv_searchtype} =~ /db|sql/i){
			$q = new Vend::DbSearch %options;
#::logDebug("Glimpsesearch object: " . ::uneval($q));
		}
# GLIMPSE
		elsif ( $options{mv_searchtype} eq 'glimpse'){
			$q = new Vend::Glimpse %options;
		}
# END GLIMPSE
		else  {
			eval {
				no strict 'refs';
				$q = "$Global::Variable->{$options{mv_searchtype}}"->new(%options);
			};
			if ($@) {
				::display_special_page(
					find_special_page('badsearch'),
					errmsg("Bad search type %s: %s", $options{mv_searchtype}, $@ ),
					);
				return 0;
			}
		}

		if(defined $options{mv_return_spec}) {
			$q->{matches} = scalar @{$q->{mv_searchspec}};
			$q->{mv_results} = [ map { [ $_ ] } @{$q->{mv_searchspec}} ];
			last SEARCH;
		}

#::logDebug(::uneval($q));
		$out = $q->search();
  } # last SEARCH

	if($q->{mv_list_only}) {
		return $q->{mv_results};
	}

	finish_search($q);

	return $q;

}

BEGIN {
	eval { require SQL::Statement; };
}

my %scalar = (qw/ st 1 ra 1 co 1 os 1/);

sub push_spec {
	my ($parm, $val, $ary, $hash) = @_;
	push(@$ary, "$parm=$val"), return
		if $ary;
	$hash->{$parm} = $val, return
		if $scalar{$parm};
	$hash->{$parm} = []
		if ! defined $hash->{$parm};
	push @{$hash->{$parm}}, $val;
	return;
}

sub sql_statement {
	my($text, $ref, $table) = @_;
#::logDebug("sql_statement input=$text");
	my $ary;
	my $hash;

	if(wantarray) {
		$hash = {};
		$ary = '';
	}
	else {
		$ary = [];
		$hash = '';
	}

	if ($table) {
		push_spec('fi', $table, $ary, $hash)
# GLIMPSE
			unless "\L$table" eq 'glimpse';
# END GLIMPSE
	}

	die "SQL is not enabled for MiniVend. Get the SQL::Statement module.\n"
		unless $INC{'SQL/Statement.pm'};

	my $parser = SQL::Parser->new('Ansi');

	# Strip possible leading stuff
	$text =~ s/^\s*sq\s*=//;
	my $stmt;
	eval {
		$stmt = SQL::Statement->new($text, $parser);
	};
	if($@ and $text =~ s/^\s*sq\s*=(.*)//m) {
#::logDebug("failed first query, error=$@");
		my $query = $1;
		push @$ary, $text if $ary;
		eval {
			$stmt = SQL::Statement->new($query, $parser);
		};
	}
	if($@) {
		::logError("Bad SQL statement: $@\nQuery was: $text.\n");
		return "se=BAD_SQL";
	}

	my $nuhash;
	my $codename;

	my $update = $stmt->command();
	undef $update if $update eq 'SELECT';
#	CODECHECK: {
#		last CODECHECK if ! $update;
#		my $i = 0;
#		for($stmt->columns()) {
#			($stmt->{MV_VALUE_RELOCATE} = $i, last)
#				if $_ eq $codename || $_ eq '0';
#			$i++;
#		}
#	}

	for($stmt->tables()) {
		my $t = $_->name();

		my $codename;
		my $db = Vend::Data::database_exists_ref($t);
		if($db) {
			$codename = $db->config('KEY') || 'code';
			$nuhash = $db->config('NUMERIC') || undef;
			push_spec( 'fi', $Vend::Cfg->{Database}{$t}{'file'}, $ary, $hash);
		}
# GLIMPSE
		elsif ("\L$t" eq 'glimpse') {
			$codename = 'code';
			undef $nuhash;
			push_spec('st', 'glimpse', $ary, $hash);
		}
# END GLIMPSE
		else {
			push_spec('fi', $t, $ary, $hash);
		}
#::logDebug("t=$t obj=$_ db=$db nuhash=" . ::uneval($nuhash));
	}

	$text =~ /\bselect\s+distinct\s+/i and push_spec( 'un', 'yes', $ary, $hash);

	for($stmt->columns()) {
		my $name = $_->name();
		#($stmt->{MV_VALUE_RELOCATE} = 0, last) if $name eq '*';
		push_spec('rf', $name, $ary, $hash);
		last if $name eq '*';
#::logDebug("column name=" . $_->name() . " table=" . $_->table());
	}
#	if(! $update) {
#		# do nothing
#	}
#	elsif ($stmt->{mv_value_relocate}) {
#		splice(@{$hash->{rf}}, $stmt->{mv_value_relocate}, 1);
#	}
#	elsif ($update eq 'insert') {
#		$stmt->{mv_value_relocate} = 0 if ! $stmt->columns();
#	}
#
	my @order;

	@order = $stmt->order();
	for(@order) {
		my $c = $_->column();
		push_spec('tf', $c, $ary, $hash);
		my $d = $_->desc() ? 'fr' : 'f';
		push_spec('to', $d, $ary, $hash);
	}

	my $where;
	my @where;
	my $numeric;
	@where = $stmt->where();
	if(defined $where[0]) {
	  my $or;
	  push_spec('co', 'yes', $ary, $hash);
	  do {
	  	my $where = shift @where;
		my $op = $where->op();
		my $col = $where->arg1();
		my $spec = $where->arg2();
#::logDebug("where=$where op=$op arg1=$col arg2=$spec");
		OP: {
			if($op eq 'OR') {
				push_spec( 'os', 'yes', $ary, $hash)     unless $or++;
				push(@where, $where->arg1() , $where->arg2());
			}
			elsif($op eq 'AND') {
				push(@where, $where->arg1() , $where->arg2());
			}
			else {

				my ($col, $spec);

				# Search spec is a variable if a ref
				$spec = $where->arg2();
				$spec = $ref->{$spec->name()}		if ref $spec;

				# Column name is a variable if a string
				$col = $where->arg1();
				$col = ref $col ? $col->name() : $::Values->{$col};

				$numeric = (defined $nuhash)
							? (exists $nuhash->{$col})
							: (
								$spec !~ /[^\d.]/		and
								($spec =~ tr/././) < 2	and
								$spec !~ /^0\d/				 );
#::logDebug("numeric for $col=$numeric");
				push_spec  ('nu', $numeric, $ary, $hash); 

#::logDebug("where col=$col spec=$spec");
				# If both are not supplied, we ignore it
				last OP unless defined $col and $spec;

				push_spec('se', $spec, $ary, $hash);
				push_spec('op', $op, $ary, $hash);
				push_spec('sf', $col, $ary, $hash);
				push_spec('ne', ($where->neg() || 0), $ary, $hash) ;

				
			}
		}
	  } while @where;

	}
	else {
		push_spec('ra', 'yes', $ary, $hash);
	}
	
#::logDebug("sql_statement output=" . Vend::Util::uneval($hash)) if $hash;
	return ($hash, $stmt) if $hash;

	my $string = join "\n", @$ary;
#::logDebug("sql_statement output=$string");
	return $string;
}

sub _value {
	my($ref, $in) = @_;
	return unless $in;
	my (@in) = split /\0/, $in;
	for(@in) {
		my($var,$val) = split /=/, $_, 2;
		$::Values->{$var} = $val;
	}
	return;
}

sub _opt {
	return ($_[2] || []) unless $_[1];
	my @fields = grep $_, split /\s*[,\0]\s*/, $_[1];
	unshift(@fields, @{$_[2]}) if $_[2];
	my $col;
	for(@fields) {
		$_ = 'none' unless $_;
	}
	\@fields;
}

sub _column_opt {
	return ($_[2] || []) unless length($_[1]);
	my @fields = grep /\S/, split /\s*[,\0]\s*/, $_[1];
	unshift(@fields, @{$_[2]}) if $_[2];
	my $col;
	for(@fields) {
		s/:.*//;
		next if /^\d+$/;
		if (! $_[0]->{mv_search_file} and defined ($col = column_index($_)) ) {
			$_ = $col + 1;
		}
		elsif ( $col = _find_field($_[0], $_) or defined $col ) {
			$_ = $col;
		}
		else {
			::logError( "Bad search column '%s=$col'" , $_ );
		}
	}
	\@fields;
}

sub _column {
	return ($_[2] || []) unless length $_[1];
	my @fields = split /\s*[,\0]\s*/, $_[1];
	unshift(@fields, @{$_[2]}) if $_[2];
	my $col;
	for(@fields) {
		next if /^\d+$/;
		next if $_[0]->{mv_verbatim_columns};
		next if /:/;
		if (! defined $_[0]->{mv_search_file} and defined ($col = column_index($_)) ) {
			$_ = $col + 1;
		}
		elsif ( $col = _find_field($_[0], $_) or defined $col ) {
			$_ = $col;
		}
		else {
			logError( "Bad search column '%s'" , $_ );
		}
	}
	\@fields;
}

sub _find_field {
	my($s, $field) = @_;
	my ($file, $i, $line, @fields);

	if($s->{mv_field_names}) {
		@fields = @{$s->{mv_field_names}};
	}
	elsif(! defined $s->{mv_search_file}) {
		return undef;
	}
	elsif(ref $s->{mv_search_file}) {
		$file = $s->{mv_search_file}->[0];
	}
	elsif($s->{mv_search_file}) {
		$file = $s->{mv_search_file};
	}
	else {
		return undef;
	}

	if(defined $file) {
		my $dir = $s->{mv_base_directory} || $Vend::Cfg->{ProductDir};
		open (Vend::Scan::FIELDS, "$dir/$file")
			or return undef;
		chomp($line = <Vend::Scan::FIELDS>);
		my $delim;
		$line = /([^-\w])/;
		$delim = quotemeta $1;
		@fields = split /$delim/, $line;
		close(Vend::Scan::FIELDS);
		$s->{mv_field_names} = \@fields;
	}
	$i = 0;
	for(@fields) {
		return $i if $_ eq $field;
		$i++;
	}
	return undef;
}

sub _command {
	return undef unless defined $_[1];
	return undef unless $_[1] =~ m{^\S+$};
	return $_[1];
}

sub _verbatim_array {
	return ($_[2] || undef) unless defined $_[1];
	my @fields;
#::logDebug("receiving verbatim_array: " . ::uneval (\@_));
	@fields = ref $_[1] ? @{$_[1]} : split /\0/, $_[1], -1;
	unshift(@fields, @{$_[2]}) if $_[2];
	return \@fields;
}

sub _array {
	return ($_[2] || undef) unless defined $_[1];
	my @fields;
	@fields = ref $_[1] ? @{$_[1]} : split /\s*[,\0]\s*/, $_[1], -1;
	unshift(@fields, @{$_[2]}) if $_[2];
	return \@fields;
}

sub _yes {
	return( defined($_[1]) && ($_[1] =~ /^[yYtT1]/));
}

sub _number {
	defined $_[1] ? $_[1] : 0;
}

sub _scalar {
	defined $_[1] ? $_[1] : '';
}

my $Pat = ($^O =~ /win32/i) ? '([A-Za-z]:)?[\\/]' : '/';

sub _file_security {
    my ($junk, $param, $passed) = @_;
    $passed = [] unless $passed;
    my(@files) = grep /\S/, split /\s*[,\0]\s*/, $param, -1;
    for(@files) {
        my $ok = (m:^$Pat:o || /\.\./) ? 0 : 1;
        if(!$ok) {
            $ok = 1 if $_ eq $::Variable->{MV_SEARCH_FILE};
            $ok = 1 if $::Scratch->{$_};
        }
		if($_ !~ /\./) {
			$_ = $Vend::Cfg->{Database}{$_}{'file'}
				if defined $Vend::Cfg->{Database}{$_}{'file'};
		}
		$ok &&= $_ !~ /$Vend::Cfg->{NoSearch}/
			if $Vend::Cfg->{NoSearch};
        push @$passed, $_ if $ok;
    }
    return $passed if @$passed;
	return [];
}

sub _file_security_scalar {
    my $result = _file_security(@_);
	return $result->[0];
}

sub _scalar_or_array {
	my(@fields) = split /\s*[,\0]\s*/, $_[1], -1;
	my $arg;
	if($arg = $_[2]) {
		$arg = [ $arg ] unless ref $arg;
		unshift(@fields, @{$arg});
	}
	scalar @fields > 1 ? \@fields : (defined $fields[0] ? $fields[0] : '');
}

sub _yes_array {
#::logDebug("_yes_array input=" . ::uneval(\@_));
	my(@fields) = split /\s*[,\0]\s*/, $_[1];
	if(defined $_[2]) {
		unshift(@fields, ref $_[2] ? @{$_[2]} : $_[2]);
	}
	map { $_ = _yes('',$_) } @fields;
#::logDebug("_yes_array fields=" . ::uneval(\@fields));
	return \@fields;
}

sub _dict_limit {
	my ($ref,$limit) = @_;
	return undef unless	defined $ref->{mv_dict_look};
	$limit = -1 if $limit =~ /^[^-0-9]/;
    $ref->{mv_dict_end} = $ref->{mv_dict_look};
    substr($ref->{mv_dict_end},$limit,1) =~ s/(.)/chr(ord($1) + 1)/e;
	return $_[1];
}

1;
__END__
