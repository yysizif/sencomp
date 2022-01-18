#!/usr/bin/perl

sub usage {
    die "Usage: $0 [FILE.csv]\n";
}

my $prev;

while(<>) {
    next if $_ eq $prev;  # they have lots of duplicates
    $prev = $_;
    s/.*,//;
    printf "0 %.2f\n", $_;
}

exit 0;
