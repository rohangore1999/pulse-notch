import os


APP_PATH = os.environ["PULSE_NOTCH_DMG_APP_PATH"]
VOLUME_ICON_PATH = os.environ["PULSE_NOTCH_DMG_VOLUME_ICON_PATH"]

volume_name = "Pulse Notch"
format = "UDZO"
compression_level = 9

files = [APP_PATH]
symlinks = {"Applications": "/Applications"}

# Finder window: compact, native, and intentionally close to the supplied
# two-icon installer reference. Finder draws the app and Applications labels.
background = "#25344a"
window_rect = ((200, 120), (680, 420))
default_view = "icon-view"
show_icon_preview = False
show_statusbar = False
show_tabview = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 112
text_size = 14
icon_locations = {
    os.path.basename(APP_PATH): (180, 215),
    "Applications": (500, 215),
}

icon = VOLUME_ICON_PATH
