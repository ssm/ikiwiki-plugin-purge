#!/usr/bin/perl
package IkiWiki::Plugin::purge;

# Copyright: 2014 Stig Sandbeck Mathisen <ssm@fnord.no>
#
# This is an Ikiwiki plugin to send PURGE requests for changed pages to a
# remote http accelerator (like Varnish Cache)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
    hook( type => "getsetup", id => "purge", call => \&getsetup );
    hook( type => "changes",  id => "purge", call => \&purge );
}

sub getsetup () {
    return plugin => {
        safe    => 0,
        rebuild => 0,
        },
        purge_method => {
        type        => "string",
        example     => "PURGE",
        description => "HTTP method to send (Default: \"PURGE\")",
        safe        => 0,
        rebuild     => 0,
        },
        purge_timeout => {
        type        => "integer",
        example     => "5",
        description => "Purge request timeout (Default: \"5\")",
        safe        => 0,
        rebuild     => 0,
        },
        purge_url => {
        type        => "string",
        example     => "http://varnish.example.org/",
        description => "URL for the host to send purges to (No default)",
        safe        => 0,
        rebuild     => 0,
        };
}

sub purge (@) {
    my @files = @_;
    return unless @files;

    # purge_url is mandatory
    return unless $config{purge_url};

    # options with defaults.
    $config{purge_method}  ||= "PURGE";
    $config{purge_timeout} ||= 5;

    eval q{use URI};
    error($@) if $@;

    eval q{use HTTP::Request};
    error($@) if $@;

    eval q{use Net::INET6Glue::INET_is_INET6};    # may not be available

    eval q{use LWP};
    error($@) if $@;
    my $ua = useragent();

    $ua->timeout( $config{purge_timeout} );
    $ua->proxy( [ "http", "https" ], $config{purge_url} );

    debug( "purge URL: " . $config{purge_url} );

    my %urls;
    foreach my $file (@files) {
        my $page = pagename($file);

        # Find the URL to purge
        my $url;
        if ( !IkiWiki::isinternal($page) ) {
            $url = urlto( $page, undef, 1 );
        }
        elsif ( defined $pagestate{$page}{meta}{permalink} ) {
            $url = URI->new_abs( $pagestate{$page}{meta}{permalink},
                $config{url} );
        }
        else {
            next;
        }

        # Remove #anchor from url, and skip if we've already purged it
        ($url) = split( '#', $url );
        next if $urls{$url}++;
    }

    # Daemonize from here, since purging may take time
    defined( my $pid = fork ) or error("Can't fork: $!");
    return if $pid;    # parent
    chdir '/';
    open STDIN,  '/dev/null';
    open STDOUT, '>/dev/null';
    POSIX::setsid() or error("Can't start a new session: $!");
    open STDERR, '>&STDOUT' or error("Can't dup stdout: $!");

    # No need to lock the wiki anymore
    IkiWiki::unlockwiki();

    # Run purge requests in the background
    foreach my $url ( keys(%urls) ) {

        my $request = HTTP::Request->new( $config{purge_method} => $url );
        chomp( my $request_as_string = $request->as_string);
        debug( "purge request: " . $request_as_string);

        my $response = $ua->request($request);
        debug( "purge response: " . $response->status_line);

    }
    exit 0;
}

1;
