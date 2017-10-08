package Geo::SpatialDB::Storage;

use Moo 2;
use Module::Runtime 'require_module';
use File::Spec::Functions 'catfile';
use Carp;
use JSON::MaybeXS;
use namespace::clean;

# ABSTRACT: Base class for key/value storage appropriate for Geo::SpatialDB

has create => ( is => 'ro' );

sub coerce {
	my $thing= shift;
	# Ignore class name if this was called as a package method
	$thing= shift if @_ or $thing && !ref($thing) && $thing->isa(__PACKAGE__);
	my %cfg;
	if (!defined $thing or !ref($thing) && !length($thing)) {
		%cfg= ( path => 'geo.db' );
	}
	elsif (!ref $thing) {
		%cfg= ( path => $thing );
	}
	if (ref($thing) eq 'HASH') {
		%cfg= %$thing;
	}
	elsif (ref($thing) && ref($thing)->can('get')) {
		return $thing
	} else {
		croak("Can't coerce $thing to Storage instance");
	}
	
	# If the config includes a path and the directory exists, load additional
	# settings from its config file.
	if (defined $cfg{path} and -d $cfg{path}) {
		my $cfgfile= catfile($cfg{path}, 'config.json');
		-f $cfgfile or croak "Storage path '$cfg{path}' lacks a config file '$cfgfile'";
		# Load extra settings from config file
		open my $cfg_fh, '<:encoding(UTF-8)', $cfgfile or croak "Can't open '$cfgfile': $!";
		local $/= undef;
		%cfg= ( %{ JSON::MaybeXS->new->relaxed->decode(<$cfg_fh>) }, %cfg );
		$cfg{CLASS} or croak "Storage CLASS not set?";
	}

	my $class= delete $cfg{CLASS} || 'LMDB_Storable';
	$class= "Geo::SpatialDB::Storage::$class"
		unless $class =~ /^Geo::SpatialDB::Storage::/;
	require_module($class);
	return $class->new(%cfg);
}

sub _config_filename { catfile(shift->path, 'config.json') }

sub save_config {
	croak "save_config: unimplemented"
}

sub _write_config_file {
	my ($self, $cfg)= @_;
	my $cfgfile= $self->_config_filename;
	my $cfg_json= JSON::MaybeXS->new->canonical->relaxed->pretty->encode({
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
