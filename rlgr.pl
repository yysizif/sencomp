#!/usr/bin/perl -w

# RLGR coder evaluation

use Carp;

use lib ".";
use SencompCommon;

# argv
my $origbits;        # bits per input sample for ratio calculation
my $maxout;          # output block size (bytes)
my $kstart = 2;      # initial rice binary part bits (-k)

# adaptation parameters
my ($U0, $D0, $U1, $D1) = (3, 1, 2, 1);
my $log2L = 2;
my $L = 2 ** $log2L;

# adaptive RLGR parameters.  Start values (0,2) taken from Figure 5...
# ...k=2 is not good, large value (e.g. 15353) won't fit output block (256)
my $kp = 0 * $L;
my $krp = $kstart * $L;

sub k { $kp >> $log2L }
sub kr { $krp >> $log2L }



sub usage {
    die "Usage: rlgr -ORIGBITS -Lmaxout [INFILE ...]\n";
}


sub parse_args {
    my @files;
    while(local $_ = shift @ARGV) {
        if (s/^-(\d+)//) {
            $origbits = $1;
        }
        elsif (s/^-k(\d+)//) {
            $kstart = $1;
            reinit();
        }
        elsif (s/^-L(\d*)//) {
            $maxout = $1;  # empty OK, meaning "endless output buffer"
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



# Reset encoder state when switching to new output block
sub reinit {
    $kp = 0 * $L;
    $krp = $kstart * $L;
}


# "folding and interleaving mapping" to get rid of negative numbers
sub fimap {
    my ($x) = @_;
    defined $x or return $x;
    return ($x >= 0? 2*$x: -2*$x-1);
}


# "Fractional adaptation" for kr according to Table 3.
# Invoked after every call to GR().
sub adapt_kr {
    my ($u) = @_;
    my $p = $u >> kr();
    if($p == 0) {
        $krp -= 2 unless $krp < 2;
    }
    elsif($p > 1) {
        $krp += $p+1;
    }
}

# "Fractional adaptation" for k according to Table 4.
# Invoked by RLGR after every codeword in "no run" mode.
sub adapt_k0 {
    my ($u) = @_;
    if ($u == 0) {
        $kp += $U0;
    }
    else {
        $kp = ($kp > $D0? $kp-$D0: 0);
    }
}

# "Fractional adaptation" for k according to Table 4.
# Invoked by RLGR after every codeword in "run" mode.
sub adapt_k {
    my ($how) = @_;
    if ($how =~ /COMPLETE/) {
        $kp += $U1;
    }
    elsif ($how =~ /PARTIAL/) {
        $kp = ($kp > $D1? $kp-$D1: 0);
    }
    else {
        die "$how:?";
    }
}

# RLGR coder: encode a sequence (0,0,0,0...u)
# where m is the count of zeroes, $u != 0.
#
# *** Problem: cannot encode trailing zeroes in "run mode", will stuff
# *** u=1 as a workaround.
#
# Returns a text bitstring ([01]+).
sub RLGR {
    my ($u, $m) = @_;

    print(defined $u? "RLGR($u, $m)": "RLGR(UNDEF, $m)");
    print(" k=", k(), " kr=", kr());

    my @ret;
    while (k() == 0 && $m--) {
        push @ret, rice(0, kr());
        adapt_kr(0);
        adapt_k0(0);            # can result in k() > 0
    }

    if (k() == 0) { # "no run" mode
        if (defined $u) {
            push @ret, rice($u, kr());
            adapt_kr($u);
            adapt_k0($u);
        }
    }
    else { # "run mode": rle counter in ~rice, then value in rice
        while ($m >= 2**k()) {
            push @ret, "0";
            $m -= 2**k();
            adapt_k(COMPLETE);
        }
        push @ret, ("1", sprintf("%0*b", k(), $m));
        adapt_k(PARTIAL);
        if (defined $u) {
            push @ret, rice($u-1, kr());
            adapt_kr($u-1);
        }
    }

    return @ret;
}


sub main {
    parse_args();
    mainloop($origbits, $maxout, sub {RLGR(fimap($_[0]), $_[1])}, \&reinit);
}

sub main1 {
    @ARGV == 2 || die;
    my ($u, $kr) = @ARGV;
    print rice($u, $kr), "\n";
}

main();
exit 0;
