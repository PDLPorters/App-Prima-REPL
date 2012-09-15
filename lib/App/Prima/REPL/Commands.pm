use strict;
use warnings;

package App::Prima::REPL::Commands;

package main;

# Creates a new text-editor tab and selects it
sub new_file {
	my ($page_widget, $index) = REPL::create_new_tab('New File', Edit =>
		text => '',
		pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
	);
	REPL::endow_editor_widget($page_widget);

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
	
	REPL::create_new_tab('Image Viewer', ImageViewer =>
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
	# working here - make this smarter so it calls new_file for anything that's
	# not an edit buffer.
	if ($page == 0 or not eval{$default_widget_for[$notebook->pageIndex]->isa('Prima::Edit')}) {
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
		my $message = $@;
		my $tabs = $notebook->tabs;
		my $header = "----- Error running ". $tabs->[$page]. " -----";
		$message = "$header\n$message\n" . ('-' x length $header);
		REPL::warn($message);
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

1;

