#!perl

use strict;
use warnings;

use Config;
BEGIN {
	# Yes, this is really necessary
	if ($Config{usethreads}) {
		require threads;
		threads->import();
		require Test::More;
		Test::More->import();
	}
	else {
		require Test::More;
		Test::More->import(skip_all => "No threading support enabled");
	}
}

use Time::HiRes 'usleep';
use Scope::Unwind qw<unwind UP>;

our $z;

sub spawn {
 local $@;
 my @diag;
 my $thread = eval {
  local $SIG{__WARN__} = sub { push @diag, "Thread creation warning: @_" };
  threads->create(@_);
 };
 push @diag, "Thread creation error: $@" if $@;
 diag @diag;
 return $thread ? $thread : ();
}

sub up1 {
 my $tid  = threads->tid();
 local $z = $tid;
 my $p    = "[$tid] up1";

 usleep rand(2.5e5);

 my @res = (
  -1,
  sub {
   my @dummy = (
    999,
    sub {
     my $foo = unwind $tid .. $tid + 2 => UP;
     fail "$p: not reached";
    }->()
   );
   fail "$p: not reached";
  }->(),
  -2
 );

 is_deeply \@res, [ -1, $tid .. $tid + 2, -2 ], "$p: unwinded correctly";

 return 1;
}

my @threads = map spawn(\&up1), 1 .. 30;

my $completed = 0;
for my $thr (@threads) {
 ++$completed if $thr->join;
}

pass 'done';

done_testing($completed + 1);
