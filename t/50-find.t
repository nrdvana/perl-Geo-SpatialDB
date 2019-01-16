use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';
use Log::Any::Adapter 'TAP';
use Geo::SpatialDB;

use_ok 'Geo::SpatialDB::Import::OpenStreetMap' or die;

my $dbdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script, 'db');
remove_tree($dbdir, { error => \my $ignored });

my $sdb= Geo::SpatialDB->new(
	storage => { path => $dbdir, create => 1 }
);

$sdb->add_entity(
	Geo::SpatialDB::Entity::RouteSegment->new(
		id   => 1,
		latlon_seq => [ (1000000,1001000), (1001000,1001000) ],
	)
);
$sdb->add_entity(
	Geo::SpatialDB::Entity::RouteSegment->new(
		id   => 2,
		latlon_seq => [ (1100000,1101000), (1101000,1101000) ],
	)
);
$sdb->storage->commit;

my $ret= $sdb->find_in([ 1000000, 1000000, 1010000, 1010000 ]);
ok( defined $ret->{entities}{1}, 'result includes obj 1' );
ok( !defined $ret->{entities}{2}, 'result excludes obj 2' );

done_testing;
