package Geo::SpatialDB::Storage;

use Moo 2;
use Module::Runtime 'require_module';
use File::Spec::Functions 'catfile';
use Carp;
use JSON;
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
	my %cfg;
	if (!defined $thing or !ref($thing) && !length($thing)) {
		%cfg= ( path => 'geo.db' );
	}
	elsif (!ref $thing or ref($thing) =~ /path/i) {
		%cfg= ( path => $thing );
	}
	elsif (ref($thing) eq 'HASH') {
		%cfg= %$thing;
	}
	elsif (ref($thing) && ref($thing)->can('get')) {
		return $thing
	} else {
		croak("Can't coerce $thing to Storage instance");
	}
	
	# If the config includes a path and the directory exists, load additional
	# settings from its config file.
	if (defined $cfg{path} and !__PACKAGE__->_storage_dir_empty($cfg{path})) {
		my $cfgfile= catfile($cfg{path}, 'config.json');
		-f $cfgfile or croak "Storage path '$cfg{path}' lacks a config file '$cfgfile'";
		# Load extra settings from config file
		open my $cfg_fh, '<:encoding(UTF-8)', $cfgfile or croak "Can't open '$cfgfile': $!";
		local $/= undef;
		%cfg= ( %{ JSON->new->relaxed->decode(<$cfg_fh>) }, %cfg );
		$cfg{CLASS} or croak "Storage CLASS not set?";
	}

	my $class= delete $cfg{CLASS} || 'LMDB_Storable';
	$class= "Geo::SpatialDB::Storage::$class"
		unless $class =~ /^Geo::SpatialDB::Storage::/;
	require_module($class);
	return $class->new(%cfg);
}

sub _storage_dir_empty {
	my ($class, $path)= @_;
	return !(grep { $_ ne '.' and $_ ne '..' } <$path/*>);
}

sub _config_filename { catfile(shift->path, 'config.json') }

=head2 save_config

This must be implemented by each subclass.  It should collect any relevant
configuration settings and pass them as a hashref to C<_write_config_file>
so that those settings can be re-loaded in the future.

=cut

sub save_config {
	croak "save_config: unimplemented"
}

sub _write_config_file {
	my ($self, $cfg)= @_;
	my $cfgfile= $self->_config_filename;
	my $cfg_json= JSON->new->canonical->relaxed->pretty->encode({
		%$cfg,
		CLASS => ref $self,
	});
	my $cfg_fh;
	open($cfg_fh, '>:encoding(UTF-8)', $cfgfile)
		and $cfg_fh->print($cfg_json)
		and close($cfg_fh)
		or croak "Can't write '$cfgfile': $!";
}

1;
