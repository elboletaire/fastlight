# dmgbuild settings for the Fastlight DMG (see scripts/dmg.sh).
#
# dmgbuild writes the window layout straight into the volume's .DS_Store, so
# no Finder or AppleScript session is needed (headless CI has neither).
#
# The layout matches the background drawn by dmg_background() in
# assets/brand/src/generate.py (DMG_W, DMG_H, DMG_APP, DMG_APPS, DMG_ICON):
# change them together. Coordinates are points from the top-left of the
# window's content area, and an icon location is the centre of its icon.

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
background = defines["background"]  # noqa: F821
icon = defines["volume_icon"]  # noqa: F821

files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: it sets the Finder info bit on the bundle, which is
# extended-attribute "detritus" that breaks `codesign --verify --strict` (and
# notarization) of the app. Finder hides ".app" by default anyway.

format = "UDZO"
compression_level = 9
filesystem = "HFS+"

# The background is 660x400 pt plus 20 pt of plain slack at the bottom. The
# window height includes the title bar (about 28 pt without a toolbar), so
# the content area comes out at 660x400 and a slightly shorter or taller
# title bar only shows more or less of the slack.
window_rect = ((200, 120), (660, 428))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_status_bar = False
show_tab_view = False
show_icon_preview = False
show_item_info = False
arrange_by = None
label_pos = "bottom"
icon_size = 128
text_size = 13
icon_locations = {
    "Fastlight.app": (170, 200),
    "Applications": (490, 200),
}
