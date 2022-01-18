#
# Encode & decode routines for Golomb-Rice(k) coding.
#

package gr;

use Carp;

sub encode
{
    my ($w, $u, $k) = @_;
    use integer;

    $u >= 0 && $k >= 0 or croak "Usage: encode(bitwriter,n,k), n>=0, k>=0";

    my $q = $u >> $k;
    my $r = $u & ~(-1<<$k);
    for ( ; $q>64; $q-=64) {
        $w->putbits(64,-1);
    }
    $w->putbits($q,~(-1<<$q));
    $w->putbits(1,0);
    $w->putbits($k,$r);
}

sub decode
{
    my ($r, $k) = @_;
    use integer;
    my $p = 0;
    while ($r->getbits(1) == 1) {
        $p++;
    }
    return $p*2**$k + $r->getbits($k);
}

# return non-zero (import success) only if wordbits is not exceeded
do { use integer; 1<<64-1 };
