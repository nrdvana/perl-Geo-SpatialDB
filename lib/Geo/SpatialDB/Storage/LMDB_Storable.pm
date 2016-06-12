package Geo::SpatialDB::Storage::LMDB_Storable;
use Moo 2;
use LMDB_File ':flags', ':cursor_op', ':error';
use Storable 'freeze', 'thaw';
sub _croak { require Carp; goto &Carp::croak }
use namespace::clean;

extends 'Geo::SpatialDB::Storage';

=head1 DESCRIPTION

Storage engine LMDB_Storable uses (as the name implies) L<Storable> to serialize
perl data structures, and LMDB (via the L<LMDB_File> module) for disk storage.
I *think* this is the fastest possible way to persist Perl objects, but if you
find something faster, I'd love to hear about it.

=head1 ATTRIBUTES

=head2 path

The path for the LMDB files.  If this is an existing directory, LMDB will be
initialized in the standard manner.  But if it is a file (or missing) then we
treat it as the database file itself, which means the directory must be
writable in order for LMDB to create the lock file along side of it.

=head2 readonly

Boolean.  If true, then open the DB in readonly mode.  Useful for read-only
filesystems.

=head2 mapsize

The maximum size of the database; default is 3GB.  (LMDB needs this parameter)

=head2 run_with_scissors

If set to 1, then enable unsafe behavior in order to get some extra speed.
Useful for large batch operations where the database can be thrown away if
the operation fails catastrophically.

=cut

has path      => ( is => 'ro', required => 1 );
has readonly  => ( is => 'ro', default => sub { 0 } );
has mapsize   => ( is => 'ro', default => sub { 0xC0000000 } );
has run_with_scissors => ( is => 'ro', default => sub { 0 } );

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
			| ($self->run_with_scissors? MDB_WRITEMAP|MDB_NOMETASYNC : 0)
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

=head1 METHODS

=head2 get

  my $value= $stor->get( $key );

Get the value of a key, or undef if the key doesn't exist.

=cut

sub get {
	my $v= shift->_db->get(shift);
	$v= thaw($v) if defined $v and substr($v, 0, 1) eq $storable_magic;
	return $v;
}

=head2 put

  $stor->put( $key, $value );

Store a value in the database.  If the key exists it will overwrite the old value.
If C<$value> is undefined, this deletes the key from the database.

=cut

sub put {
	my ($self, $k, $v)= @_;
	if (!defined $v) {
		return $self->_db->del($k);
	}
	elsif (ref $v) {
		$v= freeze($v);
		substr($v, 0, 1) eq $storable_magic
			or die_invalid_assumption();
	} else {
		ord(substr($v, 0, 1)) > 0x1F or _croak("scalars must not start with control characters");
	}
	$self->_db->put($k, $v);
}

=head2 iterator

  my $i= $stor->iterator;
  # or
  my $i= $stor->iterator( $from_key );
  # then...
  while (my $k= $i->()) { ... }
  # or
  while (my ($k, $v)= $i->()) { ... }

Return a coderef which can iterate keys or key,value pairs.
If you specify C<$from_key>, then iteration begins at the first key equal or
greater to it.

=cut

sub iterator {
	my ($self, $key)= @_;
	my $op= defined $key? MDB_SET_RANGE : MDB_FIRST;
	my $cursor= $self->_db->Cursor;
	my $data;
	return sub {
		local $LMDB_File::die_on_err= 0;
		my $ret= $cursor->get($key, $data, $op);
		$op= MDB_NEXT;
		if ($ret) {
			return if $ret == MDB_NOTFOUND;
			die $LMDB_File::last_err
		}
		return $key unless wantarray;
		$data= thaw($data) if substr($data, 0, 1) eq $storable_magic;
		return ($key, $data);
	}
}

1;
