#!/usr/bin/perl -w

# Elias Gamma coder evaluation
# RLE added: after "0" follows gamma(rle_count), rle_count >= 1.
#

use Carp;
use POSIX;

use lib ".";
use SencompCommon;

my $origbits;        # bits per input sample for ratio calculation


sub usage {
    die "Usage: egamma -ORIGBITS -Lmaxout [INFILE ...]\n";
}

# "folding and interleaving mapping" to get rid of numbers <= 0
sub fimap {
    my ($x) = @_;
    return ($x >= 0? 2*$x+1: -2*$x);
}

sub is_power2 {
    my ($x) = @_;
    return ($x & ($x-1)) == 0
}

sub encode {
    my ($u, $run_length) = @_;
    my @ret;
    if ($run_length) {
        push @ret, gamma (fimap (0));
        push @ret, gamma($run_length);
    }
    if (defined $u) {
        push @ret, gamma (fimap ($u));
    }
    return @ret;
}


sub parse_args {
    my @files;
    while(local $_ = shift @ARGV) {
        if (s/^-(\d+)//) {
            $origbits = $1;
        }
        elsif (s/^-L(\d*)//) {
            $maxout = $1;  # empty OK, meaning "no limit"
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


sub main {
    parse_args();
    mainloop($origbits, $maxout, \&encode, sub{});
}


sub main1 {
    @ARGV || die;
    my ($u) = @ARGV;
    print gamma ($u), "\n";
    #print join ("+", encode (@ARGV)), "\n";
}

main();
exit 0;
