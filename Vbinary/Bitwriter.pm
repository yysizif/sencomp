package Vbinary::Bitwriter;

# indices in $self array
sub LIST() {0}
sub COUNT() {1}


# Accumulate $nbits bits taken from $val.
sub putbits
{
    my ($self, $nbits, $val) = @_;
    die if $nbits > 64;
    push @{$self->[LIST]}, [$nbits, $val];
    $self->[COUNT] += $nbits;
}


# Merge all bits accumulted so far, pad with zero bits, return the
# result.
sub flush
{
    my ($self) = @_;
    my @a;
    for (@{$self->[LIST]}) {
        my ($nbits, $val) = @$_;
        if ($nbits > 32) {
            use integer;
            push @a, sprintf("%0*b", $nbits-32, $val>>32);
            $nbits = 32;
        }
        push @a, sprintf("%0*b", $nbits, $val);
    }
    return pack "B*", join("", @a);  # pads to x8 with zero bits
}


sub bitcount
{
    my ($self) = @_;
    return $self->[COUNT];
}


sub align
{
    my ($self, $bitboundary) = @_;
    my $len = $self->[COUNT];
    my $aligned = ($len + $bitboundary - 1) & ~($bitboundary-1);
    $self->putbits($aligned - $len, 0);
}


sub new
{
    my ($class) = @_;
    return bless [[], 0], $class;
}

1;
