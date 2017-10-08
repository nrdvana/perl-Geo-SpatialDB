package Geo::SpatialDB::Import::OpenStreetMap;

use Moo 2;
use Carp;
use XML::Parser;
use File::Temp;
use JSON::MaybeXS;
use Log::Any '$log';
use Geo::SpatialDB::Storage;
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

Since these require significant processing to make them into usable objects,
the first task is to parse all the XML files and store all the data in an
indexed L</tmp_storage> database, via multiple calls to L</load_xml>.
When this is done, call L</preprocess> to cross-reference all the relations
so that i.e. a node know which Ways it is a part of in addition to the way
knowing which nodes it is composed of.

  my $imp= Geo::SpatialDB::Import::OpenStreetMap->new();
  $imp->load_xml( $region_one_filename );
  $imp->load_xml( $region_two_filename );
  ...
  $imp->preprocess;

Once this pre-processed and indexed data is ready, you can begin importing
Entities from it.  The methods "generate_*" methods each take a reference
to the destination Geo::SpatialDB, and options about which sorts of object
to import.

=head1 ATTRIBUTES

=head2 tmp_storage

An instance of L<Geo::SpatialDB::Storage> that will be used to pre-process the
OpenStreetMap data.  Crunching data for one of the regional US databases will
require tens of gigabytes and several minutes of processing (or maybe hours with
older hardware).  The default is to create a temp dir and initialize
a new LMDB in it.  This will be deleted on completion of the script, which may
be undesirable.  You should also use the fastest available storage engine.

=head2 entity_id_prefix

The IDs from the input willb e used directly, but if this causes a problem for
your application you cna prefix them all with a string of your choosing.

=head2 stats

This holds information about the pre-processed temporary data.  It is also
saved to the temporary storage, so it can persist across script runs if you
are using persistent temp storage.

=cut

has tmp_storage      => ( is => 'lazy', init_arg => undef );
has _tmp_storage_arg => ( is => 'rw', init_arg => 'tmp_storage' );
has entity_id_prefix => ( is => 'rw' );
has stats            => ( is => 'lazy' );

sub _build_stats {
	my $self= shift;
	$self->tmp_storage->get('stats') || {};
}

sub _build_tmp_storage {
	my $self= shift;
	my $thing= $self->_tmp_storage_arg;
	return $thing if ref($thing) and ref($thing)->isa('Geo::SpatialDB::Storage');
	my %cfg= (!ref $thing or ref($thing) =~ /path/i)? ( path => $thing )
		: (ref($thing) eq 'HASH')? %$thing
		: defined $thing? croak("Can't coerce $thing to Storage instance")
		: ();
	$cfg{path}= File::Temp->newdir('geo-import-osm-XXXXX')
		unless defined $cfg{path};
	$cfg{run_with_scissors}= 1;
	$cfg{create}= 'auto';
	Geo::SpatialDB::Storage::coerce(\%cfg);
}

sub DESTROY {
	my $self= shift;
	# When cleaning up, make the storage go out of scope before its path does,
	# for the case when path is a Tmpdir object which wants to delete everything.
	my $path= $self->tmp_storage->path
		if $self->tmp_storage->can('path');
	delete $self->{tmp_storage};
}

=head1 METHODS

=head2 load_xml

  $importer->load_xml( $filename,  %options );
  $importer->load_xml( $handle,    %options );

When using a filename, if the suffix is '.bz2' or '.gz' it will automatically
pass through the appropriate decompressor.  If it is a file handle, it will
be used directly and assumed to be XML.

Can throw exceptions on read or XML parse errors, but currently it just
ignores any tag it doesn't recognize.  The data is loaded into L</tmp_storage>
and the statistics are collected in L</stats>.

Options:

=over

=item progress

Set to an instance of L<Log::Progress> to get progress updates on how much
of the input file has been read.  This may be somewhat inaccurate since it
reports the progress of reading blocks not the progress of parsing them.

=back

Returns C<$self>, for chaining.

=cut

sub load_xml {
	my ($self, $source)= @_;
	my @stack;
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
				push @{ $stack[-1]{nd} }, $obj->{ref}+0
					if @stack;
			}
			elsif ($el eq 'member') {
				push @{ $stack[-1]{member} }, $obj
					if @stack;
			}
			elsif ($el eq 'node') {
				# Convert lat/lon to microdegree integers, to save space when encoded
				my $lat= int( $obj->{lat} * 1_000_000 );
				my $lon= int( $obj->{lon} * 1_000_000 );
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
	$stor->commit;
	$self;
}

=head2 preprocess

After loading XML data, the entities need cross-referenced.  call this method
to perform that step.  If L</progress> is set, this routine will log the
progress as it runs with a sub-task ID of C<"preprocess">.

=cut

sub preprocess {
	my $self= shift;
	my $stor= $self->tmp_storage;
	my $stats= $self->stats;
	return if $stor->get('preprocessed');
	
	my ($way_id, $rel_id, $way, $rel);
	my ($progress_i, $progress_n, $progress_prev, $progress_ival)= (0, $stats->{way}+$stats->{relation}, -1, 0.05);
	
	# Relate nodes to ways that reference them
	my $i= $stor->iterator('w');
	while ((($way_id,$way)= $i->()) and $way_id =~ /^w/) {
		if ($progress_i++ / $progress_n >= $progress_prev + $progress_ival) {
			$log->info("progress: $progress_i/$progress_n");
			$progress_prev= ($progress_i-1) / $progress_n;
		}
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
		if ($progress_i++ / $progress_n >= $progress_prev + $progress_ival) {
			$log->info("progress: $progress_i/$progress_n");
			$progress_prev= ($progress_i-1) / $progress_n;
		}
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
	$stor->commit;
}

=head2 dump_json

  $importer->dump_json;  # default is STDOUT
  $importer->dump_json( $file_handle );

Dump the entire contents of the temporary cache as a json object, with each
entry (node, way, or relation) written on its own line, for improved ability
to browse or manipulate the stream.

Note that the data exported might expose some implementation details of this
module, but I will attempt to preserve the structure as much as possible.

=cut

sub dump_json {
	my ($self, $fh)= @_;
	$fh ||= \*STDOUT;

	my $json= JSON::MaybeXS->new->canonical;
	# want to export UTF-8 unless user selected a different encoding for the file handle
	my @layers= PerlIO::get_layers($fh, output => 1);
	$json->utf8(1) unless grep { /encoding|utf/i } @layers;

	my $iter= $self->tmp_storage->iterator;
	my ($id, $entity, $prev);
	print "{\n";
	while (($id, $entity)= $iter->()) {
		next unless ref $entity and $id =~ /^[nwr]\d/;
		print ",\n" if $prev;
		$prev= 1;
		print qq{ "$id": }.$json->encode($entity);
	}
	print "\n}\n";
}

=head2 aggregate_tags

  my $tags= $importer->aggregate_tags( %options );
  # Options:
  #   with_values => $bool
  #   filter => { tag_name => qr/$value_regex/, ... }
  
  # Result when with_values => 0
  {
     $tag_name1 => $count1,
     $tag_name2 => $count2,
     ...
  }

  # Result when with_values => 1
  {
     $tag_name1 => { $tag_value1 => $count1, $tag_value2 => $count2, ... },
     $tag_name2 => ...
     ...
  }

This is a helpful diagnostic tool for searching through all indexed entities
to learn what tags and what tag values are available.  By default, it only
returns the tag names and their count, but you can also return the distinct
values and their count. (but that gets large)

To reduce the size of the result, you can filter which objects are included
by specifying tags and regexes.  Only objects which have all those tags and
tag values matching the regex will be aggregated.

=cut

sub aggregate_tags {
	my ($self, %opts)= @_;
	my $with_values= $opts{values};
	my $filter= $opts{filter} || {};
	my %tags;
	my $iter= $self->tmp_storage->iterator;
	my ($id, $entity);
	ent: while (($id, $entity)= $iter->()) {
		next unless ref $entity eq 'HASH';
		my $tag= $entity->{tag};
		next unless $tag and ref $tag eq 'HASH' and keys %$tag;
		for (keys %$filter) {
			next ent unless defined $tag->{$_} and $tag->{$_} =~ $filter->{$_};
		}
		if ($with_values) {
			++$tags{$_}{$tag->{$_}} for keys %$tag;
		} else {
			++$tags{$_} for keys %$tag;
		}
	}
	return \%tags;
}

sub generate_roads {
	my ($self, $sdb, %opts)= @_;
	$self->preprocess;
	my $stor= $self->tmp_storage;
	my $stats= $self->stats;
	my $prefix= $self->entity_id_prefix // '';
	my $tmp_prefix= "~";
	my ($progress_i, $progress_n, $progress_prev, $progress_ival)= (0, $stats->{way}, -1, 0.05);
	
	my $wanted_subtypes= $opts{type} // {
		map { $_ => 1 } qw(
			motorway motorway_link rest_area
			trunk trunk_link
			primary primary_link
			secondary secondary_link
			tertiary tertiary_link
			service residential living_street
			road unclassified track )
	};
	
	# Iterate every 'way' looking for ones with a 'highway' tag
	my $i= $stor->iterator('w');
	my ($way_id, $way);
	while ((($way_id, $way)= $i->()) and $way_id =~ /^w/) {
		if ($progress_i++ / $progress_n >= $progress_prev + $progress_ival) {
			$log->info("progress: $progress_i/$progress_n");
			$progress_prev= ($progress_i-1) / $progress_n;
		}
		
		next unless $way->{tag}{highway} and $wanted_subtypes->{$way->{tag}{highway}};
		
		my $type= 'road.' . delete $way->{tag}{highway};
		$stats->{types}{$type}++;
		
		# Delete all "tiger:" tags, for now.  (they're not very useful for my purposes)
		delete $way->{tag}{$_} for grep { /^tiger:/ } keys %{ $way->{tag} };

		my $seg_idx= 0;
		my $seg_id= sprintf("%sw%X.%X", $prefix, substr($way_id,1), $seg_idx++);
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
				my $loc_id= sprintf("%sn%X", $prefix, $node_id);
				my $loc= $stor->get("$tmp_prefix$loc_id");
				if (!$loc) {
					$loc= Geo::SpatialDB::Location->new(
						id   => $loc_id,
						type => 'todo',
						lat  => $node->[0],
						lon  => $node->[1],
						rad  => 0,
						tags => $node->[3],
					);
					$stats->{gen_road_loc}++;
				}
				$loc->rel([ @{ $loc->rel // [] }, $seg_id ]);
				$stor->put("$tmp_prefix$loc_id", $loc);
				push @path, [ $node->[0], $node->[1], $loc_id ];
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
		# TODO: There should be multiple of these created
		my @segments= ( Geo::SpatialDB::RouteSegment->new(
			id     => $seg_id,
			type   => $type,
			($way->{tag}{oneway} && $way->{tag}{oneway} eq 'yes'? (oneway => 1) : ()),
			path   => \@path,
			# TODO: add tags related to road surface or speed limit
			routes => [],
		) );

		# Each Way becomes a Route.  TODO: combine connected routes with the same name
		# into a single object and concatenate the RouteSegments.
		
		# Load or create a "Route" object to represent the name and metadata of this road.
		my $road; # = TODO: search for road of same name connected to either end of this Way
		if ($road) {
			# Merge any tags that make sense to merge
		} else {
			# Multiple names are stored in name, name_1, etc
			my @names= delete $way->{tag}{name};
			my $i= 1;
			while (defined $way->{tag}{"name_$i"}) {
				push @names, delete $way->{tag}{"name_$i"};
				++$i;
			}
			# TODO: keep only the keys we care about
			# We don't bother creating a Road entry unless it has a name or tags
			if (@names || keys %{ $way->{tag} }) {
				$stats->{gen_road}++;
				my $route_id= sprintf("%sw%X", $prefix, substr($way_id,1));
				$road= Geo::SpatialDB::Route::Road->new(
					id       => $route_id,
					type     => $type,
					names    => \@names,
					tags     => $way->{tag},
					segments => [],
				);
			}
		}
		if ($road) {
			# Add segment ref to the route
			$road->segments([ @{ $road->segments//[] }, map { $_->id } @segments ]);
			# Add route reference to the segments
			push @{ $_->routes }, $road->id
				for @segments;
			# Store the road temporarily (in case there are more changes needed)
			$stor->put($tmp_prefix . $road->id, $road);
		}
		
		# Scan the relations mentioning this Way for highway names,
		# which we create as additional Route entities
		for my $rel_id (grep { /^r/ } @{ $way->{rel} }) {
			my $rel= $stor->get($rel_id);
			if ($rel && ($rel->{tag}{type}//'') eq 'route' && ($rel->{tag}{route}//'') eq 'road') {
				my $route_id= sprintf("%sr%X", $prefix, substr($rel_id,1));
				$road= $stor->get("$tmp_prefix$route_id");
				if (!$road) {
					$stats->{gen_road}++;
					my @names= grep { defined } $rel->{tag}{name}, $rel->{tag}{ref};
					# TODO: keep only the keys we care about
					if (@names || keys %{ $rel->{tag} }) {
						$road= Geo::SpatialDB::Route::Road->new(
							id       => $route_id,
							type     => 'road.network',
							names    => \@names,
							tags     => $rel->{tag},
							segments => [],
						);
					}
				}
				if ($road) {
					# Add segment ref to the route
					$road->segments([ @{ $road->segments//[] }, map { $_->id } @segments ]);
					# Add route reference to the segments
					push @{ $_->routes }, $road->id
						for @segments;
					# Then store the road again, to tmp storage
					$stor->put("$tmp_prefix$route_id", $road);
				}
			}
			#if ($rel && ($rel->{tag}{type}//'') eq 'route' && !$rel->{tag}{route}) {
			#	use DDP;
			#	p $rel;
			#}
		}
		
		# The segments are finished, so we import them
		$sdb->add_entity($_) for @segments;
		$stats->{gen_road_seg}+= @segments;
		$stats->{gen_road_seg_pts}+= scalar @path;
	}
	
	# Now, all segments are imported, but the routes are in tmp storage.
	# Copy them across.
	$i= $stor->iterator($tmp_prefix);
	my ($k, $v);
	while (($k, $v)= $i->() and index($k, $tmp_prefix)==0) {
		$sdb->add_entity($v);
	}
	$stor->rollback;
}

sub generate_trails {
	# TODO: 
}

sub generate_waterways {
	# TODO: rivers, lakes, etc
}

sub generate_gov_areas {
	# TODO: government zones
}
sub generate_postal_areas {
	# TODO: postal zones
}
sub generate_time_zone_areas {
	# TODO: time zones
}
sub generate_landuse_areas {
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
