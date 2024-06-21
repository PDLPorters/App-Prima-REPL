use strict;
use warnings;
use Prima;

package ih;
use constant Null    =>  0;
use constant StdOut  =>  1;

use constant Unique  => 10;
use constant All     => 11;
use constant NoRepeat => 12;

use constant Up      => 20;
use constant Down    => 21;

##########################################################################
             package Prima::InputHistory::Output::Null;
##########################################################################
# A ridiculously simple output handler that does nothing
sub newline_printout { }
sub command_printout { }
sub new {my $self = {}; return bless $self}

##########################################################################
             package Prima::InputHistory::Output::StdOut;
##########################################################################
# The default output handler with which InputHistory works; uses Perl's print
# statement for output.
sub printout {
	my $self = shift;
	print @_;

	# Track the last printed line so that newline printout works:
	if (defined $_[-1]) {
		$self->{last_line} = $_[-1];
	}
	else {
		$self->{last_line} = '';
	}
}
sub newline_printout {
	my $self = shift;
	if ($self->{last_line} !~ /\n$/) {
		$self->printout("\n", @_);
	}
	else {
		$self->printout(@_);
	}
}
sub command_printout {
	my $self = shift;
	my $first_line = shift;
	$self->newline_printout('> ' . $first_line, @_, "\n");
}
sub new {
	my $self = {last_line => ''};
	return bless $self
}

##########################################################################
            package Prima::InputHistory::Output::REPL;
##########################################################################
# Thanks to the tied output, I can simply "print" results and they will
# go to the output widget. I believe this should be moved into its own
# module specifically for the app.
sub printout {
	my $self = shift;
	print @_;
}
sub newline_printout {
	my $self = shift;
	print "\n" if $self->{repl}->output_column != 0;
	print @_;
}
sub command_printout {
	my $self = shift;
	my $first_line = shift;
	$self->newline_printout('> ' . $first_line, @_, "\n");
}
sub new {
  my $class = shift;
  return bless { repl => shift || die }, $class;
}


##########################################################################
                      package Prima::InputHistory;
##########################################################################
# a history-tracking and evaluating input line.

use base 'Prima::InputLine';
use Carp 'croak';

# This has the standard profile of an InputLine widget, except that it knows
# about navigation keys and other things useful for the History.
sub profile_default
{
	my %def = %{$_[ 0]-> SUPER::profile_default};

	# These lines are somewhat patterned from the Prima example called 'editor'
	my @acc = (
		# Navigation scrolls through the command history
		  ['Previous Line', 'Up', kb::Up, sub {$_[0]->move_line('up')}]
		, ['Next Line', 'Down', kb::Down, sub {$_[0]->move_line('down')}]
		, ['Earlier Lines', 'Page Up', kb::PageUp, sub {$_[0]->move_line('pgup')}]
		, ['Later Lines', 'Page Down', kb::PageDown, sub {$_[0]->move_line('pgdn')}]
		# Enter runs the line
		, ['Run', 'Return', kb::Return, sub {$_[0]->press_enter($_[0]->text)}]
		, ['Run', 'Enter', kb::Enter, sub {$_[0]->press_enter($_[0]->text)}]
		, ['TabComplete', 'Tab', kb::Tab, \&do_tab_complete]
	);

	return {
		%def,
		accelItems => \@acc,
		pageLines => 10,		# lines to 'scroll' with pageup/pagedown
		outputHandler => ih::StdOut,
		storeType => ih::All,
		pastIs => ih::Down,
		history => [],
	}
}

# This stage initializes the inputline. This is the appropriate stage for
# setting the properties from the arguments to the constructor, as well as
# connecting to the output handler.
sub init {
	my $self = shift;
	my %profile = $self->SUPER::init(@_);
	foreach ( qw(pageLines storeType pastIs) ) {
		$self->{$_} = $profile{$_};
	}

	# currentLine needs to be initialized:
	$self->{currentLine} = 0;

	# Store the history and revisions:
	$self->currentRevisions([]);
	$self->history($profile{history});

	# Set up the output handler.
	$self->outputHandler($profile{outputHandler});

	return %profile;
}

################################################################################
# Usage      : $widget->move_line(<string or count>)
# Purpose    : Moves the currently displayed line by a relative move
# Returns    : the final historical (non-relative) line number
# Parameters : the widget
#            : a move, either a signed number or one of the strings 'up,
#            : 'down', 'pgup', or 'pgdn'
# Throws     : never
# Comments   : This truncates any relative move to the limits of the history.
#            : It invokes the currentLine method to perform all of the heavy
#            : machinery. This is used primarily for the key navigation
#            : callbacks.
################################################################################
sub move_line {
	my ($self, $requested_move) = @_;

	$requested_move = $self->up_sign if $requested_move eq 'up';
	$requested_move = $self->down_sign if $requested_move eq 'down';
	$requested_move = $self->up_sign * $self->pageLines
		if $requested_move eq 'pgup';
	$requested_move = $self->down_sign * $self->pageLines
		if $requested_move eq 'pgdn';

	# Determine the requested line number. (currentLine counts backwards)
	$self->currentLine($self->currentLine() + $requested_move);
}


################################################################################
# Usage      : $widget->pastIs([new-dir])
# Purpose    : Set the direction of past entries for keyboard interaction
# Returns    : The constant indicating which direction is into the past
# Parameters : the widget
#            : optional new direction
# Throws     : if the provided value is neither ih::Up or ih::down
# Comments   : none
################################################################################
sub pastIs {
	return $_[0]->{pastIs} unless $#_;
	my ($self, $dir) = @_;
	if ($dir == ih::Up or $dir == ih::Down) {
		$self->{pastIs} = $dir;
	}
	else {
		croak("Unknown direction for pastIs; expected ih::Up or ih::Down");
	}
}

################################################################################
# Usage      : $widget->up_sign, $widget->down_sign
# Purpose    : Help get signs straight for up/down wrt history
# Returns    : The proper sign: 1 if the direction is into the past, -1 otherwise
# Parameters : the widget
# Throws     : never
# Comments   : none
################################################################################
sub up_sign {
	my $self = shift;
	return 1 if $self->{pastIs} == ih::Up;
	return -1;
}
sub down_sign {
	my $self = shift;
	return 1 if $self->{pastIs} == ih::Down;
	return -1;
}

################################################################################
# Usage      : $widget->outputHandler([optional-new-handler])
# Purpose    : Get or set the widget's output handler
# Returns    : The new or current output handler
# Parameters : the widget
#            : an optional new output handler
# Throws     : whenever the input is not one of the known constants (ih::Null,
#            : ih::StdOut) or not an object that can handle method calls of
#            : command_printout and newline_printout
# Comments   : none
################################################################################
sub outputHandler {
	return $_[0]->{outputHandler} unless $#_;

	my ($self, $outputHandler) = @_;

	# Perl scalars with text are not allowed:
	if (not ref($outputHandler) and $outputHandler !~ /^\d+$/) {
		croak("Unknown outputHandler $outputHandler");
	}
	elsif ($outputHandler == ih::Null) {
		$self->{outputHandler} = new Prima::InputHistory::Output::Null;
	}
	elsif ($outputHandler == ih::StdOut) {
		$self->{outputHandler} = new Prima::InputHistory::Output::StdOut;
	}
	else {
		# Make sure it can do what I need:
		croak("Unknown outputHandler does not appear to be an object")
			unless ref($outputHandler);
		croak("outputHandler must support methods newline_printout and command_printout")
			unless $outputHandler->can('newline_printout')
				and $outputHandler->can('command_printout');
		# Add it to self
		$self->{outputHandler} = $outputHandler;
	}
}

###################
# Basic Accessors #
###################
# The class properties. Template code for these was taken from Prima::Object's
# name example property code:

sub currentRevisions {
	return $_[0]->{currentRevisions} unless $#_;
	$_[0]->{currentRevisions} = $_[1];
}
sub history {
	return $_[0]->{history} unless $#_;
	$_[0]->{history} = $_[1];
	$_[0]->currentLine(0);
	return $_[1];
}
sub pageLines {
	return $_[0]->{pageLines} unless $#_;
	$_[0]->{pageLines} = $_[1];
}
sub storeType {
	return $_[0]->{storeType} unless $#_;
	$_[0]->{storeType} = $_[1];
}

################################################################################
# Usage      : $widget->currentLine([optional-new-line-number])
# Purpose    : As a getter, returns the current depth in the history.
#            : As a setter, this changes the contents of the input line to
#            : reflect the desired selection from the history.
# Returns    : The (possibly new) line number
# Parameters : the widget
#            : the optional new line number
# Throws     : never
# Comments   : This method works hard to make the user experience what they
#            : expect. It sets the currentRevisions before leaving the current
#            : line and consults the currentRevisions when setting up the new
#            : line; it also keeps the cursor in the same location.
#            : Note the counting is backwards: current = 0, previous = 1, etc.
################################################################################
sub currentLine {
	return $_[0]->{currentLine} unless $#_;
	my ($self, $line_number) = @_;

	# Save changes to the current line in the revision list:
	$self->currentRevisions->[$self->{currentLine}] = $self->text;

	# Get the current character offset:
	my $curr_offset = $self->charOffset;
	# Note the end-of-line position by zero:
	$curr_offset = 0 if $curr_offset == length($self->text);

	# make sure the requested line makes sense; set to zero if there is
	# no history:
	my $history_length = scalar @{$self->history};
	$line_number = 0 if $line_number < 0;
	$line_number = $history_length if $line_number > $history_length;

	# Set self's current line:
	$self->{currentLine} = $line_number;

	# Load the text using the Orcish Maneuver:
	my $new_text = defined $self->currentRevisions->[$line_number]
			? $self->currentRevisions->[$line_number]
			: $self->history->[-$line_number];
	$self->text($new_text);

	# Put the cursor at the previous offset. However, if the previous offset
	# was zero, put the cursor at the end of the line:
	$self->charOffset($curr_offset || length($new_text));

	return $line_number;
}

# Add a new notification_type for each of on_PressEnter and on_Evaluate. The
# first should be set with hooks that remove or modify any text that needs to be
# cleaned before the eval stage. In other words, if you want to define commands
# that do not parse as a function in Perl, add it as a hook under on_PressEnter.
# The best examples I can think of, which also serve to differentiate between
# the two needs, are NiceSlice processing, and processing the help command. To
# make help work as a bona-fide function, you would have to surround your topic
# with quotes:
#   help 'PDL::IO::FastRaw'
# That's ugly. It would be much nicer to avoid the quotes, if possible, with
# something like this:
#   help PDL::IO::FastRaw
# That's the kinda thing you would handle with an on_PressEnter hook. After the
# help hook handles that sort of thing, it then calls the clear_event() method
# on the InputHistory object. On the other hand, NiceSlice parsing will modify
# the contents of the evaluation, but not call clear_event because it wants the
# contents of the text to be passed to the evaluation.
#
# If the event is properly handled by one of the hooks, the hook should call the
# clear_event() method on this object.
{
	# Keep the notifications hash in its own lexically scoped block so that
	# other's can't mess with it.
	my %notifications = (
		%{Prima::InputLine-> notification_types()},
		PressEnter => nt::Request,
		Evaluate => nt::Action,
		PostEval => nt::Request,
		TabComplete => nt::Request,
	);

	sub notification_types { return \%notifications }
}

# Simulates an Evaluate event with the supplied text. The default evaluation
# is pretty lame - it just prints the result of evaling the text using the
# print command.
sub evaluate {
	my ($self, $text) = @_;
	$_[0]->notify('Evaluate', $text);
}
sub on_evaluate {
	my ($self, $text) = @_;
	my $results = eval ($text);
	$self->outputHandler->newline_printout($results) if defined $results;
	$self->outputHandler->newline_printout('undef') if not defined $results;
}

# This is the method to kick-off tab completion. It splits the input line's
# text into left, selected, and right, and issues the notification with
# these three pieces of text.
sub do_tab_complete {
	my $self = shift;
	# Get the text in three buckets: left of selection, selection, and
	# right of selection.
	my ($start, $stop) = $self->selection;
	my $text = $self->text;
	my $left = substr $text, 0, $start;
	my $selected = substr $text, $start, $stop - $start;
	my $right = substr $text, $stop;

	$self->tab_complete($left, $selected, $right);
}

sub tab_complete {
	my $self = shift;
	croak('tab_complete needs three arguments') unless @_ == 3;

	# Issue the notification
	$self->notify('TabComplete', @_);
}

# Simulates/initiates the PressEnter notification, which starts with the
# class's method. Evaluation can be prevented by a handler by calling the
# clear_event method on the InputHistory object from within the handler.
sub press_enter {
	my ($self, $text) = @_;
	# Call the hooks, allowing them to modify the text as they go:
	my $needs_to_eval = $self->notify(PressEnter => $text);
	$self->notify(Evaluate => $text) if $needs_to_eval;
	$self->notify('PostEval');
}

# This is the object's default method for handling PressEnter events. Its
# job is to handle all of the history-related munging. It does not change
# the contents of the text, so it is safe to unpack the text. Because this
# the class's default handler, it always gets called first; derived classes
# that want to provide different default behavior must be sure to handle the
# history corretly, or call this (SUPER) method.
#
# Additional PressEnter handlers are called after this one and can be added
# with $input_widget->add_notification(PressEnter => sub {});
sub on_pressenter {
	my ($self, $text) = @_;

	# Remove the endlines, if present, replacing them with safe whitespace:
	$text =~ s/\n/ /g;

	# Reset the current collection of revisions:
	$self->{currentRevisions} = [];

	# print this line:
	$self->outputHandler->command_printout($text);

	# We are about to add this text to the history. Before doing so, check if
	# the history needs to be modified before performing the add:
	if ($self->storeType == ih::NoRepeat
		and defined $self->history->[-1]
		and $self->history->[-1] eq $text
	) {
		# remove the previous entry if it's identical to this one:
		pop @{$self->history};
	}
	elsif ($self->storeType == ih::Unique) {
		# Remove all the other identical entries if they are the same is this:
		$self->history([ grep {$text ne $_} @{$self->history} ]);
	}

	# Add the text as the last element in the entry:
	push @{$self->history}, $text;

	# Remove the text from the entry
	$self->text('');

	# Set the current line to the last one:
	$self->{currentLine} = 0;
}

1;

__END__

=head1 NAME

Prima::InputHistory - an input line with evaluation, input history
navigation, and tab completion hooks

=head1 SYNOPSIS

 use strict;
 use warnings;
 use Prima qw(Application InputHistory);

 # A simple repl that prints the output to the screen

 my $window = Prima::MainWindow->new(
     text => 'Simpe REPL',
     width => 600,
 );

 my $file_name = 'my_history.txt';
 my $history_file_length = 10;
 my $inline = Prima::InputHistory->create(
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

         # Restore the history from the saved file
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
         $offset = @history - $history_file_length
             if (@history > $history_file_length);
         while ($offset < @history) {
             print $fh $history[$offset++], "\n";
         }
         close $fh;
     },
 );

 print "Press Up/Down, Page-Up/Page-Down to see your input history\n";

 run Prima;

=head1 DESCRIPTION

C<Prima::InputHistory> is like a normal L<InputLine|Prima::InputLine> that
also knows about user input history. Although originally written as part of
a REPL (Run-Eval-Print-Loop), this can be useful for any sort of input where
a user may want to refer to previous input values. The most common examples
of input history are the URL and search input lines in browsers. Also, most
console prompts allow you to go back through commands already typed using
cursor keys for navigation. Many console prompts support filename or command
completion when you press the "Tab" key.

The widget is designed with full REPL interests in mind but can easily be
tweaked or streamlined to fit a wide variety of input history and user
interaction. Supported concepts include:

=over

=item How do we track input history?

Do you want to track every entry, or just the unique entries? Or perhaps you
just want to suppress consecutive duplicates?

=item Which way is history?

You can choose whether your user presses "up" or "down" to get to previous
commands.

=item How do we tab-complete?

The widget is sensitive to the user pressing the "Tab" key and you can add
custom hooks for tab completion.

=item What to do when the user presses Enter?

How do you want to respond when the use finally says "Go"? C<InputHistory>
implements a three-stage command execution chain, providing extensive
control and flexibility.

=item What results do we print, and where?

REPLS usually show what was typed and how the system responded. Command
prompts typically only show what was typed and what was printed during the
execution of the command, suppressing the return value. Browser URL bars do
not need any this.

=back

By allowing you to provide distinct answers to all of these questions,
C<InputHistory> provides a powerful widget for line-based user interaction.

=head2 History and Navigation

Previous entries are stored in the L<history|/history> property, which is
simply an arrayref of strings. The history is collected in chronological
order, which means that these will print the oldest and most recent commands:

 print "print oldest command in history: ", $widget->history->[0], "\n";
 print "most recent command: ", $widget->history->[-1], "\n";

By pressing the "Up", "Down", "PageUp", and "PageDown" keys, the user
can change the contents of their L<InputLine|/Prima::InputLine> to show what
they have already typed. They can alter these lines and press "Enter" to
issue a new command. The modified line will be added to the bottom of the
historical record, but the modifications will not alter the historical
record of previous commands. The C<move_line> method provides programmatic
interaction similar to the keyboard navigation, and you can programmatically
issue a C<PressEnter> event, too:

 Keyboard Input   Equivalent Method Call
 --------------   --------------------------
 Up               $widget->move_line('up')
 Down             $widget->move_line('down')
 PageUp           $widget->move_line('pgup')
 PageDown         $widget->move_line('pgdn')
 Enter/Return     $widget->PressEnter

The C<move_line> method also accepts numerical input. Positive numbers move
the user's inputline deeper into the historical record, and negative numbers
move the user's inputline closer to the most recent commands. Similarly,
you can set the L</currentLine> to indicate which line in history you
want to view, B<relative to the most recent command>:

 # Select most recently executed command
 $widget->currentLine(1);
 # Select next most recently executed commnad
 $widget->currentLine(2);

 # If the use typed anything before navigating
 # through history, this restores that text:
 $widget->currentLine(0);

=head2 Tab Completion

L<Tab completion|/TabComplete> is activated by pressing the "Tab" key. Tab
completion does nothing by default. If you wish to add a tab completion
callback, you should register your callback functions with the widget. See
the event documentation for more details.

=head2 Output Handling

Compared to other Prima widgets, this one is a bit unusual in that it uses
the Visitor Design Pattern for the output handling. This approach provides
useful defaults, an easy way to turn things off, and a general mechanism to
provide sophisticated handling if so desired. To change the output handling,
you set the L<outputHandler|/outputHandler> property to an object that
has methods C<command_printout> and C<newline_printout>. Alternatively, you
can specify one of the two output handler constants, either C<ih::StdOut> or
C<ih::Null>, and the appropriate handler object will be built for
you. The C<command_printout> method is called with the original text when
the user first presses "Enter", and is meant to allow the output system to
signify the command in a special way. All results are printed using
C<newline_printout>, which are supposed to show the output on a new line.

=head1 API

As with all other Prima widgets, you can control the behavior of the widget
both by modifying various properties and by providing custom callbacks. You
can also interact with the widget programmatically by getting and setting
properties as well as issuing events.

=head2 Properties

=over

=item currentLine

The current line from the history being displayed or edited, or 0 if the
user is entering text on a new line. You can use this as an accessor to determine if
the user is currently examining a line from their history, and you can set
this value to programmatically move the user to a specific point in their
history. You cannot set this at object construction time.

=item currentRevisions

If a user begins to type something, scrolls up through history to check
something, and scrolls back to resume typing, they expect to see their
previously typed work reappear. These modifications are stored for every
line of the history in this arrayref and are reset when the user issues a
command. You cannot set this at object construction time.

=item history

The previous entries are kept in this arrayref. It is never modified by the
user when they scroll through their history and modify what they see; such
changes are stored in L<currentRevisions|/currentRevisions>. You can set
this at object construction time, although the L<SYNOPSIS|/SYNOPSIS>
demonstrates how waiting until creation time can, in some ways, provide a
cleaner approach.

=item outputHandler

The object for handling REPL output. As discussed in the
L<DESCRIPTION|/DESCRIPTION>, you can specify the constants C<ih::Null> if
you do not want any output handling, C<ih::StdOut> for printing output to
the standard output, or an object that can C<command_printout> and
C<newline_printout>. This can (and probably should) be set during object
construction time; the default is C<ih::StdOut>.

=item pageLines

When the user presses Page-Up or Page-Down, they are moved through their
history. This number determines how far they move through the history. This
can be set at object construction time and has a default value of 10.

=item pastIs

Set this value to C<ih::Up> or C<ih::Down> to indicate which key the user
should press to move further back in time. The default is C<ih::Down>. This
can be set during object construction.

=item storeType

The storeType can be one of C<ih::All> if you want every command to be
stored sequentially (including repetitions), C<ih::Unique> if you want to
store all commands only once (sorted by the most recent appearance), or
C<ih::NoRepeat> if you want to store every command sequentially, but
compress repeated commands to a single entry in the history. This can be
set at object construction time and defaults to C<ih::All>.

Note: it seems to me that this should also be open to taking a subref,
which would perform whatever custom filter/sort is desired. Presently, this
setting effects B<how a command is inserted into storage> and it is called
just after the user presses enter. In other words, this is not a replacement
for autocompletion.

=back

=head2 Methods

=over

=item evaluate

Accepts a string and runs the L<Evaluate|/Evaluate> event with the given
string rather than the (PressEnter munged) contents of the C<InputHistory>.

=item move_line

This method moves through history using (possibly named) relative moves.
Positive numbers move back in time, negative numbers move forward in time.
(Yeah, it's kinda weird, but it makes the rest of it eaiser. I swear.)
Calling C<move_line> with 1 will move back in history by one step.

The meaning of up and down as forward or backward in time depends on your
needs, and how you reflect those needs in your L<pastIs|/pastIs> property.
However, having set L<pastIs|/pastIs> to either C<ih::Up> or C<ih::Down>,
you can call C<move_line> with the strings 'up', 'down', 'pgup', or 'pgdn'
and get the correct behavior.

=item press_enter

Accepts a string and runs the L<PressEnter|/PressEnter> chain of events with
the given string rather than the contents of the C<InputHistory>.

=item tab_complete

Accepts three strings, one each for the left, selection, and right, and runs
the L<TabComplete|/TabComplete> event with the given strings.

=back

=head2 Events

The events are listed in reverse alphabetical order, which is also roughly
the order in which the user will experience them:

=over

=item TabComplete

This notification is called when the user presses the Tab key or when you
manually issue a C<TabComplete> notification. This calls any and all
callbacks that have been registered under this event. Such callbacks are
passed the C<InputHistory> object as well as three pieces of text: the text
to the left of the current selection, the current selection, and the text to
the right of the current selection. If there is no selection, the second
argument is an empty string.

If you decide to write a callback for tab completion, you should probably
adjust your behavior based on whether or not something is selected. Also,
if you decide to update the text, you should do so by modifying the widget's
text property, and you should probably clear the event:

 # Add a naive file completion
 $widget->add_notification(TabComplete => sub {
     my ($self, $left, $selection, $right) = @_;

     # Are there any files that match the description?
     # If not, let the remaining notifications have their say.
     my @files = glob("$selection*");
     return unless @files;

     # We found something, so clear the event
     $self->clear_event;

     if (@files == 1) {
         # If there's only one item, complete it
         $self->text($left . $files[0] . $right);
         # Put the cursor at the end of the filename
         $self->charOffset(length($left . $files[0]));
     }
     else {
     	 # Otherwise print the options
     	 $self->outputHandler->newline_printout(
     	     join(' | ', @files));
     }
 });

Of course, this isn't quite as friendly as a tab completion that figures out
what the user is trying to complete based on the cursor's location instead
of the cursor's selection. It also doesn't do nice things like fill in text
that all of the elements share, such as converting 'Bui' to 'Build' if both
'Build' and 'Build.PL' are in the current directory. But it's a start.

=item PressEnter

This notification is called as soon as the user presses Enter or after you
invoke the C<PressEnter> method. It clears the input line's text field,
sends a command printout of the text to the output widget, and
fires all notifications that this widget has registered with the
C<PressEnter> notification, in order of registration. (Specifically, it is
an L<nt::Request notification|Prima::Object/Execution control>.) Then,
unless one of the C<PressEnter> callbacks
L<clears the event|Prima::Object/clear_event>, this issues the callbacks
for L<Evaluate|/Evaluate>. It finishes by issuing the callbacks for
L<PostEval|/PostEval>, which get called regardless of whether the event was
cleared or not.

If you register callbacks under this event, they will receive two arguments,
the InputHistory widget and the current text being processed. By modifying
the second argument directly, your event handler can modify the text that
gets propogated to the remaining C<PressEnter> event callbacks and the
L<Evaluate|/Evaluate> event. It can also prevent further processing by
L<clearing the event|Prima::Object/clear_event>, which is helpful for
creatomg specially parsed commands.

=item Evaluate

This notification is called after all of the L<PressEnter|/PressEnter>
notifications have run, or when you invoke the C<Evaluate> method. This is
an L<nt::Action notification|Prima::Object/Execution control>, which means
that if you specify a callback for this event, it overrides the default.

The default behavior is a simple Perl string eval of the contents it
receives (which is the text from the InputLine with any modifications made
by L<PressEnter|/PressEnter> notifications). It then prints the results to
the output widget by calling C<newline_printout> with the returned result,
or the string C<'undef'> if there was no returned result.

Note that directly invoking the C<Evaluate> method bypasses the
L<PressEnter|/PressEnter> series of notifications and avoids the post-eval
notifications, too. If callbacks under these notifications perform any
special command handling, which is the case with L<App::Prima::REPL>, you
will not get those preprocessings. Only call this if you know that you do
not want to have any of the command preprocessing or post-eval performed.

=item PostEval

This notification is called as the last step of the L<PressEnter|/PressEnter>
chain, or when you invoke the C<PostEval> method. This method is not given
any arguments, it is simply called for cleanup. (If you need to know what
was issued in the L<PressEnter|/PressEnter> call that preceeded this, you
can include a L<PressEnter|/PressEnter> event that stores it in a closed-over
variable that is also accessible to your C<PostEval> callback.) This is an
L<nt::Request notification|Prima::Object/Execution control>, so C<PostEval>
events are issued in the order in which they are registered.

=back

=head1 BUGS AND LIMITATIONS

Are there bugs in this module? Probably. If you find one please let me know!
You can report bugs to L<https://github.com/run4flat/App-Prima-REPL/issues>.

=head1 SEE ALSO

This module is distributed as part of L<App::Prima::REPL>, a graphical
run-eval-print-loop written using the L<Prima> GUI toolkit. It is built atop
L<Prima::InputLine>, so you may want to check that out if you are looking
for a way to get this sort of input from the user, but don't need any sort
of history tracking or navigation.

=head1 AUTHOR

This module was written by David Mertens (dcmertens.perl@gmail.com).

=head1 LICENSE AND COPYRIGHT

Portions of this module's code are copyright (c) 2011 The Board of Trustees
at the University of Illinois.

Portions of this module's code are copyright (c) 2011-2013 Northwestern
University.

This module's documentation is copyright (c) 2011-2013 David Mertens.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
