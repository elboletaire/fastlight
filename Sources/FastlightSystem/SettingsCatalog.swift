import Foundation

/// What the system doesn't tell: other names people use for a pane, names
/// for panes whose bundle has none, icons for those without one, and the
/// sub-pages worth a result of their own. Keyed by the settings extension's
/// bundle identifier, which is also what the x-apple.systempreferences: URL
/// takes. Panes are discovered, not listed here: anything missing from this
/// table still shows up under its own name.
public enum SettingsCatalog {
    /// Extensions that aren't panes of their own (or only show up in
    /// special setups).
    static let hidden: Set<String> = [
        "com.apple.FollowUpSettings.FollowUpSettingsExtension",
        "com.apple.HeadphoneSettings",
        "com.apple.ClassKit-Settings.extension",
        "com.apple.Classroom-Settings.extension",
    ]

    static let battery = "com.apple.Battery-Settings.extension"

    /// A key in the bundle's Localizable strings that holds its name, for
    /// bundles without a display name.
    static func titleKey(_ id: String, hasBattery: Bool) -> String? {
        id == battery ? (hasBattery ? "BATTERY_PREF_TITLE" : "ENERGY_SAVER_PREF_TITLE") : nil
    }

    /// For bundles without a usable display name.
    static func fallbackName(_ id: String, hasBattery: Bool) -> String? {
        switch id {
        case battery: hasBattery ? "Battery" : "Energy"
        case "com.apple.settings.Storage": "Storage"
        case "com.apple.Touch-ID-Settings.extension": "Touch ID & Password"
        case "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension": "VPN"
        case "com.apple.Wallpaper-Settings.extension": "Wallpaper"
        case "com.apple.BluetoothSettings": "Bluetooth"
        case "com.apple.systempreferences.AppleIDSettings": "Apple Account"
        case "com.apple.Focus-Settings.extension": "Focus"
        case "com.apple.Mouse-Settings.extension": "Mouse"
        case "com.apple.Trackpad-Settings.extension": "Trackpad"
        case "com.apple.systempreferences.GeneralSettings": "General"
        case "com.apple.Network-Settings.extension": "Network"
        case "com.apple.Software-Update-Settings.extension": "Software Update"
        case "com.apple.Time-Machine-Settings.extension": "Time Machine"
        case "com.apple.Users-Groups-Settings.extension": "Users & Groups"
        case "com.apple.LoginItems-Settings.extension": "Login Items"
        default: nil
        }
    }

    /// SF Symbols for panes whose bundle has no icon Finder can draw.
    static let symbols: [String: String] = [
        battery: "battery.100percent",
        "com.apple.Siri-Settings.extension": "waveform.circle",
        "com.apple.Spotlight-Settings.extension": "magnifyingglass",
        "com.apple.Time-Machine-Settings.extension": "clock.arrow.circlepath",
        "com.apple.WalletSettingsExtension": "wallet.pass",
        "com.apple.Family-Settings.extension": "person.3",
        "com.apple.Game-Center-Settings.extension": "gamecontroller",
    ]

    static let aliases: [String: [String]] = [
        "com.apple.wifi-settings-extension": ["wifi", "wireless", "wlan"],
        "com.apple.Network-Settings.extension": ["ethernet", "firewall", "proxy", "dns"],
        battery: ["battery", "energy", "energy saver", "power", "low power mode"],
        "com.apple.Desktop-Settings.extension": ["dock", "desktop", "stage manager", "mission control", "hot corners"],
        "com.apple.Appearance-Settings.extension": ["dark mode", "light mode", "accent color", "theme"],
        "com.apple.Software-Update-Settings.extension": ["update", "updates", "upgrade macos"],
        "com.apple.LoginItems-Settings.extension": ["startup items", "open at login", "launch at login", "background items"],
        "com.apple.Sound-Settings.extension": ["audio", "volume", "alert sound"],
        "com.apple.Displays-Settings.extension": ["display", "monitor", "resolution", "night shift", "brightness"],
        "com.apple.Keyboard-Settings.extension": ["keyboard shortcuts", "dictation", "input sources", "text replacements"],
        "com.apple.Trackpad-Settings.extension": ["touchpad", "gestures"],
        "com.apple.Lock-Screen-Settings.extension": ["require password"],
        "com.apple.Users-Groups-Settings.extension": ["users", "groups", "accounts"],
        "com.apple.Touch-ID-Settings.extension": ["touch id", "fingerprint", "password"],
        "com.apple.Date-Time-Settings.extension": ["date", "time", "clock", "time zone"],
        "com.apple.Localization-Settings.extension": ["language", "region", "locale"],
        "com.apple.Sharing-Settings.extension": ["file sharing", "screen sharing", "remote login", "ssh", "computer name", "hostname"],
        "com.apple.Time-Machine-Settings.extension": ["backup", "backups"],
        "com.apple.settings.Storage": ["disk space", "free space"],
        "com.apple.Startup-Disk-Settings.extension": ["boot disk"],
        "com.apple.SystemProfiler.AboutExtension": ["about this mac", "serial number"],
        "com.apple.Accessibility-Settings.extension": ["a11y", "universal access", "voiceover"],
        "com.apple.ControlCenter-Settings.extension": ["control center", "menu bar"],
        "com.apple.Focus-Settings.extension": ["do not disturb", "dnd"],
        "com.apple.Screen-Time-Settings.extension": ["parental controls"],
        "com.apple.settings.PrivacySecurity.extension": ["privacy", "security", "gatekeeper"],
        "com.apple.AirDrop-Handoff-Settings.extension": ["airdrop", "handoff", "airplay receiver", "continuity"],
        "com.apple.Print-Scan-Settings.extension": ["printer", "printers", "scanner"],
        "com.apple.Siri-Settings.extension": ["apple intelligence"],
        "com.apple.Internet-Accounts-Settings.extension": ["mail accounts", "email accounts"],
        "com.apple.systempreferences.AppleIDSettings": ["apple id", "icloud"],
        "com.apple.WalletSettingsExtension": ["apple pay"],
        "com.apple.Profiles-Settings.extension": ["profiles", "mdm"],
        "com.apple.Transfer-Reset-Settings.extension": ["erase all content and settings", "factory reset"],
        "com.apple.Wallpaper-Settings.extension": ["background", "desktop picture"],
        "com.apple.Family-Settings.extension": ["family sharing"],
        "com.apple.Coverage-Settings.extension": ["applecare", "warranty"],
    ]

    /// A page inside a pane, opened with its anchor
    /// (x-apple.systempreferences:<pane>?<anchor>). Offered only when the
    /// installed pane lists the anchor in its search terms, so a page a
    /// macOS version doesn't have never shows up.
    struct Page {
        var anchor: String
        /// English, and an alias in other languages.
        var title: String
        var aliases: [String] = []
        /// The pane's Localizable string with this title, for its name in
        /// the user's language. Used only while its English text is
        /// `title`, in case a later macOS reuses the key for something else.
        var key: String? = nil
    }

    static let pages: [String: [Page]] = [
        "com.apple.settings.PrivacySecurity.extension": [
            Page(anchor: "Privacy_AllFiles", title: "Full Disk Access", aliases: ["fda"], key: "ALL_FILES"),
            Page(anchor: "Privacy_Accessibility", title: "Accessibility", aliases: ["accessibility access"]),
            Page(anchor: "Privacy_ScreenCapture", title: "Screen & System Audio Recording", aliases: ["screen recording", "screen capture"], key: "SCREEN_CAPTURE_HEADER"),
            Page(anchor: "Privacy_ListenEvent", title: "Input Monitoring", key: "LISTEN_EVENT"),
            Page(anchor: "Privacy_Automation", title: "Automation", aliases: ["apple events"], key: "AUTOMATION"),
            Page(anchor: "Privacy_AppBundles", title: "App Management", key: "APPLICATION_BUNDLES"),
            Page(anchor: "Privacy_DevTools", title: "Developer Tools", key: "DEV_TOOLS"),
            Page(anchor: "Privacy_FilesAndFolders", title: "Files & Folders", key: "FILE_ACCESS_COMBINED"),
            Page(anchor: "Privacy_LocationServices", title: "Location Services", aliases: ["location"], key: "LOCATION_SERVICES"),
            Page(anchor: "Privacy_Camera", title: "Camera", key: "CAMERA"),
            Page(anchor: "Privacy_Microphone", title: "Microphone", aliases: ["mic"], key: "MICROPHONE"),
            Page(anchor: "Privacy_Contacts", title: "Contacts", key: "CONTACTS"),
            Page(anchor: "Privacy_Calendars", title: "Calendars", key: "CALENDARS"),
            Page(anchor: "Privacy_Reminders", title: "Reminders", key: "REMINDERS"),
            Page(anchor: "Privacy_Photos", title: "Photos", key: "PHOTOS"),
            Page(anchor: "Privacy_SpeechRecognition", title: "Speech Recognition", key: "SPEECH_RECOGNITION"),
            Page(anchor: "Privacy_Media", title: "Media & Apple Music", key: "MEDIA"),
            Page(anchor: "Privacy_RemoteDesktop", title: "Remote Desktop", key: "REMOTE_DESKTOP"),
            Page(anchor: "Privacy_Analytics", title: "Analytics & Improvements", aliases: ["diagnostics"], key: "ANALYTICS"),
            Page(anchor: "Privacy_Advertising", title: "Apple Advertising", key: "ADVERTISING"),
            Page(anchor: "FileVault", title: "FileVault", aliases: ["disk encryption"], key: "FileVault"),
            Page(anchor: "LockdownMode", title: "Lockdown Mode", key: "Lockdown Mode"),
        ],
    ]
}
