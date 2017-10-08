use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';
use Log::Any::Adapter 'TAP';

use_ok 'Geo::SpatialDB::Import::OpenStreetMap' or die;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });
make_path($tmpdir or die "Can't create $tmpdir");

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new();

package Test::Mock::SpatialDB {
	use Moo 2;
	use Log::Any '$log';
	
	has entities       => is => 'rw';
	has location_count => is => 'rw', default => sub { 0 };
	has route_count    => is => 'rw', default => sub { 0 };
	has area_count     => is => 'rw', default => sub { 0 };
	
	sub add_entity {
		my ($self, $entity)= @_;
		$log->debugf("%s", $entity);
		$self->{location_count}++ if $entity->isa('Geo::SpatialDB::Entity::Location');
		$self->{route_count}++    if $entity->isa('Geo::SpatialDB::Entity::RouteSegment');
		push @{ $self->{entities} }, $entity;
	}
};

$importer->load_xml(catfile($FindBin::RealBin, 'data', 'peterborough.osm.bz2'));
$importer->tmp_storage->commit;

$importer->preprocess;
$importer->tmp_storage->commit;

my $sdb= Test::Mock::SpatialDB->new;
$importer->generate_roads($sdb);

is( $sdb->location_count, 358, 'locations' );
is( $sdb->route_count,    237, 'routes' );

done_testing;
