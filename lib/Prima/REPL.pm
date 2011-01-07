# The basic class for the prima-repl application.

=head1 NAME

Prima::REPL - the application class for the Prima Run-Eval-Print Loop

=head1 SYNOPSIS

 # Examples go here; they all deal with
 # applicaiton api and services:
 my $app = Prima::REPL->app;
 
 # Select the first tab:
 $app->goto_tab(0);
 
 # Register a new extension:
 $app->register_extension ( ... args ... );

=head1 DESCRIPTION

A discussion of overarching themes in using the API should go here.

=cut

package Prima::REPL;
use base 'Prima::Window';
use strict;
use warnings;

=head1 API

=head2 app

The preferred method for obtaining and constructing a Prima::REPL object. Any
hooks or plugins that need to talk to the application should obtain a reference
to it using this method. Here's an example of what I mean. This code selects
the second tab:

 # Compact form:
 Prima::REPL->app->goto_tab(1);
 # verbose form:
 my $app = Prima::REPL->app;
 $app->goto_tab(1);

=cut

# The application accessor. Since this is a singleton class, this also serves
# to return the application after it's been created.
my $app;
sub app {
	return $app if $app;
	$app = Prima::REPL->create();
	return $app;
}



