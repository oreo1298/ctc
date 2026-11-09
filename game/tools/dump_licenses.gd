# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends SceneTree
## Writes the engine's own licence and every third-party notice compiled
## into this Godot build to a text file shipped with each package.
##   godot --headless -s res://tools/dump_licenses.gd -- OUT.txt


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- OUT.txt")
		quit(2)
		return
	var out: PackedStringArray = []
	var info: Dictionary = Engine.get_version_info()
	out.append("Godot Engine %s (https://godotengine.org)" % info.get("string", ""))
	out.append("=".repeat(72))
	out.append(Engine.get_license_text())
	out.append("")
	out.append("Third-party components compiled into the Godot Engine")
	out.append("=".repeat(72))
	for c: Dictionary in Engine.get_copyright_info():
		out.append("")
		out.append("%s" % c.get("name", ""))
		for part: Dictionary in c.get("parts", []):
			for line: String in part.get("copyright", PackedStringArray()):
				out.append("  Copyright %s" % line)
			out.append("  License: %s" % part.get("license", ""))
	out.append("")
	out.append("Licence texts")
	out.append("=".repeat(72))
	var licenses: Dictionary = Engine.get_license_info()
	var names: Array = licenses.keys()
	names.sort()
	for n: Variant in names:
		out.append("")
		out.append("----- %s -----" % n)
		out.append(str(licenses[n]))
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s" % args[0])
		quit(1)
		return
	f.store_string("\n".join(out) + "\n")
	quit(0)
