#!/usr/bin/perl -w

# FELACS coding evaluation.  Note: unlike other compressors, this
# takes the stream of original values, not pre-computed deltas
# because Rice Mapper depends on original values.

use Carp;
use POSIX;

use lib ".";
use SencompCommon;

my $origbits;        # bits per input sample for ratio calculation
my $blocksz = 16;


sub usage {
    confess "Usage: felacs -ORIGBITS -bBLOCKSIZE [INFILE ...]\n";
}


sub parse_args {
    my @files;
    while(local $_ = shift @ARGV) {
        if (s/^-(\d+)//) {
            $origbits = $1;
        }
        elsif (s/^-b(\d*)//) {
            $blocksz = $1 || shift @ARGV || usage();
        }
        elsif (/^-/) {
            usage ();
        }
        elsif (-f $_) {
            push @files, $_;
            $_ = "";
        }
        else {
            usage ();
        }
        unshift @ARGV, "-$_" if $_ ne "";
    }
    defined $origbits or usage();
    unshift @ARGV, @files;
}


# "folding and interleaving mapping" to get rid of numbers < 0
# FELACS is using the clever "theta" trick from
# "Algorithms for a very high speed universal noiseless coding module"
# RF Rice, PS Yeh, W Miller - 1991
sub fimap {
    my ($x, $prev) = @_;
    if ($prev < 0) {
        $prev &= 2**$origbits-1;
    }
    my $theta = min($prev, 2**$origbits - 1 - $prev);
    if (0 <= $x && $x <= $theta) {
        return 2*$x;
    }
    elsif (-$theta <= $x && $x < 0) {
        return 2*abs($x) - 1;
    }
    else {
        return $theta + abs($x);
    }
}


sub felacs_estimation {
    local (*deltas) = @_;
    my $D = 0;
    for (@deltas) {
        $D += $_;
    }
    my $J = $blocksz;
    my $p;
    for ($p = 0; ($J<<$p) <= $D; $p++) {
        # empty
    }
    return ($p <= 7? $p: 7);
}


sub encode {
    local (*block) = @_;
    my $prev = 0;
    my $ref = fimap($block[0], 0);
    my @deltas;
    for (my $i = 1; $i < @block; $i++) {
        push @deltas, fimap($block[$i] - $block[$i-1], $block[$i-1]);
    }
    my $k = felacs_estimation(\@deltas);
    my @res;
    push @res, sprintf "%03b", $k;  # "ID bit pattern"
    push @res, sprintf "%0*b", $origbits, $ref;  # "reference value"
    for (@deltas) {
        push @res, rice($_, $k);
    }
    return @res;
}


sub output {
    local (*block, *codewords) = @_;
    for (@block) {
        print " $_:";
    }
    for (@codewords) {
        print " $_";
        $compressed += length($_);
    }
    print "\n";
}


sub main {
    parse_args();
    local $compressed = 0;  # output size counter (bits)
    my $uncompressed = 0;
    my @block;
    my $scale;
    while(<>) {
        chomp;
        /^OK/ && last;
        my $v = (split)[-1];
        $scale //= infer_scale($v);
        push @block, floor($v*$scale + 0.5);
        $uncompressed += $origbits;
        next if (@block < $blocksz);
        output(\@block, [encode(\@block)]);
        @block = ();
    }
    if (@block) {
        output (\@block, [encode (\@block)]);
        @block = ();
    }

    $compressed += $origbits; # account for the first value transmitted "as is"
    my $ratio = $uncompressed / $compressed;
    printf("insamples %u origbits %u inbits %u compressed %u ratio %.*f\n",
           $uncompressed/$origbits, $origbits, $uncompressed, $compressed,
           ($ratio < 1? 3:2), $ratio);
}


sub main1 {
    @ARGV || die;
    print expbinary (@ARGV), "\n";
    #print join ("+", encode (@ARGV)), "\n";
}

main();
exit 0;
