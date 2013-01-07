use strict;
use warnings;

package App::Prima::REPL::Commands;

use Moo;

has 'repl' => (
  is => 'ro',
  isa => sub { shift->isa('App::Prima::REPL') },
  required => 1,
);

sub alias_functions {
  my $self = shift;
  my $repl = $self->repl;

  my $namespace = shift || 'main';

  my @methods = qw/ 
    new_file open_image run_file_with_output 
    open_file init_file save_file run_file
    name clear
  /;

  no strict 'refs';
  foreach my $method (@methods) {
    my $subref = __PACKAGE__->can($method) or die "Cannot alias unfound method: $method";
    *{ $namespace . '::' . $method } = sub { unshift @_, $self; goto $subref };
  }

  # Convenience function for PDL folks.
  *{ $namespace . '::p' } = sub { print @_ };

  # Provide access to the REPL object
  # i.e. commands that were previously REPL:: now should be REPL->
  *{ $namespace . '::REPL' } = sub { $repl };

  # my_eval must use the namespace of the calling package
  *{ $namespace . '::my_eval' } = sub { 
    unshift @_, $self; 
    push @_, $namespace; 
    goto &my_eval;
  };
}

# Creates a new text-editor tab and selects it
sub new_file {
	my $self = shift;
	my $repl = $self->repl;

	my ($page_widget, $index) = $repl->create_new_tab('New File', Edit =>
		text => '',
		pack => { fill => 'both', expand => 1, padx => $repl->padding, pady => $repl->padding },
	);
	$repl->endow_editor_widget($page_widget);

	# Update the default widget for this page:
	$repl->change_default_widget($index, $page_widget);
	
	# Go to this page:
	$repl->goto_page(-1);
}

sub open_image {
	my $self = shift;
	my $repl = $self->repl;

	my $page_no = $repl->notebook->pageCount;
	my $name = shift;
	my $image;
	
	# Load the file if they specified a name:
	if ($name) {
		# Give trouble if we can't find the file; otherwise open the image:
		return $repl->warn("Could not open file $name.") unless -f $name;
		$image = Prima::Image->load($name);
	}
	else {
		# Run the dialog and return if they cancel out:
		my $dlg = Prima::ImageOpenDialog->create;
		$image = $dlg->load;
		return unless defined $image;
	}
	
	$repl->create_new_tab('Image Viewer', ImageViewer =>
		image => $image,
		allignment => ta::Center,
		vallignment => ta::Center,
		pack => { fill => 'both', expand => 1, padx => $repl->padding, pady => $repl->padding },
	);
	
	# Go to this page:
	$repl->goto_page(-1);
}

sub run_file_with_output {
	my $self = shift;
	my $repl = $self->repl;
	my $current_page = $repl->notebook->pageIndex + 1;
	$repl->goto_output;
	$self->run_file($current_page);
}

# Opens a file (optional first argument, or uses a dialog box) and imports it
# into the current tab, or a new tab if they're at the output or help tabs:
sub open_file {
	my $self = shift;
	my $repl = $self->repl;
	my $notebook = $repl->notebook;

	my ($file, $dont_warn) = @_;
	my $page = $notebook->pageIndex;
	
	# Get the filename with a dialog if they didn't specify one:
	if (not $file) {
		# Return if they cancel out:
		return unless $repl->open_text_dialog->execute;
		# Otherwise load the file:
		$file = $repl->open_text_dialog->fileName;
	}
	
	# Extract the name and create a tab:
	(undef,undef,my $name) = File::Spec->splitpath( $file );
	# working here - make this smarter so it calls new_file for anything that's
	# not an edit buffer.
	if ($page == 0 or not eval{$repl->default_widget_for->[$notebook->pageIndex]->isa('Prima::Edit')}) {
		$self->new_file($name);
	}
	else {
		$self->name($name);
	}
	
	warn "Internal: Need to check the contents of the current tab before overwriting."
			unless $page == 0 or $dont_warn;
	
	# Load the contents of the file into the tab:
    open( my $fh, $file ) or return do { warn "Couldn't open $file\n"; $repl->goto_output };
    my $text = do { local( $/ ) ; <$fh> } ;
    # Note that the default widget will always be an Edit object because if the
    # current tab was not an Edit object, a new tab will have been created and
    # selected.
    $repl->default_widget_for->[$notebook->pageIndex]->textRef(\$text);
}

# A file-opening function for initialization scripts
sub init_file {
	my $self = shift;
	$self->new_file;
	$self->open_file( @_, 1 );
}

sub save_file {
	my $self = shift;
	my $repl = $self->repl;
	my $notebook = $repl->notebook;

	my $page = $notebook->pageIndex;
	
	# Get the filename as an argument or from a save-as dialog. This would work
	# better if it got instance data for the filename from the tab itself, but
	# that would require subclassing the editor, which I have not yet tried.
	my $filename = shift;
	unless ($filename) {
		my $save_dialog = Prima::SaveDialog-> new(filter => $repl->text_file_extension_list);
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
		$textRef = $repl->output->textRef;
	}
	else {
		$textRef = $repl->default_widget_for->[$notebook->pageIndex]->textRef;
	}
	print $fh $$textRef;
	close $fh;
}

# A function to run the contents of a multiline environment
sub run_file {
	my $self = shift;
	my $repl = $self->repl;
	my $notebook = $repl->notebook;

	my $page = shift || $repl->notebook->pageIndex + 1;
	$page--;	# user starts counting at 1, not 0
	croak("Can't run output page!") if $page == 0;
	
	# Get the text from the multiline and run it:
	my $text = $repl->default_widget_for->[$page]->text;

	$self->my_eval($text);

	# If error, switch to the console and print it to the output:
	if ($@) {
		my $message = $@;
		my $tabs = $notebook->tabs;
		my $header = "----- Error running ". $tabs->[$page]. " -----";
		$message = "$header\n$message\n" . ('-' x length $header);
		$repl->warn($message);
		$@ = '';
	}
}

# Change the name of a tab
sub name {
	my $self = shift;
	my $notebook = $self->repl->notebook;

	my $name = shift;
	my $page = shift || $notebook->pageIndex + 1;

	my $tabs = $notebook->tabs;
	$tabs->[$page - 1] = "$name, #$page";
	$notebook->tabs($tabs);
}


# convenience function for clearing the output:
sub clear {
	my $self = shift;
	my $repl = $self->repl;

	$repl->output->text('');
	$repl->output_line_number(0);
	$repl->output_column(0);
}

# eval function
sub my_eval {
	my $self = shift;
	my ($text, $package) = @_;

	my $repl = $self->repl;

	# Gray the line entry:
	$repl->inline->enabled(0);
	# replace the entry text with the text 'working...' and save the old stuff
	my $old_text = $repl->inline->text;
	$repl->inline->text('working ...');
	
	# Process the text with NiceSlice if they try to use it:
	if ($text =~ /use PDL::NiceSlice/) {
		if ($repl->has_PDL) {
			$text = PDL::NiceSlice->perldlpp($text);
		}
		else {
			$repl->warn("PDL did not load properly, so I can't apply NiceSlice to your code.\n",
				"Don't be surprised if you get errors...\n");
		}
	}
	
	# Make sure any updates hit the screen before we get going:
	$::application->yield;
	# Run the stuff to be run:
	no strict;
#	eval { $eval_container->eval($text) };
#	warn $@ if $@;

	# if specified, evaluate the string in the specified package
	$text = "package $package;\n$text" if $package;
	eval $text;
	$repl->warn($@) if $@;
	use strict;
	
	# Re-enable input:
	$repl->inline->enabled(1);
	$repl->inline->text($old_text);
}

1;

