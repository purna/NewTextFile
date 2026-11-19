#!/bin/bash
# Builds and installs a Finder Sync extension that adds "New Text File"
# to the right-click menu on empty space in any Finder folder.
set -e

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Installing Apple's command line tools..."
  echo "Click Install in the popup, wait for it to finish, then run this script again."
  xcode-select --install || true
  exit 1
fi

APPNAME="NewTextFile"
BUNDLE_ID="com.pixelagent.newtextfile"
EXT_ID="$BUNDLE_ID.ext"
DEST="$HOME/Applications/$APPNAME.app"
APPEX="$DEST/Contents/PlugIns/${APPNAME}Ext.appex"
WORK="$(mktemp -d)"

# Remove any previous install
pluginkit -r "$APPEX" 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$APPEX/Contents/MacOS"

# ---------- Extension source ----------
cat > "$WORK/ext.swift" << 'EOF'
import Cocoa
import FinderSync

class NewFileSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        if menuKind == .contextualMenuForContainer {
            menu.addItem(withTitle: "New Text File", action: #selector(newTextFile(_:)), keyEquivalent: "")
        }
        return menu
    }

    @objc func newTextFile(_ sender: AnyObject?) {
        guard let dir = FIFinderSyncController.default().targetedURL() else { return }
        let fm = FileManager.default
        var url = dir.appendingPathComponent("untitled.txt")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("untitled \(n).txt")
            n += 1
        }
        fm.createFile(atPath: url.path, contents: Data())
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
EOF

# ---------- Host app source ----------
cat > "$WORK/host.swift" << 'EOF'
import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
let alert = NSAlert()
alert.messageText = "New Text File is installed"
alert.informativeText = "If the right-click item is missing, open System Settings, search for \"Finder extensions\" (General > Login Items & Extensions > Extensions) and tick New Text File. Then right-click empty space in any Finder folder."
alert.runModal()
EOF

# ---------- Plists ----------
cat > "$APPEX/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APPNAME}Ext</string>
	<key>CFBundleIdentifier</key>
	<string>$EXT_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>New Text File</string>
	<key>CFBundleDisplayName</key>
	<string>New Text File</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.FinderSync</string>
		<key>NSExtensionPrincipalClass</key>
		<string>${APPNAME}Ext.NewFileSync</string>
	</dict>
</dict>
</plist>
EOF

cat > "$DEST/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$APPNAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>New Text File</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

cat > "$WORK/ext.entitlements" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
	<array>
		<string>/</string>
	</array>
</dict>
</plist>
EOF

# ---------- Compile ----------
echo "Compiling..."
swiftc -parse-as-library -application-extension -module-name "${APPNAME}Ext" \
  -framework Cocoa -framework FinderSync \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/${APPNAME}Ext" "$WORK/ext.swift"

swiftc -module-name "$APPNAME" -framework Cocoa \
  -o "$DEST/Contents/MacOS/$APPNAME" "$WORK/host.swift"

# ---------- Sign (ad-hoc, local use) ----------
codesign --force --sign - --entitlements "$WORK/ext.entitlements" "$APPEX"
codesign --force --sign - "$DEST"

# ---------- Register and enable ----------
pluginkit -a "$APPEX"
pluginkit -e use -i "$EXT_ID" || true
killall Finder 2>/dev/null || true

echo ""
echo "Installed: $DEST"
open "$DEST"
open "x-apple.systempreferences:com.apple.ExtensionsPreferences" 2>/dev/null || true
echo "Right-click empty space in any Finder folder > New Text File"
