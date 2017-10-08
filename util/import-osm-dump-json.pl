#! /usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions;
use Log::Any '$log';
use Log::Any::Adapter 'Daemontools';
use FindBin;
use lib catdir($FindBin::Bin, '..', 'lib');
use Geo::SpatialDB::Import::OpenStreetMap;

=head1 DESCRIPTION

Dump the Nodes, Ways, and Relations as they appear in the temporary import
Storage database.  Output is a single JSON object, but with one entity per
line for ease of viewing and processing.

=head1 USAGE

  import-osm-dump-json [-v|-q] DB_DIR

=head1 OPTIONS

=over

=item -v, --verbose

Show more logging

=item -q, --quiet

Show less logging

=back

=cut

sub pod2usage { require Pod::Usage; goto &Pod::Usage::pod2usage; }
use Getopt::Long;
GetOptions(
   'verbose|quiet|v|q'  => sub { }, # already handled by Log::Any::Adapter::Daemontools
   'help'               => sub { pod2usage(1) },
   'man'                => sub { pod2usage(-exitval => 1, -verbose => 2) },
) && @ARGV > 0 or pod2usage(2);

my $db_path= shift;
!-e $db_path or -f catfile($db_path,'config.json') or pod2usage(-message => "DB_DIR must be initialized Storage, or must not exist", -exitval => 1);

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new(tmp_storage => $db_path);
$importer->dump_json;
