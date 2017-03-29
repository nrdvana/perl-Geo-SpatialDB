#! /usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use X11::GLX::DWIM;
use OpenGL ':all';
use Module::Runtime 'require_module';
use Math::Trig 'deg2rad', 'spherical_to_cartesian';

my $glx= X11::GLX::DWIM->new(gl_projection => { top => 1, bottom => -1 });

my $module= "Geo::SpatialDB::TileMap::".shift;
require_module $module;
my $mapper= $module->new(@ARGV);

$glx->target; # force lazy init
my $dlist= build_polygons($mapper);
my ($start_t, $n, $r, $tlat, $tlon)= (time, 0, 0, -80_000_000, 0);
while (1) {
	$glx->begin_frame;
	glLoadIdentity();
	glTranslated(0,0,-2);
	glRotated(-87, 1,0,0);      # vertical Z axis
	glRotated($r += 1, 0,0,1);  # spin globe
	glColor4d(1,1,1,.7);
	glCallList($dlist);
	glColor4d(.7,1,.7,1);
	for ($mapper->get_tiles_for_rect($tlat, $tlon)) {
		printf "%.2f,%.2f: tile=$_\n", $tlat*.000001, $tlon*.000001;
		glBegin(GL_POLYGON); plot_tile($_); glEnd();
	}
	glRotated($tlon * .000001, 0,0,1);
	glRotated($tlat * .000001, 0,1,0);
	glBegin(GL_LINES); glVertex3d(0,0,0); glVertex3d(1,0,0); glEnd();
	$glx->end_frame;
	++$n;
	$tlon += 330_000;
	if ($tlon > 360_000_000) { $tlon= 0; $tlat += 10_000_000; }
	if (time != $start_t) { print "$n fps\n"; $n= 0; ++$start_t; }
}

sub build_polygons {
	$mapper->tile_count < 100000
		or die "Too many verticies to render (".$mapper->tile_count.")\n";
	
	glDisable(GL_TEXTURE_2D);
	my $list_id= glGenLists(1);
	glNewList($list_id, GL_COMPILE);
	for (my $i= $mapper->tile_count; $i--;) {
		glBegin(GL_LINE_LOOP);
		plot_tile($i, 1);
		glEnd();
	}
	glEndList();
	return $list_id;
}

sub plot_tile {
	my ($tile_id, $debug)= @_;
	my @pts= $mapper->get_tile_polygon($tile_id);
	my ($lat, $lon, $x, $y, $z);
	while (@pts) {
		($lat, $lon)= (shift(@pts) * .000001, shift(@pts) * .000001);
		($x, $y, $z)= spherical_to_cartesian(1, deg2rad($lon), deg2rad(90 - $lat));
		printf("%7.2f,%7.2f (%5.2f,%5.2f,%5.2f)  ", $lat, $lon, $x, $y, $z) if $debug;
		glVertex3d($x, $y, $z);
	}
	print "\n" if $debug;
}