use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB -setup => ':all';
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';
use Log::Any::Adapter 'TAP';
use Geo::SpatialDB;
use Geo::SpatialDB::Math 'llbox';
use Geo::SpatialDB::Entity::RouteSegment;
sub RouteSegment { Geo::SpatialDB::Entity::RouteSegment->new(@_) }
sub Layer { Geo::SpatialDB::Layer->new(@_) }

my $dbdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script, 'db');
remove_tree($dbdir, { error => \my $ignored });

my $geodb= Geo::SpatialDB->new(
	storage => { path => $dbdir, create => 1 },
	layers => {
		roads => Layer(
			code => 'roads',
			name => "Roads",
			mapper => { CLASS => 'Rect', lat_divs => 180*10, lon_divs => 360*10 },
		)
	},
);

my @entities= (
	RouteSegment(
		id   => $geodb->alloc_entity_id,
		latlon_seq => [ (1.000,1.001), (1.001,1.001) ],
	),
	RouteSegment(
		id   => $geodb->alloc_entity_id,
		latlon_seq => [ (1.100,1.101), (1.101,1.101) ],
	)
);
for (@entities) {
	my $stats= $geodb->add_entity($_);
}
$geodb->storage->commit;

my $ret= $geodb->find_in(llbox(1.000, 1.000, 1.010, 1.010));
ok( defined $ret->{entities}{$entities[0]->id}, 'result includes obj 1' );
ok( !defined $ret->{entities}{$entities[1]->id}, 'result excludes obj 2' );

done_testing;
