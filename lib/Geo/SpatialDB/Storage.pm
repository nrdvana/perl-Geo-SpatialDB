package Geo::SpatialDB::Storage;
use Moo::Role 2;
use Module::Runtime 'require_module';
use File::Spec::Functions 'catfile';
use Carp;
use JSON::MaybeXS;
use namespace::clean;

# ABSTRACT: Base class for key/value storage appropriate for Geo::SpatialDB
# VERSION

=head1 DESCRIPTION

This is the base class for all Storage modules.  The only thing it currently
provides are facilities for saving out the configuration of a Storage instance
so that it can be re-loaded later from just the path name.

=head1 ATTRIBUTES

=head2 create

Whether or not the Storage instance should be created if it doesn't exist.
If false, a Storage engine should throw an exception if the instance wasn't
already initialized.  If C<1>, a Storage instance should initialize the
storage and throw an exception if it was already initialized.  If the value is
C<'auto'> then the storage should be initialized if it doesn't exist.

=cut

has create => ( is => 'ro' );

=head1 SETUP METHODS

=head2 coerce

  my $storage= Geo::SpatialDB::Storage->coerce( $something );

This is a class method.  It takes "something" and tries to coerce it into a
storage instance.  It can be a single string (path), a hashref of options,
or even an allocated storage instance (which gets returned as-is).

In the single-string path scenario, or in a hashref with a C<path> key,
this method will look up the config file at that path and include the config
settings as additional default values for the hashref.  (i.e. they will be
included in the hashref only if the hashref didn't already define them)

This allows you to say C<Geo::SpatialDB::Storage->coerce($path)> and have it
automatically detect the storage engine and any settings that it was
previously initialized with.

=head2 save_config

Every storage implementation writes a json file to its directory containing
the list of arguments to pass back to C<< Geo::SpatialDB::Storage::coerce >>
to re-create that instance.  Call save_config to update this json file.

=head2 get_ctor_args

  my $hashref= $storage->get_ctor_args;

Get list of arguments for constructor (L</coerce>, actually) which can
re-create this storage object.

=cut

sub coerce {
	my $thing= shift;
	# Ignore class name if this was called as a package method
	$thing= shift if @_ or $thing && !ref($thing) && $thing->isa(__PACKAGE__);
	# Return instances of Storage as-is
	return $thing if ref($thing) && ref($thing)->isa('Geo::SpatialDB::Storage');
	# Else coerce to a hash of parameters
	my %cfg= (!ref $thing || ref($thing)->can('mkpath'))? ( path => $thing )
		: (ref($thing) eq 'HASH')? %$thing
		: croak("Can't coerce $thing to Storage instance");
	# If the config includes a path, and the path exists, pull in additional settings
	my $class= _interpret_class_name(delete $cfg{CLASS});
	if (defined $cfg{path} && -e $cfg{path}) {
		require_module($class) if $class;
		my $include_impl= $class || __PACKAGE__;
		my %extra_cfg= $include_impl->_include_attrs_from_config(%cfg);
		if ($extra_cfg{CLASS}) {
			$class= _interpret_class_name(delete $extra_cfg{CLASS});
			require_module($class);
			# If 'CLASS' changed, and it defines its own _include_attrs_from_config,
			# then re-run that.
			%extra_cfg= $class->_include_attrs_from_config(%cfg)
				if $class->can('_include_attrs_from_config') != $include_impl->can('_include_attrs_from_config');
			$class= _interpret_class_name(delete $extra_cfg{CLASS})
				if $extra_cfg{CLASS};
		}
		%cfg= %extra_cfg;
	}
	$class ||= 'Geo::SpatialDB::Storage::LMDB_Storable';
	require_module($class);
	return $class->new(%cfg);
}

sub _interpret_class_name {
	my $name= shift;
	return undef unless $name;
	$name =~ s/^\+//? $name
	: $name =~ /::/? $name
	: 'Geo::SpatialDB::Storage::'.$name;
}

sub _storage_dir_empty {
	my ($class, $path)= @_;
	return !(grep { $_ ne '.' and $_ ne '..' } <$path/*>);
}

sub save_config {
	my $self= shift;
	$self->_save_config($self->path, $self->get_ctor_args);
}

requires 'get_ctor_args';

=head1 METADATA METHODS

=head2 indexes

  # {
  #   $index_name => { name => $index_name, %flags, ... },
  #   ...
  # ]

Returns a hashref of all the available indexes.

=head2 create_index

  $storage->create_index( $index_name, %flags );

Create a named index.  If it exists, this dies.  Flags can be used to optimize the index for
a particular kind of key or data.

=over 14

=item C<< int_key => 1 >>

All keys are platform-native integers

=item C<< int_value => 1 >>

Values are also integers

=item C<< multivalue => 1 >>

Multiple values can be stored under the same key

=back

=head2 drop_index

  $storage->drop_index( $index_name );

=cut

requires 'indexes';
requires 'create_index';
requires 'drop_index';

=head1 DATA METHODS

=head2 get

  my $value= $storage->get( $index_name, $key );

=head2 put

  $storage->put( $index_name, $key, $value, %flags );

=head2 commit

  $storage->commit

Commit all changes made to any index since the last open, commit, or rollback.
Yes, this means that any calls to L</put> will always need to be followed by
C<commit> before they become part of the stored data.

=head2 rollback

Rollback all changes made to any index since the last open, commit, or rollback.

=head2 iterator

  my $iter= $storage->iterator( $index_name );
  my $iter= $storage->iterator( $index_name, $start_key );
  my $iter= $storage->iterator( $index_name, $start_key, $limit_key );

Get an iterator for an index, optionally bounded from one key to another.

=cut

requires 'get';
requires 'put';
requires 'commit';
requires 'rollback';
requires 'iterator';
requires 'save_config';

sub _include_attrs_from_config {
	my $class= shift;
	my %cfg= @_==1? %{$_[0]} : @_;
	return %cfg unless $cfg{path} and (-f $cfg{path} or -f catfile($cfg{path}, 'config.json'));
	return %cfg, %{ $class->_load_config($cfg{path}) };
}

sub _load_config {
	my ($class, $path)= @_;
	# If a file, then that *is* the config.  If a directory, then look for config.json
	my $fname= -d $path? catfile($path, 'config.json') : $path;
	-f $fname or croak "No such storage config '$fname'";
	return JSON::MaybeXS->new->relaxed->utf8->decode(do {
		open my $fh, '<:raw', $fname or croak "Can't open '$fname': $!";
		local $/= undef;
		<$fh>
	});
}

sub _save_config {
	my ($class, $path, $cfg)= @_;
	my $fname= -d $path? catfile($path, 'config.json') : $path;
	my $data= JSON::MaybeXS->new->relaxed->canonical->pretty->utf8->encode($cfg);
	my $fh;
	open($fh, '>:raw', $fname)
		and $fh->print($data)
		and close($fh)
		or croak "Can't write storage config '$fname': $!";
}

1;
