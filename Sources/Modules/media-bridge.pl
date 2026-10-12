#!/usr/bin/perl
# Atoll does this too: /usr/bin/perl is allowed to talk to mediaremoted.
# This process loads MediaBridge.dylib and stays alive while the dylib
# prints one JSON object per line on stdout.
use strict;
use DynaLoader;

my $lib = $ARGV[0] or die "missing dylib path\n";
my $handle = DynaLoader::dl_load_file($lib, 1);
die DynaLoader::dl_error() . "\n" unless $handle;
sleep 86400 while 1;
