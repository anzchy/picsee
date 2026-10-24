import plistlib, json, os, sys
p=os.path.expanduser('~/Library/Containers/io.github.anzchy.picsee/Data/Library/Preferences/io.github.anzchy.picsee.plist')
d=plistlib.load(open(p,'rb')).get('displayPreferences.v1')
print(json.loads(d) if d else None)
