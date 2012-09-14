# Redirect standard output using this filehandle tie. Thanks to 
# http://stackoverflow.com/questions/387702/how-can-i-hook-into-perls-print
# for this one.
package App::Prima::REPL::IO::OutWindow;
use base 'Tie::Handle';
use Symbol qw<geniosym>;
use Carp;

sub TIEHANDLE {
	my $class = shift;
	my $self = {
		handler   => shift || 'REPL',
		to_stderr => 0,
	};
	return bless $self, $class;
}

sub handler {
	my $self = shift;
	return $self->{handler};
}

sub outwindow {
	my $self = shift;
	my $outwindow = $self->handler->can('outwindow')
		or croak "Output handler doesn't provide outwindow function!";
	return $outwindow;
}

sub to_stderr {
	return shift->{to_stderr};
}

# Printing to this tied file handle sends the output to the outwindow function.
sub PRINT {
	my $self = shift;
	$self->outwindow->($self->to_stderr, @_)
}
# printf behaves the same as print
sub PRINTF {
	my $self = shift;
	my $to_print = sprintf(@_);
	my $outwindow = $self->outwindow->($self->to_stderr(), @_);
}
# This function provides access to the original stdout file handle
sub print_to_terminal {
	print main::STDOUT @_;
}

package App::Prima::REPL::IO::OutWindow::Err;
our @ISA = qw(App::Prima::REPL::IO::OutWindow);
# Override the to_stderr function; everything else should fall through via the
# base class

sub TIEHANDLE {
	my $class = shift;
	my $self = $class->SUPER::TIEHANDLE(@_);
	$self->{to_stderr} = 1;
	return $self;
}
