package Gorjun;

use Moose;
use Mojo::UserAgent;
use Data::Dumper;
use GnuPG::Interface;
use GnuPG::Handles;
use IO::Handle;
use Carp;

my $DEBUG = 1;

my %ACTIONS = (
    register => {
        method    => 'post',
        path      => '/kurjun/rest/auth/register',
        has_param => 1,
        params    => [qw ( name key )],
    },

    token => {
        method    => 'post',
        path      => '/kurjun/rest/auth/token',
        has_param => 1,
        params    => [qw( message user )],
    },

    upload => {
        method    => 'post',
        path      => '/kurjun/rest/(:type)/upload',
        has_param => 1,
        params    => [qw( file token )],
    },

    info => {
        method    => 'get',
        path      => '/kurjun/rest/(:type)/info',
        has_param => 1,
        params    => [qw( id name owner version verified )],
    },

    download => {
        method    => 'get',
        path      => '/kurjun/rest/(:type)/download',
        has_param => 1,
        params    => [qw( id name token)],
    },

    authid => {
        method    => 'get',
        path      => '/kurjun/rest/auth/token?user=(:user)',
        has_param => 1,
        params    => [qw(user)],
    },
);

has host => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'http://127.0.0.1'
);

has port => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
    default  => 8080
);

has user => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
    default  => $ENV{USER}
);

has email => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
    default  => $ENV{EMAIL}
);

has gpg_pass_phrase => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
    default  => $ENV{GPG_PASS}
);

has ua => (
    is      => 'ro',
    isa     => 'Mojo::UserAgent',
    default => sub { Mojo::UserAgent->new }
);

has key => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_key',
);

has _gpg => (
    is      => 'ro',
    isa     => 'GnuPG::Interface',
    lazy    => 1,
    builder => '_build_gpg',
);

sub _build_key {
    my $self = shift;

    # check if user has a key already
    chomp( my $key = `gpg --armor --export $self->email` );
    return $key if $key;

    # don't have: create a key using his provided pass phrase
    my $instructions = <<EOI;
     %echo Generating a default key
     Key-Type: default
     Subkey-Type: default
     Name-Real: $self->name
     Name-Comment: with stupid passphrase
     Name-Email: $self->email
     Expire-Date: 0
     Passphrase: $self->gpg_pass_phrase
     %commit
     %echo done
EOI

    # save instructions to create a key
    my $temp_file = '/tmp/instructions';
    open( my $fh, '>', $temp_file );
    print $fh $instructions;
    close $fh;

    # generate and delete temp file
    `gpg --batch --generate-key $temp_file`;
    unlink $temp_file;

    # return generated key
    chomp( $key = `gpg --armor --export $self->email` );
    return $key;
}

sub register {
    my $self   = shift;
    my %params = @_;

    carp "Register in progress:" if $DEBUG;

    my $info = $ACTIONS{'register'};

    $self->send(
        method => $info->{method},
        path   => $info->{path},
        form   => \%params
    );

}

sub get_authid {
    my $self   = shift;
    my %params = @_;
    my $info   = $ACTIONS{'authid'};

    # change user in url and delete this in params
    $info->{path} =~ s/\(:user\)/$params{user}/mx;
    delete $params{user};

    my $res = $self->send(
        method => $info->{method},
        path   => $info->{path},
    );

    return $res;
}

sub token {
    my $self   = shift;
    my %params = @_;

    carp "Token in progress:" if $DEBUG;

    my $info = $ACTIONS{'token'};

    # execute get_authid first to get the author id from gorjun
    my $authid = $self->get_authid( user => $params{user} );
    croak "Could not get authid" unless $authid;

    # sign a message with user key, passing passh phrase
    croak "Without a message to encrypt" unless $params{message};
    $params{message} = $self->encrypt_msg( $params{message} );

    # send to gorjun
    my $res = $self->send(
        method => $info->{method},
        path   => $info->{path},
        form   => \%params,
    );

    return 0;
}

sub sign {
    carp "Sign: Not implemented yet";
    return 0;
}

sub upload {
    my $self   = shift;
    my %params = @_;
    my $info   = $ACTIONS{'upload'};

    carp "Upload in progress" if $DEBUG;

    croak "Upload needs a type: raw | apt | template" unless $params{type};

    # change placeholder in path and delete type from params
    $info->{path} =~ s/\(:type\)/$params{type}/mx;
    delete $params{type};

    $self->send(
        method => $info->{method},
        path   => $info->{path},
        form   => \%params
    );

    return 0;
}

sub send {
    my $self = shift;
    my %args = @_;

    my $url     = $self->base_url . $args{'path'};
    my $method  = $args{'method'};
    my $form    = $args{'form'};
    my $headers = { 'Content-Type' => 'multipart/form-data' };

    my $tx =
        $form
      ? $self->ua->$method( $url => $headers => form => $form )
      : $self->ua->$method($url);

    if ( $tx->success ) {
        return $tx->res->body;
    }
    else {
        my $err = $tx->error;
        croak "Couldn't send request: $err->{message}";
        return;
    }
}

sub base_url {
    my $self = shift;
    return $self->host . ':' . $self->port;
}

sub send_slow {

    # Build a normal transaction
    #    my $ua = Mojo::UserAgent->new;
    #    my $tx = $ua->build_tx( GET => 'https://ubatuba:8080/' );
    #
    #    # Prepare body
    #    my $body = 'Hello World!';
    #    $tx->req->headers->content_length( length $body );
    #
    #    # Start writing directly with a drain callback
    #    my $drain;
    #    $drain = sub {
    #        my $content = shift;
    #        my $chunk = substr $body, 0, 1, '';
    #        $drain = undef unless length $body;
    #        $content->write( $chunk, $drain );
    #    };
    #    $tx->req->content->$drain;
    #
    #    # Process transaction
    #    $tx = $ua->start($tx);
}

sub _build_gpg {
    my $self = shift;

    # init interface to gpg
    my $gnupg = GnuPG::Interface->new();
    $gnupg->options->hash_init(
        armor            => 1,
        meta_interactive => 0,
    );

    # set the passphrase so we don't need to type
    $gnupg->passphrase( $self->gpg_pass_phrase );

    return $gnupg;
}

# Setup the communicational channel for gpg interface
sub _gpg_channels {
    my $self   = shift;
    my %params = @_;

    my %ghandles;

    for my $p (qw{ stdin stdout stderr }) {
        $ghandles{$p} =
          $params{$p} ? IO::Handle->new( $params{$p} ) : IO::Handle->new();
    }

    # set in/out/err
    my $handles = GnuPG::Handles->new(%ghandles);

    return $handles;
}

# Encrypt a message
sub encrypt_msg {
    my $self = shift;
    my @msg  = @_;

    # setup gpg interface: stdin, stdout and stderr
    my $handles = $self->_gpg_channels;
    my $in      = $handles->stdin;
    my $out     = $handles->stdout;
    my $err     = $handles->stderr;
    my $pid     = $self->_gpg->clearsign( handles => $handles );

    # send message to be crypted to the input
    print $in @msg;
    close $in;

    # read crypted msg from the output
    my @crypted = do { local $_; < $out > };
    close $out;
    close $err;

    print Dumper( @crypted );

    # return crypted msg
    waitpid $pid, 0;
    return join '\n', @msg;
}

1;
