IkiWiki::Plugin::purge
======================

IkiWiki plugin to send PURGE requests to remote http cache server
(like Varnish Cache)

Installation
------------

See https://ikiwiki.info/plugins/install/ for how to install plugins.

Configuration
-------------

To add plugin and plugin configuration to your .setup file, run:

    ikiwiki --changesetup ~/mywiki.setup --plugin purge

Then, you need to set "purge_url" in ~/mywiki.setup to point to your
varnish cache server:

    purge_url: http://example.com/

Varnish configuration
---------------------

For Varnish, you'll need to add a handler for the non-standard "PURGE"
method, and preferrably an ACL which restricts who can send these
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
