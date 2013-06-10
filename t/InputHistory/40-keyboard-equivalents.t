use strict;
use warnings;
use Test::More;
use Prima qw(Application InputHistory);

use Prima::Utils qw(post);

# This set of tests ensure that various method calls are equivalent to
# actual use keyboard input.

my $ih1 = Prima::InputHistory->new(
    outputHandler => ih::Null,
    history => [map "line $_", 1..39],
    text => 'Current Line',
    onTabComplete => sub {
        my ($self, $left, undef, $right) = @_;
        $self->text($left . 'replaced' . $right);
    },
);
my $ih2 = Prima::InputHistory->new(
    outputHandler => ih::Null,
    history => [map "line $_", 1..39],
    text => 'Current Line',
    onTabComplete => sub {
        my ($self, $left, undef, $right) = @_;
        $self->text($left . 'replaced' . $right);
    },
);

# A utility method to make testing more succinct
sub ih_match (&$) {
    my ($subref, $explanation) = @_;
    $subref->();
    $::application->yield;
    is($ih1->text, $ih2->text, $explanation);
}

# Move to the middle of the history
ih_match {
    $ih1->currentLine(20);
    $ih2->currentLine(20);
} 'Sanity check: moving to line 20 gives same text';

# Issue the method call on the one, the keyboard event on the other, and
# make sure they stay in sync:
ih_match {
    $ih1->move_line('up');
    $ih2->key_down(kb::Up, kb::Up);
} "move_line('up') is equivalent to keyboard 'Up' input";

ih_match {
    $ih1->move_line('down');
    $ih2->key_down(kb::Down, kb::Down);
} "move_line('down') is equivalent to keyboard 'Down' input";

ih_match {
    $ih1->move_line('pgup');
    $ih2->key_down(kb::PageUp, kb::PageUp);
} "move_line('pgup') is equivalent to keyboard 'PageUp' input";

ih_match {
    $ih1->move_line('pgdn');
    $ih2->key_down(kb::PageDown, kb::PageDown);
} "move_line('pgdn') is equivalent to keyboard 'PageDown' input";


ih_match {
    my @args = qw(left selected right);
    $ih1->tab_complete(@args);
    # make equivalent key strokes in ih2
    $ih2->text(join('', @args));
    $ih2->selection(length($args[0]), length($args[0]) + length($args[1]));
    $ih2->key_down(kb::Tab, kb::Tab);
} "tab_complete(args) is equivalent to keyboard 'Tab' input given proper selection";

done_testing;
