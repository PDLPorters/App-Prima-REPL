use strict;
use warnings;
use Test::More;
use Prima qw(Application CaptureStdOut);

# Ensures that two captures can work together well, and out-of-order
# behavior leads to catastrophe.

my $capture1 = Prima::CaptureStdOut->new;
my $capture2 = Prima::CaptureStdOut->new;

pass('Two captures can peacefully coexist');

eval {
    $capture1->start_capturing;
    $capture2->start_capturing;
    $capture2->stop_capturing;
    $capture1->stop_capturing;
    1;
} and do {
    pass('Two captures can start and stop in lifo order');
    1;
} or do {
    # Restore the file handles
    Prima::CaptureStdOut::restore_STDIO();
    fail('Two captures had trouble starting and stopping in lifo order!');
    diag($@);
};

# If the previous one failed, this will very likely fail, too.
eval {
    $capture1->start_capturing;
    $capture2->start_capturing;
    $capture1->stop_capturing;
    $capture2->stop_capturing;
    1;
} and do {
    Prima::CaptureStdOut::restore_STDIO();
    fail('Out-of-order capture lifo did NOT trigger failure!');
    1;
} or do {
    Prima::CaptureStdOut::restore_STDIO();
    pass('Out-of-order capture lifo correctly triggered failure');
    diag($@);
};

done_testing;
