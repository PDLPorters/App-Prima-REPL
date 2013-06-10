use strict;
use warnings;
use Test::More;
use Prima qw(Application InputHistory);

my $input_history = Prima::InputHistory->new(
    history => [map "line $_", 1..39],
);

#################################
# Tests for setting currentLine #
#################################
$input_history->text('partial entry');
$input_history->move_line('down');
is($input_history->text, 'line 39', 'Movement changes text to history');
$input_history->text('changed');
$input_history->move_line('up');
is($input_history->text, 'partial entry', 'Move back restores partial entry');
$input_history->move_line('down');
is($input_history->text, 'changed', 'Move back-back resores another partial entry');

done_testing;
