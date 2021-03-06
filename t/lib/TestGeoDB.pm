package TestGeoDB;
use strict;
use warnings;
use FindBin;
use Exporter;
use File::Spec::Functions;
use Scalar::Util 'reftype';
use File::Path 'remove_tree','make_path';
our @EXPORT_OK= qw( get_fresh_tmpdir tmpdir new_geodb_in_tmpdir new_geodb_in_memory is_within is_nearly );
our %EXPORT_TAGS= ( all => \@EXPORT_OK );

sub import {
	my $caller= caller;
	my $setup;
	@_= map { $_ eq '-setup'? do { ++$setup; () } : ($_) } @_;
	if ($setup) {
		strict->import;
		warnings->import;
		eval 'package '.$caller.'; use Test2::V0; use Try::Tiny; use Log::Any::Adapter "TAP"; use Log::Any q{$log}; 1'
			or die $@;
	}
	goto \&Exporter::import;
}

sub get_fresh_tmpdir {
	my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
	remove_tree($tmpdir, { error => \my $ignored });
	make_path($tmpdir) or die "Can't create $tmpdir";
	return $tmpdir;
}

my $tmpdir;
sub tmpdir { $tmpdir ||= get_fresh_tmpdir(); }

sub new_geodb_in_memory {
	require Geo::SpatialDB;
	Geo::SpatialDB->new(
		storage      => { CLASS => 'Memory' },
		latlon_scale => 1
	);
}

sub new_geodb_in_tmpdir {
	require Geo::SpatialDB;
	Geo::SpatialDB->new(
		storage      => { path => tmpdir() },
		latlon_scale => 1,
	);
}

sub is_within {
	my ($actual, $expected, $tolerance, $msg)= @_;
	if (_is_elem_within('', $actual, $expected, $tolerance)) {
		main::pass($msg);
	} else {
		main::fail($msg);
	}
}

sub is_nearly { is_within($_[0], $_[1], 0.0000000000001, $_[2]); }

sub _is_elem_within {
	my ($elem, $actual, $expected, $tolerance)= @_;
	if (ref $actual && ref $expected && reftype($actual) eq 'ARRAY' && reftype($expected) eq 'ARRAY') {
		if (@$actual == @$expected) {
			my $err= 0;
			for (0 .. $#$actual) {
				_is_elem_within($elem."[$_]", $actual->[$_], $expected->[$_], $tolerance)
					or ++$err;
			}
			return !$err;
		} else {
			main::note(sprintf("element %s: has %d elements instead of %d",
				$elem, scalar @$actual, scalar @$expected));
			return;
		}
	} elsif (!ref $actual && !ref $expected) {
		if (abs($actual - $expected) > $tolerance) {
			main::note( sprintf("element %s: actual %.11e - expected %.5e = %.5e",
				$elem, $actual, $expected, $actual-$expected));
			return;
		} else {
			return 1;
		}
	} else {
		main::note("got ".ref($actual)." but expected ".(ref($expected)//'plain scalar'));
		return;
	}
}

1;
