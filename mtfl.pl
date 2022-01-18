#!/usr/bin/perl -w

# "Move-To-Front limited" is a modification to "bookstack compression"
# which avoids too high bookstack.  Excessive books are removed from
# the bookstack and handled as new if needed again.
#
# Also implements multiple bookstacks.

use Carp;
use POSIX;

use lib ".";
use SencompCommon;

my %coding;
$coding{r} = "EW"; # rle (-r)
$coding{p} = "vbinary2x1x";        # prefix (-p)
$coding{n} = "vbinary3x1x";        # newprefix (-n)

my $sign_in_prefix = 0;  # 0=encode sign in binary part using fimap()
my $origbits;        # bits per input sample for ratio calculation
my $maxout;          # output size limit (bytes)

# used by sub mtf
my $mid = unpack "C","P";  # 'P' is in the middle of printable ASCII region
my %list;
my $lastkey;
my $bubble = 1;                 # 0 = move-to-front at once
my $hash;                       # hashbin = $lastkey % $hash (-h)
my $stacklim = 5;               # stack height limit (-l)
my $insertat = $stacklim-1;     # insert new values at ... (-i)
                                # $insertat >= $stacklim is equivalent
                                # to not inserting at all

sub usage {
    confess "Usage: mtfl -ORIGBITS -rRLE_CODING -pPREFIX_CODING -nNEWPREFIX_CODING -lSTACKLIM -iINSERTAT -Lmaxout -bBUBBLE [INFILE ...]\n";
}


# Reset encoder state when switching to new output block
sub reinit {
    %list = ();
    $lastkey = undef;
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
    return gamma0($x) if $coding{r} eq EG;
    return vbinary($coding{r}, $x);
}

sub prefix_coding {
    my ($x) = @_;
    return omega0($x) if $coding{p} eq EW;
    return gamma0($x) if $coding{p} eq EG;
    return vbinary($coding{p}, $x);
}

sub newprefix_coding {
    my ($x) = @_;
    return omega0($x) if $coding{n} eq EW;
    return gamma0($x) if $coding{n} eq EG;
    return vbinary($coding{n}, $x);
}


# Encode 'p' using mtf transform.
#
# If 'p' is present in the stack, output its index+1 in PREFIX_CODING
# (vbinary2x3) and move (or bubble) 'p' to the front.
#
# Otherwise, output <stack height> in PREFIX_CODING, followed by 'p'
# in NEWPREFIX_CODING
sub mtf {
    my ($p) = @_;
    print " mtf($p)";
    my $key = pack "C", $mid + $p;  # = book number
    my $hashbin = (defined $hash && defined $lastkey?
                   (unpack "C", $lastkey) % $hash:
                   $lastkey);
    my $i = do {
        if (defined $hashbin) {
            $list{$hashbin} //= "";
            index $list{$hashbin}, $key;
        }
        else {
            -1;
        }
    };
    print(defined $lastkey?
          " $hashbin->$key@<$list{$hashbin}>=$i":
          " $key@<>=$i");
    if ($i >= 0) {  # found in the stack
        if ($i > 0) {  # not in 1st position, bubble towards 1st
            for my $list ($list{$hashbin}) {
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
        }
        $lastkey = $key;
        return prefix_coding($i+1);  # +1 as 0 is reserved for "newprefix"
    }
    elsif($insertat >= $stacklim) {
        # bookstacks disabled
        return (newprefix_coding($sign_in_prefix? fimap($p): $p));
    }
    else { # i < 0 = $p not found in the stack
        # insert new key at insertion point
        # if length limit is reached, drop the last key
        do { for my $list ($list{$hashbin}) {
            my $h = substr($list, 0, $insertat);
            my $t = (length($list) == $stacklim? substr($list, $insertat, -1):
                     length($list) > $insertat? substr($list, $insertat):
                     "");
            $list = "$h$key$t";
        }} if defined $lastkey;  # transaction undefined in the 1st call
        $lastkey = $key;
        return (prefix_coding(0),
                newprefix_coding($sign_in_prefix? fimap($p): $p));
    }
}


sub encode {
    my ($u, $run_length) = @_;
    print(defined $u?
          " encode($u, $run_length)":
          " encode(UNDEF, $run_length)");
    my @ret;
    if ($run_length) {
        push @ret, mtf(0);
        push @ret, rle_coding($run_length-1);
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
        elsif (s/^-h(\d*)//) {
            $hash = $1;
        }
        elsif (s/^-i(\d+)//) {
            $insertat = $1;
        }
        elsif (s/^-L(\d*)//) {
            $maxout = $1;  # empty OK, meaning "no limit"
        }
        elsif (s/^-l(\d+)//) {
            $stacklim = $1;
        }
        elsif (s/^-([rnp])(.*)//) {
            my $what = $1;
            $coding{$what} = $2 || shift(@ARGV);
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
    #print rle_coding(@ARGV), "\n";
    print vbinary(@ARGV), "\n";
    #print join ("+", encode (@ARGV)), "\n";
}

main();
exit 0;
