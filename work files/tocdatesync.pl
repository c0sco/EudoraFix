#!/usr/bin/perl

##############################################################################
##################### tocdatesync.pl
##################### Part of EudoraFix.app
##################### Sync the two date fields in the TOC. The second one being
##################### the one you see in the GUI, but which isn't always correct.
##################### Matt Stofko <matt@mjslabs.com>
##############################################################################

$| = 1;
use Mac::Resources;
use Mac::Memory;
use POSIX qw(strftime);

our ($data, $numrecs, $mbx);
my $MACOS_CONSTANT_fsRdWrPerm = 3;
# Open the Mac resource fork of the file
my $resref = FSOpenResourceFile($ARGV[0], "rsrc", $MACOS_CONSTANT_fsRdWrPerm);
UseResFile($resref);
# Read it in
my $tocres = GetResource("TOCF", 1001);
$data = $tocres->get;

# Count how many records we have to loop through
my $numrecs = ((length($data) - 278) / 220) - 1; # 278 byte header, 220 bytes per record, - 1 to start at 0

# Our changed flag
my $TOCchanged = 0;

# For each record
foreach $rec (0 .. $numrecs) {
	# Get the location of it in the resource fork
	$location = 277 + (220 * $rec);
	# The offsets of the two date fields
	$msgdateLoc = $location + 19;
	$msgdateLoc2 = $location + 47;

	# If the two fields don't match, sync them up
	$macosdate_first = unpack("H*", substr($data, $msgdateLoc, 4));
	$macosdate_second = unpack("H*", substr($data, $msgdateLoc2, 4));
	if (substr($macosdate_first, 0, 3) ne substr($macosdate_second, 0, 3)) {
		print "*** Updating Eudora TOC record " . ($rec + 1), "\n";
		print "\tOld date: ", strftime("%a %b %e %H:%M:%S %Y", localtime((hex($macosdate_second) + 32400) - 2082877200)), "\n";
		print "\tNew date: ", strftime("%a %b %e %H:%M:%S %Y", localtime((hex($macosdate_first) + 32400) - 2082877200)), "\n";
		substr($data, $msgdateLoc2, 4, pack("N", (hex $macosdate_first)));
		$TOCchanged = 1;
	}
}

# Did we make a change? If so write the new TOC back out
if ($TOCchanged) {
	print "Writing TOC...\n";
	RemoveResource($tocres);
	$tocres->dispose;
	$textHand = new Handle($data);
	AddResource($textHand, 'TOCF', '1001', '') or die $!;
	WriteResource($textHand) or die $!;
	ReleaseResource($textHand) or die $!;
	CloseResFile($resref);
}

print "Done.\n";