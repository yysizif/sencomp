#!/usr/bin/perl -w

# post-RLGR coder evaluation

use POSIX;
use Carp;

use lib ".";
use SencompCommon;

use Vbinary::Bitreader;
use gamma;
use gr;

# argv
my $origbits;        # bits per input sample for ratio calculation
my $maxout;          # output block size (bytes); undef=infinity
my $kstart = 4;      # initial rice binary part bits (values)
my $escmin = 3;      # min number of bits addable with ESC
my $esc = -4;        # ESC N means "add ESCMIN+N bits"
my $esc2 = 5;        # ESC2 N means "decode a run of N+1 zeroes"
my $run_mode_ttl = 4;# exit run mode after this many no-run samples
my $decoding_mode;   # encoding by default (-d)

# algorithm state; initialized by sub reinit
my $run_mode;
my ($k, $kstep);     # GR parameter and adaptation step for value encoding

my %coding;
$coding{r} = "EG"; # RLE coding (-r)
$coding{p} = "vbinary2x(1,2,3x)"; # esc kplus (-p)


sub usage {
    die "Usage: e10 -ORIGBITS [-d] [-Lmaxout] [-eESC_CODING] [-kKSTART] [INFILE ...]\n";
}


sub parse_args {
    my @files;
    while(local $_ = shift @ARGV) {
        if (s/^-(\d+)//) {
            $origbits = $1;
        }
        elsif (s/^-d//) {
            $decoding_mode = 1;
        }
        elsif (s/^-e(-?\d+)//) {
            $esc = $1;
        }
        elsif (s/^-E(-?\d+)//) {
            $esc2 = $1;
        }
        elsif (s/^-k(\d+)//) {
            $kstart = $1;
            reinit();
        }
        elsif (s/^-L(\d*)//) {
            $maxout = $1;  # empty OK, meaning "endless output buffer"
        }
        elsif (s/^-([p])(.*)//) {
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


sub k {return floor($k)}


# Reset encoder state when switching to new output block
sub reinit {
    $run_mode = 0;
    ($k, $kstep) = ($kstart, 1);
}


# "folding and interleaving mapping" to get rid of numbers <= 0
# Also, $x == $esc and $x == $esc2 are reserved for escape sequences.
sub fimap {
    my ($x) = @_;
    if (! defined $x) {
        return undef;
    }
    elsif ($x eq ESC) {
        $x = $esc;
    }
    elsif ($x eq ESC2) {
        $x = $esc2;
    }
    else {
        $x++ if ($esc >= 0 && $x >= $esc);
        $x++ if ($esc2 >= 0 && $x >= $esc2);
        $x-- if ($esc < 0 && $x <= $esc);
        $x-- if ($esc2 < 0 && $x <= $esc2);
    }
    return ($x >= 0? 2*$x: -2*$x-1);
}


# inverse of fimap (for decoding_mode)
sub fimap_ {
    my ($fx) = @_;
    use integer;
    my $x = ($fx & 1? ($fx+1)/-2: $fx/2);
#warn $x;
    return ESC if $x == $esc;
    return ESC2 if $x == $esc2;
    $x-- if ($esc >= 0 && $x > $esc);
    $x-- if ($esc2 >= 0 && $x > $esc2);
    $x++ if ($esc < 0 && $x < $esc);
    $x++ if ($esc2 < 0 && $x < $esc2);
    return $x;
}


# coding for ESC value
sub kplus_coding {
    my ($x) = @_;
    return omega0($x) if $coding{p} eq EW;
    return gamma0($x) if $coding{p} eq EG;
    return vbinary($coding{p}, $x);
}


sub rle_coding {
    my ($x) = @_;
    return omega0($x) if $coding{r} eq EW;
    return gamma0($x) if $coding{r} eq EG;
    return vbinary($coding{r}, $x);
}


sub adapt_k {
    my ($fu) = @_;
    $kstep || die;
    if ($fu >= 2**(k()+1) + 2**k()) {
        # need larger k
        # repeated step in the same direction can be larger
        # (... ramp disabled)
        $kstep = ($kstep < 0? 0.75: 1*$kstep);
        $k += $kstep;
    }
    elsif ($fu < 2**k()/2) {
        # can use smaller k.  Go down, no ramp for now
        $kstep = ($kstep > 0? -0.25: 1*$kstep);
        $k += $kstep;
    }
    else {
        # k is optimal, do nothing
    }

    if ($k < 0) {
        $k = 0;
    }
}


# If fu is way too large for current k, send ESC-code to announce k step.
# If not, do nothing; fu will be coded with current k.
sub maybe_esc {
    my ($fu, $k, $kref, $stepref) = @_;
    my $optk = $fu? ceil_log2($fu/2): 0;
    my $kplus = $optk - $k;
    if ($kplus < $escmin) {
        return ();
    }
    my $fimap_esc = fimap(ESC);
    my $bitlength_esc = (ricelen ($fimap_esc, $k)
                         + length (kplus_coding ($kplus - $escmin)));
    my @ret;
    if (ricelen($fu, $k) > $bitlength_esc + ricelen($fu, $optk)) {
        print " esc$kplus";
        push @ret, rice($fimap_esc, $k);
        push @ret, kplus_coding($kplus - $escmin);
        $$kref = $optk;
        $$stepref = 0.75;  # remember the last move was "up"
    }
    return @ret;
}


# reserved numbers:
# 0 = ESC
sub encode {
    my ($u, $run_length) = @_;
    printf "%-16s", sprintf("encode(%s, $run_length)", $u // "UNDEF");
    printf(" k=%g run_mode=$run_mode", $k);
    encode1($u, $run_length);
}

sub encode1 {
    my ($u, $run_length) = @_;
    my @ret;
    if ($run_mode) {
        push @ret, rle_coding($run_length);
        $run_mode = ($run_length? $run_mode_ttl: $run_mode-1);
        $run_length = 0;
    }
    else { # non-run mode
        if ($run_length) {
            # the coder can choose to ESC or not to ESC, decoder will
            # understand either way.
            my $cost1 = $run_length * ricelen(0, k());
            my $fimap_esc2 = fimap("ESC2");
            my $cost2 = (ricelen($fimap_esc2, k())
                         + length(rle_coding($run_length-1))
                         + $run_mode_ttl/2);
            if ($cost1 < $cost2) {
                while ($run_length--) {
                    push @ret, encode1(0,0);
                }
            }
            else {
                # encode run_length with ESC2
                push @ret, rice($fimap_esc2, k());
                push @ret, rle_coding($run_length-1);
                $run_mode = $run_mode_ttl;
                $run_length = 0;
            }
        }
    }

    if (defined $u) {
        my $fu = fimap($u);
        if ($fu >= 2*2**k()) {
            # need larger k for optimum coding
            push @ret, maybe_esc($fu, k(), \$k, \$kstep);
        }
        push @ret, rice($fu, k());
        adapt_k($fu);
    }

    return @ret;
}

my $decount = 0;

sub decode {
    my ($pieces) = @_;
    my $ascii = join "", @$pieces;
    my $br = new Vbinary::Bitreader(pack("B*", $ascii), length($ascii));

warn "lenth(\$ascii)=", length($ascii);
warn "bitcount0=", $br->bitcount();
    vbinary("vbinary2xL1c2c3xR",0);  # generate and require

    my @out;
    my $prev = $br->getbits($origbits);
    #push @out, $prev;  # v0, transferred as is
    print ++$decount,">$prev\n";  # v0, transferred as is

    while ($br->bitcount() > 0) {
warn "bitcount=", $br->bitcount();
        if ($run_mode) {
            my $run_length = gamma::decode($br) - 1;
            $run_mode = ($run_length? $run_mode_ttl: $run_mode-1);
warn "run_mode->$run_mode, run_length=$run_length";
            while ($run_length) {
                #push @out, $prev;
                print ++$decount,">$prev\n";
                $run_length--;
            }
        }
        $prev = decode1($br, $prev);
    }
warn "bitcountN=", $br->bitcount();
#    print map {"$_\n"} @out;
}


# Decode one Golomb-Rice encoded value, observing ESC/ESC2 values.
# Note: run-mode prefix, if any, was handled above in sub decode.
sub decode1 {
    my ($br, $prev) = @_;

    my $fr = gr::decode($br, k());
warn "k=", k();
warn "fr=$fr";
    my $r = fimap_($fr);
warn "fimap_($fr)=$r";
    if ($r eq "ESC") {
        my $kplus = $escmin + vbinary2xL1c2c3xR::decode($br);
warn "kplus=$kplus";
        $k = k() + $kplus;
        $kstep = 0.75;  # remember the last move was "up"
        $prev = decode1($br, $prev);  # handle r w/o run_mode bits
    }
    elsif ($r eq "ESC2") {
        my $run_length = gamma::decode($br);
        $run_mode = $run_mode_ttl;
        while ($run_length--) {
            #push @out, $prev;
            print ++$decount, ">$prev\n";
        }
        $prev = decode1($br, $prev);  # can encounter ESC (though not ESC2)
    }
    else {
warn "r=$r";
        #push @out, $prev += $r;
        print ++$decount, ">", $prev += $r, "\n";
        adapt_k($fr);
    }

    return $prev;
}

sub main {
    parse_args();
    $|=1;
    reinit();
    if ($decoding_mode) {
        decodeloop(\&decode, \&reinit);
    }
    else {
        encodeloop($origbits, $maxout, \&encode, \&reinit);
    }
}

sub main1 {
#    @ARGV == 2 || die;
#    my ($u, $k) = @ARGV;
#    print ricelen($u, $k), "\n";
#    return;
#
#    @ARGV == 1 || die;
#    print ceil_log2($ARGV[0]), "\n";
#    return;

    print " 0 ", fimap (0), "\n";
    for(1..10) {
        print "-$_ ", fimap (-$_), "\n";
        print " $_ ", fimap ($_), "\n";
    }
    return;
}

main();
exit 0;
