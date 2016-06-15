package Geo::SpatialDB::Import::OpenStreetMap;
use Moo 2;
use Carp;
use XML::Parser;
use Geo::SpatialDB::Location;
use Geo::SpatialDB::Path;
use Geo::SpatialDB::RouteSegment;
use Geo::SpatialDB::Route::Road;
use Geo::SpatialDB::Area;
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
	my $stor= $self->tmp_storage;
	my $stats= $self->stats;
	return if $stor->get('preprocessed');
	
	my ($way_id, $rel_id, $way, $rel);
	
	# Relate nodes to ways that reference them
	my $i= $stor->iterator('w');
	while ((($way_id,$way)= $i->()) and $way_id =~ /^w/) {
		$stats->{preproc_way}++;
		for my $node_id (@{ $way->{nd} // [] }) {
			my $n= $stor->get("n$node_id");
			if ($n) {
				push @{ $n->[2] }, $way_id;
				$stor->put("n$node_id", $n);
				$stats->{preproc_rewrite_node}++;
			} else {
				$log->notice("Way $way_id references missing node $node_id");
			}
		}
	}
	# Relate nodes and ways to relations that reference them
	$i= $stor->iterator('r');
	while ((($rel_id,$rel)= $i->()) and $rel_id =~ /^r/) {
		$stats->{preproc_relation}++;
		for my $m (@{ $rel->{member} // [] }) {
			my $typ= $m->{type} // '';
			# If relation mentions a way or node, load it and add the reference
			# and store it back.
			if ($typ eq 'node' && $m->{ref}) {
				my $n= $stor->get("n$m->{ref}");
				if ($n) {
					push @{ $n->[2] }, $rel_id;
					$stor->put("n$m->{ref}");
					$stats->{preproc_rewrite_node}++;
				} else {
					$log->notice("Relation $rel_id references missing node $m->{ref}");
				}
			}
			elsif ($typ eq 'way' && $m->{ref}) {
				my $way= $stor->get("w$m->{ref}");
				if ($way) {
					push @{ $way->{rel} }, $rel_id;
					$stor->put("w$m->{ref}", $way);
					$stats->{preproc_rewrite_way}++;
				}
				else {
					$log->notice("Relation $rel_id references missing way $m->{ref}");
				}
			}
		}
	}
	$stor->put(stats => $stats);
	$stor->put(preprocessed => 1);
}

sub generate_roads {
	my ($self, $sdb)= @_;
	$self->preprocess;
	my $stor= $self->tmp_storage;
	my $stats= $self->stats;
	
	# Iterate every 'way' looking for ones with a 'highway' tag
	my $i= $stor->iterator('w');
	my ($way_id, $way);
	while ((($way_id, $way)= $i->()) and $way_id =~ /^w/) {
		next unless $way->{tag}{highway};
		
		my $type= 'road.' . delete $way->{tag}{highway};

		my $route_id= "osm_${type}_" . lc($way->{tag}{name} // $way_id);
		$route_id =~ s/[^a-z0-9_.]//g;

		my @path;
		for my $node_id (@{$way->{nd}}) {
			my $node= $stor->get("n$node_id");
			if (!$node) {
				$log->error("Way $way_id references missing node $node_id");
				next;
			}
			# Is the node referenced by other ways? If so, we create it as a "location".
			# If not, then we just grab its lat/lon and ignore the rest.
			# TODO: we should generate an Intersection Location and start a new
			# RouteSegment each time more than one Way with tag of Highway
			# shares the same node.
			my %ref= map { $_ => 1 } @{ $node->[2] };
			if (1 < keys %ref) {
				my $export_id= "osm_n$node_id";
				unless ($stor->get("_exported_$export_id")) {
					my $loc= Geo::SpatialDB::Location->new(
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
					$stats->{gen_road_loc}++;
				}
				push @path, [ $node->[0], $node->[1], $export_id ];
			}
			else {
				push @path, [ $node->[0], $node->[1] ];
			}
		}
		if (!@path) {
			$log->notice("Skipping empty path generated from way $way_id");
			next;
		}
		#my $path= Geo::SpatialDB::Path->new(
		#	id  => "osm_$way_id",
		#	seq => \@path
		#);
		# TODO: There should be multiple of these
		my @segments= ( Geo::SpatialDB::RouteSegment->new(
			id     => "osm_$way_id",
			type   => $type,
			($way->{tag}{oneway} && $way->{tag}{oneway} eq 'yes'? (oneway => 1) : ()),
			path   => \@path,
			tags   => $way->{tag},
			routes => [ $route_id ],
		) );
		
		# Load or create a "Route" object to represent the name and metadata of this road.
		# TODO: this is pretty basic right now.  do smarter stuff here.
		my $road= $sdb->storage->get($route_id);
		if ($road) {
			# Add references to these segments
			$road->segments([ @{ $road->segments//[] }, map { $_->id } @segments ]);
		} else {
			my @names= delete $way->{tag}{name};
			my $i= 1;
			while (defined $way->{tag}{"name_$i"}) {
				push @names, delete $way->{tag}{"name_$i"};
				++$i;
			}
			# Scan the relations mentioning this Way for highway names,
			# which we include in the names list
			for (grep { /^r/ } @{ $way->{rel} }) {
				my $rel= $stor->get($_);
				if ($rel && $rel->{tag}{type} eq 'route' && $rel->{tag}{route} eq 'road') {
					push @names, grep { defined } $rel->{tag}{name}, $rel->{tag}{ref};
				}
			}
			
			$stats->{gen_road}++;
			$road= Geo::SpatialDB::Route::Road->new(
				id     => $route_id,
				type   => $type,
				names  => \@names,
				tags   => $way->{tag},
				segments => [ map { $_->id } @segments ],
			);
		};
		
		# Write or overwrite the road, since we modified it to reference these segment(s)
		$sdb->add_entity($road);
		# Write each segment
		$sdb->add_entity($_) for @segments;
		$stats->{gen_road_seg}+= @segments;
		$stats->{gen_road_seg_pts}+= scalar @path;
	}
}

sub generate_waterways {
}

sub generate_trails {
}

sub generate_areas {
	# TODO: government zones
	# TODO: postal zones
	# TODO: time zones
	# TODO: parks, historic areas, etc
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
