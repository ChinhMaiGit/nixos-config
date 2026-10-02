"""Turn Omarchy's themes/<name>/colors.toml into colour files for the Hyprland session.

Usage: theme-generate.py <omarchy themes dir> <output dir>
       theme-generate.py menus <generated themes> <theme-set> <background-set> <output dir>
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
            "mako.ini": mako(c),
            "alacritty.toml": alacritty(c),
            "hyprlock.conf": hyprlock(c),
            "mode": c.get("mode", "dark") + "\n",
            "title": title(name) + "\n",
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


def toml_str(value):
    return json.dumps(value, ensure_ascii=False)


def background_title(filename):
    # "1-quattro.webp" -> "Quattro", "5-oma-cityscape.jpg" -> "Oma Cityscape"
    stem = os.path.splitext(filename)[0]
    parts = stem.split("-")
    if parts[0].isdigit() and len(parts) > 1:
        parts = parts[1:]
    return " ".join(p.capitalize() for p in parts)


def menus(themes, theme_set, background_set, out):
    """Elephant menus with previews: the theme picker and one wallpaper picker per theme.
    Walker can't load WebP, so wallpapers get small PNG thumbnails."""
    names = [n.strip() for n in open(os.path.join(themes, "list")) if n.strip()]
    os.makedirs(os.path.join(out, "menus"))
    lines = [
        'name = "themes"', 'name_pretty = "Themes"', 'icon = "preferences-desktop-theme"',
        f"action = {toml_str(theme_set + ' %VALUE%')}", "fixed_order = true",
        "hide_from_providerlist = true", "",
    ]
    for name in names:
        d = os.path.join(themes, "themes", name)
        title_text = open(os.path.join(d, "title")).read().strip()
        mode = open(os.path.join(d, "mode")).read().strip()
        lines += ["[[entries]]", f"text = {toml_str(title_text)}", f"subtext = {toml_str(mode)}",
                  f"value = {toml_str(name)}", f"keywords = {toml_str([name, mode])}"]
        if os.path.exists(os.path.join(d, "preview.png")):
            lines += [f"preview = {toml_str(os.path.join(d, 'preview.png'))}", 'preview_type = "file"']
        lines.append("")
    with open(os.path.join(out, "menus", "themes.toml"), "w") as f:
        f.write("\n".join(lines))

    for name in names:
        bg_dir = os.path.join(themes, "themes", name, "backgrounds")
        thumbs = os.path.join(out, "thumbs", name)
        os.makedirs(thumbs)
        lines = [
            f"name = {toml_str('backgrounds-' + name)}", 'name_pretty = "Backgrounds"',
            'icon = "preferences-desktop-wallpaper"',
            f"action = {toml_str(background_set + ' %VALUE%')}", "fixed_order = true",
            "hide_from_providerlist = true", "",
        ]
        for filename in sorted(os.listdir(bg_dir)):
            thumb = os.path.join(thumbs, os.path.splitext(filename)[0] + ".png")
            subprocess.run(["magick", os.path.join(bg_dir, filename), "-resize", "800x450^",
                            "-gravity", "center", "-extent", "800x450", thumb], check=True)
            lines += ["[[entries]]", f"text = {toml_str(background_title(filename))}",
                      f"value = {toml_str(filename)}", f"preview = {toml_str(thumb)}",
                      'preview_type = "file"', ""]
        with open(os.path.join(out, "menus", f"backgrounds-{name}.toml"), "w") as f:
            f.write("\n".join(lines))


if __name__ == "__main__":
    if sys.argv[1] == "menus":
        menus(*sys.argv[2:6])
    else:
        main(sys.argv[1], sys.argv[2])
