 use strict;
 use warnings;
 use Prima qw(Application);
 use PrimaX::InputHistory;
 
 # A simple repl that prints the output to the screen
 
 my $window = Prima::MainWindow->new(
     text => 'Simpe REPL',
     width => 600,
 );
 
 my $file_name = 'my_history.txt';
 my $history_length = 10;
 my $inline = PrimaX::InputHistory->create(
     owner => $window,
     text => '',
     pack => {fill => 'both'},
     storeType => ih::NoRepeat,
     onCreate => sub {
         my $self = shift;
         
         # Open the file and set up the history:
         my @history;
         if (-f $file_name) {
             open my $fh, '<', $file_name;
             while (<$fh>) {
                 chomp;
                 push @history, $_;
             }
             close $fh;
         }
         
         # Store the history and revisions:
         $self->history(\@history);
     },
     onDestroy => sub {
         my $self = shift;
         
         # Save the last lines in the history file:
         open my $fh, '>', $file_name;
         # I want to save the *last* N lines, so I don't necessarily start at
         # the first entry in the history:
         my $offset = 0;
         my @history = @{$self->history};
         $offset = @history - $history_length if (@history > $history_length);
         while ($offset < @history) {
             print $fh $history[$offset++], "\n";
         }
         close $fh;
     },
 );
 
 print "Press Up/Down, Page-Up/Page-Down to see your input history\n";
 
 run Prima;