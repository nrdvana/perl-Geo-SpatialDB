package Geo::SpatialDB::Storage::LMDB_Storable;
use Moo 2;
use LMDB_File ':flags';
use Storable 'freeze', 'thaw';
sub _croak { require Carp; goto &Carp::croak }
use namespace::clean;

extends 'Geo::SpatialDB::Storage';

has path      => ( is => 'ro', required => 1 );
has readonly  => ( is => 'ro', default => sub { 0 } );
has mapsize   => ( is => 'ro', default => sub { 0xC0000000 } );
has go_faster => ( is => 'ro', default => sub { 0 } );

sub BUILD {
	my $self= shift;
	# Immediately try to access the DB so that errors get reported
	# as soon as user creates the object
	$self->get(0);
}

has _env => ( is => 'lazy' );
sub _build__env {
	my $self= shift;
	my $path= $self->path;
	LMDB::Env->new($path, {
		mapsize => $self->mapsize,
		flags   =>
			(-d $path? 0 : MDB_NOSUBDIR)
			| ($self->readonly? MDB_RDONLY : 0)
			| ($self->go_faster? MDB_WRITEMAP|MDB_NOMETASYNC : 0)
		}
	);
}

has _txn => ( is => 'lazy' );
sub _build__txn {
	shift->_env->BeginTxn;
}
has _db => ( is => 'lazy' );
sub _build__db {
	shift->_txn->OpenDB();
}

my $storable_magic= substr(freeze({}), 0, 1);
sub die_invalid_assumption {
	die "Author has made invalid assumptions for your version of Storable and needs to fix his code";
}
$storable_magic =~ /[\0-\x19]/ or die_invalid_assumption();

sub get {
	my $v= shift->_db->get(shift);
	$v= thaw($v) if substr($v, 0, 1) eq $storable_magic;
}

sub put {
	my $v= $_[2];
	if (ref $v) {
		$v= freeze($v);
		substr($v, 0, 1) eq $storable_magic
			or die_invalid_assumption();
	} else {
		ord(substr($v, 0, 1)) > 0x1F or _croak("scalars must not start with control characters");
	}
	shift->_db->put(shift, $v);
}

sub delete {
	shift->_db->del(shift);
}

1;
