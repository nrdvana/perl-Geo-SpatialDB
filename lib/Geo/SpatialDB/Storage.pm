package Geo::SpatialDB::Storage;

use Moo 2;
use Module::Runtime 'require_module';
use File::Spec::Functions 'catfile';
use Carp;
use JSON::MaybeXS;
use namespace::clean;

# ABSTRACT: Base class for key/value storage appropriate for Geo::SpatialDB

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

=head1 METHODS

=head2 coerce

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

sub _unimplemented { my ($class, $method)= @_; croak "$class has not implemented $method" }
sub get         { _unimplemented(shift, 'get') }
sub put         { _unimplemented(shift, 'put') }
sub commit      { _unimplemented(shift, 'commit') }
sub rollback    { _unimplemented(shift, 'rollback') }
sub iterator    { _unimplemented(shift, 'iterator') }
sub save_config { _unimplemented(shift, 'save_config') }

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
