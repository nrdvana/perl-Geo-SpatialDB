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

Load one or more OpenStreetMap XML files into a temporary database for further
processing.

=head1 USAGE

  import-osm-load-xml [-v|-q] DB_DIR XML_FILE ...

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
) && @ARGV == 1 or pod2usage(2);

my $db_path= shift;
-f catfile($db_path,'config.json') or pod2usage(-message => "DB_DIR must be initialized Storage", -exitval => 1);

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new(tmp_storage => $db_path);
$importer->preprocess;
$importer->tmp_storage->commit;

my $stats= $importer->stats;
printf "processed %d ways and %d relations, rewriting %d nodes and %d ways\n",
	$stats->{preproc_way}, $stats->{preproc_relation},
	$stats->{preproc_rewrite_node}, $stats->{preproc_rewrite_way};
