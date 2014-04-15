package IkiWiki::Plugin::purge;

use 5.006;
use strict;
use warnings FATAL => 'all';

=head1 NAME

IkiWiki::Plugin::purge - Purge changed pages from a front end http accelerator

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 DESCRIPTION

This plugin sends a request via HTTP to a front end http accelerator
(like varnish cache) for each page changed after a commit.

A new or changed page will normally result in several changed web
pages in ikiwiki, and the plugin will send a purge request for each.

The method (default PURGE), the request timeout and the cache URI is
configurable in the moinmoin F<blog.setup> file.

=head1 INSTALLATION

Put F<purge.pm> in F<$HOME/.ikiwiki/IkiWiki/Plugin/> or elsewhere in
your C<@INC> path.

=head1 CONFIGURATION

Add to the configuration in your F<blog.setup> file.

    # purge plugin
    # HTTP method to send (Default: "PURGE")
    purge_method: PURGE
    # Purge request timeout (Default: "5")
    #purge_timeout: 5
    # URL for the host to send purges to (No default)
    purge_url: http://frontend.example.com/

Add C<purge> to the list of plugins:

    add_plugins => [qw{goodstuff purge}],

You can also let ikiwiki add this to your setup file,

    ikiwiki --changesetup ~/blog.setup --plugin purge

=head2 Example Varnish configuration

For Varnish, you'll need to add a handler for the non-standard "PURGE"
method, and preferably an ACL which restricts who can send these
requests to empty your cache.

    acl origin_server {
        "localhost";
        "192.0.2.0"/24;
        "2001:db8::"/64;
    }

    sub vcl_recv {
        if (req.method == "PURGE") {
            if (!client.ip ~ origin_server) {
                return(synth(405,"Not allowed."));
            }
            return (purge);
        }
    }

Verify that ikiwiki sends PURGE requests to varnish by committing a
change in the wiki, and then look for those requests in the varnish
log.

    varnishncsa -d -q 'ReqMethod eq "PURGE"'

=head2 Example apache httpd configuration

Add a long expiry time for your content in your web server. For apache
httpd on Debian, the configuration would be:

    # Activate the "expiry" module
    $ a2enmod expiry

to add the "expiry" module configuration, and then add to your
virtual host configuration:

    # Set long expiry on all documents
    <Directory /path/to/your/wiki>
      <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresDefault "access plus 1 month"
      </IfModule>
    </Directory>

If you use the ikiwiki CGI, you will need to add an exception for that
path. Dynamic content should not have long expiry.

=head1 BUGS AND LIMITATIONS

Report bugs at http://rt.cpan.org/NoAuth/Bugs.html?Dist=IkiWiki-Plugin-purge

=head1 AUTHOR

Stig Sandbeck Mathisen, C<< <ssm at fnord.no> >>

=head1 LICENSE AND COPYRIGHT

Copyright: 2014 Stig Sandbeck Mathisen

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 SEE ALSO

=over 4

=item http://ikiwiki.info/

=back

=cut

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
