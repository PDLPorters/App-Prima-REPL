#!/usr/bin/perl
use strict;
use warnings;

use Prima;
use Prima::Buttons;
use Prima::Notebooks;
use Prima::ScrollWidget;
use Prima::Application;
use Prima::InputLine;
use Prima::Edit;
use Prima::PodView;
use Prima::FileDialog;
use Prima::ImageViewer;
use Carp;
use File::Spec;
use FindBin;

# Load PDL if they have it
my $loaded_PDL;
BEGIN {
	$loaded_PDL = 0;
	eval {
		require PDL;
		PDL->import;
		require PDL::NiceSlice;
		$loaded_PDL = 1;
	};
	print $@ if $@;
}

my $app_filename = File::Spec->catfile($FindBin::Bin, $FindBin::Script);
my $version = 0.1;

##########################
# Initialize the history #
##########################
my @history;
my $current_line = 0;
my $last_line = 0;

if (-f 'prima-repl.history') {
	open my $fh, '<', 'prima-repl.history';
	while (<$fh>) {
		chomp;
		push @history, $_;
	}
	close $fh;
}
# Set the current and last line to the end of the history:
$current_line = $last_line = @history;

# An important io function:
sub say {
	# print a newline if nothing is provided.
	if (@_ == 0) {
		print "\n";
		return;
	}
	# Examine the last element of @_:
	my $last_arg = pop;
	$last_arg .= "\n" unless $last_arg =~ /\n$/;
	print (@_, $last_arg);
}

# Save the last 200 lines in the history file:
END {
	open my $fh, '>', 'prima-repl.history';
	# Only store the last 200:
	my $offset = 0;
	$offset = @history - 200 if (@history > 200);
	while ($offset < @history) {
		print $fh $history[$offset++], "\n";
	}
	close $fh;
}

my @file_extension_list = (
		  ['Perl scripts'		=> '*.pl'	]
		, ['PDL modules'		=> '*.pdl'	]
		, ['Perl modules'		=> '*.pm'	]
		, ['POD documents'	=> '*.pod'		]
		, ['Test suite'		=> '*.t'		]
		, ['All'				=> '*'		]
);


# Very handy functions that I use throughout, but which I define later.
sub goto_page;
sub goto_output;


my $padding = 10;
my $window = Prima::MainWindow->new(
	pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
	text => 'Prima REPL',
	size => [600, 600], 
);
	# Add a notbook with output and help tabs:
	my $notebook = $window->insert(TabbedScrollNotebook =>
		pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
		tabs => ['Output'],
		style => tns::Simple,
	);
		my $output = $notebook->insert_to_page(0, Edit =>
			pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
			text => '',
			cursorWrap => 1,
			wordWrap => 1,
			readOnly => 1,
			backColor => cl::LightGray,
		);
		# Over-ride the defaults for these:
		$output->accelTable->insert([
			  ['', '', km::Ctrl | kb::PageUp,	\&goto_prev_page	]	# previous
			, ['', '', km::Ctrl | kb::PageDown,	\&goto_next_page	]	# next
		], '', 0);

	# Add the eval line:
	my $inline = $window->insert( InputLine =>
		text => '',
		pack => {fill => 'both', after => $notebook, padx => $padding, pady => $padding},
		accelItems => [
			# Enter runs the line
			  ['', '', kb::Return, \&pressed_enter]
			, ['', '', kb::Enter, \&pressed_enter]
			# Ctrl-Shift-Enter runs and goes to the output window
			, ['', '', kb::Return | km::Ctrl | km::Shift,	sub{ goto_output; pressed_enter()}	]
			, ['', '', kb::Enter  | km::Ctrl | km::Shift,	sub{ goto_output; pressed_enter()}	]
			# Navigation scrolls through the command history
			, ['', '', kb::Up, sub {set_new_line($current_line - 1)}]
			, ['', '', kb::Down, sub {set_new_line($current_line + 1)}]
			, ['', '', kb::PageUp, sub {set_new_line($current_line - 10)}]
			, ['', '', kb::PageDown, sub {set_new_line($current_line + 10)}]
			# Ctrl-i selects the default widget (the editor for edit tabs)
			, ['', '', km::Ctrl | ord 'i', sub {goto_page $notebook->pageIndex}]
		],
	);
	# give it the focus at the start
	$inline->select;

# A dialog box that will be used for opening and saving files:
my $open_dialog = Prima::OpenDialog-> new(filter => \@file_extension_list);


# The list of default widgets for each page. Output defaults to the evaluation
# line:
my @default_widget_for = ($inline);

sub goto_page {
	my $page = shift;
	$page = 0 if $page >= $notebook->pageCount;
	$page = $notebook->pageCount - 1 if $page == -1;
	# Make sure the page exists (problems could arrise using Alt-9, for example)
	if ($page < $notebook->pageCount) {
		$notebook->pageIndex($page);
		$default_widget_for[$page]->select;
	}
	# Silently ignore if the page does not exist
}

sub goto_next_page {
	goto_page $notebook->pageIndex + 1;
}
sub goto_prev_page {
	goto_page $notebook->pageIndex - 1;
}
sub goto_output {
	goto_page 0;
}
sub get_help {
	# There can be multiple help windows open, so don't try to display the
	# 'current' help window, since that is not well defined. Instead, open a
	# new one with this application's documentation:
	my $module = shift;
	if ($module) {
		# If a module name was passed, open it:
		say "Opening the documentation for $module";
		$::application->open_help($module);
	}
	else {
		# Otherwise, open this application's documentation:
		$::application->open_help($app_filename);
	}
	# Make sure the the opened help is visible
	$::application->get_active_window->bring_to_front;
}

# Add some accelerator keys to the window for easier navigaton:
$window->accelItems([
	  ['', '', km::Ctrl | ord 'i',	sub {$inline->select}	]	# input line
	, ['', '', km::Alt  | ord '1',		sub {goto_output}	]	# output page
	, ['', '', km::Ctrl | ord 'h',		sub {get_help}		]	# help
	, ['', '', km::Alt  | ord '2',		sub {goto_page 1}	]	# help (page 2)
	, ['', '', km::Alt  | ord '3',		sub {goto_page 2}	]	# page 3
	, ['', '', km::Alt  | ord '4',		sub {goto_page 3}	]	# .
	, ['', '', km::Alt  | ord '5',		sub {goto_page 4}	]	# .
	, ['', '', km::Alt  | ord '6',		sub {goto_page 5}	]	# .
	, ['', '', km::Alt  | ord '7',		sub {goto_page 6}	]	# .
	, ['', '', km::Alt  | ord '8',		sub {goto_page 7}	]	# .
	, ['', '', km::Alt  | ord '9',		sub {goto_page 8}	]	# page 8
	, ['', '', km::Ctrl | kb::PageUp,	\&goto_prev_page	]	# previous
	, ['', '', km::Ctrl | kb::PageDown,	\&goto_next_page	]	# next
	, ['', '', km::Ctrl | ord 'n',		sub {new_file()}	]	# new tab
	, ['', '', km::Ctrl | ord 'w',		sub {close_file()}	]	# close tab
	, ['', '', km::Ctrl | ord 'o',		sub {open_file()}	]	# open file
	, ['', '', km::Ctrl | ord 'S',		sub {save_file()}	]	# save file
]);

# Creates a new text-editor tab and selects it
sub new_file {
	my $page_no = $notebook->pageCount;
	my $name = shift || '';
	# Add the tab number to the name:
	$name .= ', ' if $name;
	$name .= '#' . ($page_no + 1);

	my @tabs = @{$notebook->tabs};
	$notebook->tabs([@tabs, $name]);
	my $page_widget = $notebook->insert_to_page(-1, Edit =>
			text => '',
			pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
			# Allow for insertions, deletions, and newlines:
			tabIndent => 1,
			syntaxHilite => 1,
			wantTabs => 1,
			wantReturns => 1,
			wordWrap => 0,
			autoIndent => 1,
			cursorWrap => 1,
		);

	# Update the accelerators.
	my $accTable = $page_widget->accelTable;

	# Add some functions to the accelerator table
	$accTable->insert([
		# Ctrl-Enter runs the file
		  ['', '', kb::Return 	| km::Ctrl,  sub{run_file()}				]
		, ['', '', kb::Enter  	| km::Ctrl,  sub{run_file()}				]
		# Ctrl-Shift-Enter runs the file and selects the output window
		, ['', '', kb::Return 	| km::Ctrl | km::Shift,	\&run_file_with_output	]
		, ['', '', kb::Enter  	| km::Ctrl | km::Shift,	\&run_file_with_output	]
		# Ctrl-PageUp/PageDown don't work by default, so add them, too:
		, ['', '', kb::PageUp 	| km::Ctrl,  \&goto_prev_page				]
		, ['', '', kb::PageDown | km::Ctrl,  \&goto_next_page				]
		], '', 0);

	# Make the editor the default widget for this page.
	push @default_widget_for, $page_widget;
	
	# Go to this page:
	goto_page -1;
}

sub open_image {
	my $page_no = $notebook->pageCount;
	my $name = shift;
	if (not defined $name) {
		say "You must provide a filename to open.";
		return;
	}
	if (not -f $name) {
		say "Could not open file $name.";
		return;
	}
	
	# Open the image:
	my $image = Prima::Image-> load($name);
	
	# Add the tab number to the name:
	$name .= ', ' if $name;
	$name .= '#' . ($page_no + 1);

	# Add this tab to the list:
	my @tabs = @{$notebook->tabs};
	$notebook->tabs([@tabs, $name]);
	# Add this tab to the notebook:
	my $page_widget = $notebook->insert_to_page(-1, ImageViewer =>
		image => $image,
		allignment => ta::Center,
		vallignment => ta::Center,
		pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
		accelItems => [
		# F5 refreshes the image
			['', '', kb::F1, sub {
				print "args are: [[", join(']],[[', @_), "]]\n";
#				$image = Prima::Image->load($name);

			}]],
	);
	
	# Make inline the default widget for this page.
	push @default_widget_for, $inline;
	
	# Go to this page:
	goto_page -1;
}

sub run_file_with_output {
	my $current_page = $notebook->pageIndex + 1;
	goto_output;
	run_file($current_page);
}

# closes the tab number, or name if provided, or current if none is supplied
sub close_file {
	# Get the desired tab; default to current tab:
	my $to_close = shift || $notebook->pageIndex + 1;	# user counts from 1
	my @tabs = @{$notebook->tabs};
	if ($to_close =~ /^\d+$/) {
		$to_close--;	# correct user's offset by 1
		$to_close += $notebook->pageCount if $to_close < 0;
		# Check that a valid value is used:
		if ($to_close == 0) {
			say "You cannot remove the output tab";
			goto_output;
			return;
		}
		
		# Close the tab
		say "Not checking if the file needs to be saved, on line ", __LINE__
				, ". This should be fixed.";
		$notebook->{notebook}->delete_page($to_close);
		splice @tabs, $to_close, 1;
		splice @default_widget_for, $to_close, 1;
	}
	else {
		# Provided a name. Close all the tags with the given name:
		my $i = 1;	# Start at tab #2, so they can't close the Output tab
		$to_close = qr/$to_close/ unless ref($to_close) eq 'Regex';
		while ($i < @tabs) {
			if ($tabs[$i] eq $to_close) {
				say "Not checking if the file needs to be saved, on line "
						, __LINE__, ". This should be fixed.";
				$notebook->{notebook}->delete_page($_);
				splice @default_widget_for, $i, 1;
				splice @tabs, $i, 1;
				redo;
			}
			$i++;
		}
	}
	
	# Update the tab numbering:
	$tabs[$_-1] =~ s/\d+$/$_/ for (2..@tabs);
	
	# Finally, set the new, final names and select the default widget:
	$notebook->tabs(\@tabs);
	$default_widget_for[$notebook->pageIndex]->select;
}

# Opens a file (optional first argument, or uses a dialog box) and imports it
# into the current tab, or a new tab if they're at the output or help tabs:
sub open_file {
	my ($file, $dont_warn) = @_;
	my $page = $notebook->pageIndex;
	
	# Get the filename with a dialog if they didn't specify one:
	if (not $file) {
		# Return if they cancel out:
		return unless $open_dialog->execute;
		# Otherwise load the file:
		$file = $open_dialog->fileName;
	}
	
	# Extract the name and create a tab:
	(undef,undef,my $name) = File::Spec->splitpath( $file );
	if ($page == 0) {
		new_file ($name);
	}
	else {
		name($name);
	}
	
	say "Need to check the contents of the current tab before overwriting, "
			, "on line ", __LINE__, ". This should be fixed."
			unless $page == 0 or $dont_warn;
	
	# Load the contents of the file into the tab:
    open( my $fh, $file ) or return say "Couldn't open $file";
    my $text = do { local( $/ ) ; <$fh> } ;
    # Note that the default widget will always be an Edit object because if the
    # current tab was not an Edit object, a new tab will have been created and
    # selected.
    $default_widget_for[$notebook->pageIndex]->textRef(\$text);
}

# A file-opening function for initialization scripts
sub init_file {
	new_file;
	open_file @_, 1;
}

sub save_file {
	my $page = $notebook->pageIndex;
	
	# Get the filename as an argument or from a save-as dialog. This would work
	# better if it got instance data for the filename from the tab itself, but
	# that would require subclassing the editor, which I have not yet tried.
	my $filename = shift;
	unless ($filename) {
		my $save_dialog = Prima::SaveDialog-> new(filter => \@file_extension_list);
		# Return if they cancel out:
		return unless $save_dialog->execute;
		# Otherwise get the filename:
		$filename = $save_dialog->fileName;
	}
	
	# Open the file and save everything to it:
	open my $fh, '>', $filename;
	my $textRef;
	# working here - this could be done better (once default widgets are
	# actually subclassed, then this could be extended so that graphs could save
	# themselves, etc. In that case, the evaluation line would save the text of
	# output, since it is the default widget for the output tab.)
	if ($page == 0) {
		$textRef = $output->textRef;
	}
	else {
		$textRef = $default_widget_for[$notebook->pageIndex]->textRef;
	}
	print $fh $$textRef;
	close $fh;
}

# A function to run the contents of a multiline environment
sub run_file {
	my $page = shift || $notebook->pageIndex + 1;
	$page--;	# user starts counting at 1, not 0
	croak("Can't run output page!") if $page == 0;
	
	# Get the text from the multiline and run it:
	my $text = $default_widget_for[$page]->text;

	my_eval($text);

	# If error, switch to the console and print it to the output:
	if ($@) {
		my $tabs = $notebook->tabs;
		my $header = "----- Error running ". $tabs->[$page]. " -----";
		say $header;
		say $@;
		say '-' x length $header;
		$@ = '';
		goto_output;
	}
}

# Change the name of a tab
sub name {
	my $name = shift;
	my $page = shift || $notebook->pageIndex + 1;
	my $tabs = $notebook->tabs;
	$tabs->[$page - 1] = "$name, #$page";
	$notebook->tabs($tabs);
}

# Changes the contents of the evaluation line to the one stored in the history.
# This is used for the up/down key callbacks for the evaluation line. The
# current_revisions array holds the revisions to the history, and it is reset
# every time the user runs the evaluation line.
my @current_revisions;
sub set_new_line {
	my $requested_line = shift;
	
	# Get the current character offset:
	my $curr_offset = $inline->charOffset;
	# Note the end-of-line position by zero:
	$curr_offset = 0 if $curr_offset == length($inline->text);
	
	# Save changes to the current line in the revision list:
	$current_revisions[$last_line - $current_line] = $inline->text;
	
	# make sure the requested line makes sense:
	$requested_line = 0 if $requested_line < 0;
	$requested_line = $last_line if $requested_line > $last_line;
	
	$current_line = $requested_line;
	
	# Load the text using the Orcish Maneuver:
	my $new_text = $current_revisions[$last_line - $current_line]
						//= $history[$requested_line];
	$inline->text($new_text);
	
	# Put the cursor at the previous offset. However, if the previous offset
	# was zero, put the cursor at the end of the line:
	$inline->charOffset($curr_offset || length($new_text));
}


my $lexicals_allowed = 0;
sub allow_lexicals { $lexicals_allowed = 1 };

# convenience function for clearing the output:
my $output_line_number = 0;
my $output_column = 0;
sub clear {
	$output->text('');
	$output_line_number = 0;
	$output_column = 0;
}

# Evaluates the text in the input line
my $current_help_topic;
sub pressed_enter {
	# They pressed return. First extract the contents of the text.
	my $in_text = $inline->text;
	# Remove the endlines, if present:
	$in_text =~ s/\n//g;
	
	# Reset the current collection of revisions:
	@current_revisions = ();
	
	# print this line:
	print "\n" if $output_column != 0;
	say "> $in_text";

	# Add this line to the last line of the history if it's not a repeat:
	if (@history == 0 or $history[$last_line - 1] ne $in_text) {
		$history[$last_line] = $in_text ;
		$last_line++;
	}
	
	# Remove the text from the entry
	$inline->text('');
	
	# Set the current line to the last one:
	$current_line = $last_line;
	
	# Check for the help command. If they just type 'help', show them the
	# documentation for this application:
	if ($in_text =~ /^\s*help\s*(.*)/) {
		get_help($1);
	}
	elsif ($in_text =~ /^pdldoc\s+(.+)/) {
		# Run pdldoc and parse its output:
		my $results = `pdldoc $1`;
		if ($results =~ /No PDL docs/) {
			say $results;
			goto_output;
		}
		# If it found output, then extract the module name and the function
		# and go there:
		elsif ($results =~ /Module (PDL::[^\s]+)\n\s+(\w+)/) {
			my $module = $1;
			my $function = $2;
			# Show help:
			get_help("$module/$function");
		}
		else {
			say "Unable to parse the output of pdldoc:";
			say $results;
		}
	}
	elsif ($in_text =~ /^\s*pdldoc\s*$/) {
		say "Please specify a PDL function about which you want more information";
		goto_output;
	}
	elsif ($in_text =~ /^\s*exit\s*$/) {
		unlink 'prima-repl.logfile';
		exit;
	}
	else {
		# A command to be eval'd. Lexical variables don't work, so croak if I
		# see one. This could probably be handled better.
		if ($in_text =~ /my/ and not $lexicals_allowed) {
			$@ = join(' ', 'It looks to me like you\'re trying to use a lexical variable.'
					, 'Lexical variables not allowed in the line evaluator'
					, 'because you cannot get to them after the current line.'
					, 'If I\'m wrong, or if you really want to use lexical variables,'
					, "do this:\n"
					, "   allow_lexicals; <command-here>"
					);
		}
		else {
			my $text_to_eval = $in_text;
			# This appears to be giving trouble. Slices do not appear to be
			# evaluated correctly. working here
			$text_to_eval = PDL::NiceSlice->perldlpp($in_text) if ($loaded_PDL);
			my_eval($text_to_eval);
		}
	
		# If error, print that to the output
		if ($@) {
			say $@;
			# Add comment hashes to the beginning of the erroneous line:
			$history[$last_line - 1] = "#$in_text";
			$@ = '';
			goto_output;
		}
	}
	$lexicals_allowed = 0
}

sub my_eval {
	my $text = shift;
	# Gray the line entry:
	$inline->enabled(0);
	# replace the entry text with the text 'working...' and save the old stuff
	my $old_text = $inline->text;
	$inline->text('working ...');
	
	# Process the text with NiceSlice if they try to use it:
	if ($text =~ /use PDL::NiceSlice/) {
		if ($loaded_PDL) {
			$text = PDL::NiceSlice->perldlpp($text);
		}
		else {
			say "PDL did not load properly, so I can't apply NiceSlice to your code.";
			say "Don't be surprised if you get errors...";
		}
	}
	
	# Make sure any updates hit the screen before we get going:
	$::application->yield;
	# Run the stuff to be run:
	no strict;
	eval $text;
	use strict;
	# Re-enable input:
	$inline->enabled(1);
	$inline->text($old_text);
}

# A function called from eval'd code and/or the child process that tells the
# parent that it can re-enable input. This 
#sub allow_input

################################
# Output handling and mangling #
################################

# Set autoflush on stdout:
$|++;

# Convenience function for PDL folks.
# working here - change this to say
sub p {	say @_ }

# Useful function to simulate user input. This is useful for initialization
# scripts when you want to run commands and put them into the command history
sub simulate_run {
    my $command = shift;
    # Get the current content of the inline and cursor position:
    my $old_text = $inline->text;
    my $old_offset = $inline->charOffset;
    # Set the content to the new command:
    $inline->text($command);
    # run it:
    pressed_enter();
    # put the original content back on the inline:
    $inline->text($old_text);
    $inline->charOffset($old_offset);
}

# Here is a utility function to print to the output window. Both standard output
# and standard error are later tied to printing to this interface, so you can
# just use 'print' or 'say' in all your code and it'll go to this.

sub outwindow {
	# Join the arguments and split them at the newlines and carriage returns:
	my @lines = split /([\n\r])/, join('', @_);
	# Remove useless parts of error messages (which refer to lines in this code)
	s/ \(eval \d+\)// for @lines;
	# Open the logfile, which I'll print to simultaneously:
	open my $logfile, '>>', 'prima-repl.logfile';
	# Go through each line and carriage return, overwriting where appropriate:
	foreach(@lines) {
		# If it's a carriage return, set the current column to zero:
		if (/\r/) {
			$output_column = 0;
			print $logfile "\\r\n";
		}
		# If it's a newline, increment the output line and set the column to
		# zero:
		elsif (/\n/) {
			$output_column = 0;
			$output_line_number++;
			print $logfile "\n";
		}
		# Otherwise, add the text to the current line, starting at the current
		# column:
		else {
			my $current_text = $output->get_line($output_line_number);
			# If the current line is blank, set the text to $_:
			if (not $current_text) {
				$current_text = $_;
			}
			# Or, if the replacement text exceeds the current line's content,
			elsif (length($current_text) < length($_) + $output_column) {
				# Set the current line to contain everything up to the current
				# column, and append the next text:
				$current_text = substr($current_text, 0, $output_column) . $_;
			}
			# Or, replace the current line's text with the next text:
			else {
				substr($current_text, $output_column, length($_), $_);
			}
			$output->delete_line($output_line_number);
			$output->insert_line($output_line_number, $current_text);
			# increase the current column:
			$output_column += length($_);
		}
	}
	
	# close the logfile:
	close $logfile;
	
	# Let the application update itself:
	$::application->yield;

	# I'm not super-enthused with manually putting the cursor at the end of
	# the text, or with forcing the scrolling. I'd like to have some way to
	# determine if the text was already at the bottom, in which case I would
	# continue scrolling, if it was not, I would not scroll. But, I cannot find
	# how to do that at the moment, so it'll just force scroll with every
	# printout. working here:
	$output->cursor_cend;
}

# Redirect standard output using this filehandle tie. Thanks to 
# http://stackoverflow.com/questions/387702/how-can-i-hook-into-perls-print
# for this one.
package IO::OutWindow;
use base 'Tie::Handle';
use Symbol qw<geniosym>;
sub TIEHANDLE { return bless geniosym, __PACKAGE__ }

our $OLD_STDOUT;
sub PRINT {
    shift;
    main::outwindow(@_)
}

sub PRINTF {
	shift;
	my $to_print = sprintf(@_);
	main::outwindow(@_);
}

tie *PRINTOUT, 'IO::OutWindow';
# Redirect standard output and standard error to the PDL console:
$OLD_STDOUT = select( *PRINTOUT );
*STDERR = \*PRINTOUT;

package main;

eval 'require PDL::Version' if not defined $PDL::Version::VERSION;

# Print the opening message:
say "Welcome to the Prima REPL, version $version.\n";
say "Using PDL version $PDL::Version::VERSION\n" if ($loaded_PDL);
print "\n";
say join(' ', 'If you don\'t know what you\'re doing, you can get help by'
				, 'typing \'help\' and pressing Enter, or by pressing Ctrl-h');

#################################
# Run any initialization script #
#################################
sub redo_initrc {
	if (-f 'prima-repl.initrc') {
		say "Running initialization script";
		# Load the init script and send it to 
		open my $fh, '<', 'prima-repl.initrc';
		my $text = do { local( $/ ) ; <$fh> };
		my_eval($text);
		print "Errors encountered running the initialization script:\n$@\n"
			if $@;
		$@ = '';
	}
	else {
		say "No initialization script found";
	}
}
redo_initrc if -f 'prima-repl.initrc';

run Prima;
# Remove the logfile. This will not happen with a system failure, which means
# that the logfile is 'saved' only when there was a problem. The special case of
# the user typing 'exit' at the prompt is handled in pressed_enter().
unlink 'prima-repl.logfile';

__END__

=head1 Prima::REPL Help

This is the help documentation for  Prima::REPL, a graphical run-eval-print-loop
(REPL) for perl development, targeted at pdl users. Its focus is on L<PDL>, the
Perl Data Language, but it works just fine even if you don't have PDL.

Prima::REPL provides a tabbed environment with an output tab, a help tab, and
arbitrarily many file tabs. It also provides a single entry line at the bottom
of the window for direct command entry.

At this point, some links to further documentation would be appropriate, as well
as a tutorial.

In keeping with the text-based L<pdl> command provided with L<PDL>, this REPL
doesn't do the I<print> part, but I'll get to that in just a little bit.

This documentation is written assuming you have C<pdl-gui> installed on your
system and are reading it from the Help tab. You could also be reading this
from CPAN or L<perldoc>, but I will be giving many interactive examples and
would encourage you to install and run C<pdl-gui> so you can follow along. Note
you do not need L<PDL> installed to run C<pdl-gui>.

=head1 Fixing Documentation Fonts

If your documentation fonts look bad, you can change them by typing a command,
but I have not yet figured that out. Sorry.

 # need command here

=head1 Tutorial

First, you'll want to have an easy way to get back to this document when you
need help. To do that, simply type 'help' in the evaluation line at the bottom
of the screen. You can look at the pod documentation for any file in the help
tab by putting the module or file name after the help command, but typing help
by itself will always give you this document.

Go back to the output tab and type the following in the evaluation line:

 print "Hello, world!"

=head1 pdldoc

The following will print the results of a pdldoc command-line search to the
output window. The quotes are required:

 pdldoc 'command'

I may end up parsing the results of this command, opening the pod, and scrolling
to the specific location, but I've not figured it out yet.

=head1 PDL Debugging

To get PDL debugging statements, type the following in the evaluation line:

 $PDL::debug = 1

=head1 Navigation

=over

=item Ctrl-i

When you are viewing the Output or Help tabs, this key combination selects the
evaluation line. When you are in an edit tab, this key combination toggles
between the entry line and the text editor.

=item Alt-1, ..., Alt-9

Selects the tab with the associated number.

=back

=head1 Ideas

Provide a general interface for tab-specific command processing. That way,
help tabs can look at the command entry and if it just looks like a module,
it'll load the documentation. Otherwise it will pass the command on to the
normal command processing functionality. New tabs (via plugins) could then
provide new commands. (The difference between commands and plain-old functons
should be stressed somehow. Functions operate through simple evaluate, whereas
commands are pulled out and parsed. These concepts need to be cleaned up.)

