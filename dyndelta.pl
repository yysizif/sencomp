#!/usr/bin/perl -w

# "dynamic delta coding" evaluation.
#
# S.Arrabi and J.Lach
# Adaptive Lossless Compression in Wireless Body Sensor Networks
# http://dx.doi.org/10.4108/ICST.BODYNETS2009.6017
#
# The algorithm is not well defined in the article,
# and involves data buffering prior to compression
# which does not fit our task.
#
# Actually the idea is "adaptive fixed-length coding" which avoids
# sending prefixes with every sample.  We implement the idea as follows.
#
# Deltas are transferred in words of W bits in complementary code, with
# 1-bit prefix P.  P=0 means a W-bit word follows.  P=1 means a control
# code C in a variable-length code follows.  C is an integer interpreted
# as follows:
#
#   C > 0 -- increase W by C bits
#   C = 0 -- run length of 0-deltas in a variable-length code follows
#
# Thus up-adaptation is handled instantly on demand and its cost is 2
# bit minimum.  The down-adaptation is handled as follows: there is a
# dissolve counter D which is set to Dmax on every change of W and
# decreased by 1 after every emitted codeword.  When D reaches 0, both
# encoder and decoder silently decrease W by 1, and set D=Dmax again.
# Dmax and W0 are the algorithm parameters.

use Carp;
use POSIX;

use lib ".";
use SencompCommon;

my %coding;
$coding{r} = "EW"; # rle (-r)
$coding{c} = "vbinary2x";        # control (-c)

my $origbits;        # bits per input sample for ratio calculation
my $maxout;          # output size limit (bytes)

my $dmax;            # adaptation delay
my $d;               # adaptation delay, running counter
my $w;               # current transfer width


sub usage {
    die "Usage: dyndelta -ORIGBITS -wBITS -dN -cCODING -rCODING -Lmaxout [INFILE ...]\n";
}


sub reinit {
    $dmax = 2;
    $d = $dmax;
    $w = 7;
}


# "folding and interleaving mapping" to get rid of numbers < 0.
sub fimap {
    my ($x) = @_;
    return ($x >= 0? 2*$x: -2*$x-1);
}


sub rle_coding {
    my ($x) = @_;
    return omega0($x) if $coding{r} eq EW;
    return vbinary($coding{r}, $x);
}

sub ctrl_coding {
    my ($x) = @_;
    return omega0($x) if $coding{c} eq EW;
    return vbinary($coding{c}, $x);
}


sub encode {
    my ($u, $run_length) = @_;
    print(defined $u?
          " encode($u, $run_length)":
          " encode(UNDEF, $run_length)");
    my @ret;
    if ($run_length) {
        push @ret, "1";
        push @ret, ctrl_coding(0);
        push @ret, rle_coding($run_length - 1);
    }
    if (defined $u) {
        # u!=0, because u=0 went into run_length.
        # Don't lose the code, extend positive range by 1
        if ($u > 0) {
            $u--;
        }
        my $fu = fimap($u);
        my $binary = binary($fu, $w);
        my $needw = length(binary($fu, 0));
        if ($w >= $needw) {
            push @ret, "0"; # no need for control
            push @ret, $binary;
            #if ($w > $needw) {  # consider decreasing w
            if (1) {  # always decrease w.  Works better...
                if (--$d == 0) {
                    if(--$w == 0) {
                        ++$w;  # undo
                    }
                    print " shift down to $w,";
                    $d = $dmax;
                }
            }
        }
        else {  # need to increase w
            push @ret, "1";
            push @ret, ctrl_coding($needw - $w);
            push @ret, $binary;
            $w = $needw;
            $d = $dmax;
            print " shift up to $w,";
        }
    }
    return @ret;
}


sub parse_args {
    my @files;
    while(local $_ = shift @ARGV) {
        if (s/^-(\d+)//) {
            $origbits = $1;
        }
        elsif (s/^-d(\d+)//) {
            $dmax = $1;
        }
        elsif (s/^-L(\d*)//) {
            $maxout = $1;  # empty OK, meaning "no limit"
        }
        elsif (s/^-([rc])(.*)//) {
            my $what = $1;
            $coding{$what} = $2 || shift(@ARGV);
            vbinary_gen($coding{$what}) if $coding{$what} =~ /^vbinary/;
        }
        elsif (s/^-w(\d+)//) {
            $w = $1;
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
    reinit();
    mainloop($origbits, $maxout, \&encode, \&reinit);
}

sub main1 {
    @ARGV || die;
    print binary(@ARGV), "\n";
    #print join("+", encode (@ARGV)), "\n";
}

main();
exit 0;
