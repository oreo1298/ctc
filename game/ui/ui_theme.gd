# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name UiTheme
extends RefCounted
## The game's UI theme, built in code so text scaling and palette tweaks are
## one function call. Modern layout, light medieval touches: parchment
## panels, ink borders, a storybook serif for headings.

const PAPER := Color("f3ead5")
const PAPER_DEEP := Color("e6d5b0")
const INK := Color("3b2f26")
const INK_SOFT := Color("6b5a4a")
const ACCENT := Color("d9483b")
const GOLD := Color("e2b33c")
const SILVER := Color("b9c0c9")
const BRONZE := Color("c98a52")

const BODY_FONT: FontFile = preload("res://fonts/Nunito.ttf")
const HEADING_FONT: FontFile = preload("res://fonts/Fraunces.ttf")


static func medal_color(m: Scoring.Medal) -> Color:
	match m:
		Scoring.Medal.GOLD:
			return GOLD
		Scoring.Medal.SILVER:
			return SILVER
		Scoring.Medal.BRONZE:
			return BRONZE
	return INK_SOFT.lerp(PAPER, 0.5)


static func body_font(weight: int = 650) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = BODY_FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f


static func heading_font(weight: int = 760) -> FontVariation:
	var ts: TextServer = TextServerManager.get_primary_interface()
	var f := FontVariation.new()
	f.base_font = HEADING_FONT
	f.variation_opentype = {
		ts.name_to_tag("wght"): weight,
		ts.name_to_tag("SOFT"): 100,
		ts.name_to_tag("WONK"): 1,
		ts.name_to_tag("opsz"): 72,
	}
	return f


static func panel_style(bg: Color = PAPER, border: int = 4, radius: int = 22) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = INK
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0.1, 0.06, 0.03, 0.28)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 6)
	s.set_content_margin_all(24)
	s.anti_aliasing = true
	return s


static func button_style(bg: Color, border: Color = INK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.border_width_bottom = 5
	s.set_corner_radius_all(14)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	s.anti_aliasing = true
	return s


static func build(text_scale: float = 1.0) -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = roundi(22 * text_scale)

	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_SOFT)
	t.set_stylebox("normal", "Button", button_style(PAPER_DEEP))
	t.set_stylebox("hover", "Button", button_style(PAPER))
	var pressed := button_style(PAPER_DEEP.darkened(0.08))
	pressed.border_width_bottom = 3
	pressed.content_margin_top = 12
	pressed.content_margin_bottom = 10
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", button_style(PAPER_DEEP.lerp(PAPER, 0.5), INK_SOFT))
	var focus := button_style(Color(0, 0, 0, 0), ACCENT)
	focus.draw_center = false
	focus.set_border_width_all(4)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	t.set_stylebox("focus", "Button", focus)

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())

	# Tabs: parchment pages with ink-edged tabs.
	var page := panel_style(PAPER_DEEP.lerp(PAPER, 0.5), 3, 12)
	page.shadow_size = 0
	page.set_content_margin_all(16)
	t.set_stylebox("panel", "TabContainer", page)
	var tab_on := button_style(PAPER_DEEP.lerp(PAPER, 0.5))
	tab_on.border_width_bottom = 0
	tab_on.corner_radius_bottom_left = 0
	tab_on.corner_radius_bottom_right = 0
	var tab_off := button_style(PAPER_DEEP.darkened(0.06), INK_SOFT)
	tab_off.border_width_bottom = 0
	tab_off.corner_radius_bottom_left = 0
	tab_off.corner_radius_bottom_right = 0
	t.set_stylebox("tab_selected", "TabContainer", tab_on)
	t.set_stylebox("tab_unselected", "TabContainer", tab_off)
	t.set_stylebox("tab_hovered", "TabContainer", tab_on)
	t.set_stylebox("tab_focus", "TabContainer", focus)
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", INK_SOFT)
	t.set_color("font_hovered_color", "TabContainer", INK)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_color("font_pressed_color", "CheckButton", INK)
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("normal", "CheckButton", empty)
	t.set_stylebox("hover", "CheckButton", empty)
	t.set_stylebox("pressed", "CheckButton", empty)
	var groove := StyleBoxFlat.new()
	groove.bg_color = PAPER_DEEP.darkened(0.12)
	groove.set_corner_radius_all(6)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	var fill := groove.duplicate() as StyleBoxFlat
	fill.bg_color = GOLD.darkened(0.1)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	# Heading label variation: storybook serif.
	t.add_type("HeadingLabel")
	t.set_type_variation("HeadingLabel", "Label")
	t.set_font("font", "HeadingLabel", heading_font())
	t.set_font_size("font_size", "HeadingLabel", roundi(46 * text_scale))
	t.set_color("font_color", "HeadingLabel", INK)

	t.add_type("TitleLabel")
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", heading_font(860))
	t.set_font_size("font_size", "TitleLabel", roundi(104 * text_scale))
	t.set_color("font_color", "TitleLabel", INK)
	t.set_color("font_outline_color", "TitleLabel", PAPER)
	t.set_constant("outline_size", "TitleLabel", roundi(14 * text_scale))

	# HUD text sits on the scene, so it gets a paper outline for contrast.
	t.add_type("HudLabel")
	t.set_type_variation("HudLabel", "Label")
	t.set_font("font", "HudLabel", body_font(800))
	t.set_font_size("font_size", "HudLabel", roundi(28 * text_scale))
	t.set_color("font_color", "HudLabel", INK)
	t.set_color("font_outline_color", "HudLabel", PAPER)
	t.set_constant("outline_size", "HudLabel", roundi(10 * text_scale))

	t.add_type("SmallLabel")
	t.set_type_variation("SmallLabel", "Label")
	t.set_font_size("font_size", "SmallLabel", roundi(18 * text_scale))
	t.set_color("font_color", "SmallLabel", INK_SOFT)

	t.add_type("BigButton")
	t.set_type_variation("BigButton", "Button")
	t.set_font("font", "BigButton", heading_font(720))
	t.set_font_size("font_size", "BigButton", roundi(32 * text_scale))
	var big := button_style(GOLD.lerp(PAPER, 0.35))
	big.content_margin_left = 40
	big.content_margin_right = 40
	t.set_stylebox("normal", "BigButton", big)
	var big_hover := button_style(GOLD.lerp(PAPER, 0.15))
	big_hover.content_margin_left = 40
	big_hover.content_margin_right = 40
	t.set_stylebox("hover", "BigButton", big_hover)

	t.add_type("HudButton")
	t.set_type_variation("HudButton", "Button")
	var hud := button_style(PAPER)
	hud.set_content_margin_all(10)
	hud.set_corner_radius_all(16)
	t.set_stylebox("normal", "HudButton", hud)
	var hud_hover := button_style(Color.WHITE)
	hud_hover.set_content_margin_all(10)
	hud_hover.set_corner_radius_all(16)
	t.set_stylebox("hover", "HudButton", hud_hover)
	t.set_stylebox("pressed", "HudButton", hud_hover)
	t.set_constant("icon_max_width", "HudButton", roundi(34 * text_scale))
	return t
