#!/usr/bin/perl

# Hysteretic noise filter
# The values are at the end of input data lines.

sub usage {
    die "Usage: noisered <threshold>, e.g. noisered 0.5\n";
}

sub infer_precision {
    my ($x) = @_;
    if ($x =~ /\.(\d+)/) {
        return length($1);
    }
    else {
        return 0;
    }
}

sub median {
    my (@a) = @_;
    if (@a & 1) {
        return (sort @a)[@a/2+1];
    }
    else {
        @a = sort @a;
        return ($a[@a/2] + $a[@a/2+1])/2;
    }
}


my $thre = shift(@ARGV) || usage();
my $prec;
my $prev;
while(<>) {
    /^OK/ && last;
    /(\d[\d.]*)$/ || die;
    my $val = $1;
    $prev //= $val;
    $prec //= infer_precision($val);
    if (abs($val - $prev) < $thre) {
        $val = $prev;
    }
    else {
        $prev = $val;
    }
    s/(\S+)$/sprintf "%.*f", $prec, $val/e;
    print;
}

exit 0;
