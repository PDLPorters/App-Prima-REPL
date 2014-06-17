use strict;
use warnings;

# Set autoflush on stdout:
$|++;

##########################################################################
                package Prima::CaptureStdOut::TieStdOut;
##########################################################################
# This class actually implements the tie behavior to capture the output

use base 'Tie::Handle';
use Carp;

sub TIEHANDLE {
	my $class = shift;
	my $handler = shift
		or croak "Prima::CaptureStdOut::TieStdOut needs an output handler";
	$handler->can('printout') or croak "Output handler doesn't provide printout method!";

	my $self = { handler => $handler, filenumber => rand() };
	return bless $self, $class;
}

# Printing to this tied file handle sends the output to the outwindow function.
sub PRINT { shift->{handler}->printout(@_) }

# printf behaves the same as print
sub PRINTF {
	my $self = shift;
	my $format = shift;
	my $to_print = sprintf($format, @_);
	$self->PRINT($to_print);
}

sub FILENO { shift->{filenumber} }

##########################################################################
                package Prima::CaptureStdOut::TieStdErr;
##########################################################################
# This class implements the tie behavior to capture standard error
our @ISA = qw(Prima::CaptureStdOut::TieStdOut);
use Carp;

# same constructor as base class except set the to_stderr attribute
sub TIEHANDLE {
	my $class = shift;
	my $self = $class->SUPER::TIEHANDLE(@_);
	$self->{handler}->can('printerr')
		or croak "Output handler doesn't provide printerr method!";
	return $self;
}

sub PRINT { shift->{handler}->printerr(@_) }

##########################################################################
                      package Prima::CaptureStdOut;
##########################################################################

use base 'Prima::TextView';
use Carp 'croak';

#                      red         green     blue
my $light_yellow = (255 << 16) | (250 << 8) | 230;
my $light_red    = (255 << 16) | (204 << 8) | 204;
my $light_grey   = (240 << 16) | (240 << 8) | 240;

# This is actually a widget that gets packed somewhere

# profile_default? Eventually I'll want to provide coloring options and
# logging file names and options.
sub init {
	my $self = shift;
	my %profile = $self->SUPER::init(@_);
	
	# Set some basic initializations
	$self->clear;
	$self->backColor($light_grey);
	
	return %profile;
}

sub clear {
	my $self = shift;
	$self->{output_type} = '';
	$self->{output_column} = 0;
	$self->{blocks} = [];
	$self->{needs_new_block} = 1;
	$self->{max_block_width} = 0;
	delete $self->{curr_block};
}

# Each line is rendered by a seperate block, so make it easy to build new
# blocks.
sub append_new_output_block {
	my ($self, $type) = @_;
	
	# Get the y-offset of the previous block (if it exists)
	my $y_off = 15;
	if (exists $self->{curr_block}) {
		my $prev_block = $self->{curr_block};
		$y_off = $prev_block->[tb::BLK_Y] + $prev_block->[tb::BLK_HEIGHT];
	}
	
	# Build a new block and assign it to the current block
	my $block = $self->{curr_block} = tb::block_create;
	# Set the x and y offsets
	$block->[tb::BLK_X] = 15;
	$block->[tb::BLK_Y] = $y_off;
	# Set up the proper block and font height
	my $font_height_px = $self->font->height;
	$block->[tb::BLK_HEIGHT] = $font_height_px;
	$block->[tb::BLK_FONT_SIZE] = $font_height_px + tb::F_HEIGHT;
	$block->[tb::BLK_APERTURE_Y] = $self->font->descent;
	# Note where the block takes ownership of the text string
	$block->[tb::BLK_TEXT_OFFSET] = length(${$self->textRef});
	# Set the background color to the usual default
	$block->[tb::BLK_BACKCOLOR] = cl::Back;
	
	# Apply per-type block fixups (colors, font weight, etc)
	my $method = "fixup_${type}_block";
	$self->$method;
	
	# Keep track of the output column and type
	$self->{output_column} = 0;
	$self->{output_type} = $type if defined $type;
	
	# Add this to the list of blocks
	push @{$self->{blocks}}, $block;
	
	# Clear the needs-new-block flag
	$self->{needs_new_block} = 0;
}

# Switch to a new block if it's a change in style
sub ensure_output_type {
	my ($self, $type) = @_;
	return if $self->{output_type} eq $type;
	$self->append_new_output_block($type);
}

sub note_printout {
	my $self = shift;
	$self->ensure_output_type('note');
	$self->append_output(@_);
}
sub fixup_note_block {
	# Notes are in dark gray and italic
	my $self = shift;
	$self->{curr_block}[tb::BLK_BACKCOLOR] = $light_yellow;
	$self->{curr_block}[tb::BLK_FONT_STYLE] = fs::Italic;
}

sub newline_printout {
	my $self = shift;
	$self->append_new_output_block('normal')
		unless $self->{output_column} == 0 
			and $self->{output_type} eq 'normal';
	$self->append_output(@_);
}

sub printout {
	my $self = shift;
	$self->ensure_output_type('normal');
	$self->append_output(@_);
}
sub fixup_normal_block {
	shift->{curr_block}[tb::BLK_BACKCOLOR] = $light_grey;
}

sub command_printout {
	my $self = shift;
	$self->ensure_output_type('command');
	$self->append_output(@_, "\n");
}
sub fixup_command_block {
	# Commands are in bold
	shift->{curr_block}[tb::BLK_FONT_STYLE] = fs::Bold;
}

sub printerr {
	my $self = shift;
	$self->ensure_output_type('error');
	$self->append_output(@_);
}
sub fixup_error_block {
	# Errors are in red
	shift->{curr_block}[tb::BLK_BACKCOLOR] = $light_red;
}

sub logfile {
	'temp-output.txt';
}

# Keep track of the capture stack so we can warn on weird behavior.
my @captures;

sub restore_STDIO {
	untie *STDERR;
	untie *STDOUT;
}

sub start_capturing {
	my $self = shift;
	
	push @captures, $self;
	
	$self->setup_capturing;
}

sub setup_capturing {
	my $self = shift;
	# Set the file handles
	tie *STDOUT, 'Prima::CaptureStdOut::TieStdOut' => $self;
	tie *STDERR, 'Prima::CaptureStdOut::TieStdErr' => $self;
}

sub stop_capturing {
	my $self = shift;
	
	# To keep things simple, always go back to the originals.
	restore_STDIO;
	
	# Croak if we're trying to stop when self is not at the top of the
	# capture stack
	if ($captures[-1] != $self) {
		croak("Out-of-order! Expected capture of $self but instead got capture of $captures[-1]")
	}
	
	# Pop self off the captures stack and setup the previous capture. If
	# there is none remaining, we already have STDIO back in place, so
	# we're done.
	pop @captures;
	$captures[-1]->setup_capturing if @captures;
}

sub append_output {
	my $self = shift;
	
	# Join the arguments and split them at the newlines and carriage returns:
	my @args = map {defined $_ ? $_ : ''} ('', @_);
	my @lines = split /([\n\r])/, join('', @args);
	# Remove useless parts of error messages (which refer to lines in this code)
	s/ \(eval \d+\)// for @lines;
	
	# Open the logfile, which I'll print to simultaneously:
	open my $logfile, '>>', $self->logfile;
	# Go through each line and carriage return, overwriting where appropriate:
	for my $line (@lines) {
		# Skip blanks
		next unless $line;
		# If it's a carriage return, set the current column to zero:
		if ($line eq "\r") {
			$self->{output_column} = 0;
			print $logfile "\\r\n";
		}
		# If it's a newline, build a new block
		elsif ($line eq "\n") {
			# Previous statement was a newline...
			if ($self->{needs_new_block}) {
				$self->append_new_output_block($self->{output_type});
				$self->{curr_block}[tb::BLK_WIDTH] = 1;
			}
			$self->{needs_new_block} = 1;
			$self->{output_column} = 0;
			print $logfile "\n";
		}
		# Otherwise, add the text to the current line, starting at the current
		# column:
		else {
			print $logfile $line;
			
			# Assume that the current block is ours to use, unless told
			# otherwise.
			$self->append_new_output_block($self->{output_type})
				if $self->{needs_new_block};
			
			# Insert current line contents where appropriate
			my $sub_start = $self->{curr_block}[tb::BLK_TEXT_OFFSET]
				+ $self->{output_column};
			if ($sub_start == length(${$self->textRef})) {
				# If we're at the end of the string, then simply append
				${$self->textRef} .= $line;
			}
			else {
				# Otherwise, replace with what we have
				substr (${$self->textRef}, $sub_start, length($line)) = $line;
			}
			$self->{output_column} += length($line);
			
			# Recalculate the block's width
			$sub_start = $self->{curr_block}[tb::BLK_TEXT_OFFSET];
			my $width_px = $self->get_text_width(
				substr (${$self->textRef}, $sub_start)
			);
			# (Re)set the (one and only) text rendering command
			my $length_in_row = length(${$self->textRef}) - $sub_start;
			{
				no warnings 'misc';
				splice @{$self->{curr_block}}, tb::BLK_START;
			}
			push @{$self->{curr_block}},
				tb::code(\&pre_text_blocks, $self->{output_type}),
				tb::text(0, $length_in_row, $width_px);
			
			# Update the maximum known width
			$self->{max_block_width} = $width_px
				if $self->{max_block_width} < $width_px;
		}
	}
	
	# close the logfile:
	close $logfile;
	
	# Update all blocks to report the same (maximum) width. This way, if
	# the user scrolls to the right and scrolls some text out of screen, its
	# coloration will still be correct
	for my $bl (@{$self->{blocks}}) {
		$bl->[tb::BLK_WIDTH] = $self->{max_block_width};
	}
	
	# Update the canvas
	$self->recalc_ymap;
	my $block = $self->{curr_block};
	my $y_off = $block->[tb::BLK_Y] + $block->[tb::BLK_HEIGHT];
	$self->paneSize($self->{max_block_width}, $y_off);
	
	$self->repaint;
	
	# Let the application update itself:
	$::application->yield;

	# I'm not super-enthused with manually putting the cursor at the end of
	# the text, or with forcing the scrolling. I'd like to have some way to
	# determine if the text was already at the bottom, in which case I would
	# continue scrolling, if it was not, I would not scroll. But, I cannot find
	# how to do that at the moment, so it'll just force scroll with every
	# printout. working here:
#	$out_widget->cursor_cend;
}

sub pre_text_blocks {
	my ($self, $canvas, $block, $state, $x, $y, $type) = @_;
	my $backup_color = $canvas->color;
	
	$y -= $block->[tb::BLK_APERTURE_Y] + 1;
	my $top = $y + $block->[tb::BLK_HEIGHT];
	my $right_edge = $block->[@{$block} - 1] + $x;
	
	if ($type eq 'note') {
		$canvas->color($light_yellow);
	}
	elsif ($type eq 'error') {
		$canvas->color($light_red);
	}
	elsif ($type eq 'normal') {
		$canvas->color($light_grey);
	}
	elsif ($type eq 'command') {
		$canvas->color(cl::White);
	}
	
	$canvas->bar(0, $y, $x, $top);
	$canvas->bar($right_edge, $y, $canvas->width, $top);
	$canvas->color($backup_color);
}

1;

__END__

=head1 NAME

Prima::CaptureStdOut - widget to capture and display text sent to standard
output and standard error

=head1 SYNOPSIS

 use strict;
 use warnings;
 use Prima qw(Application CaptureStdOut);
 
 # Build a simple application with the capture window inside
 my $window = Prima::MainWindow->new(
     text => 'Simpe REPL',
     width => 600,
 );
 my $capture = $window->insert(CaptureStdOut =>
     text => '',
     pack => {fill => 'both'},
 );
 
 # Activate the capture
 $capture->start_capturing;
 
 # Everything here is captured and displayed:
 print "This is captured text!\n";
 print "This is also captured text!\n";
 print "fileno for currently selected file handle is ", fileno(select), "\n";
 print STDERR "This will probably be captured in an error window\n";
 warn "This is a captured warning\n";
 warn "This is also a captured warning\n";
 
 # There are also special methods for various display designations:
 $capture->note_printout("This is a note");
 $capture->printerr('This will always be correctly caught');
 $capture->command_printout('This is a command!');
 
 # To restore STDOUT and STDERR:
 $capture->stop_capturing;
 
 print "This text is not captured\n";
 warn "This warning is not captured\n";
 
 run Prima;

=head1 DESRIPTION

This module provides a widget with the proper machinery to intercept the
data sent to STDOUT and STDERR and display them in a Prima widget.

... more to come ...

Note the permanence of STDOUT and STDERR based on when this module is
called. Thus, if you want to change them to something else, you must open
them as early as possible.

=cut
