#!/usr/bin/perl

##############################################################################
##################### datesync.pl
##################### Part of EudoraFix.app
##################### Given a Eudora mailbox, pull the date listed in the data
##################### fork and enter it into the resource fork date fields.
##################### Matt Stofko <stofko@stanford.edu>
##############################################################################

=head1 COPYRIGHT & LICENSE

Copyright 2006 Matt Stofko

This program is free software; you can redistribute it and/or
modify it under the terms of either:

=over 4

=item * the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any
later version, or

=item * the Artistic License version 2.0.

=back

=cut


$| = 1;
use Mac::Resources;
use Mac::Memory;
use Tie::File;
use Time::Local;
our ($data, $numrecs, $mbx);
my $MACOS_CONSTANT_fsRdWrPerm = 3;
my %months = (
				'Jan' => 0,
				'Feb' => 1,
				'Mar' => 2,
				'Apr' => 3,
				'May' => 4,
				'Jun' => 5,
				'Jul' => 6,
				"Aug" => 7,
				'Sep' => 8,
				'Oct' => 9,
				'Nov' => 10,
				'Dec' => 11
);

# Open the resource fork
my $resref = FSOpenResourceFile($ARGV[0], "rsrc", $MACOS_CONSTANT_fsRdWrPerm);
UseResFile $resref;
my $mbx = tie(@dataref, 'Tie::File', $ARGV[0], recsep => "\r") or die "Can't open mailbox data fork: $!";
my $tocres = GetResource("TOCF", 1001);
$data = $tocres->get;
my $numrecs = ((length($data) - 278) / 220) - 1; # 278 byte header, 220 bytes per record, -1 to start at 0

print "Indexing TOC...\n";
indexTOC(0);
sub indexTOC {
	use integer;
	my ($location, $msgoffsetLoc, $msgoffset, $i, $end);
	%tocoffsetindex = ();
	my %indexmeta = ();
	my $half = $#dataref / 2;
	my $quarter = $#dataref / 4;
	my $three = $half + $quarter;
	$indexmeta{$quarter} =  $mbx->offset($quarter);
	$indexmeta{$half} = $mbx->offset($half);
	$indexmeta{$three} = $mbx->offset($three);
	foreach (shift .. $numrecs) {
		$location = 277 + (220 * $_);
		$msgoffsetLoc = $location + 1;
		$msgoffset = unpack("N", substr($data, $msgoffsetLoc, 4));
		
		if ($msgoffset <= $indexmeta{$quarter}) {
			$i = 0; $end = $quarter;
		}
		elsif ($msgoffset > $indexmeta{$quarter} && $msgoffset <= $indexmeta{$half}) {
			$i = $quarter; $end = $half;
		}
		elsif ($msgoffset > $indexmeta{$half} && $msgoffset <= $indexmeta{$three}) {
			$i = $half; $end = $three;
		}
		elsif ($msgoffset > $indexmeta{$three}) {
			$i = $half; $end = $#dataref;
		}
		
		for ($i = $i; $i <= $end; $i++) {
			if ($mbx->offset($i) == ($msgoffset)) {
				if ($dataref[$i] =~ /^From\s+\Q???@???\E/) {
					$tocoffsetindex{$msgoffset} = $i;
					last;
				}
			}
		}
	}
}

foreach $rec (0 .. $numrecs) {
	$location = 277 + (220 * $rec);
	$msgoffsetLoc = $location + 1;
	$msgheadLoc = $location + 11;
	$msgdateLoc = $location + 19;
	$msgdateLoc2 = $location + 47;
	$msgheadLine = -1;

	print "*** Eudora TOC record " . ($rec + 1), "\n";

# Check that message starts where TOC says
	$msgoffset = unpack("N", substr($data, $msgoffsetLoc, 4));
	$msgoffsetLine = $tocoffsetindex{$msgoffset};
	if (!exists $tocoffsetindex{$msgoffset}) {
		print "No offset in index ($msgoffset) Record ", $rec+1, ". Skipping.\n";
		next;
	}

# Check that the headers end where they are supposed to
	my $msghead = unpack("n", substr($data, $msgheadLoc, 2));
	for ($i = $msgoffsetLine; $i <= $#dataref; $i++) {
		if ($mbx->offset($i) == ($msgoffset+$msghead)) {
			if (($dataref[$i] =~ /^\W*$/) or ($dataref[$i] =~ /^([\w\-]+\:)\s+.*$/) or ($dataref[$i] =~ /^\s*(.+?)\=(.+)\s*$/)) {
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

	$macosdate = unpack("H*", substr($data, $msgdateLoc, 4));
	$tocunixtime = hex($macosdate) - 2082877200;
	@toctime = localtime($tocunixtime);
	print "\tmsg TOC date is $toctime[2]:$toctime[1]:$toctime[0] " . ($toctime[4]+1)."/$toctime[3]/" . ($toctime[5]+1900), "\n";
	foreach $line ($msgoffsetLine .. $msgheadLine) {
		$eudoradate = $dataref[$line] if $dataref[$line] =~ /^From \Q???@???\E (\w.*)$/;
		$eudoradate = $dataref[$line] if $dataref[$line] =~ /^\QDate: \E/;
	}
	if ($eudoradate =~ /^From/) { # From ???@??? Tue Aug 31 15:31:07 2004
		print $eudoradate, "\n";
		$eudoradate =~ /From\s+\Q???@???\E\s+\w{3}\s+(\w{3})\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d{4})/;
		$eudoradate = timelocal($5, $4, $3, $2, $months{$1}, ($6 - 1900));
		$eudoradate -= 75600;
	}
	elsif ($eudoradate =~ /^Date/) { # Date: Fri, 16 Mar 2001 10:19:30
		$eudoradate =~ /^Date\:\s+\w{3},\s+(\d+)\s+(\w{3})\s+(\d{4})\s+(\d+):(\d+):(\d+)\s+/;
		$eudoradate = timelocal($6, $5, $4, $1, $months{$2}, $3);
		$eudoradate += 10800;
	}
	@time = localtime($eudoradate);
	print "\tmsg data date is $time[2]:$time[1]:$time[0] " . ($time[4]+1)."/$time[3]/" . ($time[5]+1900), "\n";
	substr($data, $msgdateLoc, 4, pack("N", ($eudoradate + 2082877200)));
	substr($data, $msgdateLoc2, 4, pack("N", ($eudoradate + 2082877200)));
}

print "Writing TOC...\n";
RemoveResource($tocres);
$tocres->dispose;
$textHand = new Handle($data);
AddResource($textHand, 'TOCF', '1001', '') or die $!;
WriteResource($textHand) or die $!;
ReleaseResource($textHand) or die $!;
#untie @dataref;
CloseResFile($resref);