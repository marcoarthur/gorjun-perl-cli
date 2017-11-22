use strict;
use warnings;
use Test::More;
use IO::All;
use lib qw(./lib);

BEGIN {
    $ENV{EMAIL} = 'marco.prado.bs@gmail.com';
    $ENV{USER}  = 'Marco';
}

sub create_file {
    my $fname = shift;
    `dd if=/dev/zero of=$fname bs=2048 count=4`;
}

use_ok('Gorjun');

my $FILE = '/tmp/temp.file';

my $g = Gorjun->new( gpg_pass_phrase => 'my pass phrase' );

chomp( my $KEY = `gpg --armor --export $ENV{EMAIL}` );

ok $g->register( name => 'Marco', key => $KEY ), "Register was done";
ok my $token = $g->token( user => 'Marco' ), "Token got";

# test uploading
create_file($FILE);
ok my $upload =
  $g->upload( type => 'raw', file => { file => $FILE }, token => $token ),
  "Upload done";
unlink $FILE;

#ok $g->sign( token => $token, signature => $upload ), 'Sign done';

done_testing();
