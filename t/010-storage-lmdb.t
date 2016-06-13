use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';

use_ok 'Geo::SpatialDB::Storage::LMDB_Storable' or die;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });
make_path($tmpdir or die "Can't create $tmpdir");

my $store= Geo::SpatialDB::Storage::LMDB_Storable->new(
	path => $tmpdir
);

$store->put(a => 1);
$store->put(c => \3);
$store->put(d => [1, 2, 3, 4]);
$store->put(e => { a => 1, b => 2 });

is( $store->get('a'), 1,                         'plain scalar' );
is( $store->get('b'), undef,                     'missing key' );
is_deeply( $store->get('c'), \3,                 'scalar ref' );
is_deeply( $store->get('d'), [1, 2, 3, 4],       'array' );
is_deeply( $store->get('e'), { a => 1, b => 2 }, 'hash' );

my @keys;
my $i= $store->iterator;
while (my $k= $i->()) {
	push @keys, $k;
}
is_deeply( \@keys, ['a', 'c', 'd', 'e'], 'iterate keys' );

@keys= ();
$i= $store->iterator('b');
while (my $k= $i->()) {
	push @keys, $k;
}
is_deeply( \@keys, ['c', 'd', 'e'], 'iterate keys from "b" onward' );

$store->commit; # test again after committing changes

@keys= ();
my @vals;
$i= $store->iterator('b');
while (my ($k,$v)= $i->()) {
	push @keys, $k;
	push @vals, $v;
}

is_deeply( \@keys, ['c', 'd', 'e'], 'iterate (k,v) keys from "b" onward' );
is_deeply( \@vals, [ \3, [1, 2, 3, 4], { a=>1, b=>2 } ], 'iterate (k,v) vals from "b" onward' );

$store->put('d', undef);
is( $store->get('d'), undef, 'deleted "d"' );

$store->commit;

done_testing;
