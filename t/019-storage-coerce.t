use strict;
use warnings;
use Test::More;
use FindBin;
use File::Spec::Functions;
use File::Path 'remove_tree','make_path';

use_ok 'Geo::SpatialDB' or die;

my $tmpdir= catdir($FindBin::RealBin, 'tmp', $FindBin::Script);
remove_tree($tmpdir, { error => \my $ignored });
make_path($tmpdir or die "Can't create $tmpdir");

new_ok( 'Geo::SpatialDB', [ storage => { path => $tmpdir } ], 'constructor with path-only' );

done_testing;
