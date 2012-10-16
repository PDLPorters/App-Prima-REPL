use strict;
use warnings;

package App::Prima::REPL;

BEGIN {
  # This should be done as early as possible, prima-repl should do it first but if not
  unless (__PACKAGE__->can('print_to_terminal')) {
    my $stdout = \*STDOUT;
    *App::Prima::REPL::print_to_terminal = sub {
      print $stdout @_;
    };
  }
}

our $VERSION = 0.03;
use Moo;

use Prima qw(Buttons Notebooks ScrollWidget Application Edit
			FileDialog ImageViewer ImageDialog);
use PrimaX::InputHistory;

has 'output_line_number' => (
  is => 'rw',
  default => sub{0},
);

has 'output_column' => (
  is => 'rw',
  default => sub{0},
);

has 'default_widget_for' => (
  is => 'rw',
  default => sub { [] },
);

has 'default_sizes' => (
  is => 'rw',
  default => sub { [400, 400] }
);

has 'default_help_page' => (
  is => 'ro',
  default => sub{ __PACKAGE__ },
);

has 'emulate_simple' => (
  is => 'rw',
  default => sub{0},
);

has 'has_PDL' => (
  is => 'ro',
  default => sub{0},
);

has 'has_Prima_Graphics' => (
  is => 'ro',
  default => sub{0},
);

has 'debug_output' => (
  is => 'ro',
  default => sub{0},
);

has 'history_output_handler' => (
  is => 'ro',
  builder => '_build_history_output_hander',
  lazy => 1,
);

has 'logfile' => (
  is => 'ro',
  default => sub { 'prima-repl.logfile' },
);

sub _build_history_output_hander {
  my $self = shift;
  return PrimaX::InputHistory::Output::REPL->new( $self );
}

has 'text_file_extension_list' => (
  is      => 'rw',
  default => sub {[
	['Perl scripts'		=> '*.pl'	],
	['PDL modules'		=> '*.pdl'	],
	['Perl modules'		=> '*.pm'	],
	['POD documents'	=> '*.pod'	],
	['Test suite'		=> '*.t'	],
	['All'			=> '*'		],
  ]},
);

# A dialog box that will be used for opening and saving files:
has 'open_text_dialog' => (
  is => 'rw',
  builder => '_build_open_text_dialog',
  lazy => 1,
);

sub _build_open_text_dialog {
  my $self = shift;
  return Prima::OpenDialog->new(filter => $self->text_file_extension_list);
};

has 'open_dialog' => (
  is => 'rw',
  default => sub { Prima::OpenDialog->new(filter => [[All => '*']]) },
);

has 'padding' => (
  is => 'rw',
  default => sub{10},
);

sub warn {
	my $self = shift;
	chomp(my $text = join('', @_));
	warn $text . "\n";
	$self->goto_output;
}

has 'window' => (
  is => 'ro',
  builder => '_build_window',
  lazy => 1,
);

sub _build_window {
  my $self = shift;
  return Prima::MainWindow->new(
    #pack => { fill => 'both', expand => 1, padx => $self->padding, pady => $self->padding },
    text => 'Prima REPL',
    size => [600, 600], 
  );
}

# Add a notbook with output tab:
has 'notebook' => (
  is => 'ro',
  builder => '_build_notebook',
  lazy => 1,
);

sub _build_notebook {
  my $self = shift;
  return $self->window->insert(TabbedScrollNotebook =>
    pack => { fill => 'both', expand => 1, padx => $self->padding, pady => $self->padding },
    tabs => ['Output'],
    style => tns::Simple,
  );
}

has 'output' => (
  is => 'ro',
  builder => '_build_output',
  lazy => 1,
);

sub _build_output {
  my $self = shift;
  my $output = $self->notebook->insert_to_page(0, Edit =>
    pack => { fill => 'both', expand => 1, padx => $self->padding, pady => $self->padding },
    text => '',
    cursorWrap => 1,
    wordWrap => 1,
    readOnly => 1,
    backColor => cl::LightGray,
    font => { name => 'monospace'},
  );

  # Over-ride the defaults for these:
  my $overrides = [
      ['', '', km::Ctrl | kb::PageUp,	sub { $self->goto_prev_page }	],	# previous
      ['', '', km::Ctrl | kb::PageDown,	sub { $self->goto_next_page }	],	# next
  ];
  $output->accelTable->insert( $overrides, '', 0 );

  return $output;
}

has 'history_filename' => (
  is => 'ro',
  default => sub{ '.prima.repl.history' },
);

has 'max_history_items' => (
  is => 'ro',
  default => sub { 200 },
);

# Add the eval line:
has 'inline' => (
  is => 'ro',
  builder => '_build_inline',
  lazy => 1,
);

sub _build_inline {
	my $self = shift;
	my $notebook = $self->notebook;
	my $padding = $self->padding;

	my $fileName = $self->history_filename;
	my $historyLength = $self->max_history_items;

	my $inline = PrimaX::InputHistory->create(
		owner => $self->window,
		text => '',
		pack => {fill => 'both', after => $notebook, padx => $padding, pady => $padding},
		storeType => ih::NoRepeat,
		outputWidget => $self->history_output_handler,
		onCreate => sub {
			my $self = shift;
			
			# Open the file and set up the history:
			my @history;
			if (-f $fileName) {
				open my $fh, '<', $fileName;
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
			
			# Save the last N lines in the history file:
			open my $fh, '>', $fileName;
			# I want to save the *last* 200 lines, so I don't necessarily start at
			# the first entry in the history:
			my $offset = 0;
			my @history = @{$self->history};
			$offset = @history - $historyLength if (@history > $historyLength);
			while ($offset < @history) {
				print $fh $history[$offset++], "\n";
			}
			close $fh;
		},
		onKeyUp => sub {
			main::my_keyup(@_);
		},
	);

	# Add the special accelerators seperately:
	# Update the accelerators.
	my $accTable = $inline->accelTable;

	# Add some functions to the accelerator table
	$accTable->insert([
		# Ctrl-Shift-Enter runs and goes to the output window
		  ['', '', kb::Return | km::Ctrl | km::Shift,	sub{ $self->goto_output; $_[0]->PressEnter}	]
		, ['', '', kb::Enter  | km::Ctrl | km::Shift,	sub{ $self->goto_output; $_[0]->PressEnter}	]
		# Ctrl-i selects the default widget (the editor for edit tabs)
		, ['', '', km::Ctrl | ord 'i', sub { $self->goto_page($self->notebook->pageIndex)}]
	], '', 0);

	# give it the focus at the start
	$inline->select;
	# Add some hooks to process help, pdldoc, and niceslicing:
	# working here:

	# The list of default widgets for each page. Output defaults to the evaluation
	# line:
	push @{ $self->default_widget_for }, $inline;

	return $inline;
}

# working here - a simple hack; override main::my_keyup to play with the
# keyup callback on the input line.
sub main::my_keyup {};

sub goto_page {
	my $self = shift;
	my $page = shift;
	$page = 0 if $page >= $self->notebook->pageCount;
	$page = $self->notebook->pageCount - 1 if $page == -1;
	# Make sure the page exists (problems could arrise using Alt-9, for example)
	if ($page < $self->notebook->pageCount) {
		$self->notebook->pageIndex($page);
		$self->default_widget_for->[$page]->select;
	}
	# Silently ignore if the page does not exist
}

sub goto_next_page {
	my $self = shift;
	$self->goto_page($self->notebook->pageIndex + 1);
}
sub goto_prev_page {
	my $self = shift;
	$self->goto_page($self->notebook->pageIndex - 1);
}
sub goto_output {
	my $self = shift;
	$self->goto_page(0);
}
sub get_help {
	my $self = shift;
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
		# Otherwise, open the default documentation:
		$::application->open_help($self->default_help_page);
	}
	
	# Make sure the the opened help is visible (but check that the active
	# window is defined, as this can cause trouble on Windows).
	$::application->get_active_window->bring_to_front
		if $::application->get_active_window;
}

# Add some accelerator keys to the window for easier navigaton:
sub BUILD {
	my $self = shift;
	$self->window->accelItems([
		  ['', '', km::Ctrl | ord 'i',		sub {$self->inline->select}	]	# input line
		, ['', '', km::Alt  | ord '1',		sub {$self->goto_output}	]	# output page
		, ['', '', km::Ctrl | ord 'h',		sub {$self->get_help}		]	# help
		, ['', '', km::Alt  | ord '2',		sub {$self->goto_page(1)}	]	# help (page 2)
		, ['', '', km::Alt  | ord '3',		sub {$self->goto_page(2)}	]	# page 3
		, ['', '', km::Alt  | ord '4',		sub {$self->goto_page(3)}	]	# .
		, ['', '', km::Alt  | ord '5',		sub {$self->goto_page(4)}	]	# .
		, ['', '', km::Alt  | ord '6',		sub {$self->goto_page(5)}	]	# .
		, ['', '', km::Alt  | ord '7',		sub {$self->goto_page(6)}	]	# .
		, ['', '', km::Alt  | ord '8',		sub {$self->goto_page(7)}	]	# .
		, ['', '', km::Alt  | ord '9',		sub {$self->goto_page(8)}	]	# page 8
		, ['', '', km::Ctrl | kb::PageUp,	sub {$self->goto_prev_page}	]	# previous
		, ['', '', km::Ctrl | kb::PageDown,	sub {$self->goto_next_page}	]	# next
		, ['', '', km::Ctrl | ord 'n',		sub {main::new_file()}		]	# new tab
		, ['', '', km::Ctrl | ord 'w',		sub {$self->close_tab()}	]	# close tab
		, ['', '', km::Ctrl | ord 'o',		sub {main::open_file()}		]	# open file
		, ['', '', km::Ctrl | ord 'S',		sub {main::save_file()}		]	# save file
	]);

	$self->setup_inline_events;
	$self->setup_graphics;
};

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
	my $self = shift;
	my ($name, @options) = @_;
	my $notebook = $self->notebook;
	my $page_no = $notebook->pageCount;
	# Add the tab number to the name:
	$name .= ', ' if $name;
	$name .= '#' . ($page_no + 1);

	my @tabs = @{$notebook->tabs};
	$notebook->tabs([@tabs, $name]);
	
	my $page_widget = $notebook->insert_to_page(-1, @options);

	# Make the editor the default widget for this page.
	push @{$self->default_widget_for}, $self->inline;
	
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
	my $self = shift;
	my ($index, $widget) = @_;
	$self->default_widget_for->[$index] = $widget;
}

################################################################################
# Usage      : REPL::get_default_widget($index)
# Purpose    : retrieves the default widget for the tab with the given index
# Returns    : the default widget
# Parameters : the tab's index (returned in list context from create_new_tab)
# Throws     : never
# Comments   : use this to modify the default widget's properties, if needed
################################################################################
sub get_default_widget {
	my $self = shift;
	my ($index) = @_;
	return $self->default_widget_for->[$index];
}

################################################################################
# Usage      : REPL::endow_editor_widget($widget)
# Purpose    : Sets the properties of an edit widget so it behaves like a
#            : multiline buffer.
# Returns    : nothing
# Parameters : the widget to endow
# Throws     : when you supply an object not derived from Prima::Edit
# Comments   : none
################################################################################
sub endow_editor_widget {
	my $self = shift;
	my $widget = shift;
	
	# Verify the object
	croak("endow_editor_widget expects a Prima::Edit widget")
		unless eval{$widget->isa("Prima::Edit")};
	
	# Allow for insertions, deletions, newlines, etc
	$widget->set(
		tabIndent => 4,
		syntaxHilite => 1,
		wantTabs => 1,
		wantReturns => 1,
		wordWrap => 0,
		autoIndent => 1,
		cursorWrap => 1,
		font => { pitch => fp::Fixed, style => fs::Bold, name => 'courier new'},
	);

	# Update the accelerators.
	my $accTable = $widget->accelTable;

	# Add some functions to the accelerator table
	$accTable->insert([
		# Ctrl-Enter runs the file
		  ['CtrlReturn', '', kb::Return 	| km::Ctrl,  sub{main::run_file()}				]
		, ['CtrlEnter', '', kb::Enter  	| km::Ctrl,  sub{main::run_file()}				]
		# Ctrl-Shift-Enter runs the file and selects the output window
		, ['CtrlShiftReturn', '', kb::Return 	| km::Ctrl | km::Shift,	\&main::run_file_with_output	]
		, ['CtrlShiftEnter', '', kb::Enter  	| km::Ctrl | km::Shift,	\&main::run_file_with_output	]
		# Ctrl-PageUp/PageDown don't work by default, so add them, too:
		, ['CtrlPageUp', '', kb::PageUp 	| km::Ctrl,  sub{$self->goto_prev_page}				]
		, ['CtrlPageDown', '', kb::PageDown | km::Ctrl,  sub{$self->goto_next_page}				]
		]
		, ''
		, 0
	);
}

# closes the tab number, or name if provided, or current if none is supplied
# ENCOUNTERIMG TROUBLE WITH THIS, working here
sub close_tab {
	my $self = shift;
	my $notebook = $self->notebook;
	# Get the desired tab; default to current tab:
	my $to_close = shift || $notebook->pageIndex + 1;	# user counts from 1
	my @tabs = @{$notebook->tabs};
	if ($to_close =~ /^\d+$/) {
		$to_close--;	# correct user's offset by 1
		$to_close += $notebook->pageCount if $to_close < 0;
		# Check that a valid value is used:
		return $self->warn("You cannot remove the output tab")
			if $to_close == 0;
		
		# Close the tab
		CORE::warn "Internal: Not checking if the file needs to be saved."
			if eval{$self->default_widget_for->[$to_close]->isa('Prima::Edit')};
		splice @tabs, $to_close, 1;
		splice @{$self->default_widget_for}, $to_close, 1;
		$notebook->Notebook->delete_page($to_close);
	}
	else {
		# Provided a name. Close all the tags with the given name:
		my $i = 1;	# Start at tab #2, so they can't close the Output tab
		$to_close = qr/$to_close/ unless ref($to_close) eq 'Regex';
		while ($i < @tabs) {
			if ($tabs[$i] eq $to_close) {
				CORE::warn "Internal: Not checking if the file needs to be saved."
					if eval{$self->default_widget_for->[$to_close]->isa('Prima::Edit')};
				$notebook->Notebook->delete_page($_);
				splice @{$self->default_widget_for}, $i, 1;
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
	$self->default_widget_for->[$notebook->pageIndex]->select;
}

#######################################
# Input line PressEnter notifications #
#######################################

sub setup_inline_events {
	my $self = shift;
	my $inline = $self->inline;

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
		if ($_[1] =~ /^\s*help\s*(.*)/ or $_[1] =~ /^\s*perldoc\s*(.*)/) {
			$self->get_help($1);
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
				$self->warn($results);
			}
			# If it found output, then extract the module name and the function
			# and go there:
			elsif ($results =~ /Module (PDL::[^\s]+)\n\s+(\w+)/) {
				my $module = $1;
				my $function = $2;
				# Show help:
				$self->get_help("$module/$function");
			}
			elsif ($results =~ /NAME\s+([^\s]+)/) {
				# We're looking at a full module's documentation. Feed the module
				# to the pod viewer:
				$self->get_help("$1");
			}
			else {
				$self->warn("Unable to parse the output of pdldoc:\n", $results);
			}
		}
		else {
			$self->warn("Please specify a PDL function about which you want more information");
		}
	});

	$inline->add_notification(Evaluate => sub {
		main::my_eval($_[1]);
	});

	# logfile handling for the exit command:
	$inline->add_notification(PressEnter => sub {
		if ($_[1] =~ /^\s*exit\s*$/) {
			unlink $self->logfile;
			exit;
		}
	});

}

###############################################################################
#             PDL::Graphics::Prima::Simple handling and emulation             #
###############################################################################

sub setup_graphics {
	my $self = shift;
	my $inline = $self->inline;

	# Add emulation for PDL::Graphics::Prima::Simple
	$inline->add_notification(PressEnter => sub {
		my $packagename = 'PDL::Graphics::Prima::Simple';
		return unless index($_[1], $packagename) > 0;
		my $text = $_[1];
		if ($text =~ /^\s*use $packagename(.*)/) {
			$inline->clear_event;
			my @args = eval $1 if $1;
			$self->emulate_simple(1);
			for my $arg (@args) {
				# Ignore everything except an array ref with bounds
				if(ref ($arg) and ref($arg) eq 'ARRAY') {
					# Make sure it is the correct size:
					$self->warn("Array references passed to $packagename indicate the\n"
						. "desired plot window size and must contain two elements")
						unless @$arg == 2;
				
					# Apparently we're good to go so save the sizes:
					$self->default_sizes = $arg;
				}
			}
		}
		elsif ($text =~ /^\s*no $packagename/) {
			$self->emulate_simple(0);
			$inline->clear_event
		}
	});


	return unless $self->has_Prima_Graphics;

	# Override PDL::Graphics::Prima::Simple::plot
	no warnings qw(redefine once);

	*PDL::Graphics::Prima::Simple::plot = sub {
		# Make sure PDL::Graphics::Prima is loaded and they provided good arguments
		return $self->warn("PDL::Graphics::Prima did not load successfully!")
			if not $self->has_Prima_Graphics;
		return $self->warn("prima_plot expects a collection of key => value pairs, but you sent"
			. " an odd number of arguments!") if @_ % 2 == 1;
		
		# Get the plotting arguments and supply a meaningful default pack:
		my %args = (
			pack => { fill => 'both', expand => 1},
			@_,
		);
		
		# Create the plotter, go to the tab, and return the plotter
		my $plotter;
		if ($self->emulate_simple) {
			$plotter = Prima::Window->create(
				text  => $args{title} || 'PDL::Graphics::Prima',
				size  => $args{size} || $self->default_sizes,
			)->insert('Plot',
				pack => { fill => 'both', expand => 1},
				%args
			);
		}
		else {
			# Figure out the plot name:
			my $name = $args{title} || 'Plot';
			# Build the plot tab and switch to it:
			$plotter = $self->create_new_tab($name, Plot => %args);
			$self->goto_page(-1);
		}
		return $plotter;
	};
	
	*main::plot = \&PDL::Graphics::Prima::Simple::plot;

}

# Here is a utility function to print to the output window. Both standard output
# and standard error are later tied to printing to this interface, so you can
# just use 'print' or 'say' in all your code and it'll go to this.

sub outwindow {
	my $self = shift;
	my $output = $self->output;

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
	open my $logfile, '>>', $self->logfile;
	print_to_terminal(@lines) if $self->debug_output or $to_stderr;
	# Go through each line and carriage return, overwriting where appropriate:
	foreach(@lines) {
		# If it's a carriage return, set the current column to zero:
		if (/\r/) {
			$self->output_column(0);
			print $logfile "\\r\n";
		}
		# If it's a newline, increment the output line and set the column to
		# zero:
		elsif (/\n/) {
			$self->output_column(0);
			$self->output_line_number($self->output_line_number + 1);
			print $logfile "\n";
		}
		# Otherwise, add the text to the current line, starting at the current
		# column:
		else {
			print $logfile $_;
			my $current_text = $output->get_line($self->output_line_number);
			# If the current line is blank, set the text to $_:
			if (not $current_text) {
				$current_text = $_;
			}
			# Or, if the replacement text exceeds the current line's content,
			elsif (length($current_text) < length($_) + $self->output_column) {
				# Set the current line to contain everything up to the current
				# column, and append the next text:
				$current_text = substr($current_text, 0, $self->output_column) . $_;
			}
			# Or, replace the current line's text with the next text:
			else {
				substr($current_text, $self->output_column, length($_), $_);
			}
			$output->delete_line($self->output_line_number);
			$output->insert_line($self->output_line_number, $current_text);
			# increase the current column:
			$self->output_column($self->output_column + length($_));
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

# Useful function to simulate user input. This is useful for initialization
# scripts when you want to run commands and put them into the command history
sub simulate_run {
    my $self = shift;
    my $inline = $self->inline;

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

sub run {
  Prima->run;
}

=head1 NAME

App::Prima::REPL - a GUI REPL written with Prima for the PDL community.

=head1 NOT HERE

At the moment, there is no working code in this module. Most of the
application logic and all of the documentation is still in F<prima-repl>,
so please check that script's documentation for real help.

=cut

1;

