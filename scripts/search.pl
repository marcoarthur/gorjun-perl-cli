#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: search.pl
#
#        USAGE: ./search.pl
#
#  DESCRIPTION:
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Marco Arthur (itaipu), msilva@optdyn.com
# ORGANIZATION:
#      VERSION: 1.0
#      CREATED: 03/13/2018 05:20:00 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;
use 5.022;
use Data::Dumper;
use Data::Dump qw( pp dumpf );
use JSON::XS;
use lib qw(./lib);
use Storable;
use List::Util qw( any );
use Scalar::Util qw(looks_like_number);
use constant {
    GORJUN_TEMPLATES => '/tmp/stored_templates',
    PROD             => 'https://cdn.subutai.io',
    MASTER           => 'https://mastercdn.subutai.io',
    DEV              => 'https://devcdn.subutai.io',
};
use Gorjun;

BEGIN {
    my %filters = (
        'HASH'   => sub {
                my $n = scalar ( keys %{ $_[0] } );
                return $_[0] if $n <= 3;

                my $clone = Storable::dclone( $_[0] );

                foreach my $k ( keys %$clone ) { 
                    next if any { $k eq $_ } qw( name owner version );
                    delete $clone->{$k};
                }
                $clone;
            }
    );

    sub get_filter {
        my ( $ctx, $object ) = @_;

        if ( $ctx->is_hash ) {
            my $object = $filters{'HASH'}->( $ctx->object_ref );
            return {
                'object'  => $object,
                'comment' => 'some items hidden',
            };
        }

        return;
    }
}


sub list_templates {

    my $mastercdn = Gorjun->new(
        host            => MASTER,
        port            => 8338,
        user            => 'arthurpbs',
        email           => 'arthurpbs@gmail.com',
        gpg_pass_phrase => 'meu apelido pantanal',
    );

    my $devcdn = Gorjun->new(
        host            => DEV,
        port            => 8338,
        user            => 'arthurpbs',
        email           => 'arthurpbs@gmail.com',
        gpg_pass_phrase => 'meu apelido pantanal',
    );

    my $prodcdn = Gorjun->new(
        host            => PROD,
        port            => 8338,
        user            => 'arthurpbs',
        email           => 'arthurpbs@gmail.com',
        gpg_pass_phrase => 'meu apelido pantanal',
    );

    # get all templates list JSON format
    my %template;

    for my $cdn ( $mastercdn, $devcdn, $prodcdn ) {

        # get all templates
        my $all = decode_json $cdn->send(
            path   => '/kurjun/rest/template/info',
            method => 'get',
        );

        # save all templates from particular host
        $template{ $cdn->host } = $all;

        # print it list
        print Dumper($all);
    }

    return \%template;
}

sub save_list {
    my $table = shift;

    store $table, GORJUN_TEMPLATES;
}

sub sort_by {

    my $param = shift;

    my $templates    = retrieve GORJUN_TEMPLATES;
    my $sorted_tmpls = {};

    for ( keys %$templates ) {
        my @list = @{ $templates->{$_} };
        my $op = looks_like_number $list[0]->{$param} ? 
                 sub { $_[0] > $_[1] } :
                 sub { $_[0] gt $_[1] };

        my @sorted =
          sort { &$op( $a->{$param}, $b->{$param} ) } @list;

        $sorted_tmpls->{$_} = \@sorted;
    }

    return $sorted_tmpls;
}

# Get templates from source
# $INPUT :      DEV | MASTER | PROD
# $ARRAY_REF :  [ {}, {}, ... ]
sub get_templates {
    my $source = shift;

    # save templates from all sources
    save_list(list_templates) unless -e GORJUN_TEMPLATES;

    # retrieve them
    my $templates = retrieve GORJUN_TEMPLATES;

    # return them
    return $source ? $templates->{$source} : $templates;
}

# Get templates from parameter
# INPUT:
#       - $pair : { param => 'owner', value => 'jenkins' }
#       - $template list: []
# OUTPUT:
#       - @templates that contains $owner listed
sub all_from_pair {
    my ( $pair , $tmpls ) = @_;

    # parameter type
    my $param_type = ref $tmpls->[0]{ $pair->{param} };

    die "Only ARRAY_REF implemented" unless $param_type eq 'ARRAY';

    return grep { 
        any { $_ eq $pair->{value} } @{ $_->{ $pair->{param} } };
    }  @$tmpls ;
}

sub all_from_single {
    my ( $pair , $tmpls ) = @_;

    return grep { $_->{ $pair->{param} } =~ /$pair->{value}/ }  @$tmpls;
}

sub all_verified {
    my $tmpls = shift;

    my @jenkins = all_from_pair (
        { param => 'owner', value => 'jenkins' }, 
        $tmpls,
    );
    my @subutai = all_from_pair (
        { param => 'owner', value => 'subutai' }, 
        $tmpls,
    );

    return (@jenkins, @subutai);
}

sub get_user_from_token {
    my $token = shift;

    my (undef, $user)  = map { s/\s+//g ; $_ } split /:/, $token;
    return $user;
}

#
#    name (e.g /info?name=master)
#    name + owner (e.g. /info?name=master&owner={owner})
#    name + token (e.g. /info?name=master&token={token})
#    name + owner + token (e.g. /info?name=master&owner={owner}&token={token})
#
#   Search is done this way:
#   
#   Case 1. CDN searches template only within verified templates (owner Jenkins/Subutai)
#   
#   Case 2. CDN searches template only within the specified owner's templates (specified owner's public templates)
#   
#   Case 3. Needs special treatment:
#   
#   a) if token is valid (not empty, not missing, and gets authed successfully) then CDN must use token's user as owner and search using template name and user as owner (thus it searches within the authed user's own templates or templates shared with him).
#   If it does not find there then it searches within verified templates.
#   If special flag verified=true provided then search is done only within verified templates regardless of token
#   
#   b) in case of invalid token it searches within verified templates
#   
#   the same as #2
#
sub search_by_parameters {
    my %params = @_;

    my $name = $params{name};
    my $owner = $params{owner};
    my $token = $params{token};
    my $tmpls  = $params{list};

    die "No list to search" unless $tmpls;
    die "Name is mandatory" unless $name;

    say '#' x 80;
    say 'Parameters on search';
    delete $params{list};
    print Dumper( \%params); # Search Parameters

    # base search
    my @verified = grep { $_->{name} eq $name } all_verified $tmpls;

    # owner search
    my @owner_tmpls = ();
    @owner_tmpls = grep { $_->{name} eq $name } all_from_pair (
        { param => 'owner', value => $owner }, 
        $tmpls,
    ) if $owner;

    # token search
    my @token_tmpls = ();
    if ($token) {
        my $user  = get_user_from_token( $token );

        # search for user's token simulated templates
        @token_tmpls = grep { $_->{name} eq $name } 
          all_from_pair( { param => 'owner', value => $user }, $tmpls, );

        # didn't find templates from this user, search on verified templates
        push @token_tmpls, grep { $_->{name} eq $params{name} } @verified if @token_tmpls == 0;
    }

    # publish results
    say '#' x 80;
    say 'Results:';

    if ( !$owner && !$token ) {
        # case 1
        say "CASE 1";
        print Dumper(\@verified);
        return;
    } elsif ( $owner && ! $token ) {
        # case 2
        say "CASE 2";
        print Dumper(\@owner_tmpls);
        return;
    } elsif ( !$owner && $token ) {
        # case 3
        say "CASE 3";
        print Dumper(\@token_tmpls);
        return;
    } elsif ( $owner && $token ) {
        # case 4
        say "CASE 4";
        print Dumper(\@owner_tmpls);
        return;
    }
}

sub show_all_template_name_owner {
    my $tmpls = get_templates(DEV);
    my @names = sort { $a->[0] gt $b->[0] } map { [ $_->{name}, $_->{owner} ] }  @$tmpls;
    print Dumper(\@names);
}

sub main {

    # Templates from PROD CDN
    my $tmpls = get_templates(PROD);
    say '#' x 80;
    say 'List being searched';
    dumpf( $tmpls, \&get_filter );

    my @res;

    # case 1
    @res = search_by_parameters ( name => 'generic-ansible' , list => $tmpls);
    print Dumper(@res);

    # case 2
    @res = search_by_parameters ( name => 'generic-ansible', 
        owner => '280dcda67a67d071970ff838d0331c33c0c04710',
        list => $tmpls
    );
    print Dumper(@res);

    # case 3
    @res = search_by_parameters ( 
        name => 'generic-ansible', 
        token => 'from user: 280dcda67a67d071970ff838d0331c33c0c04710',
        list => $tmpls
    );

    # case 3
    @res = search_by_parameters ( 
        name => 'generic-ansible', 
        token => 'from user: non-existing',
        list => $tmpls
    );
    print Dumper(@res);

    # case 4
    @res = search_by_parameters ( 
        name => 'generic-ansible', 
        token => 'from user: non-existing',
        owner => '280dcda67a67d071970ff838d0331c33c0c04710',
        list => $tmpls
    );

}

main();
