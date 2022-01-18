#!/usr/bin/perl -w

use Carp;

# All algos in desired column order
my @algos1 = qw(z22 z1 EB);  # reference
my @algos2 = qw(F16 F256 RLGR EG EW); # third-party
my @algos3 = qw(e1 e2 e3 e4 e5 DD RLGR2 e10); # homebrew
my @all_algos = (@algos1, @algos2, @algos3);

my @algos;
my @files;
my $noisered;
my $skiplen;
my $len;                        # input size limit
my $maxout = 256;               # output block size

our @args;                      # shut up a warning


sub usage {
    confess "Usage: $0 [-nMINSTEP] [-sSKIP] [-lLEN] [ALGO...] [FILE...]\n";
}


sub parse_args {
    while (local $_ = shift @ARGV) {
        if (/^-a(\d?)$/) { # select algo groups for tables 1/2/3
            if ($1) {
                push @algos, eval "\@algos$1";
            }
            else {
                push @algos, @all_algos;
            }
        }
        elsif (/^-L(\d*)$/) {
            $maxout = $1;
        }
        elsif (/^-l([\d.]*)$/) {
            $len = $1 || shift || usage();
        }
        elsif (/^-n(\d[\d.]*)$/) {
            $noisered = $1 || shift || usage();
        }
        elsif (/^-s(\d*)$/) {
            $skiplen = $1 || shift || usage();
        }
        elsif (/^-/) {
            usage();
        }
        elsif (local $origbits = DUMMY, # avoid an "undefined!" warning
               cmd_for_algo($_)) {
            push @algos, $_;
        }
        else {
            push @files, $_;
        }
    }
    @algos or @algos = @all_algos;
}



$cmd_for_algo{z1} = sub {
    return (q(perl -ple 's/0 //; s/\.//'),
            "zstd -1v 2>&1 >/dev/null");
};

$cmd_for_algo{z22} = sub {
    return (q(perl -ple 's/0 //; s/\.//'),
            "zstd --ultra -22v 2>&1 >/dev/null");
};

$cmd_for_algo{F16} = sub {
    return ("./felacs.pl -$origbits -b16 @args");
};

$cmd_for_algo{F256} = sub {
    return ("./felacs.pl -$origbits -b256 @args");
};

#$cmd_for_algo{B} = sub {
#    return ("./binary.pl -$origbits -L$maxout @args");
#};
#
#$cmd_for_algo{lB} = sub {
#    return ("./linear.pl | ./binary.pl -$origbits -L$maxout @args");
#};

$cmd_for_algo{EB} = sub {
    return ("./expbinary.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{EG} = sub {
    return ("./egamma.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{EW} = sub {
    return ("./eomega.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{RLGR} = sub { # with infinite buffer
    return ("./rlgr.pl -$origbits @args");
};

$cmd_for_algo{RLGR2} = sub {
    return ("./rlgr.pl -$origbits -k10 -L$maxout @args");
};

$cmd_for_algo{MTF} = sub {
    return ("./mtf.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{MTFL} = sub {
    return ("./mtfl.pl -$origbits -L$maxout @args");
};


$cmd_for_algo{e1} = sub { # MTF1: sign_in_prefix
    return ("./mtf.pl -$origbits -L$maxout -a @args");
};

$cmd_for_algo{e2} = sub { # MTF:
    return ("./mtf.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e3} = sub { # MTF: bubble
    return ("./mtf.pl -$origbits -L$maxout -b1 @args");
};

$cmd_for_algo{e4} = sub { # MTFLB: single stack, (bubble by default)
    return ("./mtfl.pl -$origbits -L$maxout -h1 @args");
};

$cmd_for_algo{e5} = sub { # MTFLBH
    return ("./mtfl.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e6} = sub { # post-RLGR
    return ("./e6.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e7} = sub { # post-RLGR
    return ("./e7.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e8} = sub { # post-RLGR
    return ("./e8.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e9} = sub {
    return ("./e9.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e10} = sub {
    return ("./e10.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e11} = sub {
    return ("./e11.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{DD} = sub {
    return ("./dyndelta.pl -$origbits -L$maxout @args");
};

$cmd_for_algo{e12} = sub { # mtfl with enhanced rle, optimized for short L
    return ("./mtfl2.pl -$origbits -L$maxout -h1 @args");
};



sub parse_test_output {
    my ($fd) = @_;
    while(<$fd>) {
        # insamples 25872 origbits 16 inbits 413952 compressed 239250 ratio 1.73
        if (/ ratio (\d[\d.]*)/) {
            return $1;
        }
        # v=1     nbits=1 key=Q i=4 <ORPNQMSL> 4 bits=5 599980/97635=6.15
        if (/^v=.*\d+=(\d[\d.]*)$/) {
            return $1;
        }
        # *** zstd command line interface 64-bits v1.3.8, by Yann Collet ***
        # /*stdin*\            : 11.43%   (  4000 =>    457 bytes, /*stdout*\)
        if (/stdin.*: +(\d+.\d\d)%.*stdout/) {
            return 100/$1;
        };
    }
    die;
};


sub cmd_for_algo {
    local ($_) = @_;
    local @args = split;  # separate optional command args
                          # @args is used as implicit arg in $cmd_for_algo{*}
    my $algo = shift @args;
    return ($cmd_for_algo{$algo}?
            $cmd_for_algo{$algo}->() : undef);
}


sub cmd_for_file {
    local ($_) = @_;
    my @cmd = ("cat '$_'");
    if (/^embed.*\.csv$/) {
        push @cmd, "embed/from-csv.pl";
    }
    if ($skiplen) {
        push @cmd, "sed '1,${skiplen}d'";
    }
    if (defined $len) {
        push @cmd, "sed '${len}q'";
    }
    if ($noisered) {
        push @cmd, "./noisered.pl $noisered";
    }
    return @cmd;
}

# make description of data source based on filename and
# options
sub rowheader {
    local($_) = @_;

    my $ret;
    if (/^embed\/Apt(.)_GT_Plug(\/.*).csv$/) {
        $ret = "$1$2";
    }
    elsif (/(\d)\/aem1-(.)WATT/) {
        $ret = "Period~$1, P".lc($2);
    }
    elsif (/(\d)\/bqth1919-(T|DEW)/) {
        $ret = "Period~$1, ${2}1";
        $ret =~ s/DEW/Tdp/;
    }
    elsif (/(\d)\/bqth1923-(T|DEW)/) {
        $ret = "Period~$1, ${2}2";
        $ret =~ s/DEW/Tdp/;
    }
    elsif (/data\/rle/) {
        $ret = "rle12";
    }
    elsif (/data\/aem-rle/) {
        $ret = "rle17";
    }
    else {
        die "cannot handle filename '$_'";
    }

    if ($noisered) {
        $ret .= "-noise";
    }
    if ($skiplen) {
        $ret .= ", \@$skiplen"
    }

    return $ret;
}

sub rowlabel {
    local($file) = @_;
    local $_ = rowheader($file);
    s/ +/_/g;
    s/~//g;
    #return sprintf('\nexttest\label{test:%s}', $_);;
    return sprintf('\nexttest');;
}


# Guess how many bits would be needed to store uncompressed value for
# every data point in FILE.
sub origbits {
    local ($_) = @_;
    /embed.*csv$/ && return 18;    # 15A*120V*10**2 = 18 bits
    /aem1/ && return 18;           # 100A*240V*10**1 = 18 bits
    /bq.*-T$/ && return 12;        # we know ADC was in 12-bit mode
    /bq.*-DEW$/ && return 12;      # 10 bit H, 12 bit T
    /aem-rle$/ && return 18;       # like aem1*, with const value
    /rle$/ && return 12;           # like bq*, with const value
    die "no ORIGBITS guess for $_";
}


sub run_wc {
    my ($file) = @_;
    my @cmd = (join("|", cmd_for_file($file), "wc -l"));
    return `@cmd` =~ /(\d+)/;  # =chomp
}

sub run_test {
    my ($file, $algo) = @_;
    local $origbits = origbits($file);  # used by cmd_for_algo
    my $cmd = join(" | ", cmd_for_file($file), cmd_for_algo($algo));
    warn "$cmd\n";
    open(my $fh, "$cmd|") or die "$cmd: $! $@";
    my $ratio = parse_test_output($fh);
    close $fh or die "subcommand exit $@";
    return $ratio;
}


sub main {
    parse_args();
    my @rows;
    for my $file (@files) {
        push @rows, [rowlabel($file), rowheader($file), run_wc($file)];
        for my $algo (@algos) {
            my $ratio = run_test($file, $algo);
            if ($ratio < 0.01) {
                push @{$rows[-1]}, sprintf("%.3f", $ratio);
            }
            elsif ($ratio < 100) {
                push @{$rows[-1]}, sprintf("%.2f", $ratio);
            }
            else {
                push @{$rows[-1]}, sprintf("%u", $ratio);
            }
        }
    }
    for my $row (@rows) {
        print join(" & ", @{$row});
        print "\\\\\n";
    }
}

main();
exit 0;
