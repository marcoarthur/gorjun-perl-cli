package Gorjun::Build;

use Moose;
use URI;
use Carp;
use Git::Repository;
use File::Spec::Functions;
use IPC::Run qw( run timeout );
use constant {
    GORJUN_REPO => 'https://github.com/subutai-io/gorjun.git',
    TIMEOUT     => 30,
};

has local => (
    is       => 'rw',
    isa      => 'URI',
    required => 1,
    default  => sub { URI->new( catdir( $ENV{HOME}, 'src', 'gorjun' ) ) },
);

has remote => (
    is       => 'ro',
    isa      => 'URI',
    required => 1,
    default  => sub { URI->new(GORJUN_REPO) },
);

has commit => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
    default  => 'HEAD'
);

has branch => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
    default  => 'master'
);

has _gopath => (
    is       => 'ro',
    isa      => 'URI',
    required => 1,
    default  => sub { URI->new( $ENV{GOPATH} ) },
);

has _repo => (
    is      => 'ro',
    isa     => 'Git::Repository',
    lazy    => 1,
    builder => '_set_repo',
);

sub BUILD {
    my $self = shift;

    # change to branch
    $self->_repo->run( checkout => $self->branch, { quiet => 1 } );

    # checkout the revision required
    $self->_repo->run( checkout => $self->commit, { quiet => 1 } );

    # build gorjun binary
    my @make = ("make" , "-C",   $self->_repo->work_tree );
    run \@make, timeout(TIMEOUT) or croak "Couldn't make gorjun";
}

sub _set_repo {
    my $self = shift;

    # get path for repository
    my $rpath =
      $self->remote->path =~ s/\.git$//r;    # strip out .git ending of path
    my @ghub_path = ( $self->remote->authority, $rpath );
    my $path = catdir( $self->_gopath, 'src', @ghub_path );

    # gorjun don't exist in this system: try to donwload it
    unless ( -d $path ) {
        carp "Can't find gorjun on $path trying to get it";

        my $github_src = join '', @ghub_path;
        my @cmd = ( qw( go get ), $github_src );

        run \@cmd, timeout(TIMEOUT) or croak "Can't set repository";
    }

    # create a repository object for it
    my $r = Git::Repository->new( work_tree => $path )
      or croak "Couldn't set repository
    on $path: $@";

    return $r;
}

sub status {
    my $self  = shift;
    my @infos = (
        $self->remote, $self->commit, $self->branch,
        scalar $self->_repo->run( show => ( $self->commit ) ),
    );

    return sprintf <<EOF, @infos;
Repository: %s
Commit: %s
Branch: %s

%s
EOF
}

sub start {
    my $self = shift;
    my %args = @_;

    croak "Not implemented yet";
}

sub stop {
    my $self = shift;
    my %args = @_;

    croak "Not implemented yet";
}

sub clean {
    my $self = shift;

    $self->_repo->run( checkout => 'master', { quiet => 1 } );
}

# run checks for necessary build tools
sub _has_prereq_tools {
    croak "Not implemented yet";
}

1;
