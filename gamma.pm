#
# Encode & decode routines for Elias Gamma coding.
#

package gamma;

use Carp;

sub encode
{
    my ($w, $val) = @_;
    use integer;

    if ($val <= 0) {
        croak "Usage: gamma(bitwriter,n), n >= 1";
    }

    my $len = 0;
    while($val < (1<<$len)) {
        $len++;
    }
    $w->putbits($len+1, 1);
    $w->putbits($len, $val & ~(-1<<$len));
}

sub decode
{
    my ($r) = @_;
    use integer;
    my $val;
    my $len = 0;
    while ($r->getbits(1) == 0) {
        $len++;
    }
    return 2**$len + $r->getbits($len);
}

# return non-zero (import success) only if wordbits is not exceeded
do { use integer; 1<<64-1 };
