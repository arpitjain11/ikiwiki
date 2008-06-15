#!/usr/bin/perl
# hnb markup
package IkiWiki::Plugin::hnb;

# Copyright (C) 2008 by Axel Beckert <abe@deuxchevaux.org>
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# You can reach the author by snail-mail at the following address:
#
#  Axel Beckert
#  Kuerbergstrasse 20
#  8049 Zurich, Switzerland
#
# Version History:
#
# 2008-03-10 / 0.01:   Initial release
# 2008-05-08 / 0.01.1: License, version and version history added
# 2008-05-26 / 0.02:   Using content instead of page, s/mktemp/File::Temp/

my $VERSION ='0.02';

use warnings;
use strict;
use IkiWiki 2.00;
use File::Temp qw(:mktemp);

sub import {
    hook(type => "htmlize", id => "hnb", call => \&htmlize);
}

sub htmlize (@) {
    my %params = @_;

    # hnb does output version number etc. every time to STDOUT, so
    # using files makes it easier to seprarate.

    my ($fhi, $tmpin)  = mkstemp( "/tmp/ikiwiki-hnbin.XXXXXXXXXX"  );
    my ($fho, $tmpout) = mkstemp( "/tmp/ikiwiki-hnbout.XXXXXXXXXX" );

    open(TMP, '>', $tmpin) or die "Can't write to $tmpin: $!";
    print TMP $params{content};
    close TMP;

    system("hnb '$tmpin' 'go root' 'export_html $tmpout' > /dev/null");
    # Nicer, but too much output
    #system('hnb', $tmpin, 'go root', "export_html $tmpout");
    unlink $tmpin;

    open(TMP, '<', $tmpout) or die "Can't read from $tmpout: $!";
    local $/;
    my $ret = <TMP>;
    close TMP;
    unlink $tmpout;

    $ret =~ s/.*<body>//si;
    $ret =~ s/<body>.*//si;

    return $ret;
}

1;
