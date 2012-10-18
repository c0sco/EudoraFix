#!/usr/bin/perl

##############################################################################
##################### attachsync.pl
##################### Part of EudoraFix.app
##################### Given a search path, a Eudora mailbox, and the Eudora 
##################### Attachments directory, try to relink attachments that no 
##################### longer work and that can be found in the search path -- 
##################### copying them to the Attachments directory if necessary.
##################### Usage: 
#####################  attachsync.pl <path to files> <mailbox> <Eudora Attachments path>
##################### Requirements:
#####################  Mac OS X 10.3.9 or 10.4+
#####################  Perl DBI module with SQLite driver
##################### Matt Stofko <matt@mjslabs.com>
##############################################################################

$| = 1;
use warnings;
use strict;
use Mac::Resources;
use Mac::Memory;
use Tie::File;
use Cwd;
use File::Find;
use File::Copy;
use DBI;

our ($tocdata, $tocres, $numrecs, $mbx, @dataref, $resref, %tocoffsetindex, $lookupid, $basepath);
our ($dbh, $dsn);
my $MACOS_CONSTANT_fsRdWrPerm = 3;

# Skip old-style TOC files and mailboxes that use them
exit if (-e "$ARGV[1].toc" or $ARGV[1] =~ /\.toc$/);

print "\n*** Starting repair of $ARGV[1]...\n";

# Open the resource fork and tie the data fork of the mailbox
$resref = FSOpenResourceFile($ARGV[1], "rsrc", $MACOS_CONSTANT_fsRdWrPerm);
UseResFile($resref);
$mbx = tie(@dataref, 'Tie::File', $ARGV[1], recsep => "\r") or die "Can't open mailbox data fork: $!";

# Get the TOC data from the resource fork
$tocres = GetResource("TOCF", 1001);
$tocdata = $tocres->get;

# calculate the number of TOC entries in this file for our loops
$numrecs = ((length($tocdata) - 278) / 220) - 1; # 278 byte header, 220 bytes per record, minus 1 to start at 0

# Get our current path and set the path to lookupid
($lookupid = $0) =~ s|^(.*?)/[^/]*$|$1/lookupid|;
$basepath = $1;
$lookupid =~ s| |\\ |g; # escape spaces

# Initialize file database and connect, reindexing if necessary
my $reindex = !-e "$basepath/file.index";
$dbh = DBI->connect("dbi:SQLite:dbname=$basepath/file.index", '', '');
my $loops = 0;
if ($reindex) {
	print "Reindexing files in $ARGV[0]...\n";
	initCatalogSql();
	$dbh->do(qq|begin transaction|);
	find(\&scanfiles, $ARGV[0]);
	$dbh->do(qq|commit|);
}

# Start the real work
print "Indexing TOC... ";
indexTOC();
print "done.\nRepairing mailbox...\n";
repairBox();

# Close files and exit
untie(@dataref);
$dbh->disconnect;
CloseResFile($resref);
exit 0;

##############################################################################
##################### subs
##############################################################################

#### indexTOC
#### build an index of the TOC records for searching them by their message offset in the main loop
sub indexTOC {
	use integer;
	my ($location, $msgoffsetLoc, $msgoffset);
	%tocoffsetindex = ();
	my $quarter = $#dataref / 4;
	foreach (0 .. $numrecs) {
		$location = 277 + (220 * $_); # the pointer to our TOC entry
		$msgoffsetLoc = $location + 1;
		$msgoffset = unpack("N", substr($tocdata, $msgoffsetLoc, 4));

		# break the search area into quarters so indexing really large files doesn't take quite as long
		my $start = $#dataref;
		while ($mbx->offset($start) > $msgoffset) { # back off a quarter at a time from the top until we get below the offset
			$start -= $quarter;
			$start = 0 if (($start - $quarter) < 0);
		}
		my $end = 0;
		while ($mbx->offset($end) < $msgoffset) { # go towards the end a quarter at a time from the start until we get above the offset
			$end += $quarter;
			$end = $#dataref if (($end + $quarter) > $#dataref);
		}

		for (; $start <= $end; $start++) {
			if ($mbx->offset($start) == $msgoffset) {
				if ($dataref[$start] =~ /^From\s+\Q???@???\E/) {	# if we found the start of a message
					$tocoffsetindex{$msgoffset} = $start;			# record its offset and line number
					last;
				}
			}
		}
	}
}

#### scanfiles
#### Called by find() to add file info to our catalog
sub scanfiles {
	return if /^\./;
	my @stats = stat('.');
	# use transactions to write out every 1000 entries
	if (!($loops % 1000)) { $dbh->do(qq|commit|); $dbh->do(qq|begin transaction|); }
	$dbh->do(qq|insert into fileindex (filename,directory,inode) values ("$_", "| . cwd() . qq|",$stats[1])|);
	$loops++;
}

#### repairBox
#### Main sub responsible for fixing the mailbox
sub repairBox {
	my $TOCchanged = 0;
	foreach my $rec (0 .. $numrecs) {
		my $location = 277 + (220 * $rec); # the pointer to our TOC entry
		my $msgoffsetLoc = $location + 1;
		my $msgsizLoc = $location + 7;
		my $msgheadLoc = $location + 11;
		my $msgattachLoc = $location + 52;
		my $attachHeadLine = 0;
		my $msgheadLine = -1;
		my ($msgsizLine);
		my ($found, $attachFname,$i,$attachment);
		my ($newline, $newsize,$newmsgsize,$oldmsgsize);

	# Find where in the data fork the message starts
		my $msgoffset = unpack("N", substr($tocdata, $msgoffsetLoc, 4));
		my $msgoffsetLine = $tocoffsetindex{$msgoffset};
		# error to be on the safe side if we can't find the exact start of the message
		print "No offset in index ($msgoffset) Record ", $rec+1, ".\n" if !exists $tocoffsetindex{$msgoffset};

	# Get the line the headers end on
		my $msghead = unpack("n", substr($tocdata, $msgheadLoc, 2));
		for ($i = $msgoffsetLine; $i <= $#dataref; $i++) {
			if ($mbx->offset($i) == ($msgoffset+$msghead)) {
				if (($dataref[$i] =~ /^\W*$/) or ($dataref[$i] =~ /^([\w\-]+\:)\s+.*$/) or ($dataref[$i] =~ /^\s*(.+?)\=(.+)\s*$/)) {
					# look for a blank line, or something that looks like a header, or possibly the continuation of a MIME type definition
					$msgheadLine = $i;
					last;
				}
			}
			if ($mbx->offset($i) > ($msgoffset+$msghead)) {
				if (($dataref[$i] =~ /^\W*$/) or ($dataref[$i] =~ /^([\w\-]+\:)\s+.*$/) or ($dataref[$i] =~ /^\s*(.+?)\=(.+)\s*$/)) {
					$msgheadLine = $i;
				}
			last; # end here no matter what since we are out of the range of the headers according to the TOC
			}
		}
		if ($msgheadLine == -1) {
			print "Can't find header boundry of record ", $rec+1, ", line $i ($dataref[$i]). Skipping.\n";
			next;
		}
		
	# Get the line the message ends on
		my $msgsiz = unpack("n", substr($tocdata, $msgsizLoc, 2));
		for ($i = $msgoffsetLine; $i <= $#dataref; $i++) {
			if ($mbx->offset($i) == ($msgoffset+$msgsiz)) {
				$msgsizLine = $i - 1;
				last;
			}
		}

	# Find attachments in the header (X-Attachments: lines)
		for ($i = $msgoffsetLine; $i <= $msgheadLine; $i++) {
			if ($dataref[$i] =~ /^\QX-Attachments: :\E/) {
				$attachHeadLine = $i;
				last;
			}
		}

	# Repair X-Attachments
		if ($attachHeadLine) {
			my ($attachPID, $newPID, $attachline);
			$oldmsgsize = length $dataref[$attachHeadLine];
			($attachline = $dataref[$attachHeadLine]) =~ s/^X-Attachments: //;	# Remove the header name
			my @attachments = split /:\s+/, $attachline;			# split the records out
			for ($i = 0; $i <= $#attachments; $i++) {				# loop through the attachments
				$attachments[$i] =~ /^\:.*?\:(\d+)\:(.*?)\:?$/;
				$attachPID = $1;									# grab the current ID of the parent
				chomp($attachFname = $2);							# grab the attachment file name
				$newPID = `$lookupid $attachPID /`;					# look up the directory that the ID refers to
				if ($attachFname eq "") {
					print "Parse error on record ", $rec+1, ". Skipping message.\n";
					next;
				}
				if (($newPID =~ /^Error /) || (!-e "$newPID/$attachFname")) {
				# if we have a PID and the attachment doesn't exist there already
					if ($found = findOnFSSql($attachFname)) { # look for it
					# if the attachment name is in our index
						$attachments[$i] = ":Macintosh HD:$found->[0]:$attachFname:";	# generate the new attachment line
					}
					else {																# otherwise keep it the same
						$attachments[$i] = ":Macintosh HD:$attachPID:$attachFname:";
					}
				}
			}

			$newline = "X-Attachments: @attachments";
			$newmsgsize = length $newline;
			if ($newmsgsize != $oldmsgsize) {
				$newsize = ($newmsgsize - $oldmsgsize);
				print "Changing line " . ($attachHeadLine + 1) . " to $newline ($newsize)\n";
				$dataref[$attachHeadLine] = $newline; # set the line in the file to our new X-Attachments line
				# update the size of the msg and headers in the TOC
				substr($tocdata, $msgsizLoc, 2, pack("n", $msgsiz + $newsize));
				substr($tocdata, $msgheadLoc, 2, pack("n", $msghead + $newsize));
				# update the remaining offsets in our index
				updateoffsets(0, $newsize, unpack("N", substr($tocdata, $msgoffsetLoc, 4)));
				$TOCchanged = 1; # remember to write the TOC out at the end of our loop
			}
			# add the attachment bit in the TOC if it doesn't exist
			my $attachdata = unpack("H*", substr($tocdata, $msgattachLoc, 2));
			if (sprintf("%04x",(hex($attachdata) & hex("0022"))) != hex("0022")) {
				# the attachment bit isn't set, so set it
				$attachdata |= hex("0022");
				substr($tocdata, $msgattachLoc, 2, pack("n", $attachdata));
				$TOCchanged = 1;
			}
			next;
		}

	# Find attachments in the body (Attachment converted lines)
		for ($i = $msgheadLine; $i <= $msgsizLine; $i++) {
			if ($dataref[$i] =~ /^\QAttachment converted: Macintosh HD:\E/) {
				($attachment = $dataref[$i]) =~ s/^\QAttachment converted: \E//;
				$attachment =~ /(Macintosh HD)\:(.*?) \(.{4}\/.{4}\) \(.{8}\)$/;
				next if (($attachFname = $2) =~ /^\s*$/); # this should be solved and removed at some point
				if ($found = findOnFSSql($attachFname)) {
					if ((!-e "$ARGV[2]/$attachFname") && (-e "$found->[1]/$attachFname")) {
															# copy it to attachments dir if it is on our computer and not there already
						copy("$found->[1]/$attachFname", "$ARGV[2]/$attachFname");
						print "copying $found->[1]/$attachFname to Eudora Attachments folder\n";
					}
				}
			}
		}
	}

	# if we changed the TOC then write our changed one to the file
	if ($TOCchanged) {
		print "Writing TOC...\n";
		RemoveResource($tocres);
		$tocres->dispose;
		my $textHand = new Handle($tocdata);
		AddResource($textHand, 'TOCF', '1001', '') or die "Can't make new TOC: $!";
		WriteResource($textHand) or die "Can't write new TOC: $!";
		ReleaseResource($textHand);
	}
	print "*** Repair of $ARGV[1] complete...\n";
}

#### findOnFSSpotlight
#### NOT USED. Can switch from a file catalog system to doing live lookups with spotlight. Generally slow and not as reliable.
sub findOnFSSpotlight {
	my $file = shift;
	my $cmd = qq|'/usr/bin/mdfind' '(kMDItemFSName = "$file" && kMDItemKind != "Folder")' -onlyin '$ARGV[0]'|;
	my $output = open(SPOTLIGHT, "$cmd|");
	$file = <SPOTLIGHT>;
	close SPOTLIGHT;
	return 0 if $file !~ /^$ARGV[0]/;
	$file =~ m|^(.*?)/[^/]*$|;
	return [((stat $1)[1], $1)];
}

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

#### updateoffsets
#### Loop through the TOC entries and add to their message offsets by the size that we added to the data fork
sub updateoffsets {
	my ($location,$msgoffsetLoc);
	my ($curRec, $newsize) = (shift, shift);
	my $startOffset = shift;
	foreach my $rec ($curRec .. $numrecs) {
		$location = 277 + (220 * $rec);
		$msgoffsetLoc = $location + 1;
		my $offset = unpack("N", substr($tocdata, $msgoffsetLoc, 4));
		next if $offset <= $startOffset; # skip entries that reference messages previous to what we are working on
		$tocoffsetindex{$offset+$newsize} = $tocoffsetindex{$offset}; # update the index to reflect the new offsets
		delete $tocoffsetindex{$offset};
		substr($tocdata, $msgoffsetLoc, 4, pack("N", $newsize + $offset)); # update the TOC to reflect new offset
	}
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