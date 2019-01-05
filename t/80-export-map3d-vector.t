use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB ':all';
use Geo::SpatialDB::Export::MapPolygon3D::Vector 'vector', 'vector_latlon';

my $v0= new_ok( 'Geo::SpatialDB::Export::MapPolygon3D::Vector', [ 0,0,0 ] );

subtest magnitude => sub {
	my @tests= (
		[ [0,0,0] => 0 ],
		[ [0,1,0] => 1 ],
		[ [1,1,1] => sqrt(3) ],
		[ [1,1,1,1,1,1] => sqrt(3) ],
	);
	for (@tests) {
		my ($vec, $mag)= @$_;
		my $name= sprintf(" | (%.3f,%.3f,%.3f) | = %.3f", @{$vec}[0..2], $mag);
		is( vector(@$vec)->mag, $mag, $name );
	}
	done_testing;
};

subtest cross => sub {
	my @tests= (
		[ [1,0,0] => [0,1,0] => [0,0,1] ],
		
	);
	for (@tests) {
		my ($vec_a, $vec_b, $expected)= @$_;
		my $name= sprintf("(%.3f,%.3f,%.3f) X (%.3f,%.3f,%.3f)", @$vec_a, @$vec_b);
		is_deeply( vector(@$vec_a)->cross($vec_b), $expected, $name );
	}
	done_testing;
};

subtest clip_plane => sub {
	my @tests= (
		[ [1,0,0] => [0,1,1], [0,1,1]   => 0 ],
		[ [1,0,0] => [0,1,1], [-50,2,2] => 0 ],
		[ [1,0,0] => [0,1,1], [0,1,-1]  => -1 ],
		[ [1,0,0] => [0,1,1], [0,1,0]   => -1 ],
		[ [1,0,0] => [0,1,1], [0,-1,0]  => 	1 ],
	);
	for (@tests) {
		my ($pt0, $v1, $pt2, $sign)= @$_;
		# Create plane passing through pt0 and the origin, along $v1.
		my $plane= vector(@$pt0)->cross($v1)->set_projection_origin($pt0);
		my $d= $plane->project($pt2);
		ok( $d>0 eq $sign>0 && $d<0 eq $sign<0 ) or diag "Sign mismatch: $d != $sign";
	}
};

subtest sort_heading => sub {
	my @expected;
	for (my $lon= 0; $lon < 359; $lon += 10) {
		for my $lat (-89 .. 89) {
			# vary the longitude for every vector, so avoid depending on sort of vectors of identical heading
			push @expected, vector_latlon( $lat, $lon + ($lat/90) + 1 );
		}
	}
	my @scrambled= ( $expected[0], reverse @expected[1..$#expected] );
	my @sorted= vector(0,0,1)->sort_vectors_by_heading(@scrambled);
	is_deeply( \@sorted, \@expected, 'sorted vectors' );
	done_testing;
};

done_testing;
