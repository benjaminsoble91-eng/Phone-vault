#!/usr/bin/env python3
"""CI helper: (re)create N sample backup folders in ~/PhoneVault Backups. usage: make-backups.py N"""
import plistlib, os, sys, shutil, datetime
n = int(sys.argv[1])
root = os.path.expanduser('~/PhoneVault Backups')
shutil.rmtree(root, ignore_errors=True)
kinds = [("Test iPhone", "iPhone8,2", "15.8.8"), ("Mini", "iPhone13,1", "26.5.2"), ("iPad", "iPad6,3", "16.7.16")]
for i in range(n):
    name, ptype, ver = kinds[i % 3]
    udid = '%040x' % (i + 1)
    if i == 1:
        udid = "00008101-000C496202A0001E"
    d = os.path.join(root, udid)
    os.makedirs(d)
    with open(d + '/Info.plist', 'wb') as f:
        plistlib.dump({"Device Name": "%s %d" % (name, i + 1), "Product Type": ptype, "Product Version": ver,
                       "Last Backup Date": datetime.datetime(2026, 10, 1) + datetime.timedelta(days=i),
                       "Target Identifier": udid, "Unique Identifier": udid.upper()}, f)
    with open(d + '/Manifest.plist', 'wb') as f:
        plistlib.dump({"IsEncrypted": False}, f)
    with open(d + '/Status.plist', 'wb') as f:
        plistlib.dump({"SnapshotState": "finished", "IsFullBackup": True}, f)
print("made", n, "sample backups")
