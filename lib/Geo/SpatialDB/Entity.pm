package Geo::SpatialDB::Entity;
use Moo 2;
use namespace::clean;

has id   => ( is => 'rw' );
has type => ( is => 'rw' );
has tags => ( is => 'rw' );

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

1;
