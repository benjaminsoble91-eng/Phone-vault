#!/bin/bash
# Clicks a sidebar row found through the accessibility tree: device | pending | backup
what="$1"
pos=$(osascript <<OSA 2>/dev/null
tell application "System Events"
  tell (first process whose name is "PhoneVault")
    set rowsList to rows of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
    set wanted to "$what"
    repeat with r in rowsList
      set t to ""
      try
        set t to (value of static text 1 of UI element 1 of r) as text
      end try
      if wanted is "device" and t is "iPhone 12 mini" then
      else if wanted is "pending" and t contains "iPhone" and t is not "iPhone 12 mini" then
      else if wanted is "backup" and t contains "Test iPhone" then
      else
        set t to ""
      end if
      if t is not "" then
        set p to position of r
        set s to size of r
        return ((((item 1 of p) + 60) as integer) as text) & "," & ((((item 2 of p) + (item 2 of s) / 2) as integer) as text)
      end if
    end repeat
  end tell
end tell
OSA
)
echo "row $what at: $pos"
if [ -n "$pos" ]; then
  x=$(echo "$pos" | tr -d ' ' | cut -d, -f1); y=$(echo "$pos" | tr -d ' ' | cut -d, -f2)
  /tmp/input click "$x" "$y"
else
  case "$what" in device) /tmp/input click 190 130;; pending) /tmp/input click 190 185;; backup) /tmp/input click 190 300;; esac
fi
