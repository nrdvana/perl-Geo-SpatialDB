package LMDB_File::Filtered;
use strict;
use warnings;
use parent 'LMDB_File';

sub Filter_Value_Push {
	my ($self, %args)= @_;
	
	push @{ $self->[10]{_fetch_value_filters} }, $args{Fetch}
		if $args{Fetch};
	push @{ $self->[10]{_store_value_filters} }, $args{Store}
		if $args{Store};
}

sub TIEHASH {
	my $pkg= shift;
	my $ret= $pkg->SUPER::TIEHASH(@_);
	bless $ret, $pkg;
}

sub FETCH {
	my ($self, $k)= @_;
	my $v= $self->SUPER::FETCH($k);
	for my $filter (@{ $self->[10]{_fetch_value_filters} // [] }) {
		$filter->() for ( $v );
	}
	$v;
}

sub STORE {
	my ($self, $k, $v)= @_;
	for my $filter (@{ $self->[10]{_store_value_filters} // [] }) {
		$filter->() for ( $v );
	}
	$self->SUPER::STORE($k, $v);
}

1;
