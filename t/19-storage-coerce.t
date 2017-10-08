use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';

use_ok 'Geo::SpatialDB::Storage' or die;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });

my $stor= Geo::SpatialDB::Storage->coerce({ path => $tmpdir, mapsize => 1024*1024, create => 'auto' });
isa_ok( $stor, 'Geo::SpatialDB::Storage::LMDB_Storable', 'created default LMDB_File' );
is( $stor->mapsize, 1024*1024, 'mapsize set as expected' );

undef $stor;

$stor= Geo::SpatialDB::Storage->coerce($tmpdir);
isa_ok( $stor, 'Geo::SpatialDB::Storage::LMDB_Storable', 're-created LMDB_File' );
is( $stor->mapsize, 1024*1024, 'mapsize preserved' );

undef $stor;

done_testing;
