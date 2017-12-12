# NAME

Gorjun - Perl Client to [gorjun daemon](https://github.com/subutai-io/gorjun)

# VERSION

Version 0.1

# SYNOPSIS

    my $g = Gorjun->new(
       host => 'http://127.0.0.1',
       port => '8080',
       user => 'Tester_User',
       gpg_pass_phrase => 'secret', # needed passphrase for gpg signing
    );

    # Get token
    $g->get_token( message => 'Some message', user => 'Tester_User' );

# DESCRIPTION

This modules operates gorjun daemon using its rest interface
so you can control gorjun actions in a Perl environment, sending, receiving
messages. Useful for integration tests as well as system administration of
gorjun. There are high level operations, as well as low level.

## High Level

Those are methods that performs a grouped set of low level operations. Such as
register a new user, upload a file, or sign an uploaded file. All of these won't
be executed with only one REST call, and will need to send several queries in
order to complete. All high level operations and their arguments are listed
below:

- register( name => $n, key => $k )
- get\_authid( user => $u )
- get\_token( user => $u, message => $m )
- quota( user => $u, token => $t )
- sign( signature => $s, token => $t )
- upload( file => $f, token => $t , type => $t)

## Low Level

Those are simple one REST call, generally only completing a step of the High Level
operation. They map to the REST API exactly one-to-one:
[https://github.com/subutai-io/gorjun/wiki/v1](https://github.com/subutai-io/gorjun/wiki/v1)

And all of them are completed with `send()` interface. Example:

    # list all raw files
    $g->send( 
           method => 'get'
           path   => '/kurjun/rest/raw/download'
    );

## BUGS AND KNOWN ISSUES

Gorjun depends on gpg utility, since messages should be signed using a GPG key
[https://www.gnupg.org/](https://www.gnupg.org/) . Not all operations can be completed without user intervention,
since not all gpg functions can be used in a scripted manner, requiring user to manually
type the pass phrase at least once.

## LICENSE

This software is GNU GPL3 licensed, and can be freely copied, modified and redistributed.
