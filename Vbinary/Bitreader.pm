package Vbinary::Bitreader;

# indices in $self array
sub PACK() {0}
sub OFFSET() {1}
sub MAXBITS() {2}


sub getbits
{
    my ($self, $nbits) = @_;
    my $ascii = $self->getbits_ascii($nbits) // return undef;
    return oct("0b$ascii");

}

sub getbits_ascii
{
    my ($self, $nbits) = @_;
    use integer;
    my ($pack, $offset, $maxbits) = @$self;
    if ($offset >= $maxbits) {
        return $nbits? undef: 0;
    }
    my $pack1 = substr ($pack, $offset/8);
    my $skip = $offset%8;
    my $nbits1 = $nbits + $skip;
    my $ascii1 = unpack "B$nbits1", $pack1;
    my $ascii = substr ($ascii1, $skip);
    $self->[OFFSET] = $offset + $nbits;
    return $ascii;
}


sub bitcount
{
    my ($self) = @_;
    return $self->[MAXBITS] - $self->[OFFSET];
}


sub align
{
    my ($self, $bitboundary) = @_;
    $self->[OFFSET] += ($bitboundary-1);
    $self->[OFFSET] &= ~($bitboundary-1);
}


sub new
{
    my ($class, $pack, $nbits) = @_;
    return bless [$pack, 0, $nbits // length($pack)*8], $class;
}

1;
