package Geo::SpatialDB;
use Moo 2;
use Log::Any '$log';
use Carp;
use Geo::SpatialDB::Math ':all';
use Geo::SpatialDB::Storage;
use Geo::SpatialDB::Layer;
# Need to load all the classes that Storable might want to create
use Geo::SpatialDB::Layer;
use Geo::SpatialDB::Path;
use Geo::SpatialDB::Entity::Route;
use Geo::SpatialDB::Entity::RouteSegment;
use Geo::SpatialDB::Entity::Location;
use namespace::clean;

# ABSTRACT: Generic reverse-geocoding engine on top of key/value storage
# VERSION

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

=item geo.wb

Water Body, non-flowing (lake, pond)

=item geo.wp

Water Path (river, stream, creek)

=item gov

A human governance boundary or area (state, county, township, zip code, 

=item 

=back

The taxonomy is semi-independent from the Entity classes.
The following classes are returned from the public API:

=over

=item L<Area|Geo::SpatialDB::Entity::Area>

Areas are bounded 2D spaces.  Any space on the map that you think of as
"passing into" rather than "going to" is classified as an area.
States, Counties, Parks, zip codes, and etc are all stored as Areas.
An area will provide both a bounding path and circles of approximation for
quick collision tests.

=item L<Location|Geo::SpatialDB::Location>

Locations are I<logical> "points on the map" which can be anything from road
junctions (including exit ramps) to business addresses to logical centers of
wider landmarks like "Niagra Falls".  Locations are simply a (lat,lon)
coordinate and optional radius.  Being a logical entity, multiple locations
may be stacked on the same coordinates.  Locations that share coordinates do
not contain references to eachother.

=item L<Route|Geo::SpatialDB::Entity::Route>

Route objects represent a logical named route.  They may be discontinuous,
and redundant with other routes.  Any road metadata that doesn't directly
describe the physical RouteSegment goes here.

=item L<RouteSegment|Geo::SpatialDB::Entity::RouteSegment>

Route segments are the basic unit of navigable paths across the map.
It could be a piece of a road, foot path, water way, railroad, etc.
A route has a distinct ID, and its endpoints also have distinct IDs, so this
can be used by routing algorithms, while also representing the physical
divisions in a route, like the segment of a road which is 3 lanes before it
merges back to 2.

If you are building a routing algorithm, all the relevant data you need
should be contained in RouteSegment objects.  You would then consult the
related Route objects to determine how to describe the physical route
to the user.  (In the USA at least, it is common for multiple logical routes
to share the same physical road, so any given stretch of road might have
many names, some of which are more relevant to the traveler than others.)

=back

=head1 ATTRIBUTES

=head2 layers

The configured layers, mapped by L<Geo::SpatialDB::Layer/code>.
Layers must be configured before calling add_entity, else the database
will need re-built.

=head2 layer_list

Convenience accessor for C<< values %{ $geodb->layers } >>

=head2 storage

An instance of L<Geo::SpatialDB::Storage>.

=cut

has layers           => ( is => 'lazy' );
sub layer_list          { values %{ shift->layers } }
has _storage_arg     => ( is => 'rw', init_arg => 'storage' );
has storage          => ( is => 'lazy', init_arg => undef );

sub _build_storage {
	my $sto= Geo::SpatialDB::Storage->coerce(shift->_storage_arg);
	$sto->indexes->{entity} or $sto->create_index('entity', int_key => 1);
	$sto->indexes->{path} or $sto->create_index('path', int_key => 1);
	$sto->indexes->{layer} or $sto->create_index('layer');
	$sto;
}

sub _build_layers {
	my ($self)= @_;
	return {} unless $self->storage->indexes->{layer};
	my $i= $self->storage->iterator('layer');
	my %layers;
	while (my ($k, $v)= $i->()) {
		$layers{$k}= Geo::SpatialDB::Layer->coerce($v);
	}
	return \%layers;
}

sub _save_layers {
	my $self= shift;
	$self->storage->create_index('layer')
		unless $self->storage->indexes->{layer};
	$self->storage->put('layer', $_->code => Geo::SpatialDB::Layer->get_ctor_args($_)) for $self->layer_list;
}

=head1 METHODS

=head2 alloc_path_id

Reserve a new path_id for a later call to add_path

=head2 alloc_entity_id

Reserve a new entity_id for later call to add_entity

=cut

sub alloc_path_id {
	my ($self, $count)= @_;
	my $id= $self->storage->get(INFORMATION_SCHEMA => 'next_path_id') || 1;
	$self->storage->put(INFORMATION_SCHEMA => 'next_path_id', $id+($count||1), lazy => 1);
	$id;
}

sub alloc_entity_id {
	my ($self, $count)= @_;
	my $id= $self->storage->get(INFORMATION_SCHEMA => 'next_entity_id') || 1;
	$self->storage->put(INFORMATION_SCHEMA => 'next_entity_id', $id+($count||1), lazy => 1);
	$id;
}

=head2 add_layer

  $geodb->add_layer( $layer_or_hashref );

This adds a new layer to the DB, and then iterates all entities to build the index for that
layer.

=cut

sub add_layer {
	my $self= shift;
	my $layer= @_ && ref($_[0]) && ref($_[0])->can('code')? $_[0]
		: @_ == 1 && ref($_[0]) eq 'HASH'? Geo::SpatialDB::Layer->new($_[0])
		: Geo::SpatialDB::Layer->new(@_);
	$self->layers->{$layer->code}= $layer;
	$self->_save_layers;
	my $iter= $self->storage->iterator('entity');
	my $added= 0;
	while (my ($k, $v)= $iter->()) {
		++$added if $self->_add_entity_to_layer($layer, Geo::SpatialDB::Entity->coerce($v));
	}
	return $added;
}

=head2 add_entity

  $ent= Geo::SpatialDB::Entity::...->new( id => $geodb->alloc_entity_id, ...);
  $geodb->add_entity( $ent );

Add one entity to the database, indexing it within any appropriate layers.

=cut

sub add_entity {
	my ($self, $e)= @_;
	my %added;
	$e->storage($self->storage) if $e->can('storage');
	$self->storage->put(entity => $e->id, Geo::SpatialDB::Entity->get_ctor_args($e));
	for my $layer ($self->layer_list) {
		$added{$layer->code} += $self->_add_entity_to_layer($layer, $e)
			if $layer->includes_entity($e);
	}
	return \%added;
}
sub _add_entity_to_layer {
	my ($self, $layer, $e)= @_;
	my $stor= $self->storage;
	my $index_name= $layer->index_name;
	$self->storage->create_index($index_name)
		unless $self->storage->indexes->{$index_name};
	my $added_to_tile= 0;
	for my $tile_id (@{$layer->tiles_for_entity($e)}) {
		my $bucket= $stor->get($index_name, $tile_id) // {};
		my $ents= ($bucket->{ent} //= []);
		my %seen= map { $_ => 1 } @$ents;
		if (!$seen{$e->id}) {
			push @$ents, $e->id;
			$stor->put($index_name, $tile_id, $bucket);
			++$added_to_tile;
		}
	}
	return $added_to_tile;
}

=head2 find_in

  my $entities= $db->find_in($llbox_or_llarea, $min_feature_size);

Returns all entities relevant to C<$min_feature_size> in any tile that
intersects with the given lat/lon bounding box.  The bounding box should
obey the constraints C<< $lat0 <= $lat1 >> and C<< $lon0 <= $lon1 >> except
for the case where longitude wraps the antimeridian.  In other words, if
C<< $lon0 > $lon1 >> it means to keep going until longitude wraps and reaches
the ending value.

Note that C<$min_feature_size> is not so much a measurement of the size of
features as it is a measure of the I<significance> of an entity in terms of
distance.  This measurement simply filters out L</layers> whose maximum
feature size is too small to be useful.  C<$min_feature_size> defaults to
C<< $radius/200 >>, assuming a fullscreen bounding box with screen about 1600
pixels wide and features that need at least 4 pixels to display as anything.
See discussion in L<Geo::SpatialDB::Layer/min_feature_size>.

=cut

sub find_in {
	my ($self, $range, $min_feature_size)= @_;
	ref $range && ref($range)->can('radius') or croak "find_in() takes a range of LLRad or LLBox";
	$min_feature_size //= $range->radius / 200;
	my $stor= $self->storage;
	my %result= ( range => $range );
	for my $layer ($self->layer_list) {
		next unless !$layer->max_feature_size || ($layer->max_feature_size >= $min_feature_size);
		my $index_name= $layer->index_name;
		for my $tile_id (@{ $layer->mapper->tiles_in($range) }) {
			my $bucket= $stor->get($index_name, $tile_id)
				or next;
			for (@{ $bucket->{ent} || [] }) {
				$result{entities}{$_} ||= Geo::SpatialDB::Entity->coerce($self->storage->get(entity => $_));
			}
		}
	}
	\%result;
}

=head2 get_entity

  my $ent= $geo_db->get_entity($id);

Return an entity by its ID.  This does any extra work of inflating the object that the
L</storage> might not do on its own.  This also might return a cached instance of the entity.

=cut

sub get_entity {
	my ($self, $ent_id)= @_;
	Geo::SpatialDB::Entity->coerce($self->storage->get(entity => $ent_id));
}

1;
