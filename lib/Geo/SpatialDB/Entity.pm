package Geo::SpatialDB::Entity;

use Moo 2;
use namespace::clean;

# ABSTRACT: A logical thing found on a map (as opposed to the physical features that form it)

=head1 DESCRIPTION

An entity is something like a Road, Building, Governance boundary, River,
etc.  Each entity can have arbitrary tags assigned to it.  The tags are
actually the data of the entity, aside from other sub-entities that might be
listed on their own.

The class implementing an entity should be able to represent the entity as
"features", where a "feature" is something with a specific physical location
that can be indexed.  If the space occupied by an entity will already be
attributed to sub-entities, then it should not return any features and instead
rely on those sub-entities to be indexed and reference back to this entity.

=head1 ATTRIBUTES

=head2 id

Every entity needs a distinct ID within the system.  The ID is what you use to
load or store the entity within the Geo::SpatialDB.

=head2 type

This is a taxonomy pattern identifying the nature of the entity.
(TODO: document the ones used by the Open Street Maps importer)

=head2 tags

This is a hashref of arbitrary tags.  The tags are in fact the attributes of
the entity, but need to exist in a separate namespace than the object
attributes so they're called "tags" here.  The object may choose to expose
perl methods for various tags.

=cut

has id   => ( is => 'rw' );
has type => ( is => 'rw' );
has tags => ( is => 'rw' );

=head1 METHODS

=head2 tag

  my $tag_value= $entity->tag($name);

Convenient accessor for tags->{$name};

=head2 features_at_resolution

  my @features= $entity->features_at_resolution($meters);

Each entitiy class should implement a mechanism for dividing up the entity
into fragments which have significance at a range of C<$meters>.  If the
entity is not significant at a distance of C<$meters> then this should return
an empty list.  For instance, a major highway might be significant at a
distance of 50km, but could be left out at 100km even if the highway itself
is longer than 100km.  Each feature should consist of:

  {
    lat    => $lat,     # latitude of center of feature
    lon    => $lon,     # longitude of center of feature
    radius => $meters,  # radius of feature
  }

If an entity is composed of smaller entities, and the entity *is* significant
at the given resolution but its components are not, it may query the component
features at a lower resolution and aggregate them into a larger feature.
In this case, the composed entity can return features even though its
components do not.

=cut

sub TO_JSON {
	my $self= shift;
	my %data= %$self;
	for (keys %data) {
		delete $data{$_}
			if $_ =~ /^[^a-z]/
			or !defined $data{$_}
			or (ref $data{$_} eq 'HASH' && !keys %{ $data{$_} });
	}
	\%data;
}

sub tag {
	my ($self, $key)= @_;
	return $self->{tags}{$key};
}

sub features_at_resolution {
	return;
}

sub components {
	return;
}

1;
