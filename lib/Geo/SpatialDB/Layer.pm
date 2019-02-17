package Geo::SpatialDB::Layer;
use Moo 2;
use Geo::SpatialDB::TileMapper;
use Geo::SpatialDB::Math 'earth_radius';
with 'Geo::SpatialDB::Serializable';

# ABSTRACT: Holds parameters for how to index a subset of entities in the database
# VERSION

=head1 DESCRIPTION

This object describes a configuration for indexing a portion of the map data.
Since the map data can be enormous, it helps to sub-divide it into different
layers which can be selectively queried depending on the circumstances of the
user.

The most fundamental purpose of a layer is to choose a tile mapper and then
filter out entities that are too big or too small for that tile granularity.
But, layers can also be used like in common mapping software to divide terrain
data from road data from street address data and so on.

=head1 ATTRIBUTES

=head2 code

The internal id of the layer.  This is used in the index names of C<< $geodb->storage >>.

=head2 name

A short human-readable label

=head2 description

Comment for human consumption

=head2 mapper

An instance of L<Geo::SpatialDB::TileMapper>

=head2 size_filter

Arrayref of minimum and maximum entity size (in meters) to be included in this layer.

Note that this radius can be scaled by I<significance>, according to
L</type_filters>.

=over

=item min_entity_size

Alias for C<< size_filter->[0] >>

=item max_entity_size

Alias for C<< size_filter->[1] >>

=back

=head2 type_filters

Arrayref of filters which determine whether an entity should be added to this
layer, and any parameters for the process of doing so.

Each filter is a hashref of:

  {
    type         => qr/$pattern/,
    significance => $significance_multiplier,
  }

The C<scale> attribute allows you to adjust the size of entities for
determining whether they belong to the layer or not.

For example, the Statue of Liberty is only tens of meters wide, and even
Liberty Island is only about 275m in diameter, but these might be considered
to have cartographic significance on a map that can only display things as
small as 1km.
This setting allows you to multiply the size of an entity based on its
taxonomy.

=head2 render_config

Arbitrary hashref of data which will be given to renderers when rendering this
layer.  This is not a well thought-out API, but whatever.

=cut

has code              => ( is => 'ro', required => 1 );
has name              => ( is => 'rw', required => 1, default => sub { $_[0]->code } );
sub index_name           { 'layer.' . shift->code }
has description       => ( is => 'rw' );
has _mapper_arg       => ( is => 'rw', init_arg => 'mapper', required => 1 );
has mapper            => ( is => 'lazy', init_arg => undef );
has size_filter       => ( is => 'rw' );
sub min_entity_size      { $_[0]{size_filter}[0] }
sub max_entity_size      { $_[0]{size_filter}[1] }
has type_filters      => ( is => 'rw' );
has type_filter_regex => ( is => 'lazy' );
has render_config     => ( is => 'rw' );

sub _build_mapper {
	Geo::SpatialDB::TileMapper->coerce(shift->_mapper_arg);
}

sub BUILD {
	my $self= shift;
	$self->mapper; # force instantiation
}

sub _build_type_filter_regex {
	my $self= shift;
	return undef unless @{ $self->type_filters || [] };
	my $re= join '|', map { ref $_->{type}? $_->{type} : qr/\Q$_->{type}\E/ } @{ $self->type_filters };
	return qr/$re/;
}

sub includes_entity {
	my ($self, $entity)= @_;
	if ($self->max_entity_size || $self->min_entity_size) {
		my $entity_area= $entity->features_at_resolution(earth_radius * 100);
		return unless $entity_area && @$entity_area
			&& (!$self->max_entity_size || $entity_area->[0]->radius <= $self->max_entity_size)
			&& (!$self->min_entity_size || $entity_area->[0]->radius >= $self->min_entity_size);
	}
	if (defined $self->type_filter_regex) {
		return unless $entity->type && $entity->type =~ $self->type_filter_regex;
	}
	return 1;
}

sub tiles_for_entity {
	my ($self, $entity)= @_;
	my $features= $entity->features_at_resolution($self->min_entity_size || 0);
	my %tile_added;
	for my $feature (@$features) {
		my $tiles= $self->mapper->tiles_in($feature);
		$tile_added{$_}++ for @$tiles;
	}
	return [ keys %tile_added ];
}

1;
