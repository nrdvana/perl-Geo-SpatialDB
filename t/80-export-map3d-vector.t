use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB -setup => ':all';
use Geo::SpatialDB::Math qw/ vector vector_latlon /;

subtest ctor_read_write => sub {
	my $v= vector(0,0);
	is( $v->x, 0, 'z got value' );
	is( $v->s, undef, 's undefined' );
	is( $v->t, undef, 't undefined' );
	$v->x= 1;
	is( [ $v->xyz ], [ 1,0,0 ], 'read xyz' );
	is( $v->x, 1, 'assigned x' );
	is( $v->s, undef, 's undefined' );
	is( $v->t, undef, 't undefined' );
	($v->xyz)= (3,4,5);
	is( $v->z, 5, 'assigned z via xyz' );
	$v= vector(0,0,0,0,0);
	is( $v->s, 0, 's initialized' );
	
	is_nearly( [vector_latlon(0,0)->xyz], [1,0,0], 'lat_lon' );
	is_nearly( [vector_latlon(90,0)->xyz], [0,0,1], 'lat_lon' );
	is_nearly( [vector_latlon(-90,0)->xyz], [0,0,-1], 'lat_lon' );
	done_testing;
};

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
		is( vector(@$vec_a)->cross($vec_b), $expected, $name );
	}
	done_testing;
};

subtest projection => sub {
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
		my $normal= vector(@$pt0)->cross($v1);
		my $d= $normal->project(vector(@$pt2)->sub($pt0));
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
	is( \@sorted, \@expected, 'sorted vectors' );
	done_testing;
};

done_testing;
