package Geo::SpatialDB::Serializable;
use Moo::Role;
use Scalar::Util;
use Module::Runtime;
use Carp;
use namespace::clean;

# ABSTRACT: Generic implementations for serializing to plain data and back
# VERSION

=head1 DESCRIPTION

Many things in the Geo::SpatialDB hierarchy need serialized.  This role
provides simple generic implementations that should solve most of them.

=head1 METHODS

=head2 coerce

Given a hash of arguments containing a 'CLASS' field, construct that class
while also interpreting it relative to the current package.

=head2 get_ctor_args

For a hashref-based object, take a guess about how to get the constructor
arguments back out of it.

=head2 TO_JSON

For JSON compatibility, use get_ctor_args as the TO_JSON method by default.

=cut

sub coerce {
	my ($class, $thing)= @_;
	# Return instances of this class as-is
	return $thing if Scalar::Util::blessed($thing)
		&& ($thing->isa($class) || $thing->DOES($class));
	# Else if it is a hashref with CLASS member, translate CLASS and construct it
	if (ref $thing eq 'HASH' and $thing->{CLASS}) {
		my %args= %$thing;
		return $class->_load_class(delete $args{CLASS})->new(\%args);
	}
	# Else if class can 'new', just try it
	return $class->new($thing) if $class->can('new');
	Carp::croak("Don't know how to construct $class from ".ref $thing);
}

sub get_ctor_args {
	my ($class, $self)= @_ == 2? @_ : ('Geo::SpatialDB::Serializable', $_[0]);
	my %data= %$self;
	for (keys %data) {
		delete $data{$_}
			if $_ =~ /^[^a-z]/
			or !defined $data{$_}
			or (ref $data{$_} eq 'ARRAY' && !@{ $data{$_} })
			or (ref $data{$_} eq 'HASH' && !keys %{ $data{$_} });
	}
	my $bc;
	# For each field which is also a class having ->get_ctor_args, replace it with the arguments.
	# If the current object has an implied class for that field, (denoted with _${field}_base_class)
	# then run get_ctor_args on that class (to potentially remove the need for the ->{CLASS} field).
	ref $_ && ref($_)->can('get_ctor_args') && ($_= (($bc=$self->can('_'.$_.'_base_class'))? $self->$bc->get_ctor_args($_) : $_->get_ctor_args($_)))
		for values %data;
	$data{CLASS}= _remove_class_prefix($class, ref $self)
		if $class ne ref $self;
	\%data;
}

sub TO_JSON { shift->get_ctor_args }

sub _remove_class_prefix {
	my ($class, $subclass)= @_;
	return substr($subclass, length($class)+2)
		if defined $class && substr($subclass, 0, length($class)+2) eq $class.'::';
	return $subclass;
}

sub _load_class {
	my ($root_class, $name)= @_;
	my $with_prefix= $root_class.'::'.$name;
	return $with_prefix if $with_prefix->can('new');
	return $name if $name->can('new');
	return $with_prefix if eval { Module::Runtime::require_module($with_prefix); 1 };
	return $name if eval { Module::Runtime::require_module($name); 1 };
	Carp::croak("Can't load/find module $name or $with_prefix");
}

#sub STORABLE_freeze {
#	croak ref($_[0])." Should not be seralized directly";
#}

1;
