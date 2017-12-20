package Gorjun::Build;

use Moose;
use URI;
use Carp;
use Git::Repository;
use File::Spec::Functions;
use File::Basename;
use File::Path qw(make_path);
use IPC::Run qw(start pump finish run timeout io);
use File::chdir;
use constant {
    GORJUN_REPO => 'https://github.com/subutai-io/gorjun.git',
    TIMEOUT     => 30,
};

my %DEFAULT_GORJUN = (
    db_file     => '/opt/gorjun/data/db/my.db',
    etc_file    => '/opt/gorjun/etc/gorjun.gcfg',
    net_port    => 8080,
    store_quota => '2G',
    store_path  => '/opt/gorjun/data/files',
);

use constant GORJUN_CONF => <<EOC;
[db]
path = %s

[network]
port = %d

[storage]
userquota = %s
path = %s
EOC

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

has _bg_proc => (
    is        => 'rw',
    predicate => '_has_gorjun_running',
);

sub BUILD {
    my $self = shift;

    # checkout the revision required
    $self->_repo->run( checkout => $self->commit, { quiet => 1 } );

    # build gorjun binary
    my @make = ( "make", "-C", $self->_repo->work_tree );
    run \@make, timeout(TIMEOUT) or croak "Couldn't make gorjun";

}

sub _set_repo {
    my $self = shift;

    # get path for repository
    my $path = catdir( $self->_gopath, 'src', $self->_mk_github_path );

    # gorjun don't exist in this system: try to donwload it
    unless ( -d $path ) {
        carp "Can't find gorjun on $path trying to get it";

        my $github_src = join '', $self->_mk_github_path;
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

sub start_gorjun {
    my $self = shift;
    my %args = @_;

    # If already started just return the harness
    return $self->_bg_proc if $self->_has_gorjun_running;

    # Configure gorjun
    $self->_gorjun_conf;

    # Create a background gorjun process
    my $gorjun = catfile( $self->_repo->work_tree, 'gorjun' );
    croak "Not an executable $gorjun found" unless -e $gorjun;

    # set command and output
    my @cmd = ($gorjun);
    my ( $out, $h );

    eval { $h = start \@cmd, io( $args{logs}, '<', \$out ); };
    croak "Could not spawn gorjun: $@" if $@;

    # wait one sec for booting time
    sleep 1;

    # save it for later IPC communication
    $self->_bg_proc($h);
}

sub run_test_mode {
    my $self = shift;
    my %args = @_;

    # Create a background test process
    #
    # set go test command
    my @cmd = qw( go test );
    # add the profile file
    push @cmd, qq(-coverprofile=$args{file});
    # add the test to be run
    push @cmd, qq(-run=TestMain);
    # add the module to create coverage
    my $dir = catdir( $self->_mk_github_path, $args{module} );
    # TODO: strip out forked owner and put back subutai-io
    $dir =~ s/marcoarthur/subutai-io/mx;
    push @cmd, qq(-coverpkg=) . $dir;

    # change CWD to directory of repository
    local $CWD = $self->_repo->work_tree;

    # run gorjun with coverage metrics on
    my $h = start \@cmd || croak "Could not spawn go test: $@";

    # wait for booting time
    sleep 1;
}

sub stop {
    my $self = shift;

    croak "Gorjun is not running" unless $self->_has_gorjun_running;

    return !$self->_bg_proc->signal('INT');
}

sub clean {
    my $self = shift;

    # reset the repo for master HEAD
    $self->_repo->run( checkout => 'master', { quiet => 1 } );
}

# Set gorjun directory structures and conf files
sub _gorjun_conf {
    my $self = shift;
    my %args = @_;

    # set all defaults left unset
    for ( keys %DEFAULT_GORJUN ) {
        $args{$_} //= $DEFAULT_GORJUN{$_};
    }

    # make etc paths for conf file
    my $etc = dirname( $args{etc_file} );
    make_path $etc or croak "Can't make conf path for gorjun" unless -d $etc;

    # make db file path
    my $db = dirname( $args{db_file} );
    make_path $db or croak "Can't make db path for gorjun" unless -d $db;

    # make path for store path
    make_path $args{store_path}
      or croak "Can't make store path for gorjun"
      unless -d $args{store_path};

    # write config file
    unless ( -e $args{etc_file} ) { 
        my $cfg = sprintf GORJUN_CONF,
          @args{qw( db_file net_port store_quota store_path )};
        open( my $fh, '>', $args{etc_file} ) or croak "Can't create conf file";
        print $fh $cfg;
        close $fh;
    }

    return 1;
}

# run checks for necessary build tools
sub _has_prereq_tools {
    croak "Not implemented yet";
}

sub _mk_github_path {
    my $self = shift;

    my $rpath =
      $self->remote->path =~ s/\.git$//r;    # strip out .git ending of path
    my @ghub_path = ( $self->remote->authority, $rpath );

    return @ghub_path;
}

1;
