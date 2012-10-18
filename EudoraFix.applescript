-- EudoraFix.applescript
-- EudoraFix

--  Created by Matt Stofko on 8/27/06.
--  matt@mjslabs.com

-- COPYRIGHT & LICENSE

-- Copyright 2006 Matt Stofko

-- This program is free software; you can redistribute it and/or
-- modify it under the terms of either:

-- * the GNU General Public License as published by the Free
-- Software Foundation; either version 1, or (at your option) any
-- later version, or

-- * the Artistic License version 2.0.


global whichOpen

on clicked theObject
	if name of theObject is "mailChoose" then
		set whichOpen to 1
		set can choose directories of open panel to true
		set can choose files of open panel to false
		set allows multiple selection of open panel to false
		display open panel attached to window "EudoraFix"
	end if
	
	if name of theObject is "searchChoose" then
		set whichOpen to 2
		set can choose directories of open panel to true
		set can choose files of open panel to false
		set allows multiple selection of open panel to false
		display open panel attached to window "EudoraFix"
	end if
	
	if name of theObject is "attachChoose" then
		set whichOpen to 3
		set can choose directories of open panel to true
		set can choose files of open panel to false
		set allows multiple selection of open panel to false
		display open panel attached to window "EudoraFix"
	end if
	
	if name of theObject is "fixGo" then
		set myself to POSIX path of the (path to current application)
		set archName to do shell script "uname -p"
		set pathToPerlScript to myself & "Contents/Resources/attachsync." & archName
		set theMailPath to contents of text field "mailboxPath" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix"
		set theSearchPath to contents of text field "searchPath" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix"
		set theAttachPath to contents of text field "attachPath" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix"
		set seeOutput to state of button "seeOutput" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix"
		set forceIndex to state of button "forceIndex" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix"
		set bigAttachPerlScript to ""
		set bigDatePerlScript to ""
		
		tell progress indicator "progress" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix" to start
		set theMacPath to POSIX file theMailPath
		tell application "Finder"
			if forceIndex is 1 then
				set indexFile to (myself & "Contents/Resources/file.index")
				try
					delete (POSIX file indexFile) as alias
				end try
			end if
			set dirItems to entire contents of folder theMacPath
		end tell
		set eudoraLog to quoted form of (myself & "../eudorafix.log")
		do shell script "echo '*** Starting repair at' `date` >>" & eudoraLog
		if seeOutput is 1 then
			tell application "Terminal"
				activate
				do shell script "touch " & eudoraLog
				do script with command "echo '**********';tail -n 1 -f " & eudoraLog
			end tell
		end if
		repeat with xItems in dirItems
			set tempKind to kind of xItems
			if tempKind is not "Folder" then
				set thisMailBox to quoted form of POSIX path of (xItems as string)
				set perlScript to quoted form of pathToPerlScript & " " & quoted form of theSearchPath & " " & thisMailBox & " " & quoted form of theAttachPath & ">>" & eudoraLog
				do shell script perlScript
			end if
		end repeat
		do shell script "echo >> " & eudoraLog & ";echo '*** Done at' `date` >>" & eudoraLog & "; echo '**********'"
		tell progress indicator "progress" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix" to stop
	end if
	
	-- Start DateTab stuff	
	if name of theObject is "mailChooseDate" then
		set whichOpen to 4
		set can choose directories of open panel to false
		set can choose files of open panel to true
		set allows multiple selection of open panel to false
		display open panel attached to window "EudoraFix"
	end if
	
	if name of theObject is "fixGoDate" then
		set myself to POSIX path of the (path to current application)
		set archName to do shell script "uname -p"
		set pathToPerlScript to myself & "Contents/Resources/datesync." & archName
		set theMailPath to contents of text field "mailboxPathDate" of view 1 of tab view item "DateTab" of tab view "Tabs" of window "EudoraFix"
		
		tell progress indicator "progressDate" of view 1 of tab view item "DateTab" of tab view "Tabs" of window "EudoraFix" to start
		set perlScript to "/usr/bin/perl " & quoted form of pathToPerlScript & " " & quoted form of theMailPath & ";"
		do shell script perlScript
		tell progress indicator "progressDate" of view 1 of tab view item "DateTab" of tab view "Tabs" of window "EudoraFix" to stop
	end if
	
	
end clicked

on choose menu item theObject
	if name of theObject is "help" then
		set visible of window "help" to true
	else if name of theObject is "new" then
		set visible of window "EudoraFix" to true
	end if
end choose menu item

on panel ended theObject with result withResult
	if withResult is 1 then
		if whichOpen is 1 then
			set theMailPath to path name of open panel
			set contents of text field "mailboxPath" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix" to theMailPath
		end if
		if whichOpen is 2 then
			set theSearchPath to path name of open panel
			set contents of text field "searchPath" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix" to theSearchPath
		end if
		if whichOpen is 3 then
			set theAttachPath to path name of open panel
			set contents of text field "attachPath" of view 1 of tab view item "AttachmentsTab" of tab view "Tabs" of window "EudoraFix" to theAttachPath
		end if
		if whichOpen is 4 then
			set theMailPath to path name of open panel
			set contents of text field "mailboxPathDate" of view 1 of tab view item "DateTab" of tab view "Tabs" of window "EudoraFix" to theMailPath
		end if
	end if
end panel ended
