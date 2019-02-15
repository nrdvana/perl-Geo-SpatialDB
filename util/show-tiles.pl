#! /usr/bin/env perl
use strict;
use warnings;
use FindBin;
use Time::HiRes 'sleep';
use lib "$FindBin::Bin/../lib";
use OpenGL::Sandbox qw( -V1 :all GL_TEXTURE_2D GL_LINE_LOOP GL_COMPILE GL_POLYGON GL_LINES glDisable glBegin glEnd );
use Module::Runtime 'require_module';
use Geo::SpatialDB::Math 'latlon_to_xyz';

@ARGV && $ARGV[0] =~ /^\w/
	or die "Usage: show-tiles.pl CLASS [CONSTRUCTOR_ARGS...]\n";

make_context;
setup_projection( top => 1, bottom => -1 );

my $module= "Geo::SpatialDB::TileMapper::".shift;
require_module $module;
my $mapper= $module->new(@ARGV);

next_frame;
my $dlist= build_polygons($mapper);
my ($start_t, $n, $r, $tlat, $tlon)= (time, 0, 0, -80, 0);
while (1) {
	trans 0,0,-2;
	rotate x => -87;      # vertical Z axis
	rotate z => ($r += .5);  # spin globe
	setcolor 1,1,1,.7;
	$dlist->call;
	setcolor .7,1,.7,1;
	for ($mapper->tile_at($tlat, $tlon)) {
		#printf "%.2f,%.2f: tile=%d\n", $tlat, $tlon, $_;
		glBegin(GL_POLYGON); plot_tile($_); glEnd();
	}
	rotate z => $tlon;
	rotate y => -$tlat;
	plot_xyz(GL_LINES, 0,0,0, 1,0,0);
	next_frame;
	++$n;
	$tlon += 1.30;
	#sleep .1;
	if ($tlon > 360) { $tlon= 0; $tlat += 10; }
	if (time != $start_t) { print "$n fps\n"; $n= 0; ++$start_t; }
}

sub build_polygons {
	$mapper->tile_count < 100000
		or die "Too many verticies to render (".$mapper->tile_count.")\n";
	
	glDisable(GL_TEXTURE_2D);
	my $list= OpenGL::Sandbox::V1::DisplayList->new;
	$list->compile(sub{
		for (my $i= $mapper->tile_count; $i--;) {
			glBegin(GL_LINE_LOOP);
			plot_tile($i, 1);
			glEnd();
		}
	});
	return $list;
}

sub plot_tile {
	my ($tile_id, $debug)= @_;
	my @pts= @{$mapper->tile_polygon($tile_id)};
	#printf( ('%.3f,' x 8). "\n", @pts );
	plot_xyz(undef,
		map latlon_to_xyz($pts[$_*2], $pts[$_*2+1]), 0..(@pts/2)-1
	);
}
