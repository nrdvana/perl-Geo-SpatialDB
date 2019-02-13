use FindBin;
use lib "$FindBin::Bin/lib";
use TestGeoDB -setup => ':all';
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';
use Geo::SpatialDB::Storage::Memory;
use Geo::SpatialDB::Storage::LMDB_Storable;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });

subtest test_mem_storage => sub {
	my $s= Geo::SpatialDB::Storage::Memory->new();
	test_storage($s);
	done_testing;
};

subtest test_lmdb_storage => sub {
	my $s= Geo::SpatialDB::Storage::LMDB_Storable->new(
		path => $tmpdir,
		create => 'auto',
		mapsize => 1024*1024, # because CPAN testers seems to limit memory allocation?
	);
	test_storage($s);
	done_testing;
};

sub test_storage {
	my $store= shift;
	$store->create_index('x');
	$store->put(x => a => 1);
	$store->put(x => c => \3);
	$store->put(x => d => [1, 2, 3, 4]);
	$store->put(x => e => { a => 1, b => 2 });
	$store->put(x => f => { a => 1, b => 2 }, lazy => 1);

	is( $store->get(x => 'a'), 1,                         'plain scalar' );
	is( $store->get(x => 'b'), undef,                     'missing key' );
	is( $store->get(x => 'c'), \3,                 'scalar ref' );
	is( $store->get(x => 'd'), [1, 2, 3, 4],       'array' );
	is( $store->get(x => 'e'), { a => 1, b => 2 }, 'hash' );
	is( $store->get(x => 'f'), { a => 1, b => 2 }, 'lazy put' );

	my @keys;
	my $i= $store->iterator('x');
	while (my $k= $i->()) {
		push @keys, $k;
	}
	is( \@keys, ['a', 'c', 'd', 'e', 'f'], 'iterate keys' );

	@keys= ();
	$i= $store->iterator('x', 'b');
	while (my $k= $i->()) {
		push @keys, $k;
	}
	is( \@keys, ['c', 'd', 'e', 'f'], 'iterate keys from "b" onward' );

	$store->commit; # test again after committing changes

	@keys= ();
	my @vals;
	$i= $store->iterator('x', 'b');
	while (my ($k,$v)= $i->()) {
		push @keys, $k;
		push @vals, $v;
	}

	is( \@keys, ['c', 'd', 'e', 'f'], 'iterate (k,v) keys from "b" onward' );
	is( \@vals, [ \3, [1, 2, 3, 4], { a=>1, b=>2 }, { a=>1, b=>2 } ],
		'iterate (k,v) vals from "b" onward' );

	$store->put('x', 'd', undef);
	is( $store->get('x', 'd'), undef, 'delete "d"' );
	
	$store->put('x', 'c', undef, lazy => 1);
	is( $store->get('x', 'c'), undef, 'lazy delete "c"' );
	
	$store->put('x', 'e', 42, lazy => 1);
	is( $store->get('x', 'e'), 42, 'lazy overwrite "e"' );

	$store->put('x', 'e', 43, lazy => 1);
	is( $store->get('x', 'e'), 43, 'lazy overwrite lazy "e"' );

	$store->put('x', 'e', undef, lazy => 1);
	is( $store->get('x', 'e'), undef, 'lazy delete lazy "e"' );

	$store->put('x', 'e', 42, lazy => 1);
	is( $store->get('x', 'e'), 42, 'lazy overwrite lazy deleted "e"' );

	$store->put('x', 'b', undef);
	is( $store->get('x', 'b'), undef, 'no effect on non-existent key' );

	@keys= ();
	@vals= ();
	$i= $store->iterator('x', 'b');
	while (my ($k,$v)= $i->()) {
		push @keys, $k;
		push @vals, $v;
	}
	is( \@keys, ['e', 'f'], 'iterate (k,v) keys from "b" onward' );
	is( \@vals, [ 42, { a=>1, b=>2 } ],
		'iterate (k,v) vals from "b" onward' );

	$store->commit;
}

done_testing;
