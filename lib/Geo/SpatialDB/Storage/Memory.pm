package Geo::SpatialDB::Storage::Memory;
use Moo 2;
use Storable 'freeze', 'thaw';
use Carp;
use namespace::clean;

with 'Geo::SpatialDB::Storage';

# ABSTRACT: Key/value storage in memory, for small datasets or testing
# VERSION

=head1 DESCRIPTION

This storage engine just read and writes to strings in memory.  It still uses Storable in
order to get a deep clone of the data and isolate from unintended writes to shared data.

=cut

sub get_ctor_args { return { indexes => $_[0]->indexes, data => $_[0]->data } }

BEGIN {
	has indexes => ( is => 'rw', default => sub { +{} } );
	has data => ( is => 'rw', default => sub { +{} } );
	has _txn => ( is => 'rw', default => sub { +{} } );
}

=head1 METHODS

=cut

sub create_index {
	my ($self, $name)= @_;
	$self->indexes->{$name} and croak "Index $name already exists";
	$self->indexes->{$name}= { name => $name };
	$self->_txn->{$name}= {};
}

sub drop_index {
	my ($self, $name)= @_;
	$self->indexes->{$name} or croak "No such index $name";
	delete $self->indexes->{$name};
	$self->_txn->{$name}= undef;
}

=head2 get

  my $value= $stor->get( $index_name, $key );

Get the value of a key, or undef if the key doesn't exist.

=cut

sub get {
	my ($self, $index_name, $k)= @_;
	my $v= exists $self->_txn->{$index_name}{$k}? $self->_txn->{$index_name}{$k}
		: $self->data->{$index_name}{$k};
	return ref $v? thaw($$v) : $v;
}

=head2 put

  $stor->put( $index_name, $key, $value );

Store a value in the database.  If the key exists it will overwrite the old value.
If C<$value> is undefined, this deletes the key from the database.

=cut

sub put {
	my ($self, $index_name, $k, $v)= @_;
	$self->_txn->{$index_name}{$k}= ref $v? \freeze($v) : $v;
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
	for my $index_name (keys %{$self->_txn}) {
		my $index= $self->_txn->{$index_name};
		if (!defined $index) {
			delete $self->data->{$index_name};
		} else {
			for my $k (keys %$index) {
				my $v= $index->{$k};
				if (defined $v) {
					$self->data->{$index_name}{$k}= $v;
				} else {
					delete $self->data->{$index_name}{$k};
				}
			}
		}
	}
	%{$self->_txn}= ();
}

sub rollback {
	my $self= shift;
	%{$self->_txn}= ();
}

=head2 iterator

  my $i= $stor->iterator( $index_name );
  # or
  my $i= $stor->iterator( $index_name, $from_key );
  # then...
  while (my $k= $i->()) { ... }
  # or
  while (my ($k, $v)= $i->()) { ... }

Return a coderef which can iterate keys or key,value pairs.
If you specify C<$from_key>, then iteration begins at the first key equal or
greater to it.

=cut

sub iterator {
	my ($self, $index_name, $from_key)= @_;
	$from_key= '' unless defined $from_key;
	my %snapshot;
	my $txn= $self->_txn->{$index_name};
	my $data= $self->data->{$index_name};
	for ($txn? keys %$txn : ()) {
		$snapshot{$_}= $txn->{$_} if defined $txn->{$_} and $_ ge $from_key;
	}
	for ($data? keys %$data : ()) {
		$snapshot{$_}= $data->{$_} if !exists $txn->{$_} and $_ ge $from_key;
	}
	my @keys= sort keys %snapshot;
	return sub {
		my $k= shift @keys;
		return $k unless wantarray;
		return unless defined $k;
		my $v= $snapshot{$k};
		return ($k, ref $v? thaw($$v) : $v);
	}
}

1;
