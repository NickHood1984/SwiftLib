on run argv
    set viaBundleID to "com.apple.finder"
    set targetBundleID to "com.kingsoft.wpsoffice.mac"
    set bounceDelay to 0.15

    if (count of argv) >= 1 then set viaBundleID to item 1 of argv
    if (count of argv) >= 2 then set targetBundleID to item 2 of argv
    if (count of argv) >= 3 then set bounceDelay to (item 3 of argv) as real

    do shell script "/usr/bin/open -b " & quoted form of viaBundleID
    delay bounceDelay
    do shell script "/usr/bin/open -b " & quoted form of targetBundleID
end run