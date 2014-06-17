use strict;
use warnings;
use Test::More;
use Prima qw(Application CaptureStdOut);

# Ensures that prints lead to text in the CaptureStdOut object, and that
# interacting captures don't confuse themselves or each other.

sub find {
    my ($capture, $regex) = @_;
    my $N_good = ()= $capture->text =~ /$regex/g;
    return $N_good;
}

my $capture1 = Prima::CaptureStdOut->new;
my $capture2 = Prima::CaptureStdOut->new;

# Start with sequential capturing

$capture1->start_capturing;
print "This is for capture 1\n";
print "Another for capture 1\n";
$capture1->stop_capturing;

subtest 'Each print gets logged once, and only once, to first capture' => sub {
    is(find($capture1, qr/This is for capture 1/), 1, 'First line appears once');
    is(find($capture1, qr/Another for capture 1/), 1, 'Second line appears once');
    is(find($capture1, qr/capture 1/), 2, 'Common string appears twice')
        or diag('Capture contains '.($capture1->widgets)[0]->text);
};

$capture2->start_capturing;
print "This is for capture 2\n";
print "Another for capture 2\n";
$capture2->stop_capturing;

subtest 'Each print gets logged once, and only once, to second capture' => sub {
    is(find($capture2, qr/This is for capture 2/), 1, 'First line appears once');
    is(find($capture2, qr/Another for capture 2/), 1, 'Second line appears once');
    is(find($capture2, qr/capture 2/), 2, 'Common string appears twice')
        or diag('Capture contains '.($capture2->widgets)[0]->text);
};

subtest 'No cross-capture leakage for sequential captures' => sub {
    is(find($capture1, qr/capture 2/), 0, 'Nothing from second capture in first capture');
    is(find($capture2, qr/capture 1/), 0, 'Nothing from first capture in second capture');
};


# Now try stacked capturing
$capture1->start_capturing;
print "stacked 1\n";
$capture2->start_capturing;
print "stacked 2\n";
$capture2->stop_capturing;
print "stacked 3\n";
$capture1->stop_capturing;

subtest 'No cross-capture leakage for stacked captures' => sub {
    is(find($capture1, qr/stacked [13]/), 2, 'First capture has two expected entries');
    is(find($capture2, qr/stacked 2/), 1, 'Second capture has one expected entry');
    is(find($capture1, qr/stacked 2/), 0, 'First capture has no unexpected entries');
    is(find($capture2, qr/stacked [13]/), 0, 'Second captue has no unexpected entries');
    
};

done_testing;
