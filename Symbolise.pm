#!/usr/bin/perl
use strict;

package Symbolise;

sub new {
    my ($class, $file) = @_;

    my $self = {
        'file' => $file,
        'line' => 0,
        'character' => 0,
        'content' => '',
        'length' => 0,
        'output' => '',

        'blocks' => [],
        'symbols' => {},

        'options' => {
            'strip_comments' => 0,
            'window_eq_this' => 0,
        },
    };

    bless $self, $class;

    $self->load;

    return $self;
}

sub load {
    my $self = shift;

    $self->{'content'} = do {
        local $/ = undef;
        open my $fh, "<", $self->{'file'} or die "Couldn't open file: $!";
        <$fh>;
    };

    $self->{'length'} = length $self->{'content'};

    return $self->{'content'};
}

sub process {
    my ($self, $args) = @_;

    $self->{'options'} = {(%{$self->{'options'}}, %{$args || {}})};

    my $output  = '';
    $self->parse_blocks;

    my @filtered_symbols;

    for (keys %{$self->{'symbols'}}) {
        my $l = length $_;
        push @filtered_symbols, $_ if (
            # only keep combinations that will save bytes
            ($self->{'symbols'}->{$_} > 1) &&
            (
                # this is hard, with strings that are two chars long you might save bytes
                # but with properties it's unlikely... set arbitrarily high
                ($l == 2 && $self->{'symbols'}->{$_} > 7) ||
                ($l == 3 && $self->{'symbols'}->{$_} > 6) ||
                ($l == 4 && $self->{'symbols'}->{$_} > 3) ||
                (($l == 5 || $l == 6 || $l == 7 || $l == 8) && $self->{'symbols'}->{$_} > 2) ||
                ($l > 8)
            )
        );
    }

    my $translate = {};
    my $specials = {
        'window' => 'sym__g_window_',
        'null' => 'sym__g_null_',
        'false' => 'sym__g_false_',
        'true' => 'sym__g_true_',
    };

    for (@filtered_symbols) {
        my $s = $_;
        $s =~ s/[^a-z0-9_]/_/gi;

        # let's not worry about anything that contains a non-word chars yet
        unless ($s =~ /_/) {
            $translate->{$_} = "sym__${s}_";
        }
    }

    # might even be able to optimise away some strings...
    for my $i (0..scalar @{$self->{'blocks'}}) {
        my ($block                  , $next_block                   ) = 
           ($self->{'blocks'}->[$i] , $self->{'blocks'}->[$i + 1]   );

        if ($block->{'scope'} eq 'plain') {
            my $check = $block->{'content'};

            for (keys %{$translate}) {
                my ($search, $replace) = (quotemeta $_, quotemeta $translate->{$_});
                $check =~ s/\.$search\b/\[$replace\]/g;
            }

            # shrink false, true and null
            for (keys %{$specials}) {
                my ($search, $replace) = ($_, $specials->{$_});
                $check =~ s/(?<![a-z0-9_\$])$search(?![a-z0-9_\$])/$replace/g;
            }

            $output .= $check;
        }
        elsif ($block->{'scope'} eq 'string') {
            my $check = $block->{'content'};
            $check =~ s/^['"]|['"]$//g;

            if (defined $translate->{$check}) {
                # if this is true, this content is most likely an Object key
                if ($next_block->{'scope'} eq 'plain' && $next_block->{'content'} =~ /\A\s*:/) {
                    $output .= $block->{'content'};
                }
                else {
                    $output .= $translate->{$check};

                    # catch 'string'in obj
                    if ($next_block->{'scope'} eq 'plain' && $next_block->{'content'} =~ /\Ain/) {
                        $output .= ' ';
                    }
                }
            }
            else {
                $output .= $block->{'content'};
            }
        }
        elsif ($block->{'scope'} eq 'comment') {
            if (!$self->{'options'}->{'strip_comments'}) {
                $output .= $block->{'content'};
            }
        }
        else {
            $output .= $block->{'content'};
        }
    }

    my $values = '"'.(join('", "', keys %{$translate})).'"';
    my $params = join(', ', values %{$translate});

    $values = ($self->{'options'}->{'window_eq_this'} ? 'this' : 'window').", null, !1, !0, $values";
    $params = "sym__g_window_, sym__g_null_, sym__g_false_, sym__g_true_, $params";

    $self->{'output'} = qq{(function($params){$output})($values);};

    return $self->{'output'};
}

sub parse_blocks {
    my $self = shift;

    my $last_block = {
        'content' => '',
    };

    while ($self->{'pos'} < $self->{'length'}) {
        my ($scope_content, $scope, $current_scope_end, $next_char) =
           (''            , ''    , qr//              , ''        );

        my $start = $self->{'pos'};
        my $last_content = $last_block->{'content'};

        while ($self->{'pos'} < $self->{'length'}) {
            my $char = substr $self->{'content'}, $self->{'pos'}, 1;
            $scope_content .= $char;
            $next_char = substr $self->{'content'}, $self->{'pos'} + 1, 1;

            if ($scope eq 'comment') {
                if ("$scope_content" =~ $current_scope_end) {
                    $self->{'pos'}++;
                    last;
                }
            }
            elsif ($scope eq 'string') {
                if ("$scope_content" !~ /\A['"]/) {
                    $scope = 'plain';
                }
                elsif ("$scope_content" =~ $current_scope_end) {
                    $self->{'pos'}++;
                    last;
                }
            }
            elsif ($scope eq 'regexp') {
                if ("$scope_content" =~ qr/\n/) {
                    $self->{'pos'} = $start + 1;
                    $scope_content = substr $self->{'content'}, $start, 2;
                    $scope = 'plain';
                }
                elsif ("$scope_content" =~ $current_scope_end) {
                    while ($next_char =~ /[gim]/) {
                        $scope_content .= $next_char;
                        $self->{'pos'}++;
                        $next_char = substr $self->{'content'}, $self->{'pos'} + 1, 1;
                    }

                    $self->{'pos'}++;
                    last;
                }
            }
            elsif ($scope eq 'plain') {
                if (
                    ("$scope_content$next_char" =~ qr/\/\*\Z/) ||
                    ("$scope_content$next_char" =~ qr/\/\/\Z/) ||
                    ("$scope_content" =~ qr/(?!<\\)(?:\\\\)*/ && "$next_char" =~ qr/\A['"]\Z/) ||
                    ("$scope_content" =~ qr/[^a-z0-9_\$]/ && "$next_char" =~ qr/\A\/\Z/i)
                ) {
                    $self->{'pos'}++;
                    last;
                };
            }
            else {
                if ("$scope_content$next_char" =~ qr/\/\*\Z/) {
                    $scope = 'comment';
                    $current_scope_end = qr/\*\/\Z/;
                }
                elsif ("$scope_content$next_char" =~ qr/\/\/\Z/) {
                    $scope = 'comment';
                    $current_scope_end = qr/[\n]\Z/;
                }
                elsif ("$last_content$scope_content" =~ qr/(?!<\\)(?:\\\\)*(['"])\Z/) {
                    $scope = 'string';
                    $current_scope_end = qr/(?<!\\)(?:\\\\)*$1\Z/;
                }
                elsif ("$last_content$scope_content" =~ qr/[^a-z0-9_\$]\/\Z/i) {
                    $scope = 'regexp';
                    $current_scope_end = qr/(?<!\\)(?:\\\\)*\/\Z/;
                }
                else {
                    $scope = 'plain';
                }
            }

            $self->{'pos'}++;
        }

        if ($scope eq 'plain') {
            my @plain_symbols = ($scope_content =~ /\.([a-z0-9_\$]+)(?![a-z0-9_\$])/gi);

            for (@plain_symbols) {
                if (!defined $self->{'symbols'}->{$_}) {
                    $self->{'symbols'}->{$_} = 0;
                }

                $self->{'symbols'}->{$_}++;
            }
        }
        elsif ($scope eq 'string') {
            my $symbol = substr $scope_content, 1, -1;

            if (!defined $self->{'symbols'}->{$symbol}) {
                $self->{'symbols'}->{$symbol} = 0;
            }

            $self->{'symbols'}->{$symbol}++;
        }

        $last_block = {
            'start'     => $start,
            'end'       => $self->{'pos'},
            'scope'     => $scope,
            'content'   => $scope_content,
        };

        push @{$self->{'blocks'}}, $last_block;
    }
}

1;
