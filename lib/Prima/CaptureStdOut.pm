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
sub OPEN { return shift }

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

use base 'Prima::Widget';
use Prima::Edit;
use Carp 'croak';

# This is actually a widget that gets packed somewhere

# profile_default? Eventually I'll want to provide coloring options and
# logging file names and options.
use Symbol;
sub init {
	my $self = shift;
	my %profile = $self->SUPER::init(@_);
	
	# Maybe some day get various settings from the profile. For now, I
	# just ignore.
	
	my $sym = gensym;
	tie *{$sym}, 'Prima::CaptureStdOut::TieStdOut' => $self;
	$self->{stdout} = $sym;
	$sym = gensym;
	tie *{$sym}, 'Prima::CaptureStdOut::TieStdErr' => $self;
	$self->{stderr} = $sym;
	$self->{old_stderr} = [];
	$self->{old_stdout} = [];
	
	return %profile;
}

sub ensure_output_edit {
	my ($self, $type, $is_to_stderr, @props) = @_;
	if (not defined $self->{curr_out_widget}
		or $self->{curr_out_widget}->{output_type} ne $type
	) {
		my $new_output = $self->insert(Edit =>
			pack => {
				fill => 'x', expand => 1, side => 'top',
				padx => 10, pady => 10
			},
			text => '',
			cursorWrap => 1,
			wordWrap => 1,
			readOnly => 1,
			font => { name => 'monospace'},
			@props,
		);
		$new_output->{is_to_stderr} = $is_to_stderr;
		$new_output->{output_type} = $type;
		$new_output->{output_column} = 0;
		$new_output->{output_line_number} = 0;
		$self->{curr_out_widget} = $new_output;
	}
}

#                      red         green     blue
my $light_yellow = (255 << 16) | (250 << 8) | 230;
my $light_red    = (255 << 16) | (204 << 8) | 204;
my $light_grey   = (240 << 16) | (240 << 8) | 240;
sub note_printout {
	my $self = shift;
	$self->ensure_output_edit('note', 0, backColor => $light_yellow);
	$self->append_output(@_);
}

sub newline_printout {
	my $self = shift;
	$self->ensure_output_edit('normal', 0, backColor => $light_grey);
	# Make sure we're starting on a new line!
	unshift @_, "\n" if $self->{curr_out_widget}->{output_column} != 0;
	$self->append_output(@_);
}

sub printout {
	my $self = shift;
	$self->ensure_output_edit('normal', 0, backColor => $light_grey);
	$self->append_output(@_);
}

sub command_printout {
	my $self = shift;
	$self->ensure_output_edit('command', 0, backColor => cl::White);
	# Make sure the font is bold
	$self->{curr_out_widget}->font->style(fs::Bold);
	$self->append_output(@_);
}

sub printerr {
	my $self = shift;
	$self->ensure_output_edit('error', 1, backColor => $light_red);
	$self->append_output(@_);
}

sub logfile {
	'temp-output.txt';
}

sub start_capturing {
	my $self = shift;
	
	# STDOUT is easy. Just select the tied fileahandle.
	push @{$self->{old_stdout}}, select($self->{stdout});
	
	# STDERR is trickier. We have to dup whatever is presently in
	# STDERR and save that as a backup.
	open my $prev_stderr, '>&main::STDERR'
		or die "Could not dup STDERR";
	push @{$self->{old_stderr}}, $prev_stderr;
	# Then we can simply overwrite STDERR with our tied file handle.
	*main::STDERR = $self->{stderr};
}

# Keep this backed up for error reporting
open my $original_STDERR, '>&main::STDERR';
my $original_STDOUT = select;

sub stop_capturing {
	my $self = shift;
	
	# There is a big out-of-order problem if the currently selected
	# filehandle is not ours. Let's try to detect these situations and
	# throw an error.
	
	# Compare filenumobers. My TieStdOut class gives us a fractional
	# file number generated by rand(), so we know that they should be
	# numeric, unique enough for our purposes, and distinct from the
	# file numbers of normal file handles.
	if (fileno(*main::STDERR) != fileno($self->{stderr})
		or fileno(select) != fileno($self->{stdout})
	) {
		*main::STDERR = $original_STDERR;
		select(*$original_STDOUT);
		croak("Out-of-order stop-capturing!!! Quitting before all hell breaks loose!");
	}
	
	# Restore STDERR and STDOUT.
	select (pop @{$self->{old_stdout}});
	*main::STDERR = pop @{$self->{old_stderr}};
}

sub append_output {
	my $self = shift;
	
	# Get the widget into which we will add more text
	my $out_widget = $self->{curr_out_widget};
	
	# Join the arguments and split them at the newlines and carriage returns:
	my @args = map {defined $_ ? $_ : ''} ('', @_);
	my @lines = split /([\n\r])/, join('', @args);
	# Remove useless parts of error messages (which refer to lines in this code)
	s/ \(eval \d+\)// for @lines;
	
	# Open the logfile, which I'll print to simultaneously:
	open my $logfile, '>>', $self->logfile;
	# Go through each line and carriage return, overwriting where appropriate:
	for my $line (@lines) {
		# If it's a carriage return, set the current column to zero:
		if ($line eq "\r") {
			$out_widget->{output_column} = 0;
			print $logfile "\\r\n";
		}
		# If it's a newline, increment the output line and set the column to
		# zero:
		elsif ($line eq "\n") {
			$out_widget->{output_column} = 0;
			$out_widget->{output_line_number}
				= $out_widget->{output_line_number} + 1;
			print $logfile "\n";
		}
		# Otherwise, add the text to the current line, starting at the current
		# column:
		else {
			print $logfile $line;
			my $current_text = $out_widget->get_line($out_widget->{output_line_number});
			# If the current line is blank, set the text to $_:
			if (not $current_text) {
				$current_text = $line;
			}
			# Or, if the replacement text exceeds the current line's content,
			elsif (length($current_text) < length($line) + $out_widget->{output_column}) {
				# Set the current line to contain everything up to the current
				# column, and append the next text:
				$current_text = substr($current_text, 0, $out_widget->{output_column}) . $line;
			}
			# Or, replace the current line's text with the next text:
			else {
				substr($current_text, $out_widget->{output_column}, length($line), $line);
			}
			$out_widget->delete_line($out_widget->{output_line_number});
			$out_widget->insert_line($out_widget->{output_line_number}, $current_text);
			# increase the current column:
			$out_widget->{output_column} = $out_widget->{output_column} + length($line);
		}
	}
	
#	# Make sure the output widget is tall enough to accomodate the new
#	# text XXX This almost certainly won't work!!!
#	$out_widget->height($out_widget->{output_line_number} * $out_widget->font->height);
#	# make_logical, I think
	
	
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
#	$out_widget->cursor_cend;
}

1;

__END__

=head1 NAME

Prima::CaptureStdOut - widget to capture and display text sent to standard
output and standard error

=head1 SYNOPSIS

 ... coming ...

=cut
