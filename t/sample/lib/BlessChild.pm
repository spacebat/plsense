package BlessChild;

use strict;
use warnings;
use BlessParent;

our @ISA = qw{ BlessParent };

sub new {
    my ($class, $arg_ref) = @_;
    my $self = $class->SUPER::new($arg_ref);
    bless $self, $class;
    return $self;
}

sub set_bar {
    my ($self, $bar) = @_;
    $self->{bar} = $bar;
}

sub get_bar {
    my ($self) = @_;
    return $self->{bar};

    # tstart own method of blessed child class
    #$self->
    # tend equal: SUPER::get_fuga SUPER::get_hoge SUPER::new SUPER::set_fuga SUPER::set_hoge can get_bar get_foo get_fuga get_hoge isa new set_bar set_fuga set_hoge
}

sub get_foo {
    my ($self) = @_;
    return $self->SUPER::get_hoge;

    # tstart blessed hash member
    #$self->{
    # tend equal: bar
}

1;

__END__
