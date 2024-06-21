use strict;
use warnings;
use Test::More;
use Prima qw(Application InputHistory);

{
    my $ih = Prima::InputHistory->new( outputHandler => ih::Null );
    $ih->press_enter("Test::More::pass('This press_enter text eventually gets eval-d')");
    $::application->yield;
}

subtest 'Evaluation control with PressEnter clear_event' => sub {
    plan tests => 2;
    
    my $ih = Prima::InputHistory->new(
        outputHandler => ih::Null,
        onPressEnter => sub {
            $_[0]->clear_event;
            pass('PressEnter event handler was called');
        },
        onPostEval => sub {
            pass('Post-eval event handler was called');
        },
    );
    $ih->press_enter("fail('This should never have made it to the Evalutate event handler!!')");
    $::application->yield;
};

{
    my $ih = Prima::InputHistory->new(
        outputHandler => ih::Null,
        onPressEnter => sub {
            ${$_[1]} = "Test::More::pass('PressEnter callback successfully updated the text')";
        },
    );
    $ih->press_enter("Test::More::fail('This was supposed to be changed by the PressEnter callback')");
    $::application->yield;
}

{
    my @args = qw(left selected right);
    my $ih = Prima::InputHistory->new(
        outputHandler => ih::Null,
        onTabComplete => sub {
            my ($self, @got_args) = @_;
            is_deeply(\@got_args, \@args, 'Tab completion left, selection, and right are correctly passed');
            # Change the text to something new
            $self->text('something new');
        },
    );
    $ih->tab_complete(@args);
    $::application->yield;
    is($ih->text, 'something new', 'Tab Complete callback can modify the text');
}

done_testing;
