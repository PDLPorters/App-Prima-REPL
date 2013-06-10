use strict;
use warnings;
use Test::More;
use Prima qw(Application InputHistory);

use Prima::Utils qw(post);

sub post_now (&) {
    post($_[0]);
    $::application->yield;
}

subtest 'Basic eval test' => sub {
    plan tests => 1;
    my $ih = Prima::InputHistory->new( outputHandler => ih::Null );
    $ih->text("Test::More::pass('this text gets eval-d')");
    post_now { $ih->PressEnter };
};

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
        text => "fail('Evalutate event handler was not supposed to be called!!')"
    );
    post_now { $ih->PressEnter };
};

subtest 'Text munging by PressEnter handlers' => sub {
    plan tests => 1;
    
    my $ih = Prima::InputHistory->new(
        outputHandler => ih::Null,
        onPressEnter => sub {
            $_[1] = "Test::More::pass('PressEnter callback successfully updated the text')";
        },
        text => "Test::More::fail('This was supposed to be changed by the PressEnter callback')"
    );
    post_now { $ih->PressEnter };
    
};

done_testing;
