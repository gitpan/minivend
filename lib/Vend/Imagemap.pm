#!/usr/bin/perl
#
# Imagemap.pm -- interpret NCSA imagemap in CGI program
#
# $Id: Imagemap.pm,v 1.1 1999/11/12 08:46:23 mike Exp $
#
# This module adapted from the Perl imagemap program by:
#
# V. Khera <khera@kciLink.com>  7-MAR-1995
#
# documentation for the imagemap file follows that of the NCSA imagemap
# program.  Each point is an x,y tuple.  Each line in the map consists of
# one of the following formats.  Comment lines start with "#".
#
#   circle action center edgepoint
#   rect action upperleft lowerright
#   point action point
#   poly action point1 point2 point3 point4 ... pointN
#   default action
#
# using "point" and "default" in the same map makes no sense.  if "point"
# is used, the action for the closest one is selected.
#
# To use, define an image submit map on your form
#
#   <input type=image name=mv_todo SRC="image_url">
#   You can pass a "client-side" imagemap like this:
#
#  <input type="hidden" name="todo.map" value="rect action1 0,0 25,20">
#  <input type="hidden" name="todo.map" value="rect action2 26,0 50,20">
#  <input type="hidden" name="todo.map" value="rect action3 51,0 75,20">
#
# If the @map passed parameter contains a NUL (\0) in the first array
# position, the map is assumed to be null-separated and @map is built
# by splitting it.  This allows a null-separated todo.map with
# multiple values (parsed by a cgi-lib.pl or the like) to be
# referenced.
#
# usage:
#
#   use Imagemap;
#   $action = action_map($x, $y, @map);
#

package Vend::Imagemap;
require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(action_map);
use strict;
use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $, 10);

my $Action = "";
my $minDistance = -1;

# action_map is called with the X and Y value of the map, plus the map
# $map[0] can be a null-separated map

sub action_map {
  my($x,$y,@map) = @_;
  my($matched,$method,$action,$points);

  unless(@map) {
  	::logError("No map sent");
	return undef;
  }

  # Always take the default from the map
  $Action = '';

  if($map[0] =~ /\0/) {
		@map = split /\0/, $map[0];
  }
  my $query = "$x,$y";
  unless ($query =~ m/\d+,\d+/) {
	  ::logError ("Wrong arguments; browser may not support ISMAP");
	  return undef;
  }

  for (@map) {
    chomp;
    next if (m/^\#/ || m/^\s*$/); # skip comments and blank lines
    ($method,$action,$points) = split(/ /,$_,3);
	$points = '' unless defined $points;
    eval("\$matched = &pointIn_${method}('$action','$query','$points');");
    if ($@ ne "") {
	 	::logError("Malformed imagemap: $method unknown");
		return undef;
	}
    last if $matched;
  }

  if ($Action eq "") {
    # if we have not set $Action by this time, there is no match in the
    # given set of shapes.  Just return undef and let the default in
    # MiniVend do the work;
    return undef;
  } else {
  	return $Action;
  }
}

#
# set default action.  Only if not already set
#
sub pointIn_default {
  my($action,$point,@points) = @_;

  $Action = $action if ($Action eq "");
  0;
}

#
# set default action if this point is the closest so far
# does not check for validity of parameters
#
sub pointIn_point {
  my($action,$point,$target) = @_;
  my($dist);
  my(@pt1);
  my(@pt2);

  @pt1 = $point =~ m/(\d+),(\d+)/;
  @pt2 = $target =~ m/(\d+),(\d+)/;

  $dist = ($pt1[0] - $pt2[0])**2 + ($pt1[1] - $pt2[1])**2;

  if ($minDistance == -1 || $dist < $minDistance) {
    $minDistance = $dist;
    $Action = $action;
  }
  0;
}

#
# if point is in given rectangle, set default action and cause main loop to end
#
sub pointIn_rect {
  my($action,$point,$target) = @_;
  my($ulx,$uly,$llx,$lly) = $target =~ m/(\d+),(\d+)\s+(\d+),(\d+)/;
  my($x,$y) = $point =~ m/(\d+),(\d+)/;

  if ($x >= $ulx && $y >= $uly && $x <= $llx && $y <= $lly) {
    $Action = $action;
    return 1;				# cause main loop to terminate
  }
  0;
}

#
# if point is in circle, set default action and cause main loop to end
#
sub pointIn_circle {
  my($action,$point,$target) = @_;
  my($cx,$cy,$ex,$ey) = $target =~ m/(\d+),(\d+)\s+(\d+),(\d+)/;
  my($x,$y) = $point =~ m/(\d+),(\d+)/;

  my($distanceP,$distanceE);

  # compare squares of distance from center of edgepoint and given point

  $distanceP = ($cx - $x)**2 + ($cy - $y)**2;
  $distanceE = ($cx - $ex)**2 + ($cy - $ey)**2;

  if ($distanceP <= $distanceE) {
    $Action = $action;
    return 1;				# cause main loop to terminate
  }
  0;
}

#
# if point is in given polygon, set default action and cause main loop to end
# based mostly on code by Mike Lyons <lyonsm@netbistro.com>.
#
sub pointIn_poly {
  my($action,$point,$target) = @_;
  my($x,$y) = $point =~ m/(\d+),(\d+)/;
  my($pn);
  my(@px);
  my(@py);
  my($i,$intersections,$dy,$dx,$b,$m,$x1,$y1,$x2,$y2);

  # We'll treat the test point as the origin, so translate each
  # point in the polygon appropriately
  while($target =~ s/\s*(\d+),(\d+)//) {
    $px[$pn] = $1 - $x;
    $py[$pn] = $2 - $y;
    $pn++;
  }

  # A polygon with less than 3 points is an error
  if($pn<3) {
    return 0;
  }

  # Close the polygon
  $px[$pn] = $px[0];
  $py[$pn] = $py[0];

  # Now count the number of line segments in the polygon that intersect
  # the left side of the X axis.  If it's an odd number we are inside the
  # polygon.

  # Assume no intersection
  $intersections=0;

  for($i = 0; $i < $pn; $i++) {
    $x1 = $px[$i  ]; $y1 = $py[$i  ];
    $x2 = $px[$i+1]; $y2 = $py[$i+1];

    # Line is completely to the right of the Y axis
    next if( ($x1>0) && ($x2>0) );

    # Line doesn't intersect the X axis at all
    next if( (($y1<=>0)==($y2<=>0)) && (($y1!=0)&&($y2!=0)) );

    # Special case.. if the Y on the bottom=0, we ignore this intersection
    # (otherwise a line endpoint counts as 2 hits instead of 1)
    if ($y2>$y1) {
      next if $y2==0;
    } elsif ($y1>$y2) {
      next if $y1==0;
    } else {
      # Horizontal span overlaying the X axis.  Consider it an intersection 
      # iff. it extends into the left side of the X axis
      $intersections++ if ( ($x1 < 0) || ($x2 < 0) );
      next;
    }

    # We know line must intersect the X axis, so see where
    $dx = $x2 - $x1;

    # Special case.. if a vertical line, it intersects
    unless ( $dx ) {
      $intersections++;
      next;
    }

    $dy = $y2 - $y1;
    $m = $dy / $dx;
    $b = $y2 - $m * $x2;
    next if ( ( (0 - $b) / $m ) > 0 );

    $intersections++;
  }

  # If there were an odd number of intersections to the left of the origin
  # (the clicked-on point) then it is within the polygon
  if ($intersections % 2) {
    $Action = $action;
    return 1;			# cause main loop to terminate
  }
  0;
}

1;

__END__
