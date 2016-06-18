package Geo::SpatialDB;

use Moo 2;
use Geo::SpatialDB::Location;
use Geo::SpatialDB::Path;
use Geo::SpatialDB::RouteSegment;
use Geo::SpatialDB::Route;
use Geo::SpatialDB::Area;
use Module::Runtime 'require_module';
use Log::Any '$log';
sub _croak { require Carp; goto &Carp::croak }
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
categories:

=over

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

has zoom_levels      => is => 'rw', default => sub { [ 250_000, 62_500, 15_265 ] };
has latlon_precision => is => 'rw', default => sub { 1_000_000 };
has storage          => is => 'lazy', coerce => \&_build_storage;

sub _build_storage {
	if (!$_[0] || ref($_[0]) eq 'HASH') {
		my %cfg= %{ $_[0] // {} };
		my $class= delete $cfg{CLASS} // 'LMDB_Storable';
		$class= "Geo::SpatialDB::Storage::$class";
		require_module($class);
		$class->new(%cfg);
	}
	elsif ($_[0] && ref($_[0])->can('get')) {
		$_[0]
	} else {
		_croak("Can't coerce $_[0] to Storage instance");
	}
}

sub _register_entity_within {
	my ($self, $ent, $lat0, $lon0, $lat1, $lon1)= @_;
	my $stor= $self->storage;
	# Convert radius to arc degrees
	my $level= $#{ $self->zoom_levels };
	$level-- while $level && ($lat1 - $lat0 > $self->zoom_levels->[$level]);
 	my $granularity= $self->zoom_levels->[$level];
	use integer;
	my $lat_key_0= $lat0 / $granularity;
	my $lat_key_1= $lat1 / $granularity;
	my $lon_key_0= $lon0 / $granularity;
	my $lon_key_1= $lon1 / $granularity;
	
	for my $lat_k ($lat_key_0 .. $lat_key_1) {
		for my $lon_k ($lon_key_0 .. $lon_key_1) {
			# Load detail node, add new entity ref, and save detail node
			my $bucket_key= ":$level,$lat_k,$lon_k";
			my $bucket= $stor->get($bucket_key) // {};
			my %seen;
			$bucket->{ent}= [ grep { !$seen{$_}++ } @{ $bucket->{ent}//[] }, $ent->id ];
			$stor->put($bucket_key, $bucket);
		}
	}
}

sub add_entity {
	my ($self, $e)= @_;
	# If it's a location, index the point.  Use radius to determine what level to include it in.
	if ($e->isa('Geo::SpatialDB::Location')) {
		my ($lat, $lon, $rad)= ($e->lat, $e->lon, $e->rad//0);
		# Convert radius to lat arc degrees and lon arc degrees
		my $dLat= $rad? ($rad / 111000 * $self->latlon_precision) : 0;
		# Longitude is affected by latitude
		my $dLon= $rad? ($rad / (111699 * cos($lat / (360*$self->latlon_precision)))) : 0;
		$self->storage->put($e->id, $e);
		$self->_register_entity_within($e, $lat - $dLat, $lon - $dLon, $lat + $dLat, $lon + $dLon);
	}
	elsif ($e->isa('Geo::SpatialDB::RouteSegment')) {
		unless (@{ $e->path }) {
			$log->warn("RouteSegment with zero-length path...");
		}
		my ($lat0, $lon0, $lat1, $lon1);
		for my $pt (@{ $e->path }) {
			$lat0= $pt->[0] if !defined $lat0 or $lat0 > $pt->[0];
			$lat1= $pt->[0] if !defined $lat1 or $lat1 < $pt->[0];
			$lon0= $pt->[1] if !defined $lon0 or $lon0 > $pt->[1];
			$lon1= $pt->[1] if !defined $lon1 or $lon1 < $pt->[1];
		}
		$self->storage->put($e->id, $e);
		$self->_register_entity_within($e, $lat0, $lon0, $lat1, $lon1);
	}
	elsif ($e->isa('Geo::SpatialDB::Route')) {
		# Routes don't get added to positional buckets.  Just their segments.
		$self->storage->put($e->id, $e);
	}
	else {
		$log->warn("Ignoring entity ".$e->id);
	}
}

# min_rad - the minimum radius (meters) of object that we care to see
sub _get_bucket_keys_for_area {
	my ($self, $lat0, $lon0, $lat1, $lon1, $min_rad)= @_;
	my @keys;
	$log->debugf("  sw %d,%d  ne %d,%d  min radius %d", $lat0,$lon0, $lat1,$lon1, $min_rad);
	for my $level (0 .. $#{ $self->zoom_levels }) {
		my $granularity= $self->zoom_levels->[$level];
		my $lat_height= 111000 * $granularity / $self->latlon_precision;
		last if $lat_height < $min_rad;
		# Iterate south to north
		use integer;
		my $lat_key_0= $lat0 / $granularity;
		my $lat_key_1= $lat1 / $granularity;
		my $lon_key_0= $lon0 / $granularity;
		my $lon_key_1= $lon1 / $granularity;
		for my $lat_key ($lat_key_0 .. $lat_key_1) {
			push @keys, ":$level,$lat_key,$_"
				for $lon_key_0 .. $lon_key_1;
		}
	}
	return @keys;
}

=head2 find_in_radius

=cut

sub find_at {
	my ($self, $lat, $lon, $radius, $filter)= @_;
	# Convert radius to lat arc degrees and lon arc degrees
	my $dLat= $radius? ($radius / 111000 * $self->latlon_precision) : 0;
	# Longitude is affected by latitude
	my $dLon= $radius? ($radius / (111699 * cos($lat / (360*$self->latlon_precision)))) : 0;
	my @keys= $self->_get_bucket_keys_for_area($lat-$dLat, $lon-$dLon, $lat+$dLat, $lon+$dLon, $radius/200);
	my %result;
	$log->debugf("  searching buckets: %s", \@keys);
	for (@keys) {
		my $bucket= $self->storage->get($_)
			or next;
		for (@{ $bucket->{ent} // [] }) {
			$result{entities}{$_} //= $self->storage->get($_);
		}
	}
	\%result;
}

1;
