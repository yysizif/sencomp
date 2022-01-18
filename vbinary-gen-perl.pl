#!/usr/bin/perl -w

#
# vbinary-gen-per.pl
#
# Given vbinary spec, generate encode & decode routines in Perl5.
#
# For details, see the article:
#
# \by Yu.V.Shevchuk
# \paper Vbinary: variable length integer coding revisited
# \jour Program Systems: Theory and Applications
# \vol 9
# \issue 4
# \yr 2018
#
# Copyright (C) Y.V.Shevchuk, 2020
# Copyright (C) A.K.Ailamazyan Program Systems Institute of RAS, 2020
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

use Math::BigInt;               # for vbinary_val
use Data::Dumper;               # for debugging

# variables set by parse_args() or left undefined
my $spec;                       # vbinary spec in "readable" form
my $name;                       # perl package name
my $verbose;
my $file;                       # output
my $wordbits = 64;              # provided by 'use integer' in most Perls


sub usage {
    die "Usage: vbinary-gen [-v] [-wWORDBITS] [-oOUTFILE] [-nNAME] vbinary-spec\n";
}


sub parse_args {
    while (@ARGV) {
        local $_ = shift @ARGV;
        if (s/^-v//) {
            $verbose++;
        }
        elsif (s/^-w(\S+)//) {
            # keep this option for exotic case of Perl built w/o/64
            # bit support
            $wordbits = $1 || shift @ARGV;
            usage unless $wordbits =~ /^\d+$/;
        }
        elsif (s/^-o(\S*)$//) {
            $file = $1 || shift @ARGV;
        }
        elsif (s/^-n(\S*)$//) {
            $name = $1 || shift @ARGV;
        }
        elsif (!$spec && s/^(vbinary\S+)//) {
            $spec = spec_from_identifier($1);
        }
        else {
            usage ();
        }
        unshift @ARGV, "-$_" if $_ ne "";
    }
    $name //= spec_to_identifier($spec);
    if (! defined $file) {
        $file = "$name.pm";
        $file =~ s,::,/,g;
    }
}


# Convert vbinary specification from "identifier flavor" to "readable
# flavor".  Do nothing if the specification is of readable flavor
# already.
sub spec_from_identifier {
    local ($_) = @_;
    tr[LcRs][(,)/];
    return $_;
}

# Convert vbinary specification from "readable flavor" to "identifier
# flavor".  Do nothing if the specification is of identifier flavor
# already.
sub spec_to_identifier {
    local ($_) = @_;
    tr[(,)/][LcRs];
    return $_;
}


sub die_with_pos {
    my ($errmsg, $left) = @_;
    my $consumed = substr ($spec, 0, length ($spec) - length ($left));
    my $line1 = "$errmsg: $consumed";
    my $indent = " " x length ($line1);
    die "${line1}\n${indent}${left}\n";
}


# Calculate prefixes for every extension of the next level.
sub mkprefixes {
    my ($level) = @_;
    my @res;
    for (my $i = 0; $i < $level->{extcount}; $i++) {
        push @res, sprintf ("%s%0*b",
                            $level->{prefixes}[$level->{exti}],
                            $level->{extiwidth},
                              #$level->{widths}[$level->{exti}],
                            $level->{extivalues} + $i);
    }
    return \@res;
}

# Returns 2**$width using Math::BigInt as $width may be large
# (more than 56, max representable by double)
sub nvalues {
    my ($width) = @_;
    return new Math::BigInt(2) ** $width;
}

# emit a putbits call
sub putbits {
    my($arg, $indent, $width) = @_; # width is optional
    my @res;
    if ($arg =~ /^[01]+$/) { # non-empty constant prefix
        while ($arg =~ s/^(.{$wordbits})//) {
            push @res, "${indent}\$w->putbits($wordbits, @{[oct qq(0b$1)]});";
        }
        my $sz = length($arg);
        push @res, "${indent}\$w->putbits($sz, @{[oct qq(0b$arg)]});";
    }
    elsif ($arg =~ /^$/) { # empty prefix, do nothing
    }
    else {  # must be a Perl expression <= $wordbits
        push @res, "${indent}\$w->putbits($width, $arg);";
    }
    return @res;
}


# Generate first part of the body of encoding routine, ready to
# write_output.  See also gen_encoder_tail
sub gen_encoder_head {
    my ($levels, $repeater) = @_;
    my @res;

    if (@$levels == 1) {         # vbinaryN
        # Handle as a special case (see the comment in check_spec)
        my $width = $levels->[0]{widths}[0];
        push @res, "if (\$val < (1<<$width)) {";
        push @res,     putbits("\$val", "    ", $width);
        push @res, "   return;";
        push @res, "}";
        return (undef, @res);
    }

    my $base = 0;
    for (my $i = 0; $i < @$levels; $i++) {
        my $cur = $levels->[$i];
        for (my $j = 0; $j < @{$cur->{widths}}; $j++) {
            my $width = $cur->{widths}[$j];
            if ($width > $wordbits) {
                die "level $j: width $width exceeds $wordbits, use -w\n";
            }
            my $nvalues = ($j == ($cur->{exti} // !$j)?
                           $cur->{extivalues}: nvalues($width));
            if ($nvalues) {  # there are data codewords in this extension
                #my $threshold = $base + $nvalues;
                #if ($threshold >= nvalues($wordbits)) {
                #     warn "level $j: $wordbits-bit word cannot hold $threshold";
                #}
                my $prefix = $cur->{prefixes}[$j];
                push @res, "if (\$val < @{[$base + $nvalues]}) {";
                push @res,      putbits($prefix, "    ");
                push @res,      putbits("\$val - $base", "    ", $width);
                push @res, "    return 0;"; # success
                push @res, "}";
            }
            $base += $nvalues;
        }
    }

    return ($base, @res);
}


sub gen_encoder_tail_simple {
    my ($cur, $repeater, $base) = @_;
    my $nxt = apply_repeater($cur, $repeater);
    my $capacity = level_capacity ($cur, $nxt);
    my @res;

    my $width = $cur->{extiwidth};
    my $bits = $cur->{extivalues} + $cur->{exti};
    if ($base) {
        push @res, "\$val -= $base;";
    }
    push @res, "my \$n = \$val / $capacity;";
    push @res, "if (\$n > 0) {";
    push @res,      putbits ($cur->{prefixes}[$cur->{exti}], "    ");
    # TODO: partially unroll the loop
    push @res, "    for (my \$i=0; \$i < \$n; \$i++) {";
    push @res, "       \$w->putbits($width, $bits);";
    push @res, "    }";
    push @res, "    \$val -= $capacity * \$n;";
    push @res, "}";

    $base = 0;
    for (my $j = 0; $j < @{$cur->{widths}}; $j++) {
        my $width1 = $cur->{widths}[$j];
        my $nvalues = ($j == $cur->{exti}? $cur->{extivalues}:
                       nvalues($width1));
        if ($nvalues) {  # there are data codewords in this extension
            my $bits = $cur->{extivalues} + $j;
            push @res, "if (\$val < @{[$base + $nvalues]}) {";
            push @res, "    if (\$n == 0) {";
            push @res,          putbits ($cur->{prefixes}[$cur->{exti}], " "x8);
            push @res, "    }";
            push @res,      putbits($bits, "    ", $width);
            push @res,      putbits("\$val - $base", "    ", $width1);
            push @res, "    return;";
            push @res, "}";
        }
        $base += $nvalues;
    }

    push @res, q(die __PACKAGE__ . ":encode cannot encode $val";);
    return @res;
}


sub next_extivalues {
    my ($levels, $i, $repeater) = @_;
    $nextlevel = $levels->[$i+1] ||
        apply_repeater($levels->[$i], $repeater);
    $nextnextlevel = $levels->[$i+2] ||
        apply_repeater($nextlevel, $repeater);
    my $exti = $nextlevel->{exti};
    my $width = $nextlevel->{widths}[$exti];
    my $extcount = @{$nextnextlevel->{widths}};
    my $extivalues = nvalues($width) - $extcount;
    $extivalues >= 0 || die;  # check_spec should have checked
    return $extivalues;
}

sub level_capacity {
    my ($level, $nextlevel) = @_;
    my $exti = $level->{exti};
    my $width = $level->{widths}[$exti];
    my $extcount = @{$nextlevel->{widths}};
    my $extivalues = nvalues($width) - $extcount;
    my $sum = 0;
    for (my $j = 0; $j < $extcount; $j++) {
        $sum += ($j == $exti? $extivalues:
                 nvalues ($nextlevel->{widths}[$j]));
    }
    return $sum;
}


# Generate decoder fragments handling explicit part of vbinary spec
sub gen_decoder_head {
    my ($levels, $repeater) = @_;

    my @res;
    if (@$levels == 1) {         # vbinaryN
        # Make it a special case as the general loop below needs
        # at least two levels.
        my $width = $levels->[0]{widths}[0];
        push @res, "return \$r->getbits($width);";
        return (undef, undef, @res);
    }

    my $base;
    my $extibase = 0;
    for (my $i = 0; $i < @$levels - 1; $i++) {
        my ($cur,$nxt) = @{$levels}[$i,$i+1];
        my $width = $cur->{widths}[$cur->{exti}];
        push @res, "my \$val;" if $i == 0;
        push @res, "\$val = \$r->getbits($width);";
        my @res2;
        if ($cur->{extivalues} > 0) {
            push @res2, "else {";
            push @res2, "    return $extibase + \$val;";
            push @res2, "}";
        }
        $base = $cur->{extivalues} if $i == 0;
        for (my $j = 0; $j < $cur->{extcount}; $j++) {
            if (defined $nxt->{exti} && $j == $nxt->{exti}) {
                # non-terminal extension, to be handled by next iteration
                $extibase = $base;
                $base += next_extivalues($levels, $i, $repeater);
            }
            else { # terminal extension, handle now
                my $width1 = $nxt->{widths}[$j];
                push @res, "if (\$val == @{[$cur->{extivalues} + $j]}) {";
                push @res, "    return $base + \$r->getbits($width1);";
                push @res, "}";
                $base += nvalues($width1);
            }
        }
        if (defined $nxt->{exti}) {
            push @res, "if (\$val == @{[$cur->{extivalues} + $nxt->{exti}]}) {";
            push @res, "}";
        }
        push @res, @res2;
    }

    return ($base, $extibase, @res);
}


# Continue after gen_decoder_head, generate decoder fragments
# handing repeater part of vbinary spec.  This simple version is for
# implicit repeater that repeats the last level unchanged.
sub gen_decoder_tail_simple {
    my ($cur, $repeater, $base, $extibase) = @_;
    my $nxt = apply_repeater($cur, $repeater);

    my $width = $cur->{extiwidth};
    my $exticode = $cur->{extivalues} + $cur->{exti};
    my $cap = level_capacity ($cur, $nxt);
    my @res;
    push @res, "my \$n = 0;";
    push @res, "while ((\$val = \$r->getbits($width)) == $exticode) {";
    push @res, "    \$n++;";
    push @res, "}";

    for (my $j = 0; $j < $cur->{extcount}; $j++) {
        if ($j == $cur->{exti}) {
            # non-terminal extension
            $base += $cur->{extivalues};
        }
        else {
            # terminal extension
            push @res, "if (\$val == $cur->{extivalues} + $j) {";
            my $width1 = $nxt->{widths}[$j];
            push @res, "    return $base + \$n*$cap + \$r->getbits($width1);";
            push @res, "}";
            $base += nvalues($width1);
        }
    }
    push @res, "return $extibase + \$n*$cap + \$val;";
    return @res;
}


# Continue after gen_decoder_head, generate decoder fragments
# handing repeater part of vbinary spec.  This heavier version is for
# explicit repeater that changes widths at every repitition.
sub gen_decoder_tail {
    my ($curlevel, $repeater, $base, $extibase) = @_;
    my @res;
    die "complex repeaters not supported yet";
    return @res;
}


sub gen_encoder {
    my ($levels, $repeater) = @_;
    my ($base, @res) = gen_encoder_head ($levels, $repeater);
    if (! $repeater) {
        # value exceeds finite coding size
        push @res, q(die __PACKAGE__ . ":encode cannot encode $val";);
    }
    elsif ($repeater == 1) {
        push @res, gen_encoder_tail_simple
            ($levels->[-1], $repeater, $base);
    }
    else {
        push @res, gen_encoder_tail
            ($levels->[-1], $repeater, $base);
    }
    return @res;
}


sub gen_decoder {
    my ($levels, $repeater) = @_;
    my ($base, $nbase, @res) = gen_decoder_head ($levels, $repeater);
    if (! $repeater) {
        # nothing to do
    }
    elsif ($repeater == 1) {
        push @res, gen_decoder_tail_simple
            ($levels->[-1], $repeater, $base, $nbase);
    }
    else {
        push @res, gen_decoder_tail
            ($levels->[-1], $repeater, $base, $nbase);
    }
    return @res;
}




# nip the level specification at the beginning of $_
# Return in the form [[width, ...], extindex, repeat-spec]
# repeat-spec  = undef    ; repeat last level
# repeat-spec /= [[factor divisor numerator denominator] ...]
sub parse_level {
    my @widths;
    my $exti;
    if (s/^(\d+)//) {
        @widths = ($1);
        if (s/^x//) {
            $exti = 0;
        }
    }
    elsif (s/^\(//) {
        while (1) {
            s/^(\d+)// || die_with_pos ("Width expected", $_);
            push @widths, $1;
            if (s/^x//) {
                if (defined $exti) {
                    die_with_pos ("More than one extension mark per level", $_);
                }
                $exti = @widths - 1;
            }
            if (s/^\)//) {
                last;
            }
            elsif (! s/^,//) {
                die_with_pos (", or ) expected", $_);
            }
        }
    }
    elsif (/^$/) {
        return undef;           # EOL reached
    }
    else {
        die_with_pos ("digit/left parenthesis/EOF expected", $_);
    }

    return {widths => [@widths],
            widths16 => [map {$_<<4} @widths],
            exti => $exti};
}


# If we are at the repeater specification which is the last part of
# vbinary specification, parse it and return a ref to a hash with
# repeater parameters.  Return undef if we are not at repeater
# specification.

sub parse_repeater {
    my @a;
    if (s/^\((?=[am])//) {      # positive lookahead assertion [am]
        do {
            push @a, parse_repeater1 ();
            if (! defined ($a[-1])) {
                die_with_pos ("aN or mN or ... mN/NaN/N expected", $_);
            }
        } while (s/^,//);
        if (! s/^\)//) {
            die_with_pos ("right parenthesis expected", $_);
        }
        return \@a;
    }
    else {
        push @a, parse_repeater1 ();
        if (! defined ($a[-1])) {
            return undef;
        }
    }
    return \@a;
}


# Subroutine of maybe_parse_repeater: parse a single aN oр mN/N clause,
# return [factor divisor numerator denominator], or undef if unparsable.

sub parse_repeater1 {
    my @ret = (1,1,0,1);
    my $take;
    if (s/^m(\d+)\/(\d+)//) {
        @ret[0,1] = ($1,$2);
        $take = 1;
    }
    elsif (s/^m(\d+)//) {
        @ret[0,1] = ($1,1);
        $take = 1;
    }
    if (s/^a(\d+)\/(\d+)//) {
        @ret[2,3] = ($1,$2);
        $take = 1;
    }
    elsif (s/^a(\d+)//) {
        @ret[2,3] = ($1,1);
        $take = 1;
    }
    return ($take? \@ret: undef);
}


# Apply repeat specification to $level, return the resulting
# nextlevel data
sub apply_repeater {
    my ($level, $repeater) = @_;
    my $nxt = unshare ($level);
    $repeater || die;
    if ($repeater == 1) {
        return $nxt;
    }
    for (my $i = 0; $i < @{$nxt->[0]}; $i++) {
        my ($fact, $div, $nom, $den) = @{$repeater->[$i]};
        use integer;
        $nxt->{width16s}[$i] *= $fact;
        $nxt->{width16s}[$i] /= $div;
        $nxt->{width16s}[$i] += (($nom << 4) / $den);
        $nxt->{widths}[$i] = $nxt->{widths16}[$i] >> 4;
    }
    # Calculate convenience values
    $nxt->{extcount} = $level->{extcount}; # not changed by repeater
    $nxt->{extiwidth} = $nxt->{widths}[$nxt->{exti}];
    $nxt->{extivalues} = nvalues($nxt->{extiwidth}) - $nxt->{extcount};
    $nxt->{prefixes} = mkprefixes($level);
    return $nxt;
}


# Copy a nested data structure recursively, so we can modify any part
# of it without affecting others who refer to the original term.

sub unshare {
    my ($term) = @_;
    if (ref ($term) eq ARRAY) {
        my @a;
        for (@{$term}) {
            push @a, unshare ($_);
        }
        return \@a;
    }
    elsif (ref ($term) eq HASH) {
        my %h;
        for (keys %{$term}) {
            $h{$_} = unshare ($term->{$_});
        }
        return \%h;
    }
    else {                      # not a reference = not shared
        return $term;
    }
}


# Parse "readable" vbinary spec.  Return the list of levels and the
# repeater.
sub parse_spec
{
    local ($_) = @_;

    s/^vbinary// || usage ();   # spec always starts with "vbinary"
    /^\d/ || usage ();          # base level must be present

    my $repeater;
    my @levels;
    while (/./) {
        if ($repeater = parse_repeater ()) {
            if (/./) {
                die_with_pos ("Expected nothing after repeater", $_);
            }
        }
        else {
            my $level = parse_level ($_);
            if (! defined $level->{exti} && /./) {
                die_with_pos ("Expected nothing after terminal level", $_);
            }
            push @levels, $level;
        }
    }
    if (! $repeater && defined $levels[-1]->{exti}) {
        # If no repeater is specified, repeat the last level as is.
        # Special case.
        $repeater = 1;
    }
    return (\@levels, $repeater);
}


sub write_output {
    my($encfrags, $decfrags) = @_;
    if ($file =~ m,(.*/),) {
        system "mkdir -p $1";
    }
    open (my $fh, ">$file") or die "$file: $!\n";
    for (<DATA>) {
        s/%spec%/$spec/g;
        s/%wordbits%/$wordbits/g;
        s/%name%/$name/g;
        s/^(.*)%encfrags%(.*)/join "", map {"$1$_$2"} @$encfrags/es;
        s/^(.*)%decfrags%(.*)/join "", map {"$1$_$2"} @$decfrags/es;
        print {$fh} $_;
    }
}


# check the parsed spec for errors that parse_spec could not check
# and canonicalize for convenience of use.
sub check_spec {
    my ($levels, $repeater) = @_;

    # Check all level (except maybe the last one) have the
    # non-terminal extension index established.
    for ($i = 0; $i < @$levels; $i++) {
        if (! defined $levels->[$i]{exti}) {
            die "missing 'x' at level $i\n" unless $i == (@$levels-1);
        }
    }

    # Check if the repeater matches the last level
    if (ref $repeater) {        # explicit repeater
        if (@{$levels->[-1]{widths}} != @{$repeater}) {
            die ("Repeater rule count wrong ".
                 sprintf ("(%u != %u)",
                          scalar(@{$levels->[-1]{widths}}),
                          scalar(@{$repeater})));
        }
    }

    # encoding & decoding algorithms always consider levels by pairs,
    # the current and the next.  If the spec has only one level, use
    # the repeater to add the second level for their convenience.
    # This is not possible for trivial single-level codings (vbinaryN)
    # which have no repeater; leave them as is, they well be handled
    # as a special case.
    if (@$levels == 1 && defined $levels->[0]{exti}) {
        push @$levels, apply_repeater($levels->[0], $repeater);
    }

    # Calculate and store convenience values
    $levels->[0]{prefixes} = [""];
    for ($i = 0; $i < @$levels; $i++) {
        my $cur = $levels->[$i];
        last unless defined $cur->{exti};
        my $nxt = $levels->[$i+1] // apply_repeater($cur, $repeater);
        $cur->{extiwidth} = $cur->{widths}[$cur->{exti}];
        $cur->{extcount} = @{$nxt->{widths}};
        my $nvalues = nvalues($cur->{extiwidth});
        if ($cur->{extcount} > $nvalues) {
            die ("level $i: too many extensions ($cur->{extcount}) ",
                 "for width $cur->{extiwidth}\n");
        }
        $cur->{extivalues} = $nvalues - $cur->{extcount};
        $nxt->{prefixes} = mkprefixes($cur);
    }
}


sub main {
    #$SIG{__WARN__} = sub {Carp::cluck(@_)};
    $SIG{__DIE__} = sub {Carp::confess(@_)};
    parse_args ();
    my ($levels, $repeater) = parse_spec ($spec);
    check_spec ($levels, $repeater);
    my @encfrags = gen_encoder ($levels, $repeater);
    my @decfrags = gen_decoder ($levels, $repeater);
#warn Dumper \@encfrags;
    write_output (\@encfrags, \@decfrags);
}


main ();
exit 0;


__DATA__
#
# Encode & decode routines for %spec% coding.
# Generated by vbinary-gen-perl.
#

package %name%;

sub encode
{
    my ($w, $val) = @_;
    use integer;
    %encfrags%
}

sub decode
{
    my ($r) = @_;
    use integer;
    %decfrags%
}

# return non-zero (import success) only if wordbits is not exceeded
do { use integer; 1<<%wordbits%-1 };
