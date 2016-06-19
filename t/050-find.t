use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';
use Log::Any::Adapter 'TAP';
use Geo::SpatialDB;

use_ok 'Geo::SpatialDB::Import::OpenStreetMap' or die;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });
make_path($tmpdir or die "Can't create $tmpdir");

my $sdb= Geo::SpatialDB->new(
	storage   => { path => $tmpdir }
);

$sdb->add_entity(
	Geo::SpatialDB::RouteSegment->new(
		id   => 1,
		path => [ [1000000,1001000], [1001000,1001000] ],
	)
);
$sdb->add_entity(
	Geo::SpatialDB::RouteSegment->new(
		id   => 2,
		path => [ [1100000,1101000], [1101000,1101000] ],
	)
);

my $ret= $sdb->find_in([ 1000000, 1000000, 1010000, 1010000 ]);
ok( defined $ret->{entities}{1}, 'result includes obj 1' );
ok( !defined $ret->{entities}{2}, 'result excludes obj 2' );

done_testing;
