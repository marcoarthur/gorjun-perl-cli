use strict;
use warnings;
use Test::More;
use File::Temp qw/ :POSIX /;
use constant FSIZE => 4000;
use lib qw(./lib);

BEGIN {
    $ENV{EMAIL}                = 'tester@gmail.com';
    $ENV{USER}                 = 'Tester';
    $ENV{GORJUN_HOST}          = '127.0.0.1';
    $ENV{GORJUN_PORT}          = '8080';
    $ENV{MOJO_USERAGENT_DEBUG} = 0;
}

chomp( my $KEY = `gpg --armor --export $ENV{EMAIL}` );

sub create_file {
    my $size = shift || FSIZE;
    my $fname = tmpnam();

    `dd if=/dev/zero of=$fname bs=2048 count=$size`;
    return $fname;
}

use_ok('Gorjun');

my $g = Gorjun->new( gpg_pass_phrase => 'pantano' );

my $test_info = <<EOF;

User Name: %s
User Email: %s
PGP Key:
%s

EOF

note( sprintf $test_info, ( $g->user, $g->email, $g->key ) );

SKIP: {
    eval { $g->has_user( $g->user ) };
    skip "User already register ", 1 if $@;

    ok my $res = $g->register( name => $ENV{USER}, key => $KEY ),
      "Register was done";
    note($res);
}

ok my $quota = $g->quota( user => $ENV{USER} ), "Get quota value done";
note($quota);

# ok $g->set_quota( ), "Set Quota done";

ok my $token = $g->get_token( user => "$ENV{USER}" ), "Token got";
note($token);

# test uploading
my $tmp = create_file();
ok my $upload = $g->upload(
    type  => 'raw',
    file  => { file => $tmp },
    token => $token
  ),
  "Upload done";
unlink $tmp;
note($upload);

#ok $g->sign( token => $token, signature => $upload ), 'Sign done';

done_testing();
