"""Turn Omarchy's themes/<name>/colors.toml into colour files for the Hyprland session.

Usage: theme-generate.py <omarchy themes dir> <output dir>
       theme-generate.py pickers <generated themes> <output dir>
Output: <out>/list (theme names) and <out>/themes/<name>/ with hyprland.conf, waybar.css,
mako.ini, alacritty.toml, hyprlock.conf, mode, title and a backgrounds/ link.
"""

import json
import os
import subprocess
import sys
import tomllib

FONT = "JetBrainsMono Nerd Font"


def hex6(color):
    return color.lstrip("#")[:6]


def title(name):
    return " ".join(word.capitalize() for word in name.split("-"))


def hyprland(c):
    # Like default/themed/hyprland.lua.tpl: the theme's own border spec, else its accent.
    active = c.get("hyprland_active_border") or f"rgb({hex6(c['accent'])})"
    inactive = c.get("hyprland_inactive_border") or "rgba(595959aa)"
    return f"general {{\n  col.active_border = {active}\n  col.inactive_border = {inactive}\n}}\n"


def waybar(c):
    names = ["background", "foreground", "accent", "muted", "selection",
             "dark_background", "bright_foreground", "dark_foreground"]
    return "".join(f"@define-color {n} {c[n]};\n" for n in names)


def walker(c):
    # Like Omarchy 3's default/themed/walker.css.tpl
    return (f"@define-color selected-text {c['accent']};\n@define-color text {c['foreground']};\n"
            f"@define-color base {c['background']};\n@define-color border {c['foreground']};\n"
            f"@define-color foreground {c['foreground']};\n@define-color background {c['background']};\n")


def mako(c):
    return (
        f"font={FONT} 11\n"
        f"background-color={c['background']}\n"
        f"text-color={c['foreground']}\n"
        f"border-color={c['accent']}\n"
        "border-size=2\nborder-radius=0\npadding=10\nwidth=420\n"
        "default-timeout=5000\nanchor=top-right\nouter-margin=20\n\n"
        "[mode=do-not-disturb]\ninvisible=1\n"
    )


def alacritty(c):
    # Like default/themed/alacritty.toml.tpl
    return f"""[colors.primary]
background = "{c['background']}"
foreground = "{c['foreground']}"

[colors.cursor]
text = "{c['background']}"
cursor = "{c['bright_foreground']}"

[colors.selection]
text = "{c['foreground']}"
background = "{c['selection']}"

[colors.normal]
black = "{c['background']}"
red = "{c['red']}"
green = "{c['green']}"
yellow = "{c['yellow']}"
blue = "{c['blue']}"
magenta = "{c['magenta']}"
cyan = "{c['cyan']}"
white = "{c['foreground']}"

[colors.bright]
black = "{c['muted']}"
red = "{c['bright_red']}"
green = "{c['bright_green']}"
yellow = "{c['bright_yellow']}"
blue = "{c['bright_blue']}"
magenta = "{c['bright_magenta']}"
cyan = "{c['bright_cyan']}"
white = "{c['bright_foreground']}"
"""


def hyprlock(c):
    return (
        f"$theme_inner = rgba({hex6(c['background'])}cc)\n"
        f"$theme_outer = rgb({hex6(c['accent'])})\n"
        f"$theme_font = rgb({hex6(c['bright_foreground'])})\n"
        f"$theme_check = rgb({hex6(c['green'])})\n"
        f"$theme_fail = rgb({hex6(c['red'])})\n"
    )


def main(src, out):
    names = sorted(n for n in os.listdir(src) if os.path.isfile(os.path.join(src, n, "colors.toml")))
    os.makedirs(os.path.join(out, "themes"))
    for name in names:
        with open(os.path.join(src, name, "colors.toml"), "rb") as f:
            c = tomllib.load(f)
        d = os.path.join(out, "themes", name)
        os.makedirs(d)
        files = {
            "hyprland.conf": hyprland(c),
            "waybar.css": waybar(c),
            "walker.css": walker(c),
            "mako.ini": mako(c),
            "alacritty.toml": alacritty(c),
            "hyprlock.conf": hyprlock(c),
            "mode": c.get("mode", "dark") + "\n",
            "title": title(name) + "\n",
            "colors.json": json.dumps(c) + "\n",
        }
        for filename, text in files.items():
            with open(os.path.join(d, filename), "w") as f:
                f.write(text)
        os.symlink(os.path.join(src, name, "backgrounds"), os.path.join(d, "backgrounds"))
        preview = os.path.join(src, name, "preview.png")
        if os.path.isfile(preview):
            os.symlink(preview, os.path.join(d, "preview.png"))
    with open(os.path.join(out, "list"), "w") as f:
        f.write("".join(n + "\n" for n in names))


def background_title(filename):
    # "1-quattro.webp" -> "Quattro", "5-oma-cityscape.jpg" -> "Oma Cityscape"
    stem = os.path.splitext(filename)[0]
    parts = stem.split("-")
    if parts[0].isdigit() and len(parts) > 1:
        parts = parts[1:]
    return " ".join(p.capitalize() for p in parts)


def pickers(themes, out):
    """Item lists for the image picker (picker.qml): themes with Omarchy's preview images, and
    each theme's wallpapers. Thumbnails are PNG because Qt here has no WebP image plugin."""
    names = [n.strip() for n in open(os.path.join(themes, "list")) if n.strip()]
    os.makedirs(os.path.join(out, "pickers"))
    theme_items = []
    for name in names:
        d = os.path.join(themes, "themes", name)
        theme_items.append({"label": open(os.path.join(d, "title")).read().strip(),
                            "image": os.path.join(d, "preview.png"), "value": name})
    with open(os.path.join(out, "pickers", "themes.json"), "w") as f:
        json.dump(theme_items, f)

    for name in names:
        bg_dir = os.path.join(themes, "themes", name, "backgrounds")
        thumbs = os.path.join(out, "thumbs", name)
        os.makedirs(thumbs)
        items = []
        for filename in sorted(os.listdir(bg_dir)):
            thumb = os.path.join(thumbs, os.path.splitext(filename)[0] + ".png")
            subprocess.run(["magick", os.path.join(bg_dir, filename), "-resize", "768x475^",
                            "-gravity", "center", "-extent", "768x475", thumb], check=True)
            items.append({"label": background_title(filename), "image": thumb, "value": filename})
        with open(os.path.join(out, "pickers", f"backgrounds-{name}.json"), "w") as f:
            json.dump(items, f)


if __name__ == "__main__":
    if sys.argv[1] == "pickers":
        pickers(sys.argv[2], sys.argv[3])
    else:
        main(sys.argv[1], sys.argv[2])
