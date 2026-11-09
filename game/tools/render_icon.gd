# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends SceneTree
## Renders an SVG to square PNGs for desktop icons (no rsvg-convert needed).
##   godot --headless -s res://tools/render_icon.gd -- SVG OUT_DIR SIZE...
## Writes OUT_DIR/<size>.png for each size.


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("usage: -- SVG OUT_DIR SIZE...")
		quit(2)
		return
	var svg: PackedByteArray = FileAccess.get_file_as_bytes(args[0])
	if svg.is_empty():
		printerr("cannot read %s" % args[0])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	var probe := Image.new()
	probe.load_svg_from_buffer(svg, 1.0)
	var base: float = maxf(1.0, float(probe.get_width()))
	for i: int in range(2, args.size()):
		var size: int = args[i].to_int()
		var img := Image.new()
		if img.load_svg_from_buffer(svg, float(size) / base) != OK:
			printerr("cannot render %s" % args[0])
			quit(1)
			return
		if img.get_width() != size or img.get_height() != size:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		img.save_png(args[1].path_join("%d.png" % size))
	quit(0)
