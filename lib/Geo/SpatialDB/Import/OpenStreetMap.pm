package Geo::SpatialDB::Import::OpenStreetMap;
use Moo 2;
use Carp;
use XML::Parser;
use Geo::SpatialDB::Entity::Route::Road;
use Geo::SpatialDB::Entity::Location;
use Log::Any '$log';
use namespace::clean;

# ABSTRACT: Import OpenStreetMap data as SpatialDB Entities

=head1 DESCRIPTION

OpenStreetMap data consists of Nodes, Ways, and Relations.

=over

=item Node

Each Node is a lat/lon coordinate with a unique ID to reference it by.
It can have attached editor metadata of who edited it and as part of which
changeset and etc.

=item Way

A Way consists of a sequence of nodes with attached tags and editor metadata.
Ways represent things like roads or paths.

=item Relation

A Relation references nodes, ways, or other relations to form more complex
structures than a single Way can represent.

=back

=cut

has tmp_storage      => is => 'lazy';
has stats            => is => 'lazy';
has latlon_precision => is => 'rw',   default => sub { 1_000_000 };

sub _build_stats {
	+{};
}

sub _build_tmp_storage {
	require File::Temp;
	require Geo::SpatialDB::Storage::LMDB_Storable;
	return Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => File::Temp->newdir('osm-import-XXXXX'),
		run_with_scissors => 1,
	);
}

sub DESTROY {
	my $self= shift;
	# When cleaning up, make the storage go out of scope before its path does,
	# for the case when path is a Tmpdir object which wants to delete everything.
	my $path= $self->tmp_storage->path
		if $self->tmp_storage->can('path');
	delete $self->{tmp_storage};
}

sub load_xml {
	my ($self, $source)= @_;
	my @stack;
	my $prec= $self->latlon_precision;
	my $stats= $self->stats;
	my $stor= $self->tmp_storage;
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
				$stor->put('n'.$obj->{id}, [ $lat, $lon, [], $obj->{tag} ]);
			}
			elsif ($el eq 'way') {
				$stats->{way}++;
				$stats->{way_tag}{$_}++ for keys %{ $obj->{tag} // {} };
				$stor->put('w'.$obj->{id}, $obj);
			}
			elsif ($el eq 'relation') {
				$stats->{relation}++;
				$stats->{relation_tag}{$_}++ for keys %{ $obj->{tag} // {} };
				$stats->{relation_member_type}{$_}++ for map { $_->{type} // '' } @{ $obj->{member} // []};
				$stats->{relation_member_role}{$_}++ for map { $_->{role} // '' } @{ $obj->{member} // []};
				$stor->put('r'.$obj->{id}, $obj);
			}
		}
	})->parse($self->_open_stream($source));
	$stor->put(stats => $stats);
	$stor->put(preprocessed => 0);
	$self;
}

sub preprocess {
	my $self= shift;
	my $store= $self->tmp_storage;
	return if $store->get('preprocessed');
	
	my ($way_id, $rel_id, $way, $rel);
	
	# Relate nodes to ways that reference them
	my $i= $store->iterator('w');
	while ((($way_id,$way)= $i->()) and $way_id =~ /^w/) {
		for my $node_id (@{ $way->{nd} // [] }) {
			my $n= $store->get("n$node_id");
			if ($n) {
				push @{ $n->[2] }, $way_id;
				$store->put("n$node_id", $n);
			} else {
				$log->notice("Way $way_id references missing node $node_id");
			}
		}
	}
	# Relate nodes and ways to relations that reference them
	$i= $store->iterator('r');
	while ((($rel_id,$rel)= $i->()) and $rel_id =~ /^r/) {
		for my $m (@{ $rel->{member} // [] }) {
			my $typ= $m->{type} // '';
			# If relation mentions a way or node, load it and add the reference
			# and store it back.
			if ($typ eq 'node' && $m->{ref}) {
				my $n= $store->get("n$m->{ref}");
				if ($n) {
					push @{ $n->[2] }, $rel_id;
					$store->put("n$m->{ref}");
				} else {
					$log->notice("Relation $rel_id references missing node $m->{ref}");
				}
			}
			elsif ($typ eq 'way' && $m->{ref}) {
				my $way= $store->get("w$m->{ref}");
				if ($way) {
					push @{ $way->{rel} }, $rel_id;
					$store->put("w$m->{ref}", $way);
				}
				else {
					$log->notice("Relation $rel_id references missing way $m->{ref}");
				}
			}
		}
	}
	
	$store->put(preprocessed => 1);
}

sub generate_roads {
	my ($self, $sdb)= @_;
	$self->preprocess;
	my $stor= $self->tmp_storage;
	
	# Iterate every 'way' looking for ones with a 'highway' tag
	my $i= $stor->iterator('w');
	my ($way_id, $way);
	while ((($way_id, $way)= $i->()) and $way_id =~ /^w/) {
		next unless $way->{tag}{highway};
		
		
		my @path;
		for my $node_id (@{$way->{nd}}) {
			my $node= $stor->get('n'.$node_id);
			if (!$node) {
				$log->error("Way $way_id references missing node $node_id");
				next;
			}
			# Is the node referenced by other ways? If so, we create it as a "location".
			# If not, then we just grab its lat/lon and ignore the rest.
			my %ref= map { $_ => 1 } @{ $node->[2] };
			if (1 < keys %ref) {
				my $export_id= "osm_n$node_id";
				unless ($stor->get("_exported_$export_id")) {
					my $loc= Geo::SpatialDB::Entity::Location->new(
						id   => "osm_n$node_id",
						type => 'todo',
						lat  => $node->[0],
						lon  => $node->[1],
						rad  => 0,
						tags => $node->[3],
						rel  => [ map { "osm_$_" } keys %ref ],
					);
					$sdb->add_entity($loc);
					$stor->put("_exported_$export_id", 1);
				}
				push @path, [ $node->[0], $node->[1], $export_id ];
			}
			else {
				push @path, [ $node->[0], $node->[1] ];
			}
		}
		my $route= Geo::SpatialDB::Entity::Route::Road->new(
			id     => "osm_$way_id",
			type   => 'road',
			oneway => ($way->{tag}{oneway} && $way->{tag}{oneway} eq 'yes')? 1 : 0,
			tags => $way->{tags},
			path => \@path,
		);
		$sdb->add_entity($route);
	}
}

sub _open_stream {
	my ($self, $thing)= @_;
	if (!ref($thing) or ref($thing) eq 'SCALAR' or ref($thing) =~ /^Path::Class/) {
		open my $fh, '<:raw', $thing
			or die "open('$thing'): $!\n";
		# Automatic decompression of known file extensions
		if ($thing =~ /\.bz2$/) {
			require IO::Uncompress::Bunzip2;
			$fh= IO::Uncompress::Bunzip2->new($fh);
		} elsif ($thing =~ /\.gz$/) {
			require IO::Uncompress::Gunzip;
			$fh= IO::Uncompress::Gunzip->new($fh);
		}
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
