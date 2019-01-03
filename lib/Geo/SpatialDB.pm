package Geo::SpatialDB;

use Moo 2;
use Log::Any '$log';
use Carp;
use Geo::SpatialDB::Layer;
use Geo::SpatialDB::Math ':all';
use Geo::SpatialDB::Storage;
use namespace::clean;

# ABSTRACT: Generic reverse-geocoding engine on top of key/value storage

=head1 DESCRIPTION

THIS API IS NOT FINALIZED.  If you use it, please don't blindly upgrade.  I'm
releasing it primarily for feedback on the design.

Geo::SpatialDB provides reverse geocoding services on top of a simple
key/value database.  It is designed primarily for reverse-geocoding 2D areas
for map rendering, with some limited forward-geocoding ability to find things
near a specified location.  It does *NOT* yet support calculation of the best
route between two points, but I intend to eventually add that.

By using a simple key/value back-end, Geo::SpatialDB can use static data from a
read-only filesystem, which is currently not supported by more advanced engines
like Postgres.  The current version focuses on the "LMDB" library, which has a
great design with excellent performance.

The current version is tuned for personal navigation purposes, but could be
made more generic or configurable to efficiently support wider fields of view
and custom classification of entities.

=head1 ENTITIES

Sources like OpenStreetMaps have things encoded generically as "Ways" and
"Relations", with tags to give meaning to them.
This module aims for a stronger taxonomy, to help diagnose things without an
exhaustive investigation of free-form tags.

The contents of the Geo::SpatialDB are divided into the following basic
taxonomy:

=over

=item rt

A navigable path for some mode of transportation.

=item geo

A geological or terrestrial feature (river, lake, beach, mountain, etc)

=item pol

A human governance boundary or area

=item 

=item L<Location|Geo::SpatialDB::Location>

Locations are I<logical> "points on the map" which can be anything from road
junctions (including exit ramps) to business addresses to logical centers of
wider landmarks like "Niagra Falls".  Locations are simply a (lat,lon)
coordinate and optional radius.  Being a logical entity, multiple locations
may be stacked on the same coordinates.  Locations that share coordinates do
not contain references to eachother.

=item L<RouteSegment|Geo::SpatialDB::RouteSegment>

Route segments are the basic unit of navigable paths across the map.
It could be a piece of a road, foot path, water way, railroad, etc.
A route references one or more Path objects to form an un-broken sequence
of coordinates.  Segments are broken at any intersection (but not overpass).
Multiple logical routes (like a highway which merges with a local street as
it passes through town) may share the physical route segments of the map.

If you are building a routing algorithm, all the relevant data you need
should be contained in RouteSegment objects.  You would then consult the
related Route objects to determine how to describe the physical route
to the user.

=item L<Route|Geo::SpatialDB::Route>

Route objects represent a logical named route.  They may be discontinuous,
and redundant with other routes.  Any metadata not needed for calculating
a physical route goes here.

=item L<Area|Geo::SpatialDB::Area>

Areas are 2D spaces.  Any space on the map that you think of as "passing into"
rather than "going to" is classified as an area.  States, Counties, Parks,
zip codes, and etc are all stored as Areas.  An area will provide both a
bounding path and circles of approximation, for quick collision tests.

=item L<Path|Geo::SpatialDB::Path>

Paths are an implementation detail to prevent repeating sequences of coordinates.
Paths may be used by one or more other entities.
Paths have no metadata of their own.
In a future version, paths might be replaced with an automatic coordinate
compression/decompression system, so try not to write code that depends on them.

=back

=cut

has layers           => ( is => 'rw', builder => 'load_layers', lazy => 1 );
sub layer_list          { @{ shift->layers } }
has storage          => ( is => 'rw', coerce => \&Geo::SpatialDB::Storage::coerce );

sub load_layers {
	my ($self)= @_;
	my $l= $self->storage->get('.layers') || [];
	$self->layers($l);
	return $l;
}

sub save_layers {
	my $self= shift;
	my @layers= map { $_->TO_JSON } $self->layer_list;
	$self->storage->put('.layers', \@layers);
}

sub add_entity {
	my ($self, $e)= @_;
	my %added;
	my $stor= $self->storage;
	for my $layer ($self->layer_list) {
		next unless $e->type =~ $layer->type_filter_regex;
		$layer->add_entity($self, $e);
		my $features= $e->features_at_resolution($layer->min_feature_size);
		my $layer_id= $layer->id;
		for my $feature (@$features) {
			next unless $feature->{radius} >= $layer->min_feature_size
			        and $feature->{radius} <= $layer->max_feature_size;
			for my $tile_id ($layer->mapper->tiles_in_range(latlon_radius_to_range(@{$feature}{'lat','lon','radius'}))) {
				$self->_layer_tile_add_entity($layer, $tile_id, $e);
				++$added{$layer->name};
			}
		}
	}
	return undef unless keys %added;
	# Store entity if added to any layer
	$stor->put('e'.$e->id, $e);
	return \%added;
}

sub _layer_tile_add_entity {
	my ($self, $layer, $tile_id, $entity)= @_;
	my $stor= $self->storage;
	$bucket_key= 'T'.$layer->id.'.'.$tile_id;
	my $bucket= $stor->get($bucket_key) // {};
	my %seen;
	$bucket->{ent}= [ grep { !$seen{$_}++ } @{ $bucket->{ent}//[] }, $entity->id ];
	$stor->put($bucket_key, $bucket);
	return $bucket;
}

=head2 find_at

  my $entities= $db->find_at($lat, $lon, $radius, $min_feature_size);

Convenience method for L</find_in> which takes a lat/lon and radius instead
of lat/lon bounding box.  C<$min_feature_size> defaults to C<< $radius/200 >>
assuming a screen about 1600 pixels wide and features that need at least 4
pixels to display as anything.

=head2 find_in

  my $entities= $db->find_at($lat0, $lon0, $lat1, $lon1, $min_feature_size);

Returns all entities relevant to C<$min_feature_size> in any tile that
intersects with the given lat/lon bounding box.  The bounding box should
obey the constraints C<< $lat0 <= $lat1 >> and C<< $lon0 <= $lon1 >> except
for the case where longitude wraps the antimeridian.  In other words, if
C<< $lon0 > $lon1 >> it means to keep going until longitude wraps and reaches
the ending value.

Note that C<$min_feature_size> is not so much a measurement of the size of
features as it is a measure of the I<significance> of an entity in terms of
distance.  This measurement simply filters out L</layers> whose maximum
feature size is too small to be useful.
See discussion in L<Geo::SpatialDB::Layer/min_feature_size>.

=cut

sub find_at {
	my ($self, $lat, $lon, $radius, $min_feature_size)= @_;
	$self->find_in(radius_to_range($lat, $lon, $radius), $min_feature_size || $radius / 200);
}

sub find_in {
	my ($self, $lat0, $lon0, $lat1, $lon1, $min_feature_size)= @_;
	my $stor= $self->storage;
	my $range= [ $lat0, $lon0, $lat1, $lon1 ];
	my %result= ( range => $range );
	for my $layer ($self->layer_list) {
		next unless $layer->max_feature_size > $min_feature_size;
		for my $tile_id ($layer->mapper->tiles_in_range(@$range)) {
			my $bucket= $stor->get('l'.$layer->id.'.'.$tile_id)
				or next;
			for (@{ $bucket->{ent} || [] }) {
				$result{entities}{$_} ||= $self->storage->get("e$_");
			}
		}
	}
	\%result;
}

1;
