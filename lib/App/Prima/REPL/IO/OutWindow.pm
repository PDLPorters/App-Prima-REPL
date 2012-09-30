use strict;
use warnings;

# classes for tying a handle to output via a handler package (default is REPL) 
# and specifically to its 'outwindow' function

package App::Prima::REPL::IO::OutWindow;
use base 'Tie::Handle';
use Carp;

sub TIEHANDLE {
	my $class = shift;
	my $handler = shift || croak "Must specify REPL object";
	$handler->can('outwindow') or croak "Output handler doesn't provide outwindow method!";

	my $self = {
		handler => $handler,
		to_stderr => 0,
	};

	return bless $self, $class;
}

sub outwindow { shift->{handler}->outwindow(@_) }
sub to_stderr { shift->{to_stderr} }

# Printing to this tied file handle sends the output to the outwindow function.
sub PRINT {
	my $self = shift;
	$self->outwindow($self->to_stderr, @_)
}
# printf behaves the same as print
sub PRINTF {
	my $self = shift;
	my $format = shift;
	my $to_print = sprintf($format, @_);
	$self->PRINT($to_print);
}

package App::Prima::REPL::IO::OutWindow::Err;
our @ISA = qw(App::Prima::REPL::IO::OutWindow);

# same constructor as base class except set the to_stderr attribute
sub TIEHANDLE {
	my $class = shift;
	my $self = $class->SUPER::TIEHANDLE(@_);
	$self->{to_stderr} = 1;
	return $self;
}

1;

