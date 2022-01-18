#!/usr/bin/perl -w

# "Move-To-Front" prefix encoding

use Carp;
use POSIX;

use lib ".";
use SencompCommon;

my %coding;
$coding{r} = "EW"; # rle (-r)
$coding{p} = "vbinary3x2x";        # prefix (-p)
$coding{n} = "vbinary4x";        # newprefix (-n)

my $sign_in_prefix = 0;  # 0=encode sign in binary part using fimap()
my $origbits;        # bits per input sample for ratio calculation
my $maxout;          # output block size (bytes)

# used by sub mtf
my $mid = unpack "C","P";  # 'P' is in the middle of printable ASCII region
my $list = "";
my $bubble = 0;                 # 0 = move-to-front at once


sub usage {
    die "Usage: mtf -ORIGBITS -rRLE_CODING -pPREFIX_CODING -nNEWPREFIX_CODING -Lmaxout [INFILE ...]\n";
}


# Reset encoder state when switching to new output block
sub reinit {
    $list = "";
}


# "folding and interleaving mapping" to get rid of numbers < 0.
# Used with newprefix_coding and with expbinary.
sub fimap {
    my ($x) = @_;
    return ($x >= 0? 2*$x: -2*$x-1);
}

sub rle_coding {
    my ($x) = @_;
    return omega0($x) if $coding{r} eq EW;
    return vbinary($coding{r}, $x);
}

sub prefix_coding {
    my ($x) = @_;
    return omega0($x) if $coding{p} eq EW;
    return vbinary($coding{p}, $x);
}

sub newprefix_coding {
    my ($x) = @_;
    return omega0($x) if $coding{n} eq EW;
    return vbinary($coding{n}, $x);
}


# Encode 'u' using mtf transform.
#
# If 'u' is present in the stack, output its index+1 in PREFIX_CODING
# and move 'u' to the front.
#
# Otherwise, output <stack height> in PREFIX_CODING, followed by 'u'
# in NEWPREFIX_CODING.
sub mtf {
    my ($p) = @_;
    print " mtf($p)";
    my $key = pack "C", $mid + $p;  # = book number
    my $i = index $list, $key;
    print " $key@<$list>=$i";
    if ($i >= 0) {  # found in the stack
        if ($i > 0) {  # not in 1st position, move to 1st
            if ($bubble) {
                $list = (substr($list, 0, $i-1) .
                         substr($list, $i, 1) .
                         substr($list, $i-1, 1) .
                         substr($list, $i+1));
            }
            else {          # move-to-front
                $list = ($key .
                         substr($list, 0, $i) .
                         substr($list, $i+1));
            }
        }
        return prefix_coding($i);
    }
    else { # i < 0 = $p not found in the stack
        # insert new key at the head
        $list = "$key$list";
        # insert new key at the end
        #list = "$list$key";
        return (prefix_coding (length ($list)-1),
                newprefix_coding($sign_in_prefix? fimap($p): $p));
    }
}


sub encode {
    my ($u, $run_length) = @_;
    print " encode($u, $run_length)" if defined $u;
    print " encode(UNDEF, $run_length)" if !defined $u;
    my @ret;
    if ($run_length) {
        push @ret, mtf(0);
        push @ret, rle_coding($run_length-1); # do not waste 0
    }
    if (defined $u) {
        $u != 0 or die;
        # length(expbinary(1)) == 0, conflicts with RLE.  So +1
        if ($sign_in_prefix) {
            my $expbinary = expbinary(abs($u)+1);
            my $sign = ($u < 0? -1: 1);
            push @ret, mtf($sign * length($expbinary));
            push @ret, $expbinary;
        }
        else { # remove the sign using fimap()
            my $expbinary = expbinary(fimap($u)+1);
            push @ret, mtf(length($expbinary));
            push @ret, $expbinary;
        }
    }
    return @ret;
}


sub output {
    my ($v, @codewords) = @_;
    my $lensum = lensum(@codewords);
    if ($maxout && $compressed + $lensum > $maxout*8) {
        print " maxout reached\n";
        die "maxout";  # caught in main
    }
    $compressed += $lensum;
    print " $v:";
    for (@codewords) {
        print " $_";
    }
    print "\n";
}

sub parse_args {
    my @files;
    while(local $_ = shift @ARGV) {
        if (s/^-(\d+)//) {
            $origbits = $1;
        }
        elsif (s/^-a//) {
            $sign_in_prefix = 1;
        }
        elsif (s/^-b(\d)//) {
            $bubble = $1;
        }
        elsif (s/^-L(\d*)//) {
            $maxout = $1;  # empty OK, meaning "no limit"
        }
        elsif (s/^-([rnp])(.*)//) {
            my $what = $1;
            $coding{$what} = $2 || shift(@ARGV);
            vbinary_gen($coding{$what}) if $coding{$what} =~ /^vbinary/;
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
    mainloop($origbits, $maxout, \&encode, \&reinit);
}

sub main1 {
    @ARGV || die;
    #print expbinary (@ARGV), "\n";
    print rle_coding(@ARGV), "\n";
    #print join ("+", encode (@ARGV)), "\n";
}

main();
exit 0;
