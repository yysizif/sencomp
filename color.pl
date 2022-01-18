#!/usr/bin/perl

use POSIX;

while(<>) {
    # \nexttest\label{test:Pa_period1} & Pa period~1 & 25874 & 5.21 & 3.12 & 2.29 & 1.98 & 1.08 & 1.17 & 1.40 & 1.39 & 1.51 & 1.52 & 1.53\\
    my @a = split /\s*[&]\s*/;
    for ($i=6; $i < @a; $i++) {
        my $wave =
            # map compression ratio 0..10 to wavelength 480..580
            ($a[$i] <= 10? 480 + ceil((580-480)/10 * $a[$i]):
             # map compression ratio 10..1750 to wavelength 590..720
             $a[$i] <= 1750? 590 + ceil((720-590)/(1750-10) * ($a[$i]-10)):
             # unused hole
             $a[$i] <= 299000? die("no wavelength defined for $a[$i]"):
             # map compression ratio 299000..560000 to wavelength 725..750
             $a[$i] <= 1110000? 725 + ceil((750-725)/(1110000-299000) * ($a[$i] - 299000)):
             die("no wavelength defined for $a[$i]"));
        $a[$i] =~ s/(\d{5,})/sprintf "%ue3", $1\/1000/e;
        $a[$i] =~ s/^/\\cellcolor[wave]{$wave}/;
        # preserve "\\\\","\n"
    }
    print join(" & ", @a);
}

exit 0;
