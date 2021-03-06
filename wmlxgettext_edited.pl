#!/usr/bin/perl -w

# FIXME:
# - maybe restrict "ability" matching to unit defs (not yet necessary)

use strict;
use File::Basename;
use POSIX qw(strftime);
use Getopt::Long;

# use utf8 for stdout and file reading
use utf8;
use open IO => ':utf8';
binmode(STDOUT, ':utf8');

our $toplevel = '.';
our $initialdomain = 'wesnoth';
our $domain = undef;
GetOptions ('directory=s' => \$toplevel,
	    'initialdomain=s' => \$initialdomain,
	    'domain=s' => \$domain);

$domain = $initialdomain unless defined $domain;

sub wml2postring {
  my $str = shift;

  $str =~ s/\"\"/\\\"/mg; # "" -> \"
  $str =~ s/^(.*)$/"$1\\n"/mg; # Surround with doublequotes and add final escaped newline
  $str =~ s/\n$/\n"\\n"/mg; # Split the string around newlines: "foo\nbar" -> "foo\n" LF "bar"
  $str =~ s/\\n\"$/\"\n/g; # Remove final escaped newline and add newline after last line

  return $str;
}

sub lua2postring {
  my $str = shift;
  my $quote = shift;

  if ($quote eq "'") {
    $str =~ s/"/\\"/g;
  }
  $str =~ s/^(.*)$/"$1\\n"/mg; # Surround with doublequotes and add final escaped newline
  $str =~ s/\n$/\n"\\n"/mg; # Split the string around newlines: "foo\nbar" -> "foo\n" LF "bar"
  $str =~ s/\\n\"$/\"\n/g; # Remove final escaped newline and add newline after last line

  return $str;
}

## extract strings with their refs and node info into %messages

sub possible_node_info {
  my ($nodeinfostack, $field, $value) = @_;
  if ($field =~ m/\b(speaker|id|role|description|condition|type|race)\b/) {
    push @{$nodeinfostack->[-1][2]}, "$field=$value";
  }
}

sub read_wml_file {
  my ($file) = @_;
  our (%messages,%nodeinfo);
  my ($str, $translatable, $line);
  my $readingattack = 0;
  my @nodeinfostack = (["top", [], [], []]); # dummy top node
  my @domainstack = ($initialdomain);
  my $valid_wml = 1;
  open (FILE, "<$file") or die "cannot read from $file";
 LINE: while (<FILE>) {
    # record a #define scope
    if (m/\#define/) {
      unshift @domainstack, $domainstack[0];
      next LINE;
    } elsif (m/^\s*\#enddef/) {
      shift @domainstack;
    }

    # change the current textdomain when hitting the directive
    if (m/\#textdomain\s+(\S+)/) {
      $domainstack[0] = $1;
      next LINE;
    }

    if (m/\#\s*po:\s+(.+)/) {
      push @{$nodeinfostack[-1][3]}, $1;
    }

    # skip other # lines as comments
    next LINE if m/^\s*\#/ and !defined $str and not m/#\s*wmlxgettext/;

    if (!defined $str and m/^(?:[^\"]*?)((?:_\s*)?)\"([^\"]*(?:\"\"[^\"]*)*)\"(.*)/) {
      # single-line quoted string

      $translatable = ($1 ne '');
      my $rest = $3;

      # if translatable and in the requested domain
      if ($translatable and $domainstack[0] eq $domain) {
        my $msg = wml2postring($2);
        push @{$messages{$msg}}, [$file, $.];
        push @{$nodeinfostack[-1][1]}, $msg if $valid_wml;

      } elsif (not $translatable and m/(\S+)\s*=\s*\"([^\"]*)\"/) {
        # may be a piece of node info to extract
        possible_node_info(\@nodeinfostack, $1, $2) if $valid_wml;
      }

      # process remaining of the line
      $_ = $rest . "\n";
      redo LINE;

    } elsif (!defined $str and m/^(?:[^\"]*?)((?:_\s*)?)\s*\"([^\"]*(?:\"\"[^\"]*)*)/) {
      # start of multi-line

      $translatable = ($1 ne '');
      $_ = $2;
      if (m/(.*)\r/) { $_ = "$1\n"; }
      $str = $_;
      $line = $.;

    } elsif (m/([^\"]*(?:\"\"[^\"]*)*)\"(.*)/) {
      # end of multi-line
      die "end of string without a start in $file" if !defined $str;

      $str .= $1;

      if ($translatable and $domainstack[0] eq $domain) {
        my $msg = "\"\"\n" . wml2postring($str);
        push @{$messages{$msg}}, [$file, $line];
        push @{$nodeinfostack[-1][1]}, $msg if $valid_wml;
      }
      $str = undef;

      # process remaining of the line
      $_ = $2 . "\n";
      redo LINE;

    } elsif (defined $str) {
      # part of multi-line
      if (m/(.*)\r/) { $_ = "$1\n"; }
      $str .= $_;

    } elsif (m/(\S+)\s*=\s*(.*?)\s*$/) {
      # single-line non-quoted string
      die "nested string in $file" if defined $str;
      possible_node_info(\@nodeinfostack, $1, $2) if $valid_wml;

### probably not needed ###
#      # magic handling of weapon descriptions
#      push @{$messages{wml2postring($2)}},  "$file:$."
#	if $readingattack and
#	  ($1 eq 'name' or $1 eq 'type' or $1 eq 'special');
#
#      # magic handling of unit abilities
#      push @{$messages{wml2postring($2)}},  "$file:$."
#	if $1 eq 'ability';

    } elsif (m,\[attack\],) {
      $readingattack = 1;
    } elsif (m,\[/attack\],) {
      $readingattack = 0;
    }

    # check for node opening/closing to handle message metadata
    next LINE if not $valid_wml;
    next LINE if defined $str; # skip lookup if inside multi-line
    next LINE if m/^ *\{.*\} *$/; # skip lookup if a statement line
    next LINE if m/^[^#]*=/; # skip lookup if a field line
    while (m,\[ *([a-z/+].*?) *\],g) {
      my $nodename = $1;
      #my $ind = "  " x (@nodeinfostack + ($nodename =~ m,/, ? 0 : 1));
      if ($nodename =~ s,/ *,,) { # closing node
        if (@nodeinfostack == 0) {
          warn "empty node stack on closed node at $file:$.";
          $valid_wml = 1;#hacky workaround for now
          last;
        }
        my ($openname, $nodemessages, $metadata, $comments) = @{pop @nodeinfostack};
        if ($nodename ne $openname) {
          warn "expected closed node \'$openname\' ".
               "got \'$nodename\' at $file:$.";
          $valid_wml = 1;#hacky workaround for now
          last;
        }
        # some nodes should inherit parent metadata
        if ($nodename =~ m/option/) {
          $metadata = $nodeinfostack[-1][2];
        }
        #print STDERR "$ind<<< $.: $nodename\n";
        #print STDERR "==> $file:$.: $nodename: @{$metadata}\n" if @{$nodemessages};
        for my $msg (@{$nodemessages}) {
          push @{$nodeinfo{$msg}}, [$nodename, $metadata, $comments];
        }
      } else { # opening node
        #print STDERR "$ind>>> $.: $nodename\n";
        $nodename =~ s/\+//;
        push @nodeinfostack, [$nodename, [], [], []];
      }
    }
    # do not add anything here, beware of the next's before the loop
  }
  pop @nodeinfostack if @nodeinfostack; # dummy top node
  if (@nodeinfostack) {
    warn "non-empty node stack at end of $file";
    $valid_wml = 1;#hacky workaround for now
  }

  close FILE;

  if (not $valid_wml) {
    warn "WML seems invalid for $file, node info extraction forfeited ".
         "past the error point";
  }
}

sub read_lua_file {
  my ($file) = @_;
  our (%messages,%nodeinfo);
  my ($str, $translatable, $line, $quote);
  my $curdomain = $initialdomain;
  my $metadata = undef;
  open (FILE, "<$file") or die "cannot read from $file";
  LINE: while (<FILE>) {
    if (defined $metadata and m/--\s*po:\s*(.*)$/) {
      push @{@{$metadata}[2]}, $1;
    }

    # skip comments unless told not to
    next LINE if m/^\s*--/ and not defined $str and not m/--\s*wmlxgettext/;

    # change the textdomain
    if (m/textdomain\s*\(?\s*(["'])([^"]+)\g1(.*)/) {
      $curdomain = $2;

      # process rest of the line
      $_ = $3 . "\n";
      redo LINE;
    }

    # Single-line quoted string
    # TODO: support [[long strings]]
    # TODO: get 'singlequotes' to work
    if (not defined $str and m/^(?:[^"]*?)((?:_\s*)?)\s*(")([^"]*(?:\\"[^"]*)*)"(.*)/) {
      # $1 = underscore or not
      # $2 = quote (double or single)
      # $3 = string
      # $4 = rest
      my $translatable = ($1 ne '');
      my $rest = $4;

      if ($translatable and $curdomain eq $domain) {
        my $msg = lua2postring($3, $2);
        push @{$messages{$msg}}, [$file, $.];
        push @{$nodeinfo{$msg}}, $metadata if defined $metadata;
      }

      # process rest of the line
      $_ = $rest . "\n";
      redo LINE;
    }
    # Begin multiline quoted string
    elsif (not defined $str and m/^(?:[^"]*?)((?:_\s*)?)\s*(")([^"]*(?:\\"[^"]*)*)/) {
      # $1 = underscore or not
      # $2 = quote (double or single)
      # $3 = string
      $translatable = ($1 ne '');
      $quote = $2;
      $str = $3;
      $line = $.;
    }
    # End multiline quoted string
    elsif (m/([^"]*(?:\\"[^"]*)*)(")(.*)/) {
      # $1 = string
      # $2 = quote (double or single)
      # $3 = rest
      die "end of string without a start in $file" if not defined $str;

      $str .= $1;
      my $rest = $3;

      # TODO: ensure $quote eq $2 when this matches
      if ($translatable and $curdomain eq $domain) {
        my $msg = "\"\"\n" . lua2postring($str, $quote);
        push @{$messages{$msg}}, [$file, $line];
        push @{$nodeinfo{$msg}}, $metadata if defined $metadata;
      }
      $str = undef;
      $translatable = undef;
      $line = undef;
      $quote = undef;

      # process rest of the line
      $_ = $rest . "\n";
      redo LINE;
    }
    # Middle of multiline quoted string
    elsif (defined $str) {
      $str .= $_;
    }
    # Function or WML tag
    elsif (m/function\s+([a-zA-Z0-9_.]+)\s*\(/ or m/([a-zA-Z0-9_.]+)\s*=\s*function/) {
      $metadata = ["lua", [$1], []];
    }
  }
}

our (%messages,%nodeinfo);
chdir $toplevel;
foreach my $file (@ARGV) {
  if ($file =~ m/\.lua$/i) {
    read_lua_file($file);
  } else {
    read_wml_file($file);
  }
}

## index strings by their location in the source so we can sort them

our @revmessages;
foreach my $key (keys %messages) {
  foreach my $line (@{$messages{$key}}) {
    my ($file, $lineno) = @{$line};
    push @revmessages, [ $file, $lineno, $key ];
  }
}

# sort them
@revmessages = sort { $a->[0] cmp $b->[0] or $a->[1] <=> $b->[1] } @revmessages;


## output

my $date = strftime "%F %R%z", localtime();

print <<EOH
msgid ""
msgstr ""
"Project-Id-Version: PACKAGE VERSION\\n"
"Report-Msgid-Bugs-To: https://bugs.wesnoth.org/\\n"
"POT-Creation-Date: $date\\n"
EOH
;
# we must break this string to avoid triggering a bug in some po-mode
# installations, at save-time for this file
print "\"PO-Revision-Date: YEAR-MO-DA ", "HO:MI+ZONE\\n\"\n";
print <<EOH
"Last-Translator: FULL NAME <EMAIL\@ADDRESS>\\n"
"Language-Team: LANGUAGE <LL\@li.org>\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"

EOH
;

foreach my $occurence (@revmessages) {
  my $key = $occurence->[2];
  if (defined $messages{$key}) {
    if (defined $nodeinfo{$key}) {
      my %added;
      my @lines;
      for my $info (@{$nodeinfo{$key}}) {
        my ($name, $data, $comments) = @{$info};
        my $desc = join(", ", @{$data});
        my $nodestr = $desc ? "[$name]: $desc" : "[$name]";
        # Add only unique node info strings.
        if (not defined $added{$nodestr}) {
            $added{$nodestr} = 1;
            push @lines, [sprintf("#. %s\n", $nodestr), []];
        }
        foreach my $comment (@{$comments}) {
            push @{@{$lines[-1]}[1]}, sprintf("#. $comment\n");
        }
      }
      for my $line (sort { @{$a}[0] cmp @{$b}[0] } @lines) {
        my ($tag, $comments) = @{$line};
        print $tag;
        foreach my $comment (@{$comments}) {
          print $comment;
        }
      }
    }
    my @msgs = sort { $a->[0] cmp $b->[0] or $a->[1] <=> $b->[1] } @{$messages{$key}};
    my @msgsfmt;
    foreach my $msg (@msgs) {
      my ($file, $line) = @{$msg};
      push @msgsfmt, "$file:$line";
    }
    my $locationdata = join(" ", @msgsfmt);
#    die "Translatable empty string at $locationdata" if $key =~ /^""\n$/;
    printf "#: %s\n", $locationdata;
    print "msgid $key";
    print "msgstr \"\"\n\n";

    # be sure we don't output the same message twice
    delete $messages{$key};
  }
}
