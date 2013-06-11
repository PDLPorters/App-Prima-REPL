use strict;
use warnings;
use Prima qw(Application CaptureStdOut);

# This first set of tests simply ensures that we can, indeed, capture
# standard output, and release it. THIS INVOLVES HAND-WRITTEN TAP OUTPUT,
# since I need to be able to modify the test count.

print "ok 1 - We can print to STDOUT without trouble before we get going\n";

my $capture = Prima::CaptureStdOut->new;

print "ok 2 - Constructor works; does not grab STDOUT yet\n";

$capture->start_capturing;

#### These should not make it to the TAP harness
print "not ok 2.1 - Printing should not make it to tap output\n";
warn "not ok 2.2 - Warning should not make it to tap output\n";
print STDERR "not ok 2.3 - Printing explicitly to STDERR does not reach TAP output\n";
####

$capture->stop_capturing;

print "ok 3 - None of the failing messages made it to the TAP output\n";

print "ok 4 - STDOUT and STDERR are restored after stop_capturing is called\n";

$capture->start_capturing;

#### This should not make it to the TAP harness
print "not ok 4.1 - Resuming capturing still grabs file handles\n";
####

$capture->stop_capturing;

print "ok 5 - Capturing can be resumed and again stopped without trouble\n";

print "1..5\n";
