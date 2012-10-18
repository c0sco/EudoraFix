#!/usr/bin/perl

##############################################################################
##################### longfile.pl
##################### Part of EudoraFix.app
##################### Matt Stofko <matt@mjslabs.com>
##############################################################################

$| = 1;
use warnings;
use strict;
use Tie::File;
use Cwd;
use File::Find;
use File::Copy;
use DBI;

our ($tocdata, $tocres, $numrecs, $mbx, @dataref, $resref, %tocoffsetindex, $lookupid, $basepath);
our ($dbh, $dsn);

our ($line, $filename, $msginode, $nameinode, $nameprefix, $inoderef);

# Skip old-style TOC files and mailboxes that use them
exit if (-e "$ARGV[0].toc" or $ARGV[0] =~ /\.toc$/);


# Get our paths
($lookupid = $0) =~ s|^(.*?)/[^/]*$|$1/lookupid|;
$basepath = $1;
$lookupid =~ s|\s|\\ |g;

print "\n*** Starting repair of $ARGV[0]...\n";

# Tie the data fork of the mailbox
$mbx = tie(@dataref, 'Tie::File', $ARGV[0], recsep => "\r") or die "Can't open mailbox data fork: $!";

=cut
# Initialize file database and connect, reindexing if necessary
my $reindex_new = !-e "$basepath/new.index";
my $reindex_old = !-e "$basepath/file.index.
$dbh = DBI->connect("dbi:SQLite:dbname=$basepath/file.index", '', '');
if ($reindex) {
	print "Reindexing files in $ARGV[0]...\n";
	initCatalogSql();
	$dbh->do(qq|begin transaction|);
	find(\&scanfiles, $ARGV[0]);
	$dbh->do(qq|commit|);
}
=cut

# Look for the attachments
foreach $line (@dataref) {
	if ($line =~ /^\QAttachment converted: \E(.*?)\:(.*?\#.*?) \(\w{4}\/\w{4}\) \((.*?)\)$/) {
		# parse the line into:
		$filename = $2; # full filename, pound sign and all
		$msginode = $3; # the inode
		($nameinode = $filename) =~ s/^(.*?)\#([a-z0-9A-Z]+).*$/$2/; # the number after the # in the filename
		$nameprefix = $1; # the file name up to the #
#		print "$filename - $msginode - $nameinode - $nameprefix\n";

		# first check to see if the file exists in the current attachments directory, if so then skip this line
		next if -e "$ARGV[2]/$filename";
		
		# now check to see if it exists in the old attachments directory by the inode
		$inoderef = `$lookupid $msginode $ARGV[1]`;
		if ($inoderef =~ /^$ARGV[1]/) { # found it in the old attachments directory with /path/name of $inoderef
			$inoderef =~ m|^(.*?)/([^/]+)$|; # put the basename into $1
			next if !(-e "$ARGV[2]/$1"); # move on if the old filename doesn't exist in the new attach dir
			my $padlength = length $msginode;
			$newinode = sprintf("%0${padlength}x", (stat "$ARGV[2]/$1")[1]); # otherwise get the inode of it in the new location
			$line =~ s/\(\w+\)$/$newinode/; # and put it in the message
			next;
		}
		# it found a file but it wasn't in the attachments directory
		elsif ($inoderef !~ /^Error.*(\d)+$/) {
		
			next;
		}
		
		# now as a last resort check by the inode listed in the file name
		$inoderef = `$lookupid $nameinode $ARGV[1]`;
		if ($inoderef =~ /^$ARGV[1]/) { # found it in the old attachments directory with /path/name of $inoderef
			
			next;
		}
		# it found a file but it wasn't in the attachments directory
		elsif ($inoderef !~ /^Error.*(\d)+$/) {
		
			next;
		}
		
		# i give up
	}
}

# Close files and exit
#$dbh->disconnect;
untie(@dataref);
exit 0;

##############################################################################
##################### subs
##############################################################################

#### findOnFSSql
#### Return a file's info from our catalog (a sqlite database, specifically)
sub findOnFSSql {
	my $filehash = execsql_hashref(qq|select * from fileindex where filename = "$_[0]"|, 'fileindex', 'filename');
	return 0 if !(keys %{$filehash});
	return [($filehash->{$_[0]}->{'inode'}, $filehash->{$_[0]}->{'directory'})];
}

#### initCatalogSql
#### create our table used for the file catalog
sub initCatalogSql {
	$dbh->do(qq|CREATE TABLE `fileindex` (`id` integer primary key,`filename` varchar(255) default NULL,`directory` varchar(255) default NULL,`inode` integer default NULL)|);
}



#### execsql_hashref
#### Run a bit of sql and return the results in an anonymous hash
sub execsql_hashref {
	my $sth = $dbh->prepare($_[0]);
	my $rv = $sth->execute;
	my $hashref = $sth->fetchall_hashref($_[2]) or die "DB error occured: $sth->errstr";
	$sth->finish;
	return {%{$hashref}};
}

# EOF