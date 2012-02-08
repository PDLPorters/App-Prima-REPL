#!/usr/bin/env perl
use strict;
use warnings;

use Prima qw(Buttons Notebooks ScrollWidget Application Edit
			FileDialog ImageViewer ImageDialog);
use Carp;
use File::Spec;
use FindBin;

#use InputHistory;
use PrimaX::InputHistory;
#use Eval::WithLexicals;

my $DEBUG_OUTPUT = 0;
my $initrc_filename = 'prima-repl.initrc';
# Load PDL if they have it
my ($loaded_PDL, $loaded_Prima_Graphics);
BEGIN {
	$loaded_PDL = 0;
	eval {
		require PDL;
		PDL->import;
		require PDL::NiceSlice;
		$loaded_PDL = 1;
	};
	print $@ if $@;
	
	# Load PDL::Graphics::Prima if they have it
	$loaded_Prima_Graphics = 0;
	eval {
		require PDL::Graphics::Prima;
		PDL::Graphics::Prima->import;
		require PDL::Graphics::Prima::Simple;
		PDL::Graphics::Prima::Simple->import;
		$loaded_Prima_Graphics = 1;
	};
	print $@ if $@;
}

my $app_filename = File::Spec->catfile($FindBin::Bin, $FindBin::Script);
my $version = 0.1;


#########################
# Main Application Code #
#########################

package REPL;

our @text_file_extension_list = (
		  ['Perl scripts'		=> '*.pl'	]
		, ['PDL modules'		=> '*.pdl'	]
		, ['Perl modules'		=> '*.pm'	]
		, ['POD documents'	=> '*.pod'		]
		, ['Test suite'		=> '*.t'		]
		, ['All'				=> '*'		]
);

# A dialog box that will be used for opening and saving files:
our $open_text_dialog = Prima::OpenDialog-> new(filter => \@text_file_extension_list);
our $open_dialog = Prima::OpenDialog->new(filter => [[All => '*']]);

# Very handy functions that I use throughout, but which I define later.
sub goto_page;
sub goto_output;
sub warn {
	chomp(my $text = join('', @_));
	warn $text . "\n";
	goto_output;
}

our $padding = 10;
our $window = Prima::MainWindow->new(
#	pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
	text => 'Prima REPL',
	size => [600, 600], 
);
	# Add a notbook with output tab:
	our $notebook = $window->insert(TabbedScrollNotebook =>
		pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
		tabs => ['Output'],
		style => tns::Simple,
	);
		our $output = $notebook->insert_to_page(0, Edit =>
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
	our $inline = PrimaX::InputHistory->create(
		owner => $window,
		text => '',
		pack => {fill => 'both', after => $notebook, padx => $padding, pady => $padding},
		fileName => '.prima.repl.history',
		storeType => ih::NoRepeat,
	);
	# Add the special accelerators seperately:
	# Update the accelerators.
	my $accTable = $inline->accelTable;

	# Add some functions to the accelerator table
	$accTable->insert([
		# Ctrl-Shift-Enter runs and goes to the output window
		  ['', '', kb::Return | km::Ctrl | km::Shift,	sub{ goto_output; $_[0]->PressEnter}	]
		, ['', '', kb::Enter  | km::Ctrl | km::Shift,	sub{ goto_output; $_[0]->PressEnter}	]
		# Ctrl-i selects the default widget (the editor for edit tabs)
		, ['', '', km::Ctrl | ord 'i', sub {goto_page $notebook->pageIndex}]
	], '', 0);

	# give it the focus at the start
	$inline->select;
	# Add some hooks to process help, pdldoc, and niceslicing:
	# working here:

# The list of default widgets for each page. Output defaults to the evaluation
# line:
our @default_widget_for = ($inline);

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
		print "Opening the documentation for $module\n";
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
	, ['', '', km::Ctrl | ord 'n',		sub {main::new_file()}	]	# new tab
	, ['', '', km::Ctrl | ord 'w',		sub {close_tab()}	]	# close tab
	, ['', '', km::Ctrl | ord 'o',		sub {main::open_file()}	]	# open file
	, ['', '', km::Ctrl | ord 'S',		sub {main::save_file()}	]	# save file
]);

################################################################################
# Usage      : REPL::create_new_tab($name, @creation_options)
# Purpose    : creates a new tab based on the supplied creation options
# Returns    : the page widget; also returns the tab index in list context
# Parameters : the tab's name
#            : a collection of arguments for the widget creation
# Throws     : never
# Comments   : the default widget for the new tab is the inline widget, but this
#            : can be changed using REPL::change_default_widget()
#            : to display the new tab, use REPL::goto_page(-1);
################################################################################
sub create_new_tab {
	my ($name, @options) = @_;
	my $page_no = $REPL::notebook->pageCount;
	# Add the tab number to the name:
	$name .= ', ' if $name;
	$name .= '#' . ($page_no + 1);

	my @tabs = @{$notebook->tabs};
	$notebook->tabs([@tabs, $name]);
	
	my $page_widget = $notebook->insert_to_page(-1, @options);

	# Make the editor the default widget for this page.
	push @default_widget_for, $inline;
	
	# Return the page widget and page number if they expect multiple return
	# values; or just the page widget.
	return ($page_widget, $page_no) if wantarray;
	return $page_widget if defined wantarray;
}

################################################################################
# Usage      : REPL::change_default_widget($index, $widget)
# Purpose    : changes the default widget for the tab with the given index
# Returns    : nothing
# Parameters : the tab's index (returned in list context from create_new_tab)
#            : the widget to get attention when CTRL-i is pressed
# Throws     : never
# Comments   : none
################################################################################
sub change_default_widget {
	my ($index, $widget) = @_;
	$default_widget_for[$index] = $widget;
}

# closes the tab number, or name if provided, or current if none is supplied
# ENCOUNTERIMG TROUBLE WITH THIS, working here
sub close_tab {
	# Get the desired tab; default to current tab:
	my $to_close = shift || $notebook->pageIndex + 1;	# user counts from 1
	my @tabs = @{$notebook->tabs};
	if ($to_close =~ /^\d+$/) {
		$to_close--;	# correct user's offset by 1
		$to_close += $notebook->pageCount if $to_close < 0;
		# Check that a valid value is used:
		return REPL::warn("You cannot remove the output tab")
			if $to_close == 0;
		
		# Close the tab
		CORE::warn "Internal: Not checking if the file needs to be saved.";
		splice @tabs, $to_close, 1;
		splice @default_widget_for, $to_close, 1;
		$notebook->Notebook->delete_page($to_close);
	}
	else {
		# Provided a name. Close all the tags with the given name:
		my $i = 1;	# Start at tab #2, so they can't close the Output tab
		$to_close = qr/$to_close/ unless ref($to_close) eq 'Regex';
		while ($i < @tabs) {
			if ($tabs[$i] eq $to_close) {
				CORE::warn "Internal: Not checking if the file needs to be saved.";
				$notebook->Notebook->delete_page($_);
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

#######################################
# Input line PressEnter notifications #
#######################################

# The PressEnter event goes as follows:
# 1) User presses enter
# 2) Text gets stored in InputHistory widget and widget's text is cleared
# 3) All other PressEnter notifications are called
# 4) If none of the notifications cleared the event, the (possibly modified)
#    text is eval'd.
#
# In order to modify the text that gets processed and eval'd, these methods
# should directly modify $_[1]. To prevent the eval of the text, call the
# clear_event() method on the first argument, as:
#   $_[0]->clear_event;

# The second argument is the text. If I wish to modify the text, I need to
# update $_[1] directly. This will update the text 

# Graying out the input widget. This is re-enabled in the post-eval stage:
$inline->add_notification(PressEnter => sub {
	$inline->enabled(0);
});
$inline->add_notification(PostEval => sub {
	$inline->enabled(1);
});

# The help command:
$inline->add_notification(PressEnter => sub {
	# See if they asked for help.
	if ($_[1] =~ /^\s*help\s*(.*)/) {
		get_help($1);
		$_[0]->clear_event;
	}
});

# pdldoc support:
$inline->add_notification(PressEnter => sub {
	return unless $_[1] =~ /^\s*pdldoc/;
	
	# Clear the event so that the text is not processed:
	$_[0]->clear_event;

	if ($_[1] =~ /^\s*pdldoc\s+(.+)/) {
		# Run pdldoc and parse its output:
		my $results = `pdldoc $1`;
		if ($results =~ /No PDL docs/) {
			REPL::warn($results);
		}
		# If it found output, then extract the module name and the function
		# and go there:
		elsif ($results =~ /Module (PDL::[^\s]+)\n\s+(\w+)/) {
			my $module = $1;
			my $function = $2;
			# Show help:
			get_help("$module/$function");
		}
		elsif ($results =~ /NAME\s+([^\s]+)/) {
			# We're looking at a full module's documentation. Feed the module
			# to the pod viewer:
			get_help("$1");
		}
		else {
			REPL::warn("Unable to parse the output of pdldoc:\n", $results);
		}
	}
	else {
		REPL::warn("Please specify a PDL function about which you want more information");
	}
});

# logfile handling for the exit command:
$inline->add_notification(PressEnter => sub {
	if ($_[1] =~ /^\s*exit\s*$/) {
		unlink 'prima-repl.logfile';
		exit;
	}
});

###############################################################################
#             PDL::Graphics::Prima::Simple handling and emulation             #
###############################################################################

our @default_sizes = (400, 400);
# Add emulation for PDL::Graphics::Prima::Simple
$inline->add_notification(PressEnter => sub {
	my $packagename = 'PDL::Graphics::Prima::Simple';
	return unless index($_[1], $packagename) > 0;
	my $text = $_[1];
	if ($text =~ /^\s*use $packagename(.*)/) {
		$inline->clear_event;
		my @args = eval $1 if $1;
		our $emulate_simple = 1;
		for my $arg (@args) {
			# Ignore everything except an array ref with bounds
			if(ref ($arg) and ref($arg) eq 'ARRAY') {
				# Make sure it is the correct size:
				REPL::warn("Array references passed to $packagename indicate the\n"
					. "desired plot window size and must contain two elements")
					unless @$arg == 2;
				
				# Apparently we're good to go so save the sizes:
				@default_sizes = @$arg;
			}
		}
	}
	elsif ($text =~ /^\s*no $packagename/) {
		our $emulate_simple = 0;
		$inline->clear_event
	}
});

# Override PDL::Graphics::Prima::Simple::plot

no warnings 'redefine';
sub PDL::Graphics::Prima::Simple::plot {
	# Make sure PDL::Graphics::Prima is loaded and they provided good arguments
	return REPL::warn "PDL::Graphics::Prima did not load successfully!"
		if not $loaded_Prima_Graphics;
	return REPL::warn "prima_plot expects a collection of key => value pairs, but you sent"
		. " an odd number of arguments!" if @_ % 2 == 1;
	
	# Get the plotting arguments and supply a meaningful default pack:
	my %args = (
		pack => { fill => 'both', expand => 1},
		@_,
	);
	
	# Create the plotter, go to the tab, and return the plotter
	my $plotter;
	if ($REPL::emulate_simple) {
		$plotter = Prima::Window->create(
			text  => $args{title} || 'PDL::Graphics::Prima',
			size  => $args{size} || [@REPL::default_sizes],
		)->insert('Plot',
			pack => { fill => 'both', expand => 1},
			%args
		);
	}
	else {
		# Figure out the plot name:
		my $name = $args{title} || 'Plot';
		# Build the plot tab and switch to it:
		$plotter = REPL::create_new_tab($name, Plot => %args);
		REPL::goto_page -1;
	}
	return $plotter;
}
*main::plot = \&PDL::Graphics::Prima::Simple::plot;
use warnings 'redefine';

################################################################################
#                                Handling Evals                                #
################################################################################

$inline->add_notification(Evaluate => sub {
	main::my_eval($_[1]);
});

=for consideration
# I used to issue warnings when I found 'my' in the text to be eval'd. This was
# a means to allow for such lexical variables, but I've decided to not even
# worry about it.
#my $lexicals_allowed = 0;
#sub allow_lexicals { $lexicals_allowed = 1 };
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
			main::my_eval($text_to_eval);
		}
	
		# If error, print that to the output
		if ($@) {
			REPL::warn($@);
			$@ = '';
		}
	}
	$lexicals_allowed = 0
	
});

=cut

###############################################
# Various API and useful function definitions #
###############################################

package main;
#my $eval_container = Eval::WithLexicals->new;

sub my_eval {
	my $text = shift;
	# Gray the line entry:
	$REPL::inline->enabled(0);
	# replace the entry text with the text 'working...' and save the old stuff
	my $old_text = $REPL::inline->text;
	$REPL::inline->text('working ...');
	
	# Process the text with NiceSlice if they try to use it:
	if ($text =~ /use PDL::NiceSlice/) {
		if ($loaded_PDL) {
			$text = PDL::NiceSlice->perldlpp($text);
		}
		else {
			REPL::warn("PDL did not load properly, so I can't apply NiceSlice to your code.\n",
				"Don't be surprised if you get errors...\n");
		}
	}
	
	# Make sure any updates hit the screen before we get going:
	$::application->yield;
	# Run the stuff to be run:
	no strict;
#	eval { $eval_container->eval($text) };
#	warn $@ if $@;
	eval $text;
	use strict;
	
	# Re-enable input:
	$REPL::inline->enabled(1);
	$REPL::inline->text($old_text);
}

# Creates a new text-editor tab and selects it
sub new_file {
	my ($page_widget, $index) = REPL::create_new_tab('New File', Edit =>
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
		, ['', '', kb::PageUp 	| km::Ctrl,  \&REPL::goto_prev_page				]
		, ['', '', kb::PageDown | km::Ctrl,  \&REPL::goto_next_page				]
		], '', 0);

	# Update the default widget for this page:
	REPL::change_default_widget($index, $page_widget);
	
	# Go to this page:
	REPL::goto_page -1;
}

sub open_image {
	my $page_no = $notebook->pageCount;
	my $name = shift;
	my $image;
	
	# Load the file if they specified a name:
	if ($name) {
		# Give trouble if we can't find the file; otherwise open the image:
		return REPL::warn("Could not open file $name.") unless -f $name;
		$image = Prima::Image-> load($name);
	}
	else {
		# Run the dialog and return if they cancel out:
		my $dlg = Prima::ImageOpenDialog-> create;
		$image = $dlg->load;
		return unless defined $image;
	}
	
	REPL::create_new_tab(ImageViewer =>
		image => $image,
		allignment => ta::Center,
		vallignment => ta::Center,
		pack => { fill => 'both', expand => 1, padx => $REPL::padding, pady => $REPL::padding },
	);
	
	# Go to this page:
	REPL::goto_page -1;
}

sub run_file_with_output {
	my $current_page = $notebook->pageIndex + 1;
	REPL::goto_output;
	run_file($current_page);
}

# Opens a file (optional first argument, or uses a dialog box) and imports it
# into the current tab, or a new tab if they're at the output or help tabs:
sub open_file {
	my ($file, $dont_warn) = @_;
	my $page = $notebook->pageIndex;
	
	# Get the filename with a dialog if they didn't specify one:
	if (not $file) {
		# Return if they cancel out:
		return unless $open_text_dialog->execute;
		# Otherwise load the file:
		$file = $open_text_dialog->fileName;
	}
	
	# Extract the name and create a tab:
	(undef,undef,my $name) = File::Spec->splitpath( $file );
	if ($page == 0) {
		new_file($name);
	}
	else {
		name($name);
	}
	
	warn "Internal: Need to check the contents of the current tab before overwriting."
			unless $page == 0 or $dont_warn;
	
	# Load the contents of the file into the tab:
    open( my $fh, $file ) or return do { warn "Couldn't open $file\n"; REPL::goto_output };
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
		my $save_dialog = Prima::SaveDialog-> new(filter => \@text_file_extension_list);
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
		REPL::warn($header);
		REPL::warn($@);
		REPL::warn('-' x length $header);
		$@ = '';
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


# convenience function for clearing the output:
my $output_line_number = 0;
my $output_column = 0;
sub clear {
	$output->text('');
	$output_line_number = 0;
	$output_column = 0;
}

# Convenience function for PDL folks.
sub p {	print @_ }

################################
# Output handling and mangling #
################################

# Set autoflush on stdout:
$|++;

# Useful function to simulate user input. This is useful for initialization
# scripts when you want to run commands and put them into the command history
sub REPL::simulate_run {
    my $command = shift;
    # Get the current content of the inline and cursor position:
    my $old_text = $inline->text;
    my $old_offset = $inline->charOffset;
    # Set the content to the new command:
    $inline->text($command);
    # run it:
    $inline->PressEnter();
    # put the original content back on the inline:
    $inline->text($old_text);
    $inline->charOffset($old_offset);
}

# Here is a utility function to print to the output window. Both standard output
# and standard error are later tied to printing to this interface, so you can
# just use 'print' or 'say' in all your code and it'll go to this.

sub REPL::outwindow {
	# The first argument is a boolean indicating whether the output should go
	# to stderr or stdout. I would like to make this print error text in red
	# eventually, but I need to figure out how to change the color of specific
	# text items: working here
	my $to_stderr = shift;
	
	# Join the arguments and split them at the newlines and carriage returns:
	my @args = map {defined $_ ? $_ : ''} ('', @_);
	my @lines = split /([\n\r])/, join('', @args);
	# Remove useless parts of error messages (which refer to lines in this code)
	s/ \(eval \d+\)// for @lines;
	# Open the logfile, which I'll print to simultaneously:
	open my $logfile, '>>', 'prima-repl.logfile';
	IO::OutWindow::print_to_terminal(@lines) if $DEBUG_OUTPUT or $to_stderr;
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
			print $logfile $_;
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

###############################
# Tie STDOUT to Output window #
###############################
# Redirect standard output using this filehandle tie. Thanks to 
# http://stackoverflow.com/questions/387702/how-can-i-hook-into-perls-print
# for this one.
package IO::OutWindow;
use base 'Tie::Handle';
use Symbol qw<geniosym>;
sub TIEHANDLE {
	my $package = shift;
	return bless geniosym, $package;
}

sub to_stderr {
	return 0;
}

# Printing to this tied file handle sends the output to the outwindow function.
sub PRINT {
	my $self = shift;
	REPL::outwindow($self->to_stderr(), @_)
}
# printf behaves the same as print
sub PRINTF {
	my $self = shift;
	my $to_print = sprintf(@_);
	main::outwindow($self->to_stderr(), @_);
}
# This function provides access to the original stdout file handle
sub print_to_terminal {
	print main::STDOUT @_;
}
# Create the tied file handle that we will reassign
tie *PRINTOUT, 'IO::OutWindow';
# Redirect standard output to the new tied file handle
select( *PRINTOUT );

############################################
# Tie STDERR to Output window and terminal #
############################################
package IO::OutWindow::Err;
our @ISA = qw(IO::OutWindow);
# Override the to_stderr function; everything else should fall through via the
# base class
sub to_stderr {
	return 1;
}
# Create the tied file handle
tie *ERROUT, 'IO::OutWindow::Err';
# Tie stderr to the new tied file handle
*main::STDERR = \*ERROUT;

package main;

eval 'require PDL::Version' if not defined $PDL::Version::VERSION;

# Print the opening message:
print "Welcome to the Prima REPL, version $version.\n";
print "Using PDL version $PDL::Version::VERSION\n" if ($loaded_PDL);
print "Using PDL::Graphics::Prima\n" if ($loaded_Prima_Graphics);
print "\n";
print join(' ', "If you don't know what you're doing, you can get help by"
				, "typing 'help' and pressing Enter, or by pressing Ctrl-h.\n");


#################################
# Run any initialization script #
#################################
sub redo_initrc {
	if (-f $initrc_filename) {
		print "Running initialization script\n";
		# Load the init script and send it to 
		open my $fh, '<', $initrc_filename;
		my $text = do { local( $/ ) ; <$fh> };
		my_eval($text);
		REPL::warn("Errors encountered running the initialization script:\n$@\n")
			if $@;
		$@ = '';
	}
	else {
		print "No initialization script found\n";
	}
}
redo_initrc if -f $initrc_filename;

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

At the bottom of the Prima::REPL window is a single entry line for direct
command input. The main window is a set of tabs, the first of which is an output
tab. Additional tabs can contain files or any other extension that has been
written as a Prima::REPL tab.

If your project has project-specific notes, you should be able to find them here:
L<prima-repl.initrc>.

=head1 Fixing Documentation Fonts

If your documentation fonts look bad, you can change them by going to
View->Set Font Encoding.

=head1 Basic Navigation

Before I launch into the tutorial, I want to cover some basic navigation to help
you quickly get around the REPL. The following keyboard shortcuts should be
helpful to you even as we get started:

 CTRL-h         open or switch to the help window
 ALT-1          go to the output window
 CTRL-i         put the cursor in the input line
 CTRL-PageUp    go to the previous tab
 CTRL-PageDown  go to the next tab

=head1 Tutorials

These are a collection of tutorials to get you started using the Prima REPL.
Except for the first tutorial, text that you should enter will be prefixed with
a prompt like C<< > >>.

=head2 Basic Output

Our first exercise will be getting basic output from the REPL. Enter the
following into the input line, but don't press enter yet:

 print "Hello!"

Take note of the last line of text in the output window, then press enter.
You should see the following appear on your output screen:

 > print "Hello!"
 Hello!

What happens if you type an expression like 1+1? If you just type the expression
in the input line, you will see this as output:

 > 1+1

Why didn't it print 2? It didn't print 2 because you didn't ask it to print 2.
You can easily accomplish that by using the C<print> function, or its
abbreviation C<p>. Type the following in the input line:

 p 1+1

The output should look like this:

 > p 1+1
 2

You may be used to REPLs that print out the result of whatever action you just
took. This REPL does not do that because it is geared towards PDL use, and
the output for PDL can get exceedingly long. Rather than always print
potentially long results to the output, the Prima REPL is quiet by default and
makes it easy to print your results if you want.

=head2 Finding Documentation

Prima REPL uses Prima's built-in pod viewer (which you may be using to view this
documentation). If you have the help window open, you can look at a particular
module's documentation by pressing C<g> on your keyboard. A dialog will ask for
the name of the module with the documentation you want to read and will open
that module if it manages to find it.

There are two additional commands for finding and viewing help. The first is
the C<help> command. By itself, the C<help> command brings up the documentation
for Prima REPL. (Pressing C<CTRL-h> accomplishes the same thing.) However, you
can also specify the name of a module with documentation:

 > help Carp

This command will open the pod viewer with the requested module's documentation.

Alternatively, you can use the C<pdldoc> command, which operates similarly to
the C<pdldoc> program on your computer. Typing

 > pdldoc hist

will load the pod from PDL::Basic and scroll to the documentation for the
C<hist> function and typing

 > pdldoc Ufunc

will load the pod from PDL::Ufunc into the pod viewer.

If you are looking for help on Perl, Prima, or PDL, check out L<perlintro>,
L<Prima::tutorial>, or L<PDL::QuickStart>, respectively.

One caveat to the C<help> command: if the pod viewer's current page has a
section with the text that you type into help, the viewer will scroll to that
section instead of opening that module's documentation. The only way to go to
that modules documentation is to go to some other page, then enter the name of
the module with the documentation you want to read.

=head2 Multi-line Input

The input line at the bottom of the window only allows for single-line entry.
However, sometimes it's better to work with many lines at once, such was when
you're writing a nontrivial for-loop or subroutine. You can do this with a file
buffer. To can create a new file buffer, pressing C<CTRL-n> or type C<new_file>.
This will open a new tab called "#2".

Try putting the following code in that new tab:

 print "Hello from the file buffer!\n";
 # This is a comment. Any valid Perl is allowed in file buffers.
 print "OK, that's all, folks!\n";

To execute the contents of the file buffer, switch to the input line by
pressing C<CTRL-i> (which toggles between the buffer and the input line) and
typing

 > run_file

It will probably seem like nothing happened. However, the contents of the print
statement were sent to the Output tab, so go there by clicking on the tab with
your mouse or pressing C<ALT-1>. You'll see the following in your output window:

 > run_file
 Hello from the file buffer!
 OK, that's all, folks!

Running the contents of a file buffer is useful enough that it has two keyboard
shortcuts. The first is C<CTRL-Enter>, which runs the code but keeps you on
your current file buffer. The second is C<CTRL-SHIFT-Enter>, which switches you
to the Output tab before it begins executing the code.

The output window knows how to handle carriage returns (\r) as well as newlines
(\n). For an example, put the following in your buffer and hit
C<CTRL-SHIFT-Enter>:

 for(1..10) {
   print "\r$_";
   sleep 1 unless $_ == 10;
 }
 print "\nAll done!\n";

That should take about 10 seconds to run and the numbers should overwrite each
other in the process. This is very useful if you have a long-running process and
you want to print the status without filling up the output window with redundant
lines. Furthermore, the Output tab displays all text sent to Perl's STDIO and
STERR file handles. (I had hoped that even text from low-level processes that
normally print to the screen, such as C code that uses C<printf>, would display
their results to the Output tab, but no such luck. I'm researching how to
properly print stuff from Inline::C code and hope to update this soon.)

Note that the input line is greyed out while the code executes, so if you
have a long-running process, you will not be able to type in new commands or
even switch tabs.

=head2 Editing Files

Although the multi-line buffer is not the greatest editor, it is useful in a
pinch. You can save the contents of a buffer by pressing C<CTRL-s> in the buffer
window, which will present a dialog asking where you want to save yoru file.
Alternatively, you can type

 > save_file 'filename'

at the input line. The filename is optional; if you don't supply one, you will
get a dialog box asking for the name of the file, just as if you used the
keyboard shortcut.

You can open a file with the C<open_file> function or C<CTRL-o>. You can supply
a filename to the function, but if you do not (or if you use the keyboard
shortcut), you will get a dialog asking which file you want to open. NOTE:
IF YOU ARE CURRENTLY VIEWING A FILE BUFFER, OPENING A FILE WILL OVERWRITE THE
CONTENTS OF THE BUFFER. To save yourself from losing the contents of your
current buffer, you should either create a new tab first, or switch to the
Output tab. Trying to open a file from the Output tab automatically creates a
new tab for your file.

=head2 Viewing Images

Prima makes opening and viewing images very easy, so I've added a function for
opening a tab to display an image. The function is C<open_image> and it requires
that you specify the filename of your image to open. For example, if you have an
image called C<test.jpg> in your current working directory, you could view it
with the following:

 > open_image 'test.jpg'

=head2 Plotting PDL Data

You can easily plot data with the various plotting commands if you have
L<PDL::Graphics::Prima> installed. This will create a new tab with your
specified plot (with a special exception that we'll get to shortly). The
interface is identical to L<PDL::Graphics::Prima::Simple>, and you should check
the documentation in that module for details. Here are some examples to remind
you how this works:

 > $t_data = sequence(6) / 0.5 + 1
 > $y_data = exp($t_data)
 > line_plot($t_data, $y_data)

Here's a more complicated example for a multiline buffer:

 # Create some simple data:
 $t_data = sequence(6) / 0.5 + 1;
 $y_data = exp($t_data);
 
 # Create the plotter widget:
 $plotter = plot(
     -function => [\&PDL::exp, color => cl::Blue],
     -data => [$t_data, $y_data, color => cl::Red],
     y => {
         scaling => sc::Log,
         label => 'exp(t)',
     },
     title => 'Exponential Curve',
     x => { label => 't' },
 );

This multiline buffer saves the reference to the plotting widget, allowing you
to fiddle with it from the input line if you like. For example, you can add
the hyperbolic cosine function like so:

 $plotter->dataSets->{cosh} = [\&PDL::cosh, colors => cl::Green];

=head2 RC File and Notes

Prima::REPL supports per-directory rc files. When you have a file called
C<prima-repl.initrc> in the directory from which you execute C<prima-repl>,
it will be executed upon startup. The purpose of this rc file is to allow for
per-project initialization and function definitions.

You can emulate user input with the C<simulate_run> command, which will add text
to the input line and then use the standard input lne mechanism to evaluate the
text. This can be useful because it puts the evaluated text into the user's
history. However, as this adds lines to the history file, you should use this
sparingly, only when you think the user will want to retrieve the command in
their history.

One final, useful aspect of the initrc file is that you can add documentation by
simply inserting pod in your initrc file. The link at the top of this help file
will automatically open the documentation or give a message indicating that
there is no such documentation. This way, if you declare any useful functions
in your initrc file, you can document them easily.

=head1 Inline

Running Inline code can be tricky because the code is executed using an C<eval>
block. As such, any Inline code should be declared in the C<use> line itself
rather than in the C<__DATA__> or C<__END__> blocks, as is customary. For
example:

 use Inline C => q{
     void my_print_hi() {
         PerlIO_stdoutf("Hello there!\n");
     }
 };

I use the PerlIO function for printing to stdout. In principle, this is supposed
to be captured and redirected, but I have not succeeded. :-(

=head1 PDL Debugging

To get PDL debugging statements, type the following in the evaluation line:

 $PDL::debug = 1

=head1 Other keyboard shortcuts

 CTRL-n  create a new file
 CTRL-w  close the currently open file or tab
 CTRL-o  open a file
 CTRL-S  Save a file (notice the capital)
 CTRL-2 through CTRL-9
         switch to tab 2 through 9


=head1 AUTHOR

This program is Copyright David Mertens, 2011.

=cut
