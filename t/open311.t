#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Warn;
use FixMyStreet::App;
use CGI::Simple;
use HTTP::Response;
use DateTime;

use FindBin;
use lib "$FindBin::Bin/../perllib";
use lib "$FindBin::Bin/../commonlib/perllib";

use_ok( 'Open311' );

my $o = Open311->new();
ok $o, 'created object';

my $err_text = <<EOT
<?xml version="1.0" encoding="utf-8"?><errors><error><code>400</code><description>Service Code cannot be null -- can't proceed with the request.</description></error></errors>
EOT
;

is $o->_process_error( $err_text ), "400: Service Code cannot be null -- can't proceed with the request.\n", 'error text parsing';
is $o->_process_error( '503 - service unavailable' ), 'unknown error', 'error text parsing of bad error';

my $o2 = Open311->new( endpoint => 'http://192.168.50.1/open311/', jurisdiction => 'example.org' );

my $u = FixMyStreet::App->model('DB::User')->new( { email => 'test@example.org', name => 'A User' } );

my $p = FixMyStreet::App->model('DB::Problem')->new( {
    latitude => 1,
    longitude => 1,
    title => 'title',
    detail => 'detail',
    user => $u,
} );

my $expected_error = qr{.*request failed: 500 Can.t connect to 192.168.50.1:80 \([^)]*\).*};

warning_like {$o2->send_service_request( $p, { url => 'http://example.com/' }, 1 )} $expected_error, 'warning generated on failed call';

my $dt = DateTime->now();

my $user = FixMyStreet::App->model('DB::User')->new( {
    name => 'Test User',
    email => 'test@example.com',
} );

my $problem = FixMyStreet::App->model('DB::Problem')->new( {
    id => 80,
    external_id => 81,
    state => 'confirmed',
    title => 'a problem',
    detail => 'problem detail',
    category => 'pothole',
    latitude => 1,
    longitude => 2,
    user => $user,
} );

subtest 'posting service request' => sub {
    my $extra = {
        url => 'http://example.com/report/1',
    };

    my $results = make_service_req( $problem, $extra, $problem->category, '<?xml version="1.0" encoding="utf-8"?><service_requests><request><service_request_id>248</service_request_id></request></service_requests>' );

    is $results->{ res }, 248, 'got request id';

    my $req = $o->test_req_used;

    my $description = <<EOT;
title: a problem

detail: problem detail

url: http://example.com/report/1

Submitted via FixMyStreet
EOT
;

    my $c = CGI::Simple->new( $results->{ req }->content );

    is $c->param('email'), $user->email, 'correct email';
    is $c->param('first_name'), 'Test', 'correct first name';
    is $c->param('last_name'), 'User', 'correct last name';
    is $c->param('lat'), 1, 'latitide correct';
    is $c->param('long'), 2, 'longitude correct';
    is $c->param('description'), $description, 'descritpion correct';
    is $c->param('service_code'), 'pothole', 'service code correct';
};

for my $test (
    {
        desc  => 'extra values in service request',
        extra => [
            {
                name  => 'title',
                value => 'A title',
            }
        ],
        params => [
            [ 'attribute[title]', 'A title', 'extra paramater used correctly' ]
        ]
    },
    {
        desc  => 'first and last names in extra used correctly',
        extra => [
            {
                name  => 'first_name',
                value => 'First',
            },
            {
                name  => 'last_name',
                value => 'Last',
            },
        ],
        params => [
            [ 'first_name', 'First', 'first name correct' ],
            [ 'last_name',  'Last',  'last name correct' ],
            [ 'attribute[first_name]', undef, 'no first_name attribute param' ],
            [ 'attribute[last_name]',  'Last', 'last_name attribute param correct' ],
        ],
    },
    {
        title => 'magic fms_extra parameters handled correctly',
        extra => [
            {
                name  => 'fms_extra_title',
                value => 'Extra title',
            }
        ],
        params => [
            [
                'attribute[title]',
                'Extra title',
                'fms_extra extra param used correctly'
            ]
        ],
    },
  )
{
    subtest $test->{desc} => sub {
        $problem->extra( $test->{extra} );

        my $extra = { url => 'http://example.com/report/1', };

        my $results = make_service_req( $problem, $extra, $problem->category,
'<?xml version="1.0" encoding="utf-8"?><service_requests><request><service_request_id>248</service_request_id></request></service_requests>'
        );
        my $req = $o->test_req_used;
        my $c   = CGI::Simple->new( $results->{req}->content );

        for my $param ( @{ $test->{params} } ) {
            is $c->param( $param->[0] ), $param->[1], $param->[2];
        }
    };
}

my $comment = FixMyStreet::App->model('DB::Comment')->new( {
    id => 38362,
    user => $user,
    problem => $problem,
    anonymous => 0,
    text => 'this is a comment',
    confirmed => $dt,
    extra => { title => 'Mr', email_alerts_requested => 0 },
} );

subtest 'basic request update post parameters' => sub {
    my $results = make_update_req( $comment, '<?xml version="1.0" encoding="utf-8"?><service_request_updates><request_update><update_id>248</update_id></request_update></service_request_updates>' );

    is $results->{ res }, 248, 'got update id';

    my $req = $o->test_req_used;

    my $c = CGI::Simple->new( $results->{ req }->content );

    is $c->param('description'), 'this is a comment', 'email correct';
    is $c->param('email'), 'test@example.com', 'email correct';
    is $c->param('status'), 'OPEN', 'status correct';
    is $c->param('service_request_id_ext'), 80, 'external request id correct';
    is $c->param('service_request_id'), 81, 'request id correct';
    is $c->param('public_anonymity_required'), 'FALSE', 'anon status correct';
    is $c->param('updated_datetime'), $dt, 'correct date';
    is $c->param('title'), 'Mr', 'correct title';
    is $c->param('last_name'), 'User', 'correct first name';
    is $c->param('first_name'), 'Test', 'correct second name';
    is $c->param('email_alerts_requested'), 'FALSE', 'email alerts flag correct';
};

foreach my $test (
    {
        desc => 'comment with fixed state sends status of CLOSED',
        state => 'fixed',
        anon  => 0,
        status => 'CLOSED',
    },
    {
        desc => 'comment with fixed - user state sends status of CLOSED',
        state => 'fixed - user',
        anon  => 0,
        status => 'CLOSED',
    },
    {
        desc => 'comment with fixed - council state sends status of CLOSED',
        state => 'fixed - council',
        anon  => 0,
        status => 'CLOSED',
    },
    {
        desc => 'comment with closed state sends status of CLOSED',
        state => 'closed',
        anon  => 0,
        status => 'CLOSED',
    },
    {
        desc => 'comment with investigating state sends status of OPEN',
        state => 'investigating',
        anon  => 0,
        status => 'OPEN',
    },
    {
        desc => 'comment with planned state sends status of OPEN',
        state => 'planned',
        anon  => 0,
        status => 'OPEN',
    },
    {
        desc => 'comment with in progress state sends status of OPEN',
        state => 'in progress',
        anon  => 0,
        status => 'OPEN',
    },
    {
        desc => 'anonymous commment sets public_anonymity_required to true',
        state => 'confirmed',
        anon  => 1,
        status => 'OPEN',
    },
) {
    subtest $test->{desc} => sub {
        $comment->problem->state( $test->{state} );
        $comment->anonymous( $test->{anon} );

        my $results = make_update_req( $comment, '<?xml version="1.0" encoding="utf-8"?><service_request_updates><request_update><update_id>248</update_id></request_update></service_request_updates>' );

        my $c = CGI::Simple->new( $results->{ req }->content );
        is $c->param('status'), $test->{status}, 'correct status';
        is $c->param('public_anonymity_required'), $test->{anon} ? 'TRUE' : 'FALSE', 'correct anonymity';
    };
}


for my $test (
    {
        desc         => 'update name name taken from comment over user',
        comment_name => 'First Last',
        user_name    => 'Personal Family',
        extra        => undef,
        first_name   => 'First',
        last_name    => 'Last'
    },
    {
        desc         => 'update name name taken from user if no comment name',
        comment_name => '',
        user_name    => 'Personal Family',
        extra        => undef,
        first_name   => 'Personal',
        last_name    => 'Family'
    },
    {
        desc         => 'update name taken from extra if available',
        comment_name => 'First Last',
        user_name    => 'Personal Family',
        extra        => { first_name => 'Forename', last_name => 'Surname' },
        first_name   => 'Forename',
        last_name    => 'Surname'
    },
  )
{
    subtest $test->{desc} => sub {
        $comment->name( $test->{comment_name} );
        $user->name( $test->{user_name} );
        $comment->extra( $test->{ extra } );

        my $results = make_update_req( $comment,
'<?xml version="1.0" encoding="utf-8"?><service_request_updates><request_update><update_id>248</update_id></request_update></service_request_updates>'
        );

        my $c = CGI::Simple->new( $results->{req}->content );
        is $c->param('first_name'), $test->{first_name}, 'first name correct';
        is $c->param('last_name'),  $test->{last_name},  'last name correct';
    };
}

subtest 'No update id in reponse' => sub {
    my $results;
    warning_like {
        $results = make_update_req( $comment, '<?xml version="1.0" encoding="utf-8"?><service_request_updates><request_update><update_id></update_id></request_update></service_request_updates>' )
    } qr/Failed to submit comment \d+ over Open311/, 'correct error message';

    is $results->{ res }, 0, 'No update_id is a failure';
};

subtest 'error reponse' => sub {
    my $results;
    warning_like {
        $results = make_update_req( $comment, '<?xml version="1.0" encoding="utf-8"?><errors><error><code>400</code><description>There was an error</description</error></errors>' )
    } qr/Failed to submit comment \d+ over Open311.*There was an error/, 'correct error messages';

    is $results->{ res }, 0, 'error in response is a failure';
};

done_testing();

sub make_update_req {
    my $comment = shift;
    my $xml = shift;

    return make_req( $comment, $xml, 'post_service_request_update', 'update.xml' );
}

sub make_service_req {
    my $problem = shift;
    my $extra = shift;
    my $service_code = shift;
    my $xml = shift;

    return make_req( $problem, $xml, 'send_service_request', 'requests.xml', $extra, $service_code );
}

sub make_req {
    my $object = shift;
    my $xml    = shift;
    my $method = shift;
    my $path   = shift;
    my @args   = @_;

    my $o =
      Open311->new( test_mode => 1, end_point => 'http://localhost/o311' );

    my $test_res = HTTP::Response->new();
    $test_res->code(200);
    $test_res->message('OK');
    $test_res->content($xml);

    $o->test_get_returns( { $path => $test_res } );

    my $res = $o->$method($object, @args);

    my $req = $o->test_req_used;

    return { res => $res, req => $req };
}
