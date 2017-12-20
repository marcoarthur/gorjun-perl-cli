use strict;
use warnings;
use Test::More;
use URI;
use lib qw(./lib);

BEGIN {
    $ENV{GORJUN_COVER} = 1;
}

# modules to get coverage
my @COVER = qw(auth upload config db raw apt template );

use_ok('Gorjun::Build');

# just build gorjun first of all
ok my $gb = Gorjun::Build->new(
    remote => URI->new('https://github.com/marcoarthur/gorjun.git'),
    branch => 'dev',
    commit => 'HEAD'
  ),
  'Created a gorjun build';
note( $gb->status );

# run all tests for each module. Reason for this is limitation of
# go test that only give coverage for one selected package.
# See go test -coverpkg option.
for my $module (@COVER) {

    # set gorjun in test mode
    $gb->run_test_mode(
        module => $module,
        file   => "cover_${module}.out",
    );

    # run tests in t/test.t
    do 't/test.t';
    sleep 3;    # waits gorjun shutdown properly
}

done_testing();
