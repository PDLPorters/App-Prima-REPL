 use strict;
 use warnings;
 use Prima qw(Application CaptureStdOut);
 
 # A simple test of CaptureStdOut
 
 my $window = Prima::MainWindow->new(
     text => 'Simpe REPL',
     width => 600,
 );
 
 my $capture = $window->insert(CaptureStdOut =>
     pack => {fill => 'both'},
 );
 
 # Activate the capture
 $capture->start_capturing;
 
 $capture->note_printout("This is a note");
 $capture->printerr('This will always be correctly caught');
 print "This is captured text!\n";
 print "This is also captured text!\n";
 print "fileno for currently selected file handle is ", fileno(select), "\n";
 print STDERR "This will probably be captured in an error window\n";
 warn "This is a captured warning\n";
 warn "This is also a captured warning\n";
 $capture->command_printout('This is a command!');
 
 $capture->stop_capturing;
 
 print "And this text is not captured\n";
 warn "And this warning is not captured\n";
 
 run Prima;