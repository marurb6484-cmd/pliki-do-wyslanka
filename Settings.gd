
extends Control
## Ustawienia: sterowanie, grafika, dźwięk, HUD, postęp.
## Każda zmiana jest natychmiast stosowana i zapisywana.

var _control_buttons: Array[Button] = []
var _quality_buttons: Array[Button] = []
var _fps_buttons: Array[Button] = []
var _toggles: Dictionary = {}

var _sensitivity_label: Label
var _tilt_label: Label
var _tilt_slider_label: Label
var _graphics_note: Label
var _graphics_advanced_container: VBoxContainer
var _graphics_advanced: bool = false
var _graphics_simple_button: Button
var _graphics_advanced_button: Button
var _render_scale_slider: HSlider
var _render_scale_value: Label

var _reset_confirm: bool = false
var _reset_button: Button

var _file_dialog: FileDialog
var _message_dialog: AcceptDialog
var _import_confirmation: ConfirmationDialog
var _music_list: ItemList
var _music_status: Label
var _music_move_up: Button
var _music_move_down: Button
var _music_remove: Button
var _style_search: LineEdit
var _style_catalog_list: ItemList
var _style_installed_list: ItemList
var _style_kind_option: OptionButton
var _style_resolution_option: OptionButton
var _style_obstacle_option: OptionButton
var _style_status: Label
var _style_progress: ProgressBar
var _style_pack_count: OptionButton
var _style_preview_name: Label
var _style_preview_info: Label
var _style_preview_root: Node3D
var _style_preview_viewport: SubViewport
var _style_preview_container: SubViewportContainer
var _style_only_downloaded: CheckButton
var _style_dirt_option: OptionButton
var _style_animal_option: OptionButton
var _style_preview_model: Node3D
var _style_preview_dragging: bool = false
var _style_preview_rotation: HSlider
var _style_download_confirm: ConfirmationDialog
var _style_delete_confirm: ConfirmationDialog
var _style_delete_target_id: String = ""
var _style_auto_proportion: CheckButton

# Konto i synchronizacja chmurowa
var _cloud_email: LineEdit
var _cloud_password: LineEdit
var _cloud_display_name: LineEdit
var _cloud_status: Label
var _cloud_user_label: Label
var _cloud_conflict_dialog: AcceptDialog


func _ready() -> void:
	UIKit.add_menu_background(self)

	var margin := UIKit.make_screen_margin(self, 30)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	column.add_child(UIKit.make_header("USTAWIENIA", GameManager.go_back))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)

	tabs.add_child(_build_controls_tab())
	tabs.add_child(_build_graphics_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_hud_tab())
	tabs.add_child(_build_other_tab())
	tabs.add_child(_build_language_tab())
	tabs.add_child(_build_content_tab())
	if GameSettings.open_content_tab_requested:
		tabs.current_tab = 6
		GameSettings.open_content_tab_requested = false

	_refresh()
	CloudSaveManager.status_changed.connect(_on_cloud_status_changed)
	CloudSaveManager.authenticated.connect(_on_cloud_authenticated)
	CloudSaveManager.auth_failed.connect(_on_cloud_auth_failed)
	CloudSaveManager.save_conflict.connect(_on_cloud_save_conflict)
	CloudSaveManager.cloud_save_received.connect(_on_cloud_save_received)
	CloudSaveManager.profile_received.connect(_on_cloud_profile_received)
	CloudSaveManager.profile_updated.connect(_on_cloud_profile_updated)


func _make_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	UIKit.configure_touch_scroll(scroll)
	scroll.name = LocaleManager.tr_text(title)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var tab_column := VBoxContainer.new()
	tab_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_column.add_theme_constant_override("separation", 16)

	scroll.add_child(tab_column)

	return tab_column


func _add_toggle(
	parent: Control,
	key: String,
	text: String,
	callback: Callable
) -> void:
	var button := UIKit.make_button(text, 30, 90)
	button.toggle_mode = true

	button.toggled.connect(func(pressed: bool) -> void:
		callback.call(pressed)
		_refresh()
	)

	parent.add_child(button)
	_toggles[key] = button


func _add_advanced_graphics_toggle(parent: Control, key: String, label_text: String, supported: bool) -> void:
	# Nie pokazujemy opcji, których aktywny renderer w ogóle nie obsługuje.
	if not supported:
		return
	var button := UIKit.make_button(label_text, 27, 90)
	button.toggle_mode = true
	button.toggled.connect(func(pressed: bool) -> void:
		GameSettings.set_advanced_graphics_option(key, pressed)
		_refresh()
	)
	parent.add_child(button)
	_toggles[key] = button
	button.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	button.add_theme_color_override("font_hover_color", Color(0.55, 1.0, 0.68))


func _set_toggle_tint(key: String, tint: Color) -> void:
	if not _toggles.has(key):
		return
	var button: Button = _toggles[key]
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_hover_color", tint.lightened(0.18))


func _on_render_scale_changed(value: float) -> void:
	GameSettings.set_render_scale_percent(value)
	_update_render_scale_label()


func _update_render_scale_label() -> void:
	if _render_scale_value == null:
		return
	var value: float = GameSettings.render_scale_percent
	_render_scale_value.text = "%d%%" % int(value)
	var tint: Color = Color(0.35, 0.95, 0.55) if value > 100.0 else Color(1.0, 0.38, 0.34) if value < 100.0 else Color(0.9, 0.92, 0.96)
	_render_scale_value.add_theme_color_override("font_color", tint)


func _slider_row(
	parent: Control,
	title: String,
	min_value: float,
	max_value: float,
	step: float,
	value: float,
	callback: Callable
) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	parent.add_child(row)

	var label := UIKit.make_label(title, 30)
	label.custom_minimum_size.x = 0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = 1.35
	row.add_child(label)

	var slider_well := PanelContainer.new()
	slider_well.name = "OddzielonaStrefaSuwaka"
	slider_well.custom_minimum_size = Vector2(230, 88)
	slider_well.size_flags_horizontal = Control.SIZE_SHRINK_END
	var well_style := StyleBoxFlat.new()
	well_style.bg_color = Color(0.025, 0.055, 0.085, 0.96)
	well_style.border_color = Color(0.0, 0.72, 0.88, 0.72)
	well_style.set_border_width_all(2)
	well_style.set_corner_radius_all(12)
	well_style.content_margin_left = 18.0
	well_style.content_margin_right = 18.0
	well_style.content_margin_top = 10.0
	well_style.content_margin_bottom = 10.0
	slider_well.add_theme_stylebox_override("panel", well_style)
	row.add_child(slider_well)
	var slider := UIKit.make_slider(min_value, max_value, step, value)
	slider.custom_minimum_size = Vector2(0, 76)
	slider.focus_mode = Control.FOCUS_ALL
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if callback.is_valid():
		slider.value_changed.connect(callback)
	slider_well.add_child(slider)

	return label


# =========================================================
# STEROWANIE
# =========================================================

func _build_controls_tab() -> Control:
	var tab := _make_tab("STEROWANIE")

	tab.add_child(
		UIKit.make_label("TRYB STEROWANIA", 34, UIKit.COLOR_ACCENT)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tab.add_child(row)

	var names: Array[String] = [
		"JOYSTICK",
		"PRZYCISKI ◀ ▶",
		"ŻYROSKOP"
	]

	for i: int in range(3):
		var button := UIKit.make_button(names[i], 32, 100)
		button.toggle_mode = true

		button.pressed.connect(func() -> void:
			GameSettings.set_control_mode(i)
			_refresh()
		)

		row.add_child(button)
		_control_buttons.append(button)

	var description := UIKit.make_label(
		"Gaz, hamulec i boost są zawsze po prawej stronie. Przytrzymanie hamulca po zatrzymaniu = cofanie. Gaz + hamulec w ostrym zakręcie = kontrolowany poślizg.",
		26,
		UIKit.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT,
		false
	)

	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(description)

	_sensitivity_label = _slider_row(
		tab,
		"",
		0.4,
		2.0,
		0.05,
		GameSettings.steering_sensitivity,
		func(value: float) -> void:
			GameSettings.set_steering_sensitivity(value)
			_refresh()
	)

	tab.add_child(
		UIKit.make_label("ŻYROSKOP", 34, UIKit.COLOR_ACCENT)
	)

	_tilt_slider_label = _slider_row(
		tab,
		"",
		10.0,
		45.0,
		1.0,
		GameSettings.gyro_max_tilt,
		func(value: float) -> void:
			GameSettings.set_gyro_max_tilt(value)
			_refresh()
	)

	var gyro_row := HBoxContainer.new()
	gyro_row.add_theme_constant_override("separation", 12)
	tab.add_child(gyro_row)

	_add_toggle(
		gyro_row,
		"gyro_invert",
		"Odwróć żyroskop",
		GameSettings.set_gyro_invert
	)

	var calibrate := UIKit.make_button(
		"KALIBRUJ (połóż telefon neutralnie)",
		28,
		90
	)

	calibrate.pressed.connect(func() -> void:
		GameSettings.calibrate_gyro()
		_refresh()
	)

	gyro_row.add_child(calibrate)

	_tilt_label = UIKit.make_label("", 28, UIKit.COLOR_MUTED)
	tab.add_child(_tilt_label)

	_add_toggle(
		tab,
		"haptics",
		"Wibracje przy uderzeniach",
		GameSettings.set_haptics_enabled
	)

	return tab.get_parent()


# =========================================================
# GRAFIKA
# =========================================================

func _build_graphics_tab() -> Control:
	var tab := _make_tab("GRAFIKA")

	tab.add_child(
		UIKit.make_label(
			"JAKOŚĆ (ustawia też przełączniki poniżej)",
			34,
			UIKit.COLOR_ACCENT
		)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tab.add_child(row)

	for i: int in range(GameSettings.QUALITY_NAMES.size()):
		var button := UIKit.make_button(
			GameSettings.QUALITY_NAMES[i],
			32,
			100
		)

		button.toggle_mode = true

		button.pressed.connect(func() -> void:
			GameSettings.set_quality_preset(i)
			_refresh()
		)

		row.add_child(button)
		_quality_buttons.append(button)

	_add_toggle(tab, "dynamic_resolution", "Automatyczne skalowanie rozdzielczości", GameSettings.set_dynamic_resolution_enabled)
	_set_toggle_tint("dynamic_resolution", Color(1.0, 0.38, 0.34))
	tab.add_child(UIKit.make_label("RĘCZNA SKALA ROZDZIELCZOŚCI 3D", 30, UIKit.COLOR_ACCENT))
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 12)
	tab.add_child(scale_row)
	_render_scale_value = UIKit.make_label("", 26, UIKit.COLOR_TEXT)
	_render_scale_value.custom_minimum_size.x = 105
	scale_row.add_child(_render_scale_value)
	var scale_well := PanelContainer.new()
	scale_well.custom_minimum_size = Vector2(0, 92)
	scale_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scale_well_style := StyleBoxFlat.new()
	scale_well_style.bg_color = Color(0.025, 0.055, 0.085, 0.96)
	scale_well_style.border_color = Color(0.0, 0.72, 0.88, 0.72)
	scale_well_style.set_border_width_all(2)
	scale_well_style.set_corner_radius_all(12)
	scale_well_style.content_margin_left = 20.0
	scale_well_style.content_margin_right = 20.0
	scale_well_style.content_margin_top = 8.0
	scale_well_style.content_margin_bottom = 8.0
	scale_well.add_theme_stylebox_override("panel", scale_well_style)
	scale_row.add_child(scale_well)
	_render_scale_slider = HSlider.new()
	_render_scale_slider.min_value = 35.0
	_render_scale_slider.max_value = 150.0
	_render_scale_slider.step = 5.0
	_render_scale_slider.value = GameSettings.render_scale_percent
	_render_scale_slider.custom_minimum_size = Vector2(0, 76)
	_render_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_render_scale_slider.focus_mode = Control.FOCUS_ALL
	_render_scale_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_render_scale_slider.value_changed.connect(_on_render_scale_changed)
	scale_well.add_child(_render_scale_slider)
	var scale_help := UIKit.make_label("Poniżej 100%: mniej pikseli i zwykle więcej FPS (czerwony). 100%: natywna skala. Powyżej 100%: supersampling, ostrzejszy obraz, ale większe obciążenie GPU (zielony). Automatyka może obniżyć skalę, jeśli zabraknie wydajności.", 22, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	scale_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(scale_help)
	tab.add_child(UIKit.make_label("BARDZO NISKA: ogranicza efekty, cienie i światła. Opcje oznaczone na czerwono poprawiają wydajność po wyłączeniu; zielone poprawiają jakość obrazu, ale mogą obciążać GPU.", 23, UIKit.COLOR_MUTED))

	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 12)
	tab.add_child(view_row)
	_graphics_simple_button = UIKit.make_button("TRYB PROSTY", 28, 78)
	_graphics_simple_button.toggle_mode = true
	_graphics_simple_button.pressed.connect(func() -> void: _set_graphics_view(false))
	view_row.add_child(_graphics_simple_button)
	_graphics_advanced_button = UIKit.make_button("TRYB ZAAWANSOWANY", 28, 78)
	_graphics_advanced_button.toggle_mode = true
	_graphics_advanced_button.pressed.connect(func() -> void: _set_graphics_view(true))
	view_row.add_child(_graphics_advanced_button)

	_graphics_advanced_container = VBoxContainer.new()
	_graphics_advanced_container.add_theme_constant_override("separation", 14)
	tab.add_child(_graphics_advanced_container)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_graphics_advanced_container.add_child(grid)

	_add_toggle(grid, "shadows", "Cienie", GameSettings.set_shadows_enabled)
	_add_toggle(grid, "neons", "Neony", GameSettings.set_neon_enabled)
	_add_toggle(grid, "headlights", "Reflektory", GameSettings.set_headlights_enabled)
	_add_toggle(grid, "reflections", "Odbicia", GameSettings.set_reflections_enabled)
	_add_toggle(grid, "effects", "Efekty (cząsteczki, poświata)", GameSettings.set_effects_enabled)
	_add_toggle(grid, "show_fps", "Licznik FPS", GameSettings.set_show_fps)
	_set_toggle_tint("shadows", Color(0.35, 0.95, 0.55))
	_set_toggle_tint("neons", Color(0.35, 0.95, 0.55))
	_set_toggle_tint("headlights", Color(0.35, 0.95, 0.55))
	_set_toggle_tint("reflections", Color(0.35, 0.95, 0.55))
	_set_toggle_tint("effects", Color(0.35, 0.95, 0.55))
	var basic_help := UIKit.make_label(
		"Cienie: bardziej realistyczne zacienienie, ale większe obciążenie GPU. Neony i reflektory: dodatkowe światła i lepszy wygląd robotów; więcej źródeł światła obniża FPS. Odbicia: pokazują otoczenie na powierzchniach, ale są kosztowne. Efekty: cząsteczki i poświaty dodają szczegółów, lecz obciążają GPU. Licznik FPS nie poprawia obrazu — tylko pokazuje wydajność.",
		22, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	basic_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_graphics_advanced_container.add_child(basic_help)

	_graphics_advanced_container.add_child(UIKit.make_label("POST-PROCESSING I JAKOŚĆ OBRAZU", 32, UIKit.COLOR_ACCENT))
	var post_grid := GridContainer.new()
	post_grid.columns = 2
	post_grid.add_theme_constant_override("h_separation", 12)
	post_grid.add_theme_constant_override("v_separation", 10)
	_graphics_advanced_container.add_child(post_grid)
	_add_advanced_graphics_toggle(post_grid, "fx_glow", "Glow / bloom", GameSettings.supports_glow())
	_add_advanced_graphics_toggle(post_grid, "fx_depth_fog", "Mgła głębiowa / wysokościowa", GameSettings.supports_depth_fog())
	_add_advanced_graphics_toggle(post_grid, "fx_ssao", "SSAO – cieniowanie kontaktowe", GameSettings.supports_ssao())
	_add_advanced_graphics_toggle(post_grid, "fx_ssil", "SSIL – światło pośrednie", GameSettings.supports_forward_plus_effects())
	_add_advanced_graphics_toggle(post_grid, "fx_ssr", "SSR – odbicia ekranowe", GameSettings.supports_forward_plus_effects())
	_add_advanced_graphics_toggle(post_grid, "fx_sdfgi", "SDFGI – globalne oświetlenie", GameSettings.supports_forward_plus_effects())
	_add_advanced_graphics_toggle(post_grid, "fx_volumetric_fog", "Mgła wolumetryczna", GameSettings.supports_forward_plus_effects())
	_add_advanced_graphics_toggle(post_grid, "fx_taa", "TAA – antyaliasing czasowy", GameSettings.supports_forward_plus_effects())
	_add_advanced_graphics_toggle(post_grid, "fx_debanding", "Debanding – redukcja pasów", GameSettings.supports_debanding())
	_add_advanced_graphics_toggle(post_grid, "fx_roughness_limiter", "Ograniczanie migotania odbić", GameSettings.supports_roughness_limiter())
	var fx_note := UIKit.make_label(
		"Wyświetlane są wyłącznie efekty obsługiwane przez aktywny renderer. Mobile: Glow, mgła głębiowa, debanding, ograniczanie migotania odbić oraz ReflectionProbe. Odbicia ReflectionProbe są dostępne w osobnym przełączniku Odbicia. SSR, SSIL, SDFGI, mgła wolumetryczna i TAA wymagają Forward+.",
		22, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	fx_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_graphics_advanced_container.add_child(fx_note)
	var quality_help := UIKit.make_label(
		"CO POPRAWIA OBRAZ I CO KOSZTUJE WYDAJNOŚĆ?\n" +
		"• Glow / bloom — poświata jasnych elementów; zwiększa koszt renderowania.\n" +
		"• Mgła głębiowa — dodaje głębi i atmosfery; może obciążać GPU.\n" +
		"• SSAO — przyciemnia miejsca styku obiektów, poprawia wrażenie przestrzeni; kosztowne.\n" +
		"• SSIL — symuluje odbite światło; poprawia realizm, mocno obciąża GPU.\n" +
		"• SSR — odbicia widoczne na ekranie; poprawiają realizm, mogą być kosztowne.\n" +
		"• SDFGI — globalne oświetlenie pośrednie; duża poprawa realizmu i duży koszt.\n" +
		"• Mgła wolumetryczna — przestrzenne snopy światła i mgła; bardzo kosztowna.\n" +
		"• TAA — wygładza krawędzie i migotanie; może lekko zmiękczać obraz i kosztuje wydajność.\n" +
		"• Debanding — usuwa widoczne pasy tonalne; zwykle niewielki koszt.\n" +
		"• Ograniczanie migotania odbić — stabilizuje błyszczące powierzchnie; niewielki lub umiarkowany koszt.\n" +
		"• Wyższa skala renderowania — ostrzejszy obraz, ale więcej pracy GPU. 100% oznacza natywną skalę renderowania 3D.\n" +
		"ULTRA automatycznie włącza wszystkie powyższe opcje obsługiwane przez renderer, ustawia skalę 100% i wyłącza dynamiczne obniżanie rozdzielczości. Niektóre efekty są niedostępne na rendererze Mobile.",
		22, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	quality_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_graphics_advanced_container.add_child(quality_help)

	_graphics_advanced_container.add_child(
		UIKit.make_label("LIMIT FPS", 34, UIKit.COLOR_ACCENT)
	)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	_graphics_advanced_container.add_child(fps_row)

	for value: int in GameSettings.FPS_OPTIONS:
		var fps_button := UIKit.make_button(
			"BEZ LIMITU" if value == 0 else str(value),
			30,
			96
		)

		fps_button.toggle_mode = true

		fps_button.pressed.connect(func() -> void:
			GameSettings.set_fps_limit(value)
			_refresh()
		)

		fps_row.add_child(fps_button)
		_fps_buttons.append(fps_button)

	var test_title := UIKit.make_label("TEST WYDAJNOŚCI", 34, UIKit.COLOR_ACCENT)
	tab.add_child(test_title)
	var test_description := UIKit.make_label(
		"Uruchamia osobną jazdę testową na losowej trasie z robotami AI. Zobaczysz średnie i minimalne FPS, 1% low, draw calls oraz liczbę obiektów. Test nie przyznaje nagród ani nie zmienia postępu.",
		24,
		UIKit.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT,
		false
	)
	test_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(test_description)
	var test_button := UIKit.make_button("URUCHOM TEST GRAFIKI", 32, 92)
	test_button.pressed.connect(_launch_graphics_test)
	tab.add_child(test_button)

	_graphics_note = UIKit.make_label(
		"",
		26,
		UIKit.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT,
		false
	)

	_graphics_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_graphics_advanced_container.add_child(_graphics_note)
	_set_graphics_view(false)

	return tab.get_parent()


func _set_graphics_view(advanced: bool) -> void:
	_graphics_advanced = advanced
	if _graphics_advanced_container != null:
		_graphics_advanced_container.visible = advanced
	if _graphics_simple_button != null:
		_graphics_simple_button.set_pressed_no_signal(not advanced)
	if _graphics_advanced_button != null:
		_graphics_advanced_button.set_pressed_no_signal(advanced)


func _launch_graphics_test() -> void:
	GameManager.launch_graphics_test_from_settings()


# =========================================================
# DŹWIĘK
# =========================================================

func _refresh_music_list() -> void:
	if _music_list == null:
		return
	var selected: int = _music_list.get_selected_items()[0] if not _music_list.get_selected_items().is_empty() else -1
	_music_list.clear()
	for i: int in range(MusicManager.tracks.size()):
		var prefix: String = "▶  " if i == MusicManager.current_index else "%d.  " % (i + 1)
		_music_list.add_item(prefix + MusicManager.get_track_title(i))
	if selected >= 0 and selected < _music_list.item_count:
		_music_list.select(selected)
	_update_music_edit_buttons()


func _update_music_edit_buttons() -> void:
	if _music_list == null:
		return
	var selected_items: PackedInt32Array = _music_list.get_selected_items()
	var selected: int = selected_items[0] if not selected_items.is_empty() else -1
	_music_move_up.disabled = selected <= 0
	_music_move_down.disabled = selected < 0 or selected >= MusicManager.tracks.size() - 1
	_music_remove.disabled = selected < 0


func _move_selected_music(direction: int) -> void:
	if _music_list == null:
		return
	var selected_items: PackedInt32Array = _music_list.get_selected_items()
	if selected_items.is_empty():
		return
	var selected: int = selected_items[0]
	if MusicManager.move_track(selected, direction):
		var target: int = clampi(selected + signi(direction), 0, MusicManager.tracks.size() - 1)
		_refresh_music_list()
		_music_list.select(target)
		_music_status.text = MusicManager.get_status()


func _remove_selected_music() -> void:
	if _music_list == null:
		return
	var selected_items: PackedInt32Array = _music_list.get_selected_items()
	if selected_items.is_empty():
		return
	var selected: int = selected_items[0]
	if MusicManager.remove_track(selected):
		_refresh_music_list()
		if _music_list.item_count > 0:
			_music_list.select(mini(selected, _music_list.item_count - 1))
		_music_status.text = MusicManager.get_status()


func _build_audio_tab() -> Control:
	var tab := _make_tab("DŹWIĘK")

	for entry: Array in [
		["master", "Głośność główna", GameSettings.master_volume],
		["sfx", "Efekty", GameSettings.sfx_volume],
		["engine", "Silniki robotów", GameSettings.engine_volume],
		["ui", "Interfejs", GameSettings.ui_volume]
	]:
		var channel: String = entry[0]

		var label: Label = _slider_row(
			tab,
			"%s: %d%%" % [
				str(entry[1]),
				int(float(entry[2]) * 100.0)
			],
			0.0,
			1.0,
			0.05,
			float(entry[2]),
			Callable()
		)

		var slider_well: PanelContainer = label.get_parent().get_child(1) as PanelContainer
		var slider: HSlider = slider_well.get_child(0) as HSlider
		var title: String = entry[1]

		slider.value_changed.connect(func(value: float) -> void:
			GameSettings.set_volume(channel, value)
			label.text = "%s: %d%%" % [
				title,
				int(value * 100.0)
			]
		)

	var test := UIKit.make_button("TEST DŹWIĘKU", 30, 90)
	test.pressed.connect(func() -> void:
		AudioManager.play("boost")
	)

	tab.add_child(test)

	var music_title := UIKit.make_label("WŁASNA MUZYKA", 32, UIKit.COLOR_ACCENT)
	tab.add_child(music_title)
	_music_status = UIKit.make_label(MusicManager.get_status(), 24, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	_music_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(_music_status)
	var music_row := HBoxContainer.new()
	tab.add_child(music_row)
	var import_music := UIKit.make_button("DODAJ UTWORY / LISTĘ", 28, 84)
	music_row.add_child(import_music)
	var toggle_music := UIKit.make_button("ODTWÓRZ / PAUZA", 28, 84)
	music_row.add_child(toggle_music)
	var next_music := UIKit.make_button("NASTĘPNY", 28, 84)
	music_row.add_child(next_music)
	_music_list = ItemList.new()
	_music_list.custom_minimum_size = Vector2(0, 220)
	_music_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_list.select_mode = ItemList.SELECT_SINGLE
	tab.add_child(_music_list)
	var edit_music_row := HBoxContainer.new()
	tab.add_child(edit_music_row)
	_music_move_up = UIKit.make_button("↑ PRZESUŃ WYŻEJ", 25, 72)
	_music_move_down = UIKit.make_button("↓ PRZESUŃ NIŻEJ", 25, 72)
	_music_remove = UIKit.make_button("USUŃ Z LISTY", 25, 72)
	edit_music_row.add_child(_music_move_up)
	edit_music_row.add_child(_music_move_down)
	edit_music_row.add_child(_music_remove)
	var music_dialog := FileDialog.new()
	music_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	music_dialog.access = FileDialog.ACCESS_FILESYSTEM
	music_dialog.use_native_dialog = true
	music_dialog.add_filter("*.mp3, *.ogg, *.wav", "Muzyka (MP3, OGG, WAV)")
	music_dialog.title = "Wybierz utwory muzyczne"
	add_child(music_dialog)
	import_music.pressed.connect(func() -> void: music_dialog.popup_centered_clamped(Vector2i(1100, 760)))
	music_dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		var count: int = MusicManager.add_files(paths)
		_music_status.text = "%d utworów dodano. %s" % [count, MusicManager.get_status()]
		_refresh_music_list()
	)
	toggle_music.pressed.connect(func() -> void:
		MusicManager.toggle_playback()
		_music_status.text = MusicManager.get_status()
		_refresh_music_list()
	)
	next_music.pressed.connect(func() -> void:
		MusicManager.next_track()
		_music_status.text = MusicManager.get_status()
		_refresh_music_list()
	)
	_music_move_up.pressed.connect(func() -> void: _move_selected_music(-1))
	_music_move_down.pressed.connect(func() -> void: _move_selected_music(1))
	_music_remove.pressed.connect(_remove_selected_music)
	_music_list.item_selected.connect(func(_index: int) -> void: _update_music_edit_buttons())
	MusicManager.track_changed.connect(func(_title: String, _index: int, _count: int) -> void:
		_music_status.text = MusicManager.get_status()
		_refresh_music_list()
	)
	_refresh_music_list()

	var note := UIKit.make_label(
		"Muzyka jest kopiowana do pamięci gry i działa offline. Możesz zmieniać kolejność utworów i usuwać je z playlisty (plik pozostaje w pamięci gry). Obsługiwane formaty: MP3, OGG i WAV. Na Androidzie dostępność plików zależy od systemowego selektora plików.",
		22,
		UIKit.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT,
		false
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)

	return tab.get_parent()


# =========================================================
# HUD
# =========================================================

func _build_hud_tab() -> Control:
	var tab := _make_tab("HUD")

	var edit := UIKit.make_button("EDYTUJ UKŁAD HUD", 36, 110)
	edit.pressed.connect(func() -> void:
		GameManager.open_hud_editor(GameManager.SCENE_SETTINGS)
	)

	tab.add_child(edit)

	var info := UIKit.make_label(
		"Elementy HUD można przesuwać, skalować i ukrywać. Układ zapisywany jest osobno dla każdej proporcji ekranu (aktualnie: %s)." % GameSettings.get_aspect_bucket(get_viewport_rect().size),
		26,
		UIKit.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT,
		false
	)

	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(info)

	var opacity_label: Label = _slider_row(
		tab,
		"Przezroczystość HUD",
		0.3,
		1.0,
		0.05,
		GameSettings.hud_opacity,
		func(value: float) -> void:
			GameSettings.set_hud_opacity(value)
	)

	opacity_label.text = "Krycie HUD"

	var reset := UIKit.make_button(
		"PRZYWRÓĆ DOMYŚLNY UKŁAD (wszystkie ekrany)",
		30,
		96
	)

	reset.pressed.connect(func() -> void:
		for bucket: String in GameSettings.hud_layouts.keys():
			GameSettings.reset_hud_layout(bucket)

		reset.text = "PRZYWRÓCONO"
	)

	tab.add_child(reset)

	return tab.get_parent()


# =========================================================
# POSTĘP
# =========================================================

func _build_other_tab() -> Control:
	var tab := _make_tab("POSTĘP")

	tab.add_child(
		UIKit.make_label(
			"CrunpBot Racer %s" % str(
				ProjectSettings.get_setting(
					"application/config/version",
					""
				)
			),
			32
		)
	)

	tab.add_child(
		UIKit.make_label(
			"Postęp zapisywany automatycznie: %s" % ProjectSettings.globalize_path(SaveManager.save_path),
			22,
			UIKit.COLOR_MUTED
		)
	)

	tab.add_child(UIKit.make_label("STYL ROZGRYWKI", 30, UIKit.COLOR_ACCENT))
	var play_style_note := UIKit.make_label("Prosty: automatyczne ustawienia i mniej decyzji. Zaawansowany: pełna kontrola nad konfiguracją wyścigu.", 22, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	play_style_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(play_style_note)
	var play_style_row := HBoxContainer.new()
	play_style_row.add_theme_constant_override("separation", 12)
	tab.add_child(play_style_row)
	var simple_style_button := UIKit.make_button("TRYB PROSTY", 26, 76)
	simple_style_button.toggle_mode = true
	simple_style_button.button_pressed = GameSettings.is_simple_play_style()
	var advanced_style_button := UIKit.make_button("TRYB ZAAWANSOWANY", 26, 76)
	advanced_style_button.toggle_mode = true
	advanced_style_button.button_pressed = not GameSettings.is_simple_play_style()
	simple_style_button.pressed.connect(func() -> void:
		GameSettings.set_play_style("simple")
		simple_style_button.set_pressed_no_signal(true)
		advanced_style_button.set_pressed_no_signal(false)
	)
	advanced_style_button.pressed.connect(func() -> void:
		GameSettings.set_play_style("advanced")
		advanced_style_button.set_pressed_no_signal(true)
		simple_style_button.set_pressed_no_signal(false)
	)
	play_style_row.add_child(simple_style_button)
	play_style_row.add_child(advanced_style_button)

	_build_cloud_account_section(tab)

	tab.add_child(
		UIKit.make_label(
			"KOPIA ZAPASOWA POSTĘPU",
			30,
			UIKit.COLOR_ACCENT
		)
	)

	var export_button := UIKit.make_button(
		"EKSPORTUJ POSTĘP DO PLIKU",
		32,
		100
	)

	export_button.pressed.connect(_open_export_dialog)
	tab.add_child(export_button)

	var import_button := UIKit.make_button(
		"IMPORTUJ POSTĘP Z PLIKU",
		32,
		100
	)

	import_button.pressed.connect(_open_import_dialog)
	tab.add_child(import_button)

	var backup_note := UIKit.make_label(
		"Eksport obejmuje CR, roboty, ulepszenia, stacje dokujące, skórki, rekordy i statystyki. Nie obejmuje ustawień grafiki, sterowania, dźwięku ani HUD.",
		24,
		UIKit.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT,
		false
	)

	backup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(backup_note)

	tab.add_child(
		UIKit.make_label(
			"RESET",
			30,
			UIKit.COLOR_ACCENT
		)
	)

	_reset_button = UIKit.make_button(
		"RESETUJ POSTĘP",
		32,
		100
	)

	_reset_button.pressed.connect(_on_reset_progress)
	tab.add_child(_reset_button)

	var reset_note := UIKit.make_label(
		"Reset usuwa postęp wszystkich robotów, ulepszenia stacji, rekordy i statystyki. Ustawienia gry pozostają zachowane.",
		24,
		UIKit.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT,
		false
	)

	reset_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(reset_note)

	return tab.get_parent()



# =========================================================
# KONTO I ZAPIS W CHMURZE
# =========================================================

func _build_cloud_account_section(parent: VBoxContainer) -> void:
	parent.add_child(UIKit.make_label("KONTO CRUNPBOT I CHMURA", 30, UIKit.COLOR_ACCENT))
	var explanation := UIKit.make_label(
		"Zaloguj się, aby przenosić postęp między urządzeniami. Zapis lokalny pozostaje dostępny offline. Przy konflikcie nic nie zostanie nadpisane bez Twojej decyzji.",
		22, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(explanation)

	_cloud_user_label = UIKit.make_label(_cloud_account_text(), 23, UIKit.COLOR_TEXT)
	_cloud_user_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_cloud_user_label)

	_cloud_display_name = LineEdit.new()
	_cloud_display_name.placeholder_text = LocaleManager.tr_text("Nazwa gracza (przy rejestracji)")
	_cloud_display_name.custom_minimum_size.y = 62
	parent.add_child(_cloud_display_name)
	_cloud_email = LineEdit.new()
	_cloud_email.placeholder_text = LocaleManager.tr_text("Adres e-mail")
	_cloud_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_cloud_email.custom_minimum_size.y = 62
	parent.add_child(_cloud_email)
	_cloud_password = LineEdit.new()
	_cloud_password.placeholder_text = LocaleManager.tr_text("Hasło (minimum 10 znaków)")
	_cloud_password.secret = true
	_cloud_password.custom_minimum_size.y = 62
	parent.add_child(_cloud_password)

	var auth_row := HBoxContainer.new()
	auth_row.add_theme_constant_override("separation", 10)
	parent.add_child(auth_row)
	var register_button := UIKit.make_button("UTWÓRZ KONTO", 25, 82)
	register_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	register_button.pressed.connect(_on_cloud_register_pressed)
	auth_row.add_child(register_button)
	var login_button := UIKit.make_button("ZALOGUJ", 25, 82)
	login_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	login_button.pressed.connect(_on_cloud_login_pressed)
	auth_row.add_child(login_button)

	var sync_row := HBoxContainer.new()
	sync_row.add_theme_constant_override("separation", 10)
	parent.add_child(sync_row)
	var upload_button := UIKit.make_button("WYŚLIJ LOKALNY ZAPIS", 23, 82)
	upload_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upload_button.pressed.connect(_on_cloud_upload_pressed)
	sync_row.add_child(upload_button)
	var download_button := UIKit.make_button("POBIERZ Z CHMURY", 23, 82)
	download_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	download_button.pressed.connect(_on_cloud_download_pressed)
	sync_row.add_child(download_button)
	var profile_button := UIKit.make_button("ZAPISZ NAZWĘ PROFILU W CHMURZE", 22, 78)
	profile_button.pressed.connect(_on_cloud_profile_save_pressed)
	parent.add_child(profile_button)
	var logout_button := UIKit.make_button("WYLOGUJ", 23, 82)
	logout_button.pressed.connect(_on_cloud_logout_pressed)
	parent.add_child(logout_button)

	_cloud_status = UIKit.make_label("Gotowy. Zapis lokalny działa niezależnie od sieci.", 21, UIKit.COLOR_MUTED)
	_cloud_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_cloud_status)

	var cloud_assets_note := UIKit.make_label(
		"Udostępnianie skinów i tras przez chmurę jest obecnie wyłączone. Pliki i własne dodatki pozostają lokalne na urządzeniu.",
		21, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	cloud_assets_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(cloud_assets_note)

	_cloud_conflict_dialog = AcceptDialog.new()
	_cloud_conflict_dialog.title = LocaleManager.tr_text("KONFLIKT ZAPISÓW")
	_cloud_conflict_dialog.dialog_text = LocaleManager.tr_text("Wykryto dwa różne zapisy. Wybierz, który ma pozostać aktywny.")
	_cloud_conflict_dialog.add_button(LocaleManager.tr_text("ZACHOWAJ LOKALNY"), false, "keep_local")
	_cloud_conflict_dialog.add_button(LocaleManager.tr_text("UŻYJ CHMUROWEGO"), false, "use_cloud")
	_cloud_conflict_dialog.add_button(LocaleManager.tr_text("ANULUJ"), false, "cancel")
	_cloud_conflict_dialog.custom_action.connect(_on_cloud_conflict_action)
	add_child(_cloud_conflict_dialog)




func _cloud_account_text() -> String:
	if CloudSaveManager.token.is_empty():
		return LocaleManager.tr_text("Status konta: niezalogowano")
	var display_name := str(CloudSaveManager.user.get("display_name", "Gracz"))
	var email := str(CloudSaveManager.user.get("email", ""))
	return "%s: %s  %s" % [LocaleManager.tr_text("Zalogowano jako"), display_name, email]




func _on_cloud_profile_received(profile: Dictionary) -> void:
	if _cloud_display_name != null and not str(profile.get("public_name", "")).is_empty():
		_cloud_display_name.text = str(profile.get("public_name", ""))

func _on_cloud_profile_updated(profile: Dictionary) -> void:
	_on_cloud_status_changed("Profil zapisany w chmurze: %s" % str(profile.get("public_name", "")))

func _on_cloud_profile_save_pressed() -> void:
	if _cloud_display_name == null or CloudSaveManager.token.is_empty():
		_on_cloud_status_changed("Zaloguj się przed edycją profilu.")
		return
	var err := CloudSaveManager.update_cloud_profile(_cloud_display_name.text.strip_edges())
	if err != OK:
		_on_cloud_status_changed("Nie udało się zapisać profilu (kod %d)." % err)

func _on_cloud_register_pressed() -> void:
	if _cloud_email == null or _cloud_password == null:
		return
	var err := CloudSaveManager.register_email(_cloud_email.text.strip_edges(), _cloud_password.text, _cloud_display_name.text.strip_edges())
	if err != OK:
		_on_cloud_auth_failed("Nie udało się rozpocząć rejestracji (kod %d)." % err)


func _on_cloud_login_pressed() -> void:
	if _cloud_email == null or _cloud_password == null:
		return
	var err := CloudSaveManager.login_email(_cloud_email.text.strip_edges(), _cloud_password.text)
	if err != OK:
		_on_cloud_auth_failed("Nie udało się rozpocząć logowania (kod %d)." % err)


func _on_cloud_upload_pressed() -> void:
	var err := CloudSaveManager.upload_local_save()
	if err != OK:
		_on_cloud_status_changed("Nie udało się rozpocząć wysyłania (kod %d)." % err)


func _on_cloud_download_pressed() -> void:
	var err := CloudSaveManager.download_cloud_save()
	if err != OK:
		_on_cloud_status_changed("Nie udało się rozpocząć pobierania (kod %d)." % err)


func _on_cloud_logout_pressed() -> void:
	CloudSaveManager.logout_account()
	_cloud_user_label.text = _cloud_account_text()


func _on_cloud_status_changed(message: String) -> void:
	if _cloud_status != null:
		_cloud_status.text = message


func _on_cloud_authenticated(_account: Dictionary) -> void:
	if _cloud_user_label != null:
		_cloud_user_label.text = _cloud_account_text()
	if _cloud_password != null:
		_cloud_password.clear()
	CloudSaveManager.get_cloud_profile()


func _on_cloud_auth_failed(message: String) -> void:
	_on_cloud_status_changed("Logowanie: " + message)


func _progress_summary(path: String) -> String:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or config.load(path) != OK:
		return "Brak czytelnego zapisu"
	var currency := int(config.get_value("progress", "currency", config.get_value("economy", "player_points", 0)))
	var unlocked: Variant = config.get_value("progress", "unlocked_robots", [])
	var unlocked_count := unlocked.size() if unlocked is Array else 0
	var selected_robot := int(config.get_value("selection", "robot", 0))
	var career: Variant = config.get_value("career", "state", {})
	var career_stage := "—"
	if career is Dictionary:
		career_stage = str(career.get("stage", career.get("chapter", "—")))
	return "%s: %d\n%s: %d\n%s: %d\n%s: %s" % [LocaleManager.tr_text("CR"), currency, LocaleManager.tr_text("Odblokowane roboty"), unlocked_count, LocaleManager.tr_text("Wybrany robot ID"), selected_robot, LocaleManager.tr_text("Etap kariery"), career_stage]


func _on_cloud_save_conflict(local_updated_at: String, cloud_save: Dictionary) -> void:
	_show_cloud_save_comparison(local_updated_at, cloud_save)


func _on_cloud_save_received(cloud_save: Dictionary) -> void:
	if cloud_save.is_empty():
		return
	_show_cloud_save_comparison(Time.get_datetime_string_from_system(), cloud_save)


func _show_cloud_save_comparison(local_updated_at: String, cloud_save: Dictionary) -> void:
	if _cloud_conflict_dialog == null:
		return
	var cloud_path := CloudSaveManager.CLOUD_IMPORT
	var local_path := "user://crunpbot_conflict_local.cfg"
	SaveManager.export_progress(local_path)
	var cloud_time := "Nieznany czas"
	var cloud_timestamp: Variant = cloud_save.get("updated_at", null)
	if cloud_timestamp is int or cloud_timestamp is float:
		cloud_time = Time.get_datetime_string_from_unix_time(int(int(cloud_timestamp) / 1000))
	_cloud_conflict_dialog.dialog_text = "%s\n%s\n%s\n\n%s\n%s %s\n%s\n\n%s" % [LocaleManager.tr_text("LOKALNY ZAPIS"), local_updated_at, _progress_summary(local_path), LocaleManager.tr_text("ZAPIS CHMUROWY"), LocaleManager.tr_text("Aktualizacja:"), cloud_time, _progress_summary(cloud_path), LocaleManager.tr_text("Wybierz świadomie. Druga wersja nie zostanie usunięta z serwera ani z lokalnej kopii.")]
	_cloud_conflict_dialog.popup_centered(Vector2i(760, 620))


func _on_cloud_conflict_action(action: String) -> void:
	match action:
		"keep_local":
			# Konflikt został już pobrany; ustawiamy aktualną rewizję serwera jako bazę
			# i ponawiamy wysyłkę lokalnej kopii. Serwer zachowa poprzednią rewizję w historii.
			var err := CloudSaveManager.upload_local_save()
			if err != OK:
				_on_cloud_status_changed("Nie udało się ponowić wysyłania lokalnego zapisu (kod %d)." % err)
		"use_cloud":
			if CloudSaveManager.apply_cloud_save_after_confirmation():
				_on_cloud_status_changed("Zapis chmurowy zastosowano. Poprzedni lokalny zapis zachowano w kopii bezpieczeństwa.")
		"cancel":
			_on_cloud_status_changed("Konflikt pozostawiono bez zmian. Żaden zapis nie został nadpisany.")


# =========================================================
# JĘZYK
# =========================================================

func _build_language_tab() -> Control:
	var tab := _make_tab("JĘZYK")
	tab.add_child(UIKit.make_label("JĘZYK INTERFEJSU", 34, UIKit.COLOR_ACCENT))
	var note := UIKit.make_label(
		"Wybierz język gry. Zmiana jest zapisywana automatycznie. Nieprzetłumaczone teksty pozostają w języku polskim.",
		23, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)
	var language_select := OptionButton.new()
	language_select.custom_minimum_size.y = 66
	var codes: Array[String] = LocaleManager.get_languages()
	for code: String in codes:
		language_select.add_item(LocaleManager.get_language_name(code))
		language_select.set_item_metadata(language_select.item_count - 1, code)
		if code == LocaleManager.language_code:
			language_select.select(language_select.item_count - 1)
	language_select.item_selected.connect(func(index: int) -> void:
		var code: String = str(language_select.get_item_metadata(index))
		LocaleManager.set_language(code)
		get_tree().reload_current_scene()
	)
	tab.add_child(language_select)
	return tab.get_parent()

# =========================================================
# DODATKOWA ZAWARTOŚĆ / STYLE PACKI
# =========================================================

func _build_content_tab() -> Control:
	var tab := _make_tab("DODATKOWA ZAWARTOŚĆ")
	tab.add_child(UIKit.make_label("PAKIET STYLU: MODERN HOME", 36, UIKit.COLOR_ACCENT))
	var credit := UIKit.make_label(
		"Modele 3D mebli, przedmiotów, przeszkód i zabrudzeń. Pobierane na żądanie, po instalacji dostępne offline. Źródło: Poly Haven • CC0 1.0 Universal.",
		21, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(credit)
	_style_status = UIKit.make_label(StylePackManager.get_status_text(), 25, UIKit.COLOR_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	_style_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(_style_status)
	var scan_row := HBoxContainer.new()
	tab.add_child(scan_row)
	var scan := UIKit.make_button("ODŚWIEŻ KATALOG ONLINE", 28, 86)
	scan.pressed.connect(func() -> void: StylePackManager.refresh_catalog())
	scan_row.add_child(scan)
	_style_resolution_option = OptionButton.new()
	_style_resolution_option.add_item("Tekstury 1K — standard")
	_style_resolution_option.add_item("Tekstury 2K — większa szczegółowość")
	_style_resolution_option.selected = 1 if StylePackManager.preferred_resolution == "2k" else 0
	_style_resolution_option.item_selected.connect(func(index: int) -> void:
		StylePackManager.set_preferred_resolution("2k" if index == 1 else "1k")
	)
	scan_row.add_child(_style_resolution_option)
	_style_search = LineEdit.new()
	_style_search.placeholder_text = "Szukaj modelu: sofa, toy, crumbs, dust, mud, shoe…"
	_style_search.custom_minimum_size = Vector2(0, 58)
	_style_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_search.text_changed.connect(_refresh_style_catalog_list)
	tab.add_child(_style_search)
	tab.add_child(UIKit.make_label("AUTOMATYCZNY PAKIET MODELI", 30, UIKit.COLOR_ACCENT))
	var auto_note := UIKit.make_label("Wybierz do 200 modeli z katalogu Poly Haven. Pobieranie odbywa się po kolei. Automatyczne przypisanie działa na podstawie nazw i tagów; każdy model można później obejrzeć i przypisać ręcznie. Poly Haven nie musi zawierać modeli każdego rodzaju brudu, plam ani przeszkód.", 21, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	auto_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(auto_note)
	var auto_row := HBoxContainer.new()
	tab.add_child(auto_row)
	_style_pack_count = OptionButton.new()
	for amount: int in [5, 10, 20, 50, 100, 150, 200]: _style_pack_count.add_item("%d modeli" % amount)
	_style_pack_count.select([5, 10, 20, 50, 100, 150, 200].find(StylePackManager.auto_pack_limit) if [5, 10, 20, 50, 100, 150, 200].has(StylePackManager.auto_pack_limit) else 2)
	auto_row.add_child(_style_pack_count)
	var auto_install := UIKit.make_button("ZBUDUJ PAKIET MODERN HOME", 24, 72)
	auto_install.pressed.connect(func() -> void: StylePackManager.start_auto_pack([5, 10, 20, 50, 100, 150, 200][_style_pack_count.selected]))
	auto_row.add_child(auto_install)
	_style_catalog_list = ItemList.new()
	_style_catalog_list.custom_minimum_size = Vector2(0, 380)
	_style_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_catalog_list.size_flags_vertical = Control.SIZE_FILL
	_style_catalog_list.select_mode = ItemList.SELECT_SINGLE
	var catalog_list_row := HBoxContainer.new()
	catalog_list_row.custom_minimum_size = Vector2(0, 320)
	catalog_list_row.add_theme_constant_override("separation", 20)
	tab.add_child(catalog_list_row)
	var catalog_scroll := ScrollContainer.new()
	UIKit.configure_touch_scroll(catalog_scroll)
	catalog_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog_scroll.add_child(_style_catalog_list)
	catalog_list_row.add_child(catalog_scroll)
	var actions := VBoxContainer.new()
	tab.add_child(actions)
	var download_row := HBoxContainer.new()
	actions.add_child(download_row)
	var download := UIKit.make_button("POBIERZ WYBRANY MODEL", 27, 82)
	download.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	download.pressed.connect(_download_selected_style_asset)
	download_row.add_child(download)
	var delete_row := HBoxContainer.new()
	actions.add_child(delete_row)
	var remove := UIKit.make_button("USUŃ WYBRANY PAKIET", 27, 82)
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.pressed.connect(_request_delete_selected_style_asset)
	delete_row.add_child(remove)
	var remove_all := UIKit.make_button("USUŃ WSZYSTKIE PAKIETY", 27, 82)
	remove_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_all.pressed.connect(_request_delete_all_style_assets)
	delete_row.add_child(remove_all)
	_style_progress = ProgressBar.new()
	_style_progress.custom_minimum_size = Vector2(0, 28)
	_style_progress.max_value = 100.0
	tab.add_child(_style_progress)
	tab.add_child(UIKit.make_label("ZAINSTALOWANE MODELE", 30, UIKit.COLOR_ACCENT))
	_style_installed_list = ItemList.new()
	_style_installed_list.custom_minimum_size = Vector2(0, 420)
	_style_installed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_installed_list.size_flags_vertical = Control.SIZE_FILL
	_style_installed_list.select_mode = ItemList.SELECT_SINGLE
	_style_installed_list.item_selected.connect(_on_style_installed_selected)
	var installed_preview_row := HBoxContainer.new()
	installed_preview_row.custom_minimum_size = Vector2(0, 760)
	installed_preview_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(installed_preview_row)
	var installed_list_panel := VBoxContainer.new()
	installed_list_panel.custom_minimum_size.x = 520
	installed_list_panel.size_flags_horizontal = Control.SIZE_FILL
	installed_preview_row.add_child(installed_list_panel)
	installed_list_panel.add_child(UIKit.make_label("LISTA MODELI", 25, UIKit.COLOR_ACCENT))
	var installed_list_row := HBoxContainer.new()
	installed_list_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	installed_list_row.add_theme_constant_override("separation", 20)
	installed_list_panel.add_child(installed_list_row)
	var installed_scroll := ScrollContainer.new()
	UIKit.configure_touch_scroll(installed_scroll)
	installed_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	installed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	installed_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	installed_scroll.add_child(_style_installed_list)
	installed_list_row.add_child(installed_scroll)
	var preview_panel := VBoxContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	installed_preview_row.add_child(preview_panel)
	var preview_title := UIKit.make_label("PODGLĄD WYBRANEGO MODELU 3D", 30, UIKit.COLOR_ACCENT)
	preview_panel.add_child(preview_title)
	_style_preview_name = UIKit.make_label("Wybierz pobrany model z listy", 24, UIKit.COLOR_TEXT)
	preview_panel.add_child(_style_preview_name)
	var preview_square := AspectRatioContainer.new()
	preview_square.ratio = 1.0
	preview_square.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_square.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_square.custom_minimum_size = Vector2(680, 680)
	preview_panel.add_child(preview_square)
	_style_preview_container = SubViewportContainer.new()
	_style_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_preview_container.stretch = true
	_style_preview_viewport = SubViewport.new()
	_style_preview_viewport.size = Vector2i(640, 640)
	_style_preview_viewport.transparent_bg = false
	_style_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_style_preview_container.add_child(_style_preview_viewport)
	var preview_world := Node3D.new()
	_style_preview_viewport.add_child(preview_world)
	var preview_camera := Camera3D.new()
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.size = 5.4
	preview_camera.position = Vector3(4.0, 3.2, 4.0)
	preview_camera.look_at(Vector3.ZERO, Vector3.UP)
	preview_camera.current = true
	preview_world.add_child(preview_camera)
	var preview_light := DirectionalLight3D.new()
	preview_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	preview_light.light_energy = 1.6
	preview_world.add_child(preview_light)
	var preview_fill := OmniLight3D.new()
	preview_fill.position = Vector3(-2.0, 1.2, -1.5)
	preview_fill.light_energy = 0.8
	preview_world.add_child(preview_fill)
	_style_preview_root = Node3D.new()
	preview_world.add_child(_style_preview_root)
	preview_square.add_child(_style_preview_container)
	_style_preview_container.gui_input.connect(_on_style_preview_gui_input)
	_style_preview_rotation = HSlider.new()
	_style_preview_rotation.min_value = 0.0
	_style_preview_rotation.max_value = 360.0
	_style_preview_rotation.step = 1.0
	_style_preview_rotation.value = 35.0
	_style_preview_rotation.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(_style_preview_model):
			_style_preview_model.rotation.y = deg_to_rad(value)
	)
	preview_panel.add_child(_style_preview_rotation)
	_style_preview_info = UIKit.make_label("Model jest automatycznie centrowany i dopasowywany do kwadratu. Przeciągnij palcem po podglądzie, aby obracać i przesuwać model; możesz też użyć suwaka.", 20, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	_style_preview_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_panel.add_child(_style_preview_info)
	_style_auto_proportion = CheckButton.new()
	_style_auto_proportion.text = "AUTOMATYCZNIE POPRAWIAJ PROPORCJE MODELI (także już pobranych)"
	_style_auto_proportion.button_pressed = StylePackManager.auto_correct_proportions
	_style_auto_proportion.toggled.connect(func(enabled: bool) -> void:
		StylePackManager.set_auto_correct_proportions(enabled)
		if not _style_installed_list.get_selected_items().is_empty():
			_on_style_installed_selected(_style_installed_list.get_selected_items()[0])
	)
	tab.add_child(_style_auto_proportion)
	_style_only_downloaded = CheckButton.new()
	_style_only_downloaded.text = "UŻYWAJ WYŁĄCZNIE POBRANYCH MODELI (bez standardowych zamienników)"
	_style_only_downloaded.button_pressed = StylePackManager.is_downloaded_only_mode()
	_style_only_downloaded.toggled.connect(func(enabled: bool) -> void:
		StylePackManager.set_downloaded_only_mode(enabled)
		if enabled:
			_style_status.text = "Tryb wyłącznie pobranych modeli włączony. Brakujące przypisania nie będą zastępowane standardowymi modelami; uzupełnij meble, przeszkody i zabrudzenia."
	)
	tab.add_child(_style_only_downloaded)
	var assign_row := HBoxContainer.new()
	tab.add_child(assign_row)
	_style_kind_option = OptionButton.new()
	_style_kind_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kind: String in FurnitureModels.KINDS:
		_style_kind_option.add_item(kind)
	assign_row.add_child(_style_kind_option)
	var assign := UIKit.make_button("PRZYPISZ DO MEBLA", 27, 82)
	assign.pressed.connect(_assign_selected_style_asset)
	assign_row.add_child(assign)
	var obstacle_row := HBoxContainer.new()
	tab.add_child(obstacle_row)
	_style_obstacle_option = OptionButton.new()
	_style_obstacle_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for obstacle_name: String in ["Puf / poduszka", "Puszka / opakowanie", "Zabawka / klocek", "But / kapeć", "Przedmiot domowy"]:
		_style_obstacle_option.add_item(obstacle_name)
	obstacle_row.add_child(_style_obstacle_option)
	var assign_obstacle := UIKit.make_button("PRZYPISZ DO PRZESZKODY", 27, 82)
	assign_obstacle.pressed.connect(_assign_selected_style_obstacle)
	obstacle_row.add_child(assign_obstacle)
	var dirt_row := HBoxContainer.new()
	tab.add_child(dirt_row)
	_style_dirt_option = OptionButton.new()
	_style_dirt_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for dirt_name: String in ["Kurz", "Okruchy", "Kłaczki", "Błoto", "Piasek", "Sierść zwierząt", "Plama / rozlany płyn"]:
		_style_dirt_option.add_item(dirt_name)
	dirt_row.add_child(_style_dirt_option)
	var assign_dirt := UIKit.make_button("PRZYPISZ DO ZABRUDZENIA", 27, 82)
	assign_dirt.pressed.connect(_assign_selected_style_dirt)
	dirt_row.add_child(assign_dirt)
	var animal_row := HBoxContainer.new()
	tab.add_child(animal_row)
	_style_animal_option = OptionButton.new()
	_style_animal_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for animal_name: String in ["Kot", "Pies", "Królik", "Agama brodata", "Papuga", "Chomik", "Świnka morska", "Żółw", "Jeż", "Fretka"]:
		_style_animal_option.add_item(animal_name)
	animal_row.add_child(_style_animal_option)
	var assign_animal := UIKit.make_button("PRZYPISZ ANIMOWANE ZWIERZĘ", 27, 82)
	assign_animal.pressed.connect(_assign_selected_style_animal)
	animal_row.add_child(assign_animal)
	var license_note := UIKit.make_label(
		"LICENCJE I PRAWA: Poly Haven publikuje swoje zasoby jako CC0 1.0 Universal, co pozwala na użycie także w projektach komercyjnych. Atrybucja samego modelu nie jest wymagana, ale korzystanie z ich API wymaga widocznego oznaczenia Powered by Poly Haven oraz unikalnego User-Agent. Dla każdego pobranego modelu zapisywany jest osobny manifest z autorem, źródłem, licencją, adresem oryginału, rozmiarem i sumą kontrolną. Pobieramy wyłącznie modele glTF/GLB z kompletem wymaganych zależności i weryfikacją rozmiaru oraz MD5.",
		22, UIKit.COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false
	)
	license_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(license_note)
	StylePackManager.catalog_updated.connect(_on_style_catalog_updated)
	StylePackManager.status_changed.connect(_on_style_pack_status)
	StylePackManager.download_progress.connect(_on_style_download_progress)
	StylePackManager.pack_changed.connect(_on_style_pack_changed)
	StylePackManager.download_confirmation_requested.connect(_on_style_download_confirmation_requested)
	_style_download_confirm = ConfirmationDialog.new()
	_style_download_confirm.title = "DUŻY PAKIET MODELU"
	_style_download_confirm.confirmed.connect(func() -> void: StylePackManager.confirm_pending_download(true))
	_style_download_confirm.get_cancel_button().pressed.connect(func() -> void: StylePackManager.confirm_pending_download(false))
	var skip_large_button := _style_download_confirm.add_button("POMIŃ", true, "skip_large")
	skip_large_button.pressed.connect(func() -> void: StylePackManager.skip_pending_download())
	add_child(_style_download_confirm)
	_style_delete_confirm = ConfirmationDialog.new()
	_style_delete_confirm.title = "POTWIERDŹ USUWANIE MODELI"
	_style_delete_confirm.confirmed.connect(_confirm_style_pack_deletion)
	add_child(_style_delete_confirm)
	_refresh_installed_style_list()
	return tab.get_parent()

func _on_style_catalog_updated(_count: int) -> void:
	_refresh_style_catalog_list()

func _on_style_pack_status(message: String) -> void:
	if is_instance_valid(_style_status): _style_status.text = message
	_refresh_installed_style_list()

func _on_style_download_progress(_asset_id: String, downloaded: int, total: int) -> void:
	if is_instance_valid(_style_progress):
		_style_progress.value = 0.0 if total <= 0 else clampf(float(downloaded) / float(total) * 100.0, 0.0, 100.0)
	if is_instance_valid(_style_status) and total > 0:
		_style_status.text = "Pobieranie: %d%% (%s / %s)" % [int(float(downloaded) / float(total) * 100.0), _format_bytes(downloaded), _format_bytes(total)]

func _on_style_pack_changed(_asset_id: String, _installed: bool) -> void:
	_refresh_installed_style_list()

func _refresh_style_catalog_list(_query: String = "") -> void:
	if _style_catalog_list == null: return
	_style_catalog_list.clear()
	for asset: Dictionary in StylePackManager.search_catalog(_style_search.text, 120):
		var label: String = "%s  •  %s" % [str(asset.get("name", asset.get("id", "?"))), str(asset.get("category", "Model 3D"))]
		_style_catalog_list.add_item(label)
		_style_catalog_list.set_item_metadata(_style_catalog_list.item_count - 1, str(asset.get("id", "")))
	_style_catalog_list.custom_minimum_size.y = maxi(380, _style_catalog_list.item_count * 54)

func _refresh_installed_style_list() -> void:
	if _style_installed_list == null: return
	_style_installed_list.clear()
	for asset: Dictionary in StylePackManager.get_installed_assets():
		var label: String = "%s  •  %s  •  %s" % [str(asset.get("name", asset.get("id", ""))), str(asset.get("resolution", "")), _format_bytes(int(asset.get("size_bytes", 0)))]
		_style_installed_list.add_item(label)
		_style_installed_list.set_item_metadata(_style_installed_list.item_count - 1, str(asset.get("id", "")))
	_style_installed_list.custom_minimum_size.y = maxi(420, _style_installed_list.item_count * 58)

func _on_style_installed_selected(index: int) -> void:
	if _style_installed_list == null or not is_instance_valid(_style_preview_root): return
	var asset_id: String = str(_style_installed_list.get_item_metadata(index))
	for child: Node in _style_preview_root.get_children():
		_style_preview_root.remove_child(child)
		child.queue_free()
	var model: Node3D = StylePackManager.get_preview_instance(asset_id)
	if model == null:
		_style_preview_name.text = "Nie udało się wczytać modelu: " + asset_id
		_style_preview_info.text = "Plik może być niekompletny albo nieobsługiwany przez importer glTF."
		return
	_style_preview_root.add_child(model)
	# Wylicz środek z AABB wszystkich siatek w globalnych transformacjach.
	# Sam pivot sceny glTF bywa przesunięty, dlatego nie wolno centrować po originie.
	var model_bounds: AABB = _get_style_model_bounds(model)
	var pivot := Node3D.new()
	pivot.name = "PodgladPivotWycentrowany"
	_style_preview_root.add_child(pivot)
	model.reparent(pivot)
	if model_bounds.has_volume():
		model.position -= model_bounds.get_center()
		var largest_axis: float = maxf(model_bounds.size.x, maxf(model_bounds.size.y, model_bounds.size.z))
		var fit_scale: float = 3.8 / maxf(largest_axis, 0.01)
		pivot.scale = Vector3.ONE * clampf(fit_scale, 0.002, 100.0)
	_style_preview_model = pivot
	_style_preview_model.rotation.y = deg_to_rad(_style_preview_rotation.value)
	var info: Dictionary = StylePackManager.get_installed_asset_info(asset_id)
	_style_preview_name.text = str(info.get("name", asset_id))
	_style_preview_info.text = "ID: %s • Autor: %s • Licencja: %s • Źródło: %s" % [asset_id, str(info.get("author", "nieznany")), str(info.get("license", "nieznana")), str(info.get("source_url", "Poly Haven"))]

func _get_style_model_bounds(model_root: Node3D) -> AABB:
	var combined: AABB = AABB()
	var found_mesh: bool = false
	var stack: Array[Node] = [model_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				# Transform3D mnoży AABB z lewej strony. Liczymy granice
				# względem korzenia modelu, aby pivot glTF i transformacje
				# rodziców nie przesuwały środka poza okno podglądu.
				var root_inverse: Transform3D = model_root.global_transform.affine_inverse()
				var mesh_to_root: Transform3D = root_inverse * mesh_instance.global_transform
				var mesh_bounds: AABB = mesh_to_root * mesh_instance.mesh.get_aabb()
				if not found_mesh:
					combined = mesh_bounds
					found_mesh = true
				else:
					combined = combined.merge(mesh_bounds)
	return combined if found_mesh else AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


func _on_style_preview_gui_input(event: InputEvent) -> void:
	if not is_instance_valid(_style_preview_model):
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_style_preview_model.position.x += drag.relative.x * 0.008
		_style_preview_model.position.y -= drag.relative.y * 0.008
		_style_preview_model.rotation.y += drag.relative.x * 0.004
		_style_preview_rotation.set_value_no_signal(wrapf(rad_to_deg(_style_preview_model.rotation.y), 0.0, 360.0))
		_style_preview_dragging = true
		accept_event()
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_style_preview_dragging = mouse_button.pressed
	elif event is InputEventMouseMotion and _style_preview_dragging:
		var motion := event as InputEventMouseMotion
		_style_preview_model.position.x += motion.relative.x * 0.008
		_style_preview_model.position.y -= motion.relative.y * 0.008
		_style_preview_model.rotation.y += motion.relative.x * 0.004
		_style_preview_rotation.set_value_no_signal(wrapf(rad_to_deg(_style_preview_model.rotation.y), 0.0, 360.0))
		accept_event()


func _selected_catalog_asset_id() -> String:
	if _style_catalog_list == null: return ""
	var selected: PackedInt32Array = _style_catalog_list.get_selected_items()
	if selected.is_empty(): return ""
	return str(_style_catalog_list.get_item_metadata(selected[0]))

func _selected_installed_asset_id() -> String:
	if _style_installed_list == null: return ""
	var selected: PackedInt32Array = _style_installed_list.get_selected_items()
	if selected.is_empty(): return ""
	return str(_style_installed_list.get_item_metadata(selected[0]))

func _download_selected_style_asset() -> void:
	var asset_id: String = _selected_catalog_asset_id()
	if asset_id.is_empty():
		_style_status.text = "Wybierz model z katalogu."
		return
	_style_progress.value = 0.0
	StylePackManager.download_asset(asset_id)

func _request_delete_selected_style_asset() -> void:
	var asset_id: String = _selected_installed_asset_id()
	if asset_id.is_empty():
		_style_status.text = "Wybierz zainstalowany model."
		return
	_style_delete_target_id = asset_id
	_style_delete_confirm.dialog_text = "Czy na pewno usunąć wybrany pobrany model?\nModel zostanie odinstalowany, a jego przypisania zostaną wyczyszczone."
	_style_delete_confirm.get_ok_button().text = "USUŃ"
	_style_delete_confirm.get_cancel_button().text = "ANULUJ"
	_style_delete_confirm.popup_centered(Vector2i(560, 240))


func _request_delete_all_style_assets() -> void:
	if StylePackManager.get_installed_assets().is_empty():
		_style_status.text = "Nie ma pobranych modeli do usunięcia."
		return
	_style_delete_target_id = "*"
	_style_delete_confirm.dialog_text = "Czy na pewno usunąć WSZYSTKIE pobrane modele?\nTa operacja nie usuwa modeli wbudowanych w grę. Wszystkie przypisania pobranych modeli zostaną wyczyszczone."
	_style_delete_confirm.get_ok_button().text = "USUŃ WSZYSTKIE"
	_style_delete_confirm.get_cancel_button().text = "ANULUJ"
	_style_delete_confirm.popup_centered(Vector2i(600, 270))


func _confirm_style_pack_deletion() -> void:
	var succeeded: bool = false
	if _style_delete_target_id == "*":
		succeeded = StylePackManager.delete_all_packs()
	else:
		succeeded = StylePackManager.delete_pack(_style_delete_target_id)
	_style_delete_target_id = ""
	if succeeded:
		for child: Node in _style_preview_root.get_children():
			child.queue_free()
		_style_preview_model = null
		_style_preview_name.text = "Wybierz pobrany model z listy"
		_style_preview_info.text = "Pobrane modele można ponownie zainstalować z katalogu online."
	_refresh_installed_style_list()

func _assign_selected_style_asset() -> void:
	var asset_id: String = _selected_installed_asset_id()
	if asset_id.is_empty():
		_style_status.text = "Najpierw wybierz zainstalowany model."
		return
	var kind: String = _style_kind_option.get_item_text(_style_kind_option.selected)
	if not StylePackManager.assign_asset_to_kind(asset_id, kind):
		_style_status.text = "Nie udało się przypisać modelu."
	else:
		_style_status.text = "Model przypisany. Nowe obiekty tej kategorii użyją pobranego glTF/GLB; kolizje pozostają bez zmian."

func _assign_selected_style_dirt() -> void:
	var asset_id: String = _selected_installed_asset_id()
	if asset_id.is_empty():
		_style_status.text = "Najpierw wybierz zainstalowany model."
		return
	if not StylePackManager.assign_dirt_asset(asset_id, _style_dirt_option.selected):
		_style_status.text = "Nie udało się przypisać modelu do zabrudzenia."
	else:
		_style_status.text = "Pobrany model przypisano do wybranego rodzaju zabrudzenia."

func _assign_selected_style_animal() -> void:
	var asset_id: String = _selected_installed_asset_id()
	if asset_id.is_empty():
		_style_status.text = "Najpierw wybierz pobrany model 3D."
		return
	var species_ids: Array[String] = ["cat", "dog", "rabbit", "bearded_dragon", "parrot", "hamster", "guinea_pig", "turtle", "hedgehog", "ferret"]
	var species: String = species_ids[_style_animal_option.selected]
	if not StylePackManager.assign_animal_asset(asset_id, species):
		_style_status.text = "Nie przypisano modelu. Zwierzę musi zawierać animację w pliku glTF/GLB."
	else:
		_style_status.text = "Animowany model przypisany. Nowe zwierzęta tego gatunku użyją pobranego modelu."


func _assign_selected_style_obstacle() -> void:
	var asset_id: String = _selected_installed_asset_id()
	if asset_id.is_empty():
		_style_status.text = "Najpierw wybierz zainstalowany model."
		return
	if not StylePackManager.assign_obstacle_asset(asset_id, _style_obstacle_option.selected):
		_style_status.text = "Nie udało się przypisać modelu do przeszkody."
	else:
		_style_status.text = "Model przypisany do wyglądu przeszkody. Jej dotychczasowa kolizja pozostaje bez zmian."

func _on_style_download_confirmation_requested(_asset_id: String, asset_name: String, package_bytes: int) -> void:
	if _style_download_confirm == null:
		StylePackManager.confirm_pending_download(false)
		return
	_style_download_confirm.dialog_text = "Model: %s\nRozmiar pakietu wraz z zależnościami: %s.\nCzy chcesz pobrać?" % [asset_name, _format_bytes(package_bytes)]
	_style_download_confirm.get_ok_button().text = "POBIERZ"
	_style_download_confirm.get_cancel_button().text = "ANULUJ PAKIET"
	_style_download_confirm.popup_centered(Vector2i(620, 290))


func _format_bytes(value: int) -> String:
	if value < 1024: return "%d B" % value
	if value < 1048576: return "%.1f KB" % (float(value) / 1024.0)
	return "%.2f MB" % (float(value) / 1048576.0)


# =========================================================
# WYBÓR PLIKU
# =========================================================

func _create_file_dialog(
	mode: FileDialog.FileMode,
	default_name: String = ""
) -> FileDialog:
	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = mode
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.rrsave", "Robot Racing - zapis postępu")
	_file_dialog.size = Vector2i(1000, 700)

	if not default_name.is_empty():
		_file_dialog.current_file = default_name

	add_child(_file_dialog)

	return _file_dialog


func _open_export_dialog() -> void:
	var dialog := _create_file_dialog(
		FileDialog.FILE_MODE_SAVE_FILE,
		"RobotRacing_progress.rrsave"
	)

	dialog.title = "Eksportuj postęp"
	dialog.file_selected.connect(_on_export_file_selected)

	dialog.popup_centered_clamped(Vector2i(1000, 700))


func _open_import_dialog() -> void:
	var dialog := _create_file_dialog(
		FileDialog.FILE_MODE_OPEN_FILE
	)

	dialog.title = "Wybierz zapis do importu"
	dialog.file_selected.connect(_on_import_file_selected)

	dialog.popup_centered_clamped(Vector2i(1000, 700))


# =========================================================
# EKSPORT
# =========================================================

func _on_export_file_selected(path: String) -> void:
	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()

	if not path.ends_with(".rrsave"):
		path += ".rrsave"

	var success: bool = SaveManager.export_progress(path)

	if success:
		_show_message(
			"Eksport zakończony",
			"Plik postępu został zapisany:\n%s" % path
		)
	else:
		_show_message(
			"Błąd eksportu",
			"Nie udało się zapisać pliku.\nSprawdź wybrane miejsce i uprawnienia."
		)


# =========================================================
# IMPORT
# =========================================================

func _on_import_file_selected(path: String) -> void:
	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()

	# Najpierw sprawdzamy plik. Nie zmieniamy jeszcze aktualnego zapisu.
	if not SaveManager.validate_progress_file(path):
		_show_message(
			"Nieprawidłowy zapis",
			"Wybrany plik jest uszkodzony, niekompletny albo ma nieobsługiwany format.\nAktualny postęp nie został zmieniony."
		)
		return

	_show_import_confirmation(path)


func _show_import_confirmation(path: String) -> void:
	if is_instance_valid(_import_confirmation):
		_import_confirmation.queue_free()

	_import_confirmation = ConfirmationDialog.new()
	_import_confirmation.title = "Potwierdź import"
	_import_confirmation.dialog_text = "Czy na pewno chcesz zastąpić obecny postęp danymi z wybranego pliku?\n\nPrzed importem zostanie utworzona kopia obecnego zapisu."

	_import_confirmation.ok_button_text = "IMPORTUJ"
	_import_confirmation.cancel_button_text = "ANULUJ"

	add_child(_import_confirmation)

	_import_confirmation.confirmed.connect(func() -> void:
		_perform_import(path)
	)

	_import_confirmation.popup_centered()


func _perform_import(path: String) -> void:
	var success: bool = SaveManager.import_progress(path)

	if not success:
		_show_message(
			"Błąd importu",
			"Nie udało się zaimportować zapisu.\nAktualny postęp powinien pozostać zachowany."
		)
		return

	# Wczytujemy zaimportowane dane do singletonu.
	# Ustawienia GameSettings nie są przeładowywane ani zmieniane.
	PlayerProgress.call("_load")

	PlayerProgress.currency_changed.emit(PlayerProgress.currency)
	PlayerProgress.progress_changed.emit()

	_reset_confirm = false

	if is_instance_valid(_reset_button):
		_reset_button.text = "RESETUJ POSTĘP"

	_show_message(
		"Import zakończony",
		"Postęp został zaimportowany.\nKopia poprzedniego zapisu została zachowana przez SaveManager."
	)


# =========================================================
# RESET POSTĘPU
# =========================================================

func _on_reset_progress() -> void:
	if not _reset_confirm:
		_reset_confirm = true
		_reset_button.text = "NA PEWNO? DOTKNIJ PONOWNIE"
		return

	PlayerProgress.reset_progress()

	_reset_confirm = false
	_reset_button.text = "POSTĘP ZRESETOWANY"

	_show_message(
		"Reset zakończony",
		"Postęp gry został przywrócony do wartości początkowych.\nUstawienia grafiki, sterowania, dźwięku i HUD pozostały zachowane."
	)


# =========================================================
# KOMUNIKATY
# =========================================================

func _show_message(title_text: String, message_text: String) -> void:
	if is_instance_valid(_message_dialog):
		_message_dialog.queue_free()

	_message_dialog = AcceptDialog.new()
	_message_dialog.title = title_text
	_message_dialog.dialog_text = message_text

	add_child(_message_dialog)
	_message_dialog.popup_centered()


# =========================================================
# ODŚWIEŻANIE
# =========================================================

func _refresh() -> void:
	if _render_scale_slider != null:
		_render_scale_slider.set_value_no_signal(GameSettings.render_scale_percent)
		_update_render_scale_label()
	for i: int in range(_control_buttons.size()):
		_control_buttons[i].set_pressed_no_signal(
			i == GameSettings.control_mode
		)

	for i: int in range(_quality_buttons.size()):
		_quality_buttons[i].set_pressed_no_signal(
			i == GameSettings.quality
		)

	for i: int in range(_fps_buttons.size()):
		_fps_buttons[i].set_pressed_no_signal(
			GameSettings.FPS_OPTIONS[i] == GameSettings.fps_limit
		)

	var states: Dictionary = {
		"shadows": GameSettings.shadows_enabled,
		"neons": GameSettings.neon_enabled,
		"headlights": GameSettings.headlights_enabled,
		"reflections": GameSettings.reflections_enabled,
		"effects": GameSettings.effects_enabled,
		"show_fps": GameSettings.show_fps,
		"dynamic_resolution": GameSettings.dynamic_resolution_enabled,
		"fx_glow": GameSettings.glow_enabled,
		"fx_ssao": GameSettings.ssao_enabled,
		"fx_ssil": GameSettings.ssil_enabled,
		"fx_ssr": GameSettings.ssr_enabled,
		"fx_sdfgi": GameSettings.sdfgi_enabled,
		"fx_volumetric_fog": GameSettings.volumetric_fog_enabled,
		"fx_depth_fog": GameSettings.depth_fog_enabled,
		"fx_taa": GameSettings.taa_enabled,
		"fx_debanding": GameSettings.debanding_enabled,
		"fx_roughness_limiter": GameSettings.roughness_limiter_enabled,
		"gyro_invert": GameSettings.gyro_invert,
		"haptics": GameSettings.haptics_enabled
	}

	for key: String in states.keys():
		if _toggles.has(key):
			var button: Button = _toggles[key]
			button.set_pressed_no_signal(bool(states[key]))
			# Przy zmianie widoku ustawień nie pozostawiamy niedostępnych przełączników aktywnych.
			if key == "fx_ssao":
				button.visible = GameSettings.supports_ssao()
			elif key in ["fx_ssil", "fx_ssr", "fx_sdfgi", "fx_volumetric_fog", "fx_taa"]:
				button.visible = GameSettings.supports_forward_plus_effects()
			elif key == "fx_debanding":
				button.visible = GameSettings.supports_debanding()
			elif key == "fx_roughness_limiter":
				button.visible = GameSettings.supports_roughness_limiter()

			var base: String = button.text.trim_suffix(": WŁ").trim_suffix(": WYŁ")

			button.text = "%s: %s" % [
				base,
				"WŁ" if bool(states[key]) else "WYŁ"
			]

	_sensitivity_label.text = "Czułość skrętu: %.2f" % GameSettings.steering_sensitivity
	_tilt_slider_label.text = "Maks. przechył: %d°" % int(GameSettings.gyro_max_tilt)

	var renderer: String = GameSettings.get_renderer()
	var notes: Array[String] = []

	notes.append(
		"Renderer: %s  |  GPU: %s (%s)  |  skala renderowania: %d%%" % [
			renderer,
			GameSettings.get_gpu_family(),
			GameSettings.get_gpu_adapter_name(),
			int(GameSettings.get_render_scale() * 100.0)
		]
	)

	notes.append(
		"NISKA: bez cieni, bez świateł neonów, tylko reflektory gracza. ŚREDNIA: cienie, światła tylko robota gracza. WYSOKA/ULTRA: światła wszystkich robotów, lampy w mieszkaniu, poświata, MSAA."
	)

	notes.append(
		"Odbicia sondą i SSR są niezależne. SSR, SSIL, SDFGI, TAA i mgła wolumetryczna wymagają Forward+. Na rendererze Mobile niedostępne są SSAO i SSR."
	)

	notes.append(
		"90 FPS i BEZ LIMITU działają tylko na ekranach o takiej częstotliwości odświeżania."
	)

	notes.append(
		"Renderer jest wybierany przy uruchomieniu kompilacji gry. Zmiana presetu jakości nie przełącza renderera; wymagałoby to osobnej konfiguracji uruchomieniowej/builda."
	)

	_graphics_note.text = "\n".join(notes)


func _process(_delta: float) -> void:
	if _tilt_label != null and _tilt_label.is_visible_in_tree():
		var raw: float = GameSettings.read_raw_tilt()

		_tilt_label.text = "Odczyt czujnika: %.2f  (neutralny: %.2f)%s" % [
			raw,
			GameSettings.gyro_neutral,
			"" if OS.has_feature("mobile") else "  - brak czujnika na PC"
		]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		GameManager.go_back()
