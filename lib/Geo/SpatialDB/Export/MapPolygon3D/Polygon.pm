package Geo::SpatialDB::Export::MapPolygon3D::Polygon;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK= qw( polygon );

sub new {
	my $class= shift;
	bless [ @_ ], ref($class)||$class;
}

sub polygon {
	__PACKAGE__->new(@_);
}

sub clone {
	bless [ @{$_[0]} ], ref $_[0];
}

sub clip_to_planes {
	my $self= shift;
	for my $plane (@_) {
		my @d= map $plane->project($_), @$self;
		my @new_v;
		my $prev= $#$self;
		my $was_out= $d[$prev] < 0;
		for (0..$#$self) {
			if ($was_out && $d[$_] < 0) { # both out, no vertex
			}
			elsif (!$was_out && $d[$_] >= 0) { # both in, queue next
				push @new_v, $self->[$_];
			}
			elsif ($d[$_] > 0 or $d[$prev] > 0) { # line crosses plane
				my $pos= $d[$prev] / ($d[$prev] - $d[$_]);
				my $next= $self->[$_];
				my $mid= $self->[$prev]->clone;
				# Might include texture coordinates, or not.
				defined $mid->[$_] and $mid->[$_] += ($next->[$_] - $mid->[$_]) * $pos
					for 0..4;
				push @new_v, $was_out? ( $mid, $next ) : ( $mid );
				$was_out= $d[$_] < 0;
			}
			$prev= $_;
		}
		if (@new_v < 3) {
			@$self= ();
			last;
		}
		@$self= @new_v;
	}
	return $self;
}

sub to_triangles {
	my $self= shift;
	map $self->new($self->[0], $self->[$_-1], $self->[$_]), 2..$#$self;
}

1;
