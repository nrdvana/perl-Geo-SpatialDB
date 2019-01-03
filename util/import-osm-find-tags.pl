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

Search and aggregate the tags (and optionally tag values) found on all
entities in the temporary import Storage database.

=head1 USAGE

  import-osm-find-tags [-v|-q] DB_DIR [--filter TAG=REGEX ...] [--values]

=head1 OPTIONS

=over

=item -f --filter TAG=REGEX

Only aggregate tags for entities who have a TAG matching the REGEX

=item --values

Also aggregate the values of each tag.  (this can make some very large output)

=item -v, --verbose

Show more logging

=item -q, --quiet

Show less logging

=back

=cut

sub pod2usage { require Pod::Usage; goto &Pod::Usage::pod2usage; }
use Getopt::Long;
GetOptions(
	'filter|f=s'         => \my @opt_filter,
	'values'             => \my $opt_values,
	'verbose|quiet|v|q'  => sub { }, # already handled by Log::Any::Adapter::Daemontools
	'help'               => sub { pod2usage(1) },
	'man'                => sub { pod2usage(-exitval => 1, -verbose => 2) },
) && @ARGV == 1 or pod2usage(2);

my %filter;
for (@opt_filter) {
	$_ =~ /^([^=]+)(=(.*))?$/ or pod2usage(-message => "Invalid filter pattern: $_");
	$filter{$1}= defined $3? qr/$3/ : qr/./;
}

my $db_path= shift;
-f catfile($db_path,'config.json')
	or pod2usage(-message => "DB_DIR must be initialized Storage");

my $importer= Geo::SpatialDB::Import::OpenStreetMap->new(tmp_storage => $db_path);
my $tags= $importer->aggregate_tags(
	values => $opt_values,
	filter => \%filter,
);
use JSON;
print JSON->new->canonical->pretty->encode($tags);
