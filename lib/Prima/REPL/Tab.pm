# Base class for all REPL tabs

sub process_commands {
	my ($self, $command) = @_;
	# No processing needs to happen here. Just call the app's eval:
	Prima::REPL->do_single_line($command);
}
