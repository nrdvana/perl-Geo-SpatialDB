use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';
use Log::Any::Adapter 'TAP';
use Geo::SpatialDB;
use Geo::SpatialDB::Export::D3;

use_ok 'Geo::SpatialDB::Import::OpenStreetMap' or die;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });
make_path($tmpdir or die "Can't create $tmpdir");

my $sdb= Geo::SpatialDB->new(
	storage      => { path => $tmpdir },
	latlon_scale => 1,
);
my $ex= Geo::SpatialDB::Export::D3->new(
	spatial_db => $sdb,
	radius     => 1
);

sub is_within {
	my ($actual, $expected, $tolerance, $msg)= @_;
	if (_is_elem_within('', $actual, $expected, $tolerance)) {
		pass $msg;
	} else {
		fail $msg;
	}
}

sub _is_elem_within {
	my ($elem, $actual, $expected, $tolerance)= @_;
	if (ref $actual eq 'ARRAY' && ref $expected eq 'ARRAY') {
		if (@$actual == @$expected) {
			my $err= 0;
			for (0 .. $#$actual) {
				_is_elem_within($elem."[$_]", $actual->[$_], $expected->[$_], $tolerance)
					or ++$err;
			}
			return !$err;
		} else {
			note sprintf("element %s: has %d elements instead of %d",
				$elem, scalar @$actual, scalar @$expected);
			return;
		}
	} elsif (!ref $actual && !ref $expected) {
		if (abs($actual - $expected) > $tolerance) {
			note sprintf("element %s: abs(%.3e - %.3e) = %.3e",
				$elem, $actual, $expected, $actual-$expected);
			return;
		} else {
			return 1;
		}
	} else {
		note "got ".ref($actual)." but expected ".(ref($expected)//'plain scalar');
		return;
	}
}

subtest latlon_to_xyz => sub {
	my $ll2xyz= $ex->_latlon_to_xyz_coderef;
	is_within(
		$ll2xyz->([ 0, 0 ]),
		[ 1, 0, 0 ],
		.000000001,
		'0,0'
	);
	is_within(
		$ll2xyz->([ 90, 0 ]),
		[ 0, 0, 1 ],
		.000000001,
		'90,0'
	);
	is_within(
		$ll2xyz->([ -90, 0 ]),
		[ 0, 0, -1 ],
		.000000001,
		'-90,0'
	);
	is_within(
		$ll2xyz->([ 0, 90 ]),
		[ 0, 1, 0 ],
		.000000001,
		'0,90'
	);
};

subtest path_to_xyz => sub {
	my $rseg= Geo::SpatialDB::RouteSegment->new(
		id => 'foo',
		path => [ [ 40.01, 70.01 ], [ 40.02, 70.02 ] ]
	);
	my $paths= $ex->generate_route_lines({ entities => { foo => $rseg } });
	is( $#$paths, 0, 'one path' );
	is( $#{ $paths->[0][1] }, 1, 'two verticies' );
	is_within(
		$paths->[0][1],
		[
			[ 0.261838633349351, 0.719786587993401, 0.642921299873136 ],
			[ 0.261674657326358, 0.719726808351777, 0.64305497047523 ],
		],
		.000000001,
		'vertex values',
	);
};

subtest path_to_polygons => sub {
	my $rseg= Geo::SpatialDB::RouteSegment->new(
		id => 'foo',
		path => [ [ 40.01, 70.01 ], [ 40.02, 70.02 ] ]
	);
	my $polys= $ex->generate_route_polygons({ entities => { foo => $rseg } }, road_width => .000001);
	is( $#$polys, 0, 'one path' );
	is( $#{ $polys->[0][1] }, 3, 'four verticies' );
	is_within(
		$polys->[0][1],
		[
			[ 0.261839245831099, 0.719785949238465, 0.642921765553541 ],
			[ 0.261838020867602, 0.719787226748336, 0.64292083419273  ],
			[ 0.261675269808106, 0.719726169596841, 0.643055436155635 ],
			[ 0.261674044844609, 0.719727447106712, 0.643054504794824 ]
		],
		.000000001,
		'vertex values'
	);
};

done_testing;
