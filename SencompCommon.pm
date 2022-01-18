# SencompCommon: miscellaneous stuff used by more than one compressor

package SencompCommon;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(infer_scale min lensum ceil_log2
                 spec_to_identifier vbinary_gen
                 vbinary gamma0 omega0 gamma omega
                 expbinary binary rice ricelen
                 encodeloop decodeloop mainloop);

use Carp;
use POSIX;
use Vbinary::Bitwriter;


sub infer_scale {
    my ($v) = @_;
    if ($v =~ /\.(\d+)/) {
        return 10**length($1);
    }
    else {
        return 1;
    }
}

sub min {
    my ($a, $b) = @_;
    return $a < $b? $a: $b;
}


sub lensum {
    my (@codewords) = @_;
    my $sum = 0;
    for (@codewords) {
        $sum += length($_);
    }
    return $sum;
}

sub log2 {log($_[0])/log(2)}

sub ceil_log2 {
    my ($x) = @_;
    $x or confess "cannot take log(0)";
    return ceil(log($x)/log(2));
}


# Convert vbinary specification from "readable flavor" to "identifier
# flavor".  Do nothing if the specification is of identifier flavor
# already.
sub spec_to_identifier {
    local ($_) = @_;
    tr[(,)/][LcRs];
    return $_;
}


sub vbinary_gen {
    my ($spec) = @_;
    my $name = spec_to_identifier($spec);
    #if(-f "$name.pm") {
    #    return; # already done
    #}
    my $cmd = "./vbinary-gen-perl.pl $name";
    `$cmd`; $? == 0 or die "$cmd: exit code $?";
}


sub vbinary {
    my ($spec, $x) = @_;
    $x >= 0 or confess $x;
    my $vbinary = spec_to_identifier($spec);
    if (! eval {require "$vbinary.pm"}) {
        vbinary_gen($vbinary);
        require "$vbinary.pm";
    }
    my $w = new Vbinary::Bitwriter();
    &{"${vbinary}::encode"}($w, $x);
    my $buf = $w->flush();
    my $nbits = $w->bitcount();
    return unpack("B$nbits", $buf);
}


# Elias encoders shifted by one to accept n=0,
# to be interchangeable with vbinary
sub omega0 { omega((shift)+1) }
sub gamma0 { gamma((shift)+1) }


# gamma coder: encodes u \in {1,2,...}
# Returns a text bitstring ([01]+).
sub gamma {
    my ($u) = @_;
    $u >= 1 or Carp::confess "u=$u must be > 0";
    my $eb = expbinary($u);
    my $leb = length($eb);
    return ("0"x$leb) . "1" . $eb;
}


# Elias omega coder: encodes u \in {1,2,...}
# Returns a text bitstring ([01]+).
sub omega {
    my ($n) = @_;
    $n >= 1 or die $n;
    my $ret = "0";
    while ($n != 1) {
        my $prepend = sprintf("%b", $n);
        $ret = "$prepend$ret";
        $n = length($prepend) - 1;
    }
    return $ret;
}


# "exponential binary" coder: encodes u \in {1,2,...}
# Returns a text bitstring ("[01]*").
sub expbinary {
    my ($u) = @_;
    $u > 0 or die $u;
    #my $lb = floor(log2($u));
    #return sprintf ("%0*b", $lb, $u - 2**$lb);
    my $bin = sprintf ("%b", $u);
    $bin =~ s/^1//;
    return $bin;
}


# Return a text binary "[01]+" representation of u in {0,1,...},
# not smaller than w bits.
sub binary {
    my ($u, $w) = @_;
    return sprintf ("%0*b", $w, $u);
}



# Golomb-Rice coder: encodes u \in {0,1,...}
# with Rice parameter k \in {0,1,...}.
# Returns a text bitstring ([01]+).
sub rice {
    my ($u, $k) = @_;
    $u // confess("rice(undef, $k) called");
    use vars qw($::hush);  # used by esc2coding.pl, for one
    print " rice($u,$k) " unless $::hush;
    if($k == 0) {
        my $q = $u;
        return ("1"x$q) . "0";
    }
    elsif($k > 0) {
        my $q = $u >> $k;
        my $r = $u & ~(-1<<$k);
        return ("1"x$q) . "0" . sprintf ("%0*b", $k, $r);
    }
    else {
        Carp::confess "k=$k must be >= 0";
    }
}

# Return bit length of rice code
sub ricelen {
    my ($u, $k) = @_;
    confess "k=$k too large" if ! (1<<$k);
    use integer;
    return $u/(1<<$k) + 1 + $k;
}


my $blockstart = 0;    # static for sub output

sub output {
    my ($v, @codewords) = @_;
    my $lensum = lensum(@codewords);
    if ($maxout && ($compressed - $blockstart) + $lensum > $maxout*8) {
        print " maxout reached\n";
        $blockstart = $compressed;
        return undef;
    }
    print " $v:";
    for (@codewords) {
        print " $_";
    }
    print "\n";
    return $lensum;
}


sub decodeloop {
    local (*decode, *reinit) = @_;
    my @a;
    while(<>) {
        chomp;
        if (/maxout reached/) {
            decode(\@a);
            @a = ();
            reinit();
        }
        else { # accumulate ascii-bin from encoder output
            if (s/.*://) { # skip the summary line that does not contain ':'
                s/\s//g;
                push @a, $_;
            }
        }
    }
    decode(\@a);
}


# provide bit pattern for the 1st value encoded "as is", making sure
# negative values do not exceed $origbits
sub format_1stvalue {
    my ($v) = @_;
    return sprintf("%0*b", $origbits, $v & ~(-1<<$origbits));
}

sub encodeloop { &mainloop };  # alias

# should be called encodeloop
sub mainloop {
    local ($origbits, $maxout, *encode, *encoder_reinit) = @_;
    local $compressed = 0;    # output size counter (bits), used by sub output
    my $uncompressed = 0;     # input size counter (bits)
    my $run_length = 0;
    my $prev;

    while(<>) {
        chomp;
        /^OK/ && last;
        my $v = (split)[-1];
        $scale //= infer_scale($v);
        $v = floor($v*$scale + 0.5);
        $uncompressed += $origbits;

#        print "$.>$v ";

        if (! defined $prev) {
            # first value transmitted "as is"
            output ($v, format_1stvalue($v));
            $compressed += $origbits;
            $prev = $v;
            next;
        }

        my $r = $v - $prev;
        if ($r == 0) {
            $run_length++;
            next;
        }
        my $size = output ($r, encode ($r, $run_length));
        if ($size) {
            $compressed += $size;
        }
        else {
            # switch to new block
            encoder_reinit();
            if (! $run_length) {
                # $v will be the 1st value in the block
                $compressed += output ($v, format_1stvalue($v)) // die;
            }
            else {
                # $prev will be the 1st value in the block,
                # then go the rest of run_length and r
                $compressed += output ($prev, format_1stvalue($prev)) // die;
                $compressed += output ($r, encode ($r, --$run_length)) // die;
            }
        }
        $run_length = 0;
        $prev = $v;
    }

    if ($run_length) {
        $compressed += output ("EOF", encode (undef, $run_length)) // do {
            # switch to new block
            encoder_reinit();
            $compressed += $origbits;
            output ("EOF", encode (undef, $run_length)) // die;
        };
        $uncompressed += $run_length * $origbits;
        $run_length = 0;
    }

    my $ratio = $uncompressed / $compressed;
    printf("insamples %u origbits %u inbits %u compressed %u ratio %.*f\n",
           $uncompressed/$origbits, $origbits, $uncompressed, $compressed,
           ($ratio < 1? 3:2), $ratio);
}


1;
