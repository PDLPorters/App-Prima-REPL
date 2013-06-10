use strict;
use warnings;
use Test::More;
use Prima qw(Application InputHistory);

my $input_history = Prima::InputHistory->new(
    history => [map "line $_", 1..39],
);
is($input_history->currentLine, 0, 'Constructor sets current line to zero');
is(scalar(@{$input_history->history}), 39, 'Constructor sets history');

#################################
# Tests for setting currentLine #
#################################
$input_history->currentLine(3);
is($input_history->text, 'line 37', 'Text is properly set after a currentLine');
$input_history->currentLine(0);
is($input_history->text, 'InputHistory1',
    'Text is properly stored and restored after going back to new line');
$input_history->currentLine(-10);
is($input_history->currentLine, 0, 'Negative currentLine requests are truncated at zero');
# Check edge conditions
subtest 'Do not cycle or cut off second-to-last entry' => sub {
    $input_history->currentLine(38);
    is($input_history->currentLine, 38, 'Offset is correct');
    is($input_history->text, 'line 2', 'Text is correct');
};
subtest 'Do not cycle or cut off last entry' => sub {
    $input_history->currentLine(39);
    is($input_history->currentLine, 39, 'Offset is correct');
    is($input_history->text, 'line 1', 'Text is correct');
};

subtest 'Cut off at, do not cycle past last entry' => sub {
    $input_history->currentLine(40);
    is($input_history->currentLine, 39, 'Offset is correct');
    is($input_history->text, 'line 1', 'Text is correct');
};
subtest 'Cut off at, do not cycle past last entry' => sub {
    $input_history->currentLine(40);
    is($input_history->currentLine, 39, 'Offset is correct');
    is($input_history->text, 'line 1', 'Text is correct');
};


###################################
# Tests for move_line and friends #
###################################
$input_history->currentLine(0);
# Default behavior: down goes into the past
$input_history->move_line('up');
is($input_history->currentLine, 0, 'Cannot move up when already at top');
$input_history->move_line('down');
is($input_history->currentLine, 1, 'Moving in direction of past works');
$input_history->move_line('pgup');
is($input_history->currentLine, 0, 'Paging up more than we have cuts off');
$input_history->pastIs(ih::Up);
$input_history->move_line('up');
is($input_history->currentLine, 1, 'Switching direction of past works');
$input_history->move_line('pgup');
is($input_history->currentLine, 11, 'Pageup increments by many');
$input_history->move_line(2);
is($input_history->currentLine, 13, 'Positive arguments to move_line go back in time');


done_testing;
