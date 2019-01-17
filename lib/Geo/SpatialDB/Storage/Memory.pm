package Geo::SpatialDB::Storage::Memory;
use Moo 2;
use Storable 'freeze', 'thaw';
use Carp;
use namespace::clean;

extends 'Geo::SpatialDB::Storage';

# ABSTRACT: Key/value storage in memory, for small datasets or testing
# VERSION

=head1 DESCRIPTION

This storage engine just read and writes to strings in memory.  It still uses Storable in
order to get a deep clone of the data and isolate from unintended writes to shared data.

=cut

has data => ( is => 'rw', default => sub { +{} } );
has _txn => ( is => 'rw', default => sub { +{} } );

=head1 METHODS

=head2 get

  my $value= $stor->get( $key );

Get the value of a key, or undef if the key doesn't exist.

=cut

sub get {
	my ($self, $k)= @_;
	my $v= exists $self->_txn->{$k}? $self->_txn->{$k} : $self->data->{$k};
	return defined $v? thaw($v) : undef;
}

=head2 put

  $stor->put( $key, $value );

Store a value in the database.  If the key exists it will overwrite the old value.
If C<$value> is undefined, this deletes the key from the database.

=cut

sub put {
	my ($self, $k, $v)= @_;
	$self->_txn->{$k}= defined $v? freeze($v) : undef;
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
	for my $k (keys %{$self->_txn}) {
		my $v= $self->_txn->{$k};
		if (defined $v) {
			$self->data->{$k}= $v;
		} else {
			delete $self->data->{$k};
		}
		%{$self->_txn}= ();
	}
}

sub rollback {
	my $self= shift;
	%{$self->_txn}= ();
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
	my ($self, $from_key)= @_;
	$from_key= '' unless defined $from_key;
	my %snapshot;
	my $txn= $self->_txn;
	for (keys %$txn) {
		$snapshot{$_}= $txn->{$_} if defined $txn->{$_} and $_ ge $from_key;
	}
	for (keys %{$self->data}) {
		$snapshot{$_}= $self->data->{$_} if !exists $txn->{$_} and $_ ge $from_key;
	}
	my @keys= sort keys %snapshot;
	return sub {
		my $k= shift @keys;
		return $k unless wantarray;
		return ($k, thaw($snapshot{$k}));
	}
}

1;
