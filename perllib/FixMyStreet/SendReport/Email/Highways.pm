package FixMyStreet::SendReport::Email::Highways;

# this is more or less the same code as the TfL one

use Moo;
extends 'FixMyStreet::SendReport::Email::SingleBodyOnly';

has contact => (
    is => 'ro',
    default => 'Pothole'
);

1;
