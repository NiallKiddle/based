# dmgbuild settings — the drag-to-install window.
# Invoked by scripts/build.sh; layout matches scripts/make_dmg_background.py.
import os

app = defines.get("app", "dist/Based.app")  # noqa: F821 (defines is injected by dmgbuild)
appname = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [appname]
icon = defines.get("icon")  # noqa: F821  volume icon

background = defines.get("background")  # noqa: F821
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
icon_locations = {
    appname: (170, 200),
    "Applications": (490, 200),
}
