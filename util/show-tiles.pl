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
my ($start_t, $n, $r)= (time, 0, 0);
while (1) {
	$glx->begin_frame;
	glLoadIdentity();
	glTranslated(0,0,-2);
	glRotated($r += 1, 0,1,0);
	glRotated(90, 1,0,0);
	glCallList($dlist);
	$glx->end_frame;
	++$n;
	if (time != $start_t) { print "$n fps\n"; $n= 0; ++$start_t; }
}

sub build_polygons {
	my $mapper= shift;
	$mapper->tile_count < 100000
		or die "Too many verticies to render (".$mapper->tile_count.")\n";
	
	glColor4d(1,1,1,1);
	glDisable(GL_TEXTURE_2D);
	my $list_id= glGenLists(1);
	glNewList($list_id, GL_COMPILE);
	my ($x, $y, $z);
	for (my $i= $mapper->tile_count; $i--;) {
		my @pts= $mapper->get_tile_polygon($i);
		glBegin(GL_LINE_LOOP);
		while (@pts) {
			printf("%7.2f,%7.2f ", $pts[1]*.000001, $pts[0]*.000001);
			($x, $y, $z)= spherical_to_cartesian(1, deg2rad($pts[1]*.000001), deg2rad($pts[0]*.000001 + 90));
			printf(" (%5.2f,%5.2f,%5.2f) ", $x, $y, $z);
			glVertex3d($x, $y, $z);
			splice(@pts, 0, 2);
		}
		print("\n");
		glEnd();
	}
	glEndList();
	return $list_id;
}
