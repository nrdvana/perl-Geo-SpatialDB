use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });

subtest test_mem_storage => sub {
	if (use_ok 'Geo::SpatialDB::Storage::Memory') {
		my $s= Geo::SpatialDB::Storage::Memory->new();
		test_storage($s);
	}
	done_testing;
};

subtest test_lmdb_storage => sub {
	if (use_ok 'Geo::SpatialDB::Storage::LMDB_Storable') {
		my $s= Geo::SpatialDB::Storage::LMDB_Storable->new(
			path => $tmpdir,
			create => 'auto',
			mapsize => 1024*1024, # because CPAN testers seems to limit memory allocation?
		);
		test_storage($s);
	}
	done_testing;
};

sub test_storage {
	my $store= shift;
	$store->create_index('x');
	$store->put(x => a => 1);
	$store->put(x => c => \3);
	$store->put(x => d => [1, 2, 3, 4]);
	$store->put(x => e => { a => 1, b => 2 });

	is( $store->get(x => 'a'), 1,                         'plain scalar' );
	is( $store->get(x => 'b'), undef,                     'missing key' );
	is_deeply( $store->get(x => 'c'), \3,                 'scalar ref' );
	is_deeply( $store->get(x => 'd'), [1, 2, 3, 4],       'array' );
	is_deeply( $store->get(x => 'e'), { a => 1, b => 2 }, 'hash' );

	my @keys;
	my $i= $store->iterator('x');
	while (my $k= $i->()) {
		push @keys, $k;
	}
	is_deeply( \@keys, ['a', 'c', 'd', 'e'], 'iterate keys' );

	@keys= ();
	$i= $store->iterator('x', 'b');
	while (my $k= $i->()) {
		push @keys, $k;
	}
	is_deeply( \@keys, ['c', 'd', 'e'], 'iterate keys from "b" onward' );

	$store->commit; # test again after committing changes

	@keys= ();
	my @vals;
	$i= $store->iterator('x', 'b');
	while (my ($k,$v)= $i->()) {
		push @keys, $k;
		push @vals, $v;
	}

	is_deeply( \@keys, ['c', 'd', 'e'], 'iterate (k,v) keys from "b" onward' );
	is_deeply( \@vals, [ \3, [1, 2, 3, 4], { a=>1, b=>2 } ], 'iterate (k,v) vals from "b" onward' );

	$store->put('x', 'd', undef);
	is( $store->get('x', 'd'), undef, 'deleted "d"' );

	$store->put('x', 'b', undef);
	is( $store->get('x', 'b'), undef, 'no effect on non-existent key' );

	$store->commit;
}

done_testing;
