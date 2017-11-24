use strict;
use warnings;
use Test::More;
use lib qw(./lib);

BEGIN {
    $ENV{EMAIL} = 'hub@gmail.com';
    $ENV{USER}  = 'Hub';
    $ENV{MOJO_USERAGENT_DEBUG} = 1;
}

my $FILE = '/tmp/temp.file';
chomp( my $KEY = `gpg --armor --export $ENV{EMAIL}` );

sub create_file {
    my $fname = shift;
    my $size = shift;
    $size = 40000 unless $size;

    `dd if=/dev/zero of=$fname bs=2048 count=$size`;
}

use_ok('Gorjun');
my $g = Gorjun->new( gpg_pass_phrase => 'my pass phrase' );

ok $g->register( name => 'Hub', key => $KEY ), "Register was done";

# ok $g->quota, "Get Quota done";
# ok $g->set_quota( ), "Set Quota done";

ok my $token = $g->token( user => 'Hub' ),     "Token got";

# test uploading
create_file($FILE);
ok my $upload =
  $g->upload( 
      type => 'raw',
      file => { file => $FILE },
      token => $token ),
  "Upload done";
unlink $FILE;

#ok $g->sign( token => $token, signature => $upload ), 'Sign done';

done_testing();
