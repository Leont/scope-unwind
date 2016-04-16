package Scope::Unwind;

use strict;
use warnings;
use XSLoader;
use Exporter 5.57 'import';
my @words = qw/HERE SUB UP SCOPE CALLER EVAL TOP/;
our @EXPORT = ('unwind', @words);
our %EXPORT_TAGS = (
	ALL   => \@EXPORT,
	words => \@words,
);

XSLoader::load(__PACKAGE__, __PACKAGE__->VERSION);

#ABSTRACT: Return to an upper scope

1;

__END__

=head1 DESCRIPTION

This module lets you return from any subroutine in your call stack.

=func unwind

    unwind;
    unwind @values, $context;

Returns C<@values> I<from> the subroutine, eval or format context pointed by or just above C<$context>, and immediately restarts the program flow at this point - thus effectively returning C<@values> to an upper scope.
If C<@values> is empty, then the C<$context> parameter is optional and defaults to the current context (making the call equivalent to a bare C<return;>) ; otherwise it is mandatory.

The upper context isn't coerced onto C<@values>, which is hence always evaluated in list context.
This means that

    my $num = sub {
     my @a = ('a' .. 'z');
     unwind @a => HERE;
     # not reached
    }->();

will set C<$num> to C<'z'>.

=func HERE

    my $current_context = HERE;

The context of the current scope.

=func SUB

    my $sub_context = SUB;
    my $sub_context = SUB $from;

The context of the closest subroutine above C<$from>.
If C<$from> already designates a subroutine context, then it is returned as-is ; hence C<SUB SUB == SUB>.
If no subroutine context is present in the call stack, then a warning is emitted and the current context is returned (see L</DIAGNOSTICS> for details).

=func EVAL

    my $eval_context = EVAL;
    my $eval_context = EVAL $from;

The context of the closest eval above C<$from>.
If C<$from> already designates an eval context, then it is returned as-is ; hence C<EVAL EVAL == EVAL>.
If no eval context is present in the call stack, then a warning is emitted and the current context is returned (see L</DIAGNOSTICS> for details).

=func UP

    my $upper_context = UP;
    my $upper_context = UP $from;

The context of the scope just above C<$from>.
If C<$from> points to the top-level scope in the current stack, then a warning is emitted and C<$from> is returned (see L</DIAGNOSTICS> for details).

=func TOP

    my $top_context = TOP;

Returns the context that currently represents the highest scope.

=func SCOPE

    my $context = SCOPE;
    my $context = SCOPE $level;

The C<$level>-th upper context, regardless of its type.
If C<$level> points above the top-level scope in the current stack, then a warning is emitted and the top-level context is returned (see L</DIAGNOSTICS> for details).

=func CALLER

    my $context = CALLER;
    my $context = CALLER $level;

The context of the C<$level>-th upper subroutine/eval/format.
It kind of corresponds to the context represented by C<caller $level>, but while e.g. C<caller 0> refers to the caller context, C<CALLER 0> will refer to the top scope in the current context.
If C<$level> points above the top-level scope in the current stack, then a warning is emitted and the top-level context is returned (see L</DIAGNOSTICS> for details).

=head1 ACKNOWLEDGEMENTS

This module blatantly steals from Vincent Pit's Scope::Upper, but tried so provide a much more limited functionality set: only unwinding is supported, no localization or destructors in upper scopes
