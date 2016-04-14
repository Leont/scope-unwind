package Scope::Unwind;

use strict;
use warnings;
use XSLoader;
use Exporter 5.57 'import';
our @EXPORT = qw/unwind HERE SUB UP SCOPE CALLER EVAL TOP/;
our %EXPORT_TAGS = (
	ALL   => \@EXPORT,
	words => [ qw/HERE SUB UP SCOPE CALLER EVAL TOP/ ],
);

XSLoader::load(__PACKAGE__, __PACKAGE__->VERSION);

#ABSTRACT: Return to an upper scope

1;
