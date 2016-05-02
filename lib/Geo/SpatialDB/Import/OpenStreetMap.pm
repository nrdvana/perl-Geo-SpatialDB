package Geo::SpatialDB::Import::OpenStreetMap;
use Moo 2;
use Carp;
use XML::Parser;
use namespace::clean;

#has store_edit_metadata => is => 'rw';
#
#has store_tags          => is => 'rw';
#has tag_filter          => is => 'rw';
#
#sub import {
#	my ($self, $source)= @_;
#	my $fh= $self->_open_stream($source);
#	
#}

has node_cache     => is => 'lazy';
has way_cache      => is => 'lazy';
has relation_cache => is => 'lazy';
has stats          => is => 'lazy';
has latlon_precision => is => 'rw', default => sub { 1_000_000 };

sub _build_stats {
	my $self= shift;
	$self->_tie_hash_to_file(\my %cache, './_stats');
	\%cache;
}
sub _build_node_cache {
	my $self= shift;
	$self->_tie_hash_to_file(\my %cache, './_node_cache');
	\%cache;
}
sub _build_way_cache {
	my $self= shift;
	$self->_tie_hash_to_file(\my %cache, './_way_cache');
	\%cache;
}
sub _build_relation_cache {
	my $self= shift;
	$self->_tie_hash_to_file(\my %cache, './_relation_cache');
	\%cache;
}

sub _tie_hash_to_file {
	my ($self, $hash, $path)= @_;
	require LMDB_File::Filtered;
	require Fcntl;
	use Storable 'freeze', 'thaw';
	my $db= tie %$hash, 'LMDB_File::Filtered', $path, {
		mapsize => 1024*1024*1024*1024,
		flags => LMDB_File::MDB_NOSUBDIR()
		}
		or die "Failed to tie hash to $path";
	$db->Filter_Value_Push(Fetch => sub { $_=thaw($_) }, Store => sub { $_=freeze($_) });
	$db;
}

sub load_xml {
	my ($self, $source)= @_;
	my @stack;
	my $prec= $self->latlon_precision;
	my $stats= { %{ $self->stats } };
	XML::Parser->new( Handlers => {
		Start => sub {
			my ($expat, $el, %attr) = @_;
			push @stack, \%attr;
		},
		End => sub {
			my ($expat, $el) = @_;
			my $obj = pop @stack;
			if ($el eq 'tag') {
				$stack[-1]{tag}{$obj->{k}} = $obj->{v}
					if @stack;
			}
			elsif ($el eq 'nd') {
				push @{ $stack[-1]{nd} }, $obj->{ref}
					if @stack;
			}
			elsif ($el eq 'member') {
				push @{ $stack[-1]{member} }, $obj
					if @stack;
			}
			elsif ($el eq 'node') {
				# Convert lat/lon to microdegree integers
				my $lat= int( $obj->{lat} * $prec );
				my $lon= int( $obj->{lon} * $prec );
				$stats->{node}++;
				$stats->{node_tag}{$_}++ for keys %{ $obj->{tag} // {} };
				$self->node_cache->{$obj->{id}}= [ $lat, $lon ];
			}
			elsif ($el eq 'way') {
				$stats->{way}++;
				$stats->{way_tag}{$_}++ for keys %{ $obj->{tag} // {} };
				$self->way_cache->{$obj->{id}}= $obj;
			}
			elsif ($el eq 'relation') {
				$stats->{relation}++;
				$stats->{relation_tag}{$_}++ for keys %{ $obj->{tag} // {} };
				$stats->{relation_member_type}{$_}++ for map { $_->{type} // '' } @{ $obj->{member} // {}};
				$stats->{relation_member_role}{$_}++ for map { $_->{role} // '' } @{ $obj->{member} // {}};
				$self->relation_cache->{$obj->{id}}= $obj;
			}
		}
	})->parse($self->_open_stream($source));
	use DDP;
	p $stats;
	$self->stats->{$_}= $stats->{$_} for keys %$stats;
}

sub construct_way {
	my ($self, $id)= @_;
	my $spec= $self->way_cache->{$id};
	my @path= map { $self->node_cache->{$_} } @{ $spec->{nd} };
	return { id => $id, path => \@path, tags => $spec->{tag} };
}

sub construct_relation {
	my ($self, $id)= @_;
	my $spec= $self->relation_cache->{$id};
	for (@{ $spec->{member} }) {
		if ($_->{type} eq 'node') {
			my $latlon= $self->node_cache->{$_->{ref}};
			@{$_}{'lat','lon'}= @$latlon;
		}
	}
	return $spec;
}

sub _open_stream {
	my ($self, $thing)= @_;
	if (!ref($thing) or ref($thing) eq 'SCALAR' or ref($thing) =~ /^Path::Class/) {
		open my $fh, '<:raw', $thing
			or die "open('$thing'): $!\n";
		return $fh;
	}
	elsif (ref($thing) eq 'GLOB' or ref($thing) =~ /^IO::/ or $thing->can('read')) {
		return $thing;
	}
	else {
		croak "Don't know how to read or open $thing";
	}
}

1;
