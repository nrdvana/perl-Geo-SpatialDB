package Geo::SpatialDB::Storage::LMDB_Storable;
use Moo 2;
use LMDB_File ':flags', ':cursor_op', ':error';
use Storable 'freeze', 'thaw';
use Carp;
use File::Path 'make_path';
use Scalar::Util 'weaken';
use namespace::clean;

with 'Geo::SpatialDB::Storage';

# ABSTRACT: Key/value storage on LMDB, encoding Perl objects with 'Storable'
# VERSION

=head1 DESCRIPTION

Storage engine LMDB_Storable uses (as the name implies) L<Storable> to serialize
perl data structures, and LMDB (via the L<LMDB_File> module) for disk storage.
I *think* this is the fastest possible way to persist Perl objects, but if you
find something faster, I'd love to hear about it.

=head1 ATTRIBUTES

=head2 path

The path for the LMDB files.  This must be a directory, and must be writeable
unless L</readonly> is true.  The directory will be created if L</create> is
C<'auto'> or C<1>.

=head2 create

Whether to create the database.  Value of '1' means it must not previously
exist.  Value of 'auto' means create it unless it exists.

=head2 readonly

Boolean.  If true, then open the DB in readonly mode.  Useful for read-only
filesystems.

=head2 mapsize

The maximum size of the database; default is 3GB.  (LMDB needs this parameter)

=head2 maxdbs

The maximum number of named sub-databases (indexes, in this module's terminology).
The default of 250 should be sufficient for all Geo::SpatialDB activity.

=head2 run_with_scissors

If set to 1, then enable unsafe behavior in order to get some extra speed.
Useful for large batch operations where the database can be thrown away if
the operation fails catastrophically.

=cut

BEGIN { # so role sees it exists
	has path      => ( is => 'ro', required => 1 );
	has readonly  => ( is => 'ro', default => sub { 0 } );
	has mapsize   => ( is => 'ro', default => sub { 0xC0000000 } );
	has maxdbs    => ( is => 'ro', default => sub { 250 } );
	has run_with_scissors => ( is => 'ro', default => sub { 0 } );

	has indexes   => ( is => 'lazy' );
}

sub _build_indexes {
	my $self= shift;
	# Prevent an infinite loop by making sure the DB object for INFORMATION_SCHEMA is created.
	$self->{_dbs}{INFORMATION_SCHEMA} //= $self->_txn->OpenDB('INFORMATION_SCHEMA');
	my $idx_set= $self->get('INFORMATION_SCHEMA', 'indexes');
	defined $idx_set->{INFORMATION_SCHEMA} or croak "Storage lacks a valid list of indexes";
	$idx_set;
}

sub _save_indexes {
	$_[0]->put('INFORMATION_SCHEMA', 'indexes', $_[0]->indexes);
}

sub BUILD {
	my $self= shift;
	
	# Immediately try to access the DB so that errors get reported
	# as soon as user creates the object
	$self->indexes;
}

sub get_ctor_args {
	my $self= shift;
	return {
		CLASS => ref($self),
		map { $_ => $self->$_ }
		qw( readonly mapsize run_with_scissors )
	}
}

sub DESTROY {
	my $self= shift;
	warn "Destroying LMDB_Storable instance with uncommitted data!"
		if $self->_has_txn && $self->_written;
}

has _env => ( is => 'lazy' );
sub _build__env {
	my $self= shift;
	my $path= $self->path;
	my $initialize;
	if ($self->_storage_dir_empty($path)) {
		$self->create or croak "Storage directory '$path' not initialized  (try create => 'auto')";
		-d $path or make_path($path) or croak "Can't create $path";
		$initialize= 1;
	} elsif (($self->create||0) eq '1') {
		croak "Storage directory '$path' already exists";
	}
	my $env= LMDB::Env->new("$path", {
		mapsize => $self->mapsize,
		maxdbs  => $self->maxdbs,
		flags   =>
			($self->readonly? MDB_RDONLY : 0)
			| ($self->run_with_scissors? MDB_WRITEMAP|MDB_NOMETASYNC : 0)
		}
	);
	$self->_initialize_lmdb($env) if $initialize;
	$env;
}

sub _initialize_lmdb {
	my ($self, $env)= @_;
	my $txn= $env->BeginTxn;
	my $schema= $txn->OpenDB('INFORMATION_SCHEMA', MDB_CREATE);
	$schema->put('indexes', '1'.freeze({ INFORMATION_SCHEMA => { name => 'INFORMATION_SCHEMA' }}));
	undef $schema;
	$txn->commit;
	$self->save_config;
}

has _txn => ( is => 'lazy', clearer => 1, predicate => 1 );
has _written => ( is => 'rw' );
sub _build__txn {
	shift->_env->BeginTxn;
}

has _dbs => ( is => 'rw', default => sub { +{} } );
has _cursors => ( is => 'rw', default => sub { +{} } );

=head1 METADATA METHODS

See descriptions in L<Geo::SpatialDB::Storage>

=head2 create_index

=head2 drop_index

=cut

sub create_index {
	my ($self, $name, %flags)= @_;
	$flags{name}= $name;
	my $flags= $self->_index_flags_to_mdb_flags(\%flags) + MDB_CREATE;
	my $indexes= $self->{indexes}= $self->_build_indexes; # get a fresh copy, for safety
	defined $self->indexes->{$name} and croak "Index $name already exists";
	my $db= $self->_txn->OpenDB($name, $flags);
	$self->_dbs->{$name}= $db;
	$self->_save_indexes;
}

sub drop_index {
	my ($self, $name)= @_;
	my $indexes= $self->{indexes}= $self->_build_indexes; # get a fresh copy, for safety
	defined $indexes->{$name} or croak "Index $name does not exist";
	my $db= delete($self->_dbs->{$name}) // $self->_open_db_with_same_flags($indexes->{$name});
	$db->drop(1);
	delete $indexes->{$name};
	$self->_save_indexes;
}

sub _index_flags_to_mdb_flags {
	my ($self, $flags)= @_;
	return ($flags->{int_key}? MDB_INTEGERKEY : 0)
		+  (!$flags->{multivalue}? 0
			: MDB_DUPSORT + ($flags->{int_value}? MDB_DUPFIXED|MDB_INTEGERDUP : 0)
		   );
}

sub _open_db_with_same_flags {
	my ($self, $name)= @_;
	my $info= ref $name eq 'HASH'? $name : $self->indexes->{$name}; 
	my $flags= $self->_index_flags_to_mdb_flags($info);
	$self->_txn->OpenDB($name, $flags);
}

=head1 METHODS

=head2 get

  my $value= $stor->get( $index_name, $key );

Get the value of a key, or undef if the key doesn't exist.  Dies if the index doesn't exist.

=cut

sub get {
	my ($self, $dbname, $key)= @_;
	my $db= $self->{_dbs}{$dbname} //= $self->_open_db_with_same_flags($dbname);
	my $v= (exists $self->{_written} && exists $self->{_written}{$dbname}{$key})?
		$self->{_written}{$dbname}{$key} : $db->get($key);
	return (!defined $v? $v : substr($v,0,1)? thaw(substr($v,1)) : substr($v,1));
}

=head2 put

  $stor->put( $index_name, $key, $value, %flags );

Store a value in the database.  If the key exists it will overwrite the old value.
If C<$value> is undefined, this deletes the key from the database.  If $index_name does
not exist, it dies.

If C<%flags> include C<< lazy => 1 >> then the write will not take place immediately,
with the idea that the value might change many times before the next L</commit>.

=cut

sub put {
	my ($self, $dbname, $k, $v)= @_;
	my $db= $self->{_dbs}{$dbname} //= $self->_open_db_with_same_flags($dbname);
	$v= ref $v? '1'.freeze($v) : "0".$v if defined $v;
	if (@_ > 4) {
		my %flags= @_[4..$#_];
		# iterating non-existent keys is awkward, so make sure it exists.
		# If not, write the value even though it was lazy.
		if (exists $flags{lazy} && (!defined $v || defined $db->get($k))) {
			$self->{_written}{$dbname}{$k}= $v;
			return;
		}
	}
	delete $self->{_written}{$dbname}{$k};
	if (!defined $v) {
		local $LMDB_File::die_on_err= 0;
		my ($ret, $err);
		{
			local $@;
			$ret= $db->del($k);
			$err= $@;
		}
		croak $err if $ret && $ret != MDB_NOTFOUND;
		return;
	}
	$db->put($k, $v);
}

=head2 commit, rollback

  $stor->commit()
  # - or -
  $stor->rollback()

All 'get' or 'put' operations operate under an implied transaction.
If you want to save your changes, or get a fresh view of the database to
see concurrent changes by other processes, you need to call 'commit' or 'rollback'.

=cut

sub commit {
	my $self= shift;
	if ($self->_has_txn) {
		# Write any lazy-puts that havent been written yet
		if (my $w= $self->_written) {
			for my $dbname (keys %$w) {
				my $db= $self->{_dbs}{$dbname} //= $self->_open_db_with_same_flags($dbname);
				for my $k (keys %{$w->{$dbname}}) {
					my $v= $w->{$dbname}{$k};
					if (!defined $v) {
						local $LMDB_File::die_on_err= 0;
						my ($ret, $err);
						{
							local $@;
							$ret= $db->del($k);
							$err= $@;
						}
						croak $err if $ret && $ret != MDB_NOTFOUND;
					} else {
						$db->put($k, $v);
					}
				}
			}
			$self->_written(undef);
		}
		# Need to forcibly clean up all other handles to this txn, due to LMDB_Storable GC bugs
		%{ $self->_cursors }= ();
		%{ $self->_dbs }= ();
		$self->_txn->commit;
		$self->_clear_txn;
	}
}

sub rollback {
	my $self= shift;
	if ($self->_has_txn) {
		# Need to forcibly clean up all other handles to this txn, due to LMDB_Storable GC bugs
		%{ $self->_cursors }= ();
		%{ $self->_dbs }= ();
		$self->_txn->abort;
		$self->_clear_txn;
	}
	$self->_written(undef);
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
	my ($self, $dbname, $key)= @_;
	my $db= $self->{_dbs}{$dbname} //= $self->_open_db_with_same_flags($dbname);
	my $op= defined $key? MDB_SET_RANGE : MDB_FIRST;
	my $cursor= $db->Cursor;
	$self->_cursors->{$cursor}= $cursor; # this is the official reference
	weaken($cursor); # hold onto a weak ref so we know when it's gone
	weaken($self);
	my $data;
	return sub {
		again:
		local $LMDB_File::die_on_err= 0;
		croak "Iterator refers to a terminated transaction" unless $cursor;
		my $ret= $cursor->get($key, $data, $op);
		$op= MDB_NEXT;
		if ($ret) {
			return if $ret == MDB_NOTFOUND;
			croak $LMDB_File::last_err
		}
		# Check for lazy-writes.
		if (defined $self && $self->{_written} && exists $self->{_written}{$dbname}{$key}) {
			$data= $self->{_written}{$dbname}{$key};
			goto again unless defined $data;
		}
		return $key unless wantarray;
		return ($key, substr($data,0,1)? thaw(substr($data,1)) : substr($data,1));
	}
}

1;
