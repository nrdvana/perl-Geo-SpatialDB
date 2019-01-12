use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB ':all';
use Geo::SpatialDB::Math qw/ polygon vector /;

my @tests= (
	[ 'square in half',
		[ [0,0,0] => [1,0,0] => [1,1,0] => [0,1,0] ],
		[ [0,.5,0] => [1,.5,0] => [1,1,0] => [0,1,0] ],
		[ [0,1,0], # horizontal plane, upper half "in"
		  [0,.5,0] ], # from y=.5 upward
	],
	[ 'square minus upper right corner',
		[ [0,0,0] => [1,0,0] => [1,1,0] => [0,1,0] ],
		[ [0,0,0] => [1,0,0] => [1,.5,0] => [.5,1,0] => [0,1,0] ],
		[ [-1,-1,0], # diagonal plane along (-1,1), with below as "in"
		  [1.5,0,0] ], # from x=1.5, cutting off the corner of the square
	],
	[ 'square minus lower left corner',
		[ [0,0,0] => [1,0,0] => [1,1,0] => [0,1,0] ],
		[ [0,.5,0] => [.5,0,0] => [1,0,0] => [1,1,0] => [0,1,0] ],
		[ [1,1,0], # diagonal plane along (-1,1), with above as "in"
		  [.5,0,0] ], # from x=0.5, cutting off the corner of the square
	],
	[ 'square with texture coordinates minus all corners',
		[ [0,0,0,0,0] => [1,0,0,1,0] => [1,1,0,1,1] => [0,1,0,0,1] ],
		[ [0,.5,0,0,.5], [.5,0,0,.5,0] => [1,.5,0,1,.5] => [.5,1,0,.5,1] ],
		[ [-1,-1,0], # diagonal plane along (-1,1), with below as "in"
		  [1.5,0,0] ], # from x=1.5, cutting off the corner of the square
		[ [1,1,0], # diagonal plane along (-1,1), with above as "in"
		  [0.5,0,0] ], # from x=0.5, cutting off the corner of the square
		[ [-1,1,0], # diagonal plane alone (1,1), with above as "in"
		  [.5,0,0] ],
		[ [1,-1,0],
		  [0,.5,0] ],
	],
);
for (@tests) {
	my ($name, $polygon, $expected, @plane_and_refpt)= @$_;
	$polygon= polygon(map vector(@$_), @$polygon);
	my @planes= map vector(@{$_->[0]})->set_projection_origin($_->[1]), @plane_and_refpt;
	$polygon->clip_to_planes(@planes);
	is_deeply( $polygon, $expected, $name );
}

done_testing;
