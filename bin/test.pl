use Prima qw(Application MsgBox);

package test;
use base 'Prima::MainWindow';

{
	my %notifications = (
		%{Prima::MainWindow-> notification_types()},
		Blarg => nt::Default,
	);

	sub notification_types { return \%notifications; }
}


sub on_blarg {
	print "object method called with args ", join(', ', @_), "\n";
	$_[1] = 'modified by class';
}

package main;

my $window = test-> new( 
	text => 'Hello world!',
	size => [ 200, 200],
	onBlarg => sub {
		print "hook called with args, ", join(', ', @_), "\n";
		$_[1] = 'modified by hook';
	},
);

my $value = 'argument 1';
$window->notify('Blarg', $value);

run Prima;

print "Value is now $value\n";
