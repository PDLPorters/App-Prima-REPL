use Prima qw(Application MsgBox);
use InputHistory;

my $window = Prima::MainWindow-> new( 
	text => 'Hello world!',
	size => [ 200, 200],
);

$|++;
my $inline = Prima::Ex::InputHistory->create(
	owner => $window,
	text => '',
	outputWidget => ih::StdOut,
	storeType => ih::NoRepeat,
);

run Prima;

