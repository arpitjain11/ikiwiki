#!/usr/bin/perl
# ikiwiki w3m cgi meta-wrapper
if (! exists $ENV{PATH_INFO} || ! length $ENV{PATH_INFO}) {
	die "PATH_INFO should be set";
}
my $path=$ENV{PATH_INFO};
$path=~s!/!!g;
$path="$ENV{HOME}/.ikiwiki/wrappers/$path";
if (! -x $path) {
	print "Content-type: text/html\n\n";
	print "Cannot find ikiwiki wrapper: $path\n";
	exit 1;
}
exec $path;
die "$path: exec error: $!";
