#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Path qw(make_path);
use LWP::UserAgent;
use XML::Parser;

my $CONFIG_FILE = "$ENV{HOME}/.config/rss-watch/config";
my $LATEST_DIR = "$ENV{HOME}/.local/share/rss-watch/latest";
my %LATEST;
my %CONFIG;
my $OPT_IGNORE_LAST = 0;
my $XPARSER = XML::Parser->new(Style => 'Tree');

sub item2hash {
    my ($xml) = @_;
    my %ret = ();

    for (my $i = 1; $i < scalar @$xml; $i+=2) {
        my $key = $xml->[$i];
        next if $key eq 0;
        # index 0 is the attributes, or empty
        # index 1 is text value or empty
        my @val_arr;
        #print("Key: $key\n");
        my $val = $xml->[$i+1];
        # Copy the attributes
        push(@val_arr, $val->[0]);
        if (scalar @$val >= 3 && $val->[1] == 0) {
            # Type is a string, copy that as well
            push(@val_arr, $val->[2]);
        }
        $ret{$key} = \@val_arr;
    }

    #print(Dumper(\%ret));
    return \%ret;
}

sub getxmlchild {
    my ($xo, $ctname) = @_;
    my $start = 0;
    $start = 1 if (ref($xo->[0]) eq 'HASH');

    for (my $i = $start; $i < scalar @$xo; $i+=2) {
        if ($xo->[$i] eq $ctname) {
            return $xo->[$i+1];
        }
    }
    return undef;
}

sub filterxmlnodes {
    my ($xo, $ctname) = @_;
    my @ret = ();

    for (my $i = 1; $i < scalar @$xo; $i+=2) {
        #print("Processing: ", $xo->[$i], " \n");
        if ($xo->[$i] eq $ctname) {
            #print("Added\n");
            #print(scalar @ret, "\n");
            push(@ret, $xo->[$i+1]);
        }
    }
    return \@ret;
}

sub readfile {
    my ($fp) = @_;
    local $/ = undef;
    open my $fh, "<", $fp or die "could not open $fp $!";
    my $c = <$fh>;
    local $/ = "\n";
    chomp($c);
    close($fh);
    return $c;
}

sub writefile {
    my ($fp, $cont) = @_;
    open my $fh, ">", $fp or die "could not open $fp $!";
    print($fh $cont, "\n");
    close($fh) or die "Couldn't close file $fp $!";
}

sub parse_latest {
    if (not -d $LATEST_DIR) {
        my $crt = make_path($LATEST_DIR);
        if ($crt == 0) {
            print("Cannot create latest directory!\n");
            exit 1;
        }
    }

    my @files = glob($LATEST_DIR . '/*');
    foreach my $fp (@files) {
        my $key = basename($fp);

        $LATEST{$key} = readfile($fp);
    }
    #print("LATEST\n");
    #print(Dumper(\%LATEST));
}

sub save_latest {
    my ($fname) = @_;
    return if not defined($LATEST{$fname});
    writefile("$LATEST_DIR/$fname", $LATEST{$fname});
}

sub parse_config {
    open(my $fh, "<", $CONFIG_FILE) or die('Cannot open config file');
    my @feeds = ();
    my %curr_feed = ();

    my $line = 0;
    while (<$fh>) {
        $line++;
        chomp;
        my $l = $_;

        next if ($l eq "" or $l =~ m/^#/);

        if ($l =~ m/^\[feed\s+(.*)\]$/) {
            my $name = $1;

            if (scalar %curr_feed > 0) {
                push(@feeds, {%curr_feed});
            }
            %curr_feed = ();

            if (not defined($name)) {
                print("No name for need!\n");
                exit 1;
            }
            $curr_feed{name} = $name;
            next;
        }

        #print("Line: $l\n");
        my @parts = split(/\s+=\s+/, $l, 2);
        if (scalar @parts != 2) {
            print("Error in config at line: $line\n");
            exit 1;
        }
        my $key = $parts[0];
        my $val = $parts[1];
        if ($key eq "script") {
            # Allow more than one script to be specified
            if (defined($curr_feed{script})) {
                push(@{$curr_feed{script}}, $val);
            } else {
                $curr_feed{script} = [ $val ];
            }
        } else {
            # Normal operation for other keys
            $curr_feed{$parts[0]} = $parts[1];
        }
    }
    if (scalar %curr_feed > 0) {
        push(@feeds, {%curr_feed});
    }

    $CONFIG{feeds} = \@feeds;
    
    close($fh);
}

sub sh_escape {
    my ($txt) = @_;
    $txt =~ s/'/'\\''/;
    return $txt;
}

sub exec_script {
    my ($feed, $xmlitem) = @_;

    my $cmdArr = $feed->{script};
    #print(Dumper($xmlitem));
    foreach my $cmdRef (@$cmdArr) {
        my $cmd = $cmdRef; # Copy it

        while ($cmd =~ /[^\\]\$([\w:<>]+)/g) {
            my $fullmatch = $1;
            my $key;
            my $attr;
            if ($fullmatch =~ /^(.*?)<(.*?)>/) {
                # If key specifies an attribute
                $key = $1;
                $attr = $2;
            } else {
                $key = $1;
            }
            #print("Matched: $key with attr: $attr\n");
            if (not exists $xmlitem->{$key}) {
                print("No xml entry with key: '$key' found. Skipping\n");
                next;
            }
            my $val;
            if ($attr) {
                # We want the attribue's value, not the contents of the tag
                if (not exists $xmlitem->{$key}[0]->{$attr}) {
                    print("No xml attribute entry with key: '$key' and attr: '$attr' found. Skipping\n");
                    next;
                }
                $val = $xmlitem->{$key}[0]->{$attr};
            } else {
                $val = $xmlitem->{$key}[1];
            }
            #print("Using: $val\n");
            my $escaped_val = sh_escape($val);
            $cmd =~ s/\$$fullmatch/$escaped_val/;
        }

        qx($cmd);
    }
}

sub handle_feed {
    my ($xml, $feed) = @_;
    my $xobj = $XPARSER->parse($xml);
    my $fname = $feed->{name};
    #print(Dumper(\$xobj));

    #$xobj{rss};
    #print($xobj[0]);
    my $rss = getxmlchild($xobj, "rss");
    return undef if not defined($rss);
    $rss = getxmlchild($rss, "channel");
    return undef if not defined($rss);
    my $items = filterxmlnodes($rss, "item");
    return undef if (scalar @$items == 0);
    #print(Dumper($items));

    my $last_hit = 0;
    # Convert xml items into perl hashes
    my @item_hashes = ();
    foreach (@$items) {
        my $item_hash = item2hash($_);

        if ($OPT_IGNORE_LAST == 0 && defined($LATEST{$fname}) and $LATEST{$fname} eq $item_hash->{guid}[1]) {
            # Stop if we reached the last handled item
            # or if there is no 'last' defined
            $last_hit = 1;
            last;
        }
        push(@item_hashes, $item_hash);
    }
    my $lastid = $item_hashes[0]->{guid}[1];
    #print(Dumper(\@item_hashes));
    if (not defined($lastid)) {
        if ($last_hit) {
            # No new entries
            return 1;
        } else {
            # Last is not hit, but items are empty?
            # Possibly an error
            return 0;
        }
    }

    if ($OPT_IGNORE_LAST == 0 && not defined($LATEST{$fname})) {
        # This is most likely the first run, do not run all of the backlog
        # only the items after this one
        $LATEST{$fname} = $lastid;
        save_latest($fname);
        return 1;
    }
    if (defined($LATEST{$fname}) and not $last_hit) {
        print("Possible missed releases in feed '$fname'\n");
    }

    $LATEST{$fname} = $lastid;

    #print("Last id: $lastid\n");

    foreach (@item_hashes) {
        exec_script($feed, $_);
    }

    if ($OPT_IGNORE_LAST == 0) {
        save_latest($fname);
    }

    return 1;
}




if (! -f $CONFIG_FILE) {
    print("No config file exists, create one!\n");
    exit 1;
}

# Undocumented debug option
$OPT_IGNORE_LAST = scalar @ARGV >= 1 && $ARGV[0] eq "-d";

parse_config();
#print(Dumper(\%CONFIG));
#exit;
parse_latest();

my $ua = LWP::UserAgent->new();
$ua->agent('RssWatch');
#print(Dumper(\%CONFIG));
foreach (@{$CONFIG{feeds}}) {
    my $item = $_;
    my $resp = $ua->get($item->{url});
    if (not $resp->is_success) {
        print("Failed to GET url: '$item->{url}' status: ", $resp->status_line, "\n");
        next;
    }

    my $fret = handle_feed($resp->decoded_content, $item);
    if (not $fret) {
        print("Getting feed failed\n");
    }
    #print($resp->decoded_content, "\n");
}
