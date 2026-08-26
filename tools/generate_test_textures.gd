## generate_test_textures.gd
##
## WHAT: Regenerates the four 64x64 test textures used by levels/test/.
##
## RUN IT:
##     godot --headless --path . --script tools/generate_test_textures.gd
##
## WHY IT EXISTS: the test room needs textures, and a template repository
##       should not carry third-party art with unclear licensing. Generating
##       them from code means the assets are reproducible, provably original,
##       and reviewable as a diff -- you can see exactly what a texture is by
##       reading forty lines instead of opening a paint program.
##
## WHY 64x64: the texture budget in the project brief. The PS1 addressed
##       textures out of a 4-bit or 8-bit paletted page; 64x64 is the size that
##       makes the resulting chunkiness read as deliberate rather than as a
##       mistake.
##
## The output is deterministic -- the RNG is seeded -- so re-running this makes
## no diff unless the code changed.

extends SceneTree

const OUT_DIR := "res://assets/textures/"
const SIZE := 64
const RNG_SEED := 19941209  # PS1 launch in Europe. Any constant would do.

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = RNG_SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_save(_checker(), "test_checker.png")
	_save(_brick(), "test_brick.png")
	_save(_grate(), "test_grate.png")
	_save(_lamp(), "test_lamp.png")

	print("Done. Re-import the project so Godot picks the textures up.")
	quit()


func _save(image: Image, file_name: String) -> void:
	var path := OUT_DIR + file_name
	var err := image.save_png(path)
	print("  %-20s %s  (%dx%d, %s)" % [
		file_name, error_string(err), image.get_width(), image.get_height(),
		"RGBA8" if image.get_format() == Image.FORMAT_RGBA8 else "RGB8"])


## Small per-pixel value jitter. Flat procedural colour reads as computer
## output; PS1 textures were hand-painted and never perfectly flat.
func _grain(color: Color, amount: float) -> Color:
	var d := _rng.randf_range(-amount, amount)
	return Color(
		clampf(color.r + d, 0.0, 1.0),
		clampf(color.g + d, 0.0, 1.0),
		clampf(color.b + d, 0.0, 1.0),
		color.a)


## THE AFFINE MAPPING TEST. A regular grid is the only pattern where a viewer
## can tell warped from correct at a glance -- any organic texture hides the
## artefact. 8px cells give 8 across the texture, which stays legible once the
## texture is tiled down a floor and crushed to 320x240.
func _checker() -> Image:
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	var light := Color(0.82, 0.78, 0.70)
	var dark := Color(0.17, 0.14, 0.19)
	for y in SIZE:
		for x in SIZE:
			var on := (int(x / 8.0) + int(y / 8.0)) % 2 == 0
			img.set_pixel(x, y, _grain(light if on else dark, 0.035))
	img.generate_mipmaps()
	return img


## Wall texture. Irregular enough to show colour quantisation banding, regular
## enough that affine warping is still visible on a wall seen edge-on.
func _brick() -> Image:
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	var mortar := Color(0.42, 0.40, 0.37)
	var course_height := 16
	var brick_width := 32
	for y in SIZE:
		var course := int(y / float(course_height))
		# Every other course is offset by half a brick, as real bonding is.
		var offset := 0 if course % 2 == 0 else brick_width / 2
		for x in SIZE:
			var in_mortar_row := (y % course_height) < 2
			var in_mortar_col := ((x + offset) % brick_width) < 2
			if in_mortar_row or in_mortar_col:
				img.set_pixel(x, y, _grain(mortar, 0.03))
			else:
				# Per-brick tint, so quantisation has distinct steps to land on.
				var brick_id := course * 8 + int((x + offset) / float(brick_width))
				var tint := 0.06 * sin(float(brick_id) * 2.399)
				img.set_pixel(x, y, _grain(Color(0.46 + tint, 0.30 + tint * 0.6, 0.25 + tint * 0.4), 0.04))
	img.generate_mipmaps()
	return img


## THE ALPHA-SCISSOR TEST. A metal grid: opaque bars, fully transparent holes,
## nothing in between. Binary alpha is what the PS1 had, and it is what
## psx_cutout.gdshader reproduces. RGB is kept sensible inside the transparent
## holes rather than left black, because nearest filtering can still sample a
## hole pixel at a bar edge.
func _grate() -> Image:
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	var bar := Color(0.55, 0.56, 0.58)
	var bar_shadow := Color(0.30, 0.31, 0.34)
	var cell := 16
	var thickness := 5
	for y in SIZE:
		for x in SIZE:
			var on_vertical := (x % cell) < thickness
			var on_horizontal := (y % cell) < thickness
			if on_vertical or on_horizontal:
				# Shade the lower/right side of each bar so it reads as round.
				var edge := (x % cell) == thickness - 1 or (y % cell) == thickness - 1
				img.set_pixel(x, y, _grain(bar_shadow if edge else bar, 0.04))
			else:
				img.set_pixel(x, y, Color(bar.r, bar.g, bar.b, 0.0))
	img.generate_mipmaps()
	return img


## Billboard sprite: a hanging lamp. Deliberately a neutral prop -- a template
## should not ship anybody's art direction. Round, so it is obvious the quad is
## turning to face the camera rather than being a flat card.
func _lamp() -> Image:
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE * 0.5, SIZE * 0.55)
	var glass_radius := 17.0
	var shell_radius := 21.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(centre)
			# The bracket the lamp hangs from.
			if x >= SIZE / 2 - 2 and x < SIZE / 2 + 2 and y < centre.y - glass_radius + 2:
				img.set_pixel(x, y, _grain(Color(0.26, 0.25, 0.24), 0.03))
			elif d < glass_radius:
				# Warm falloff from a hot core, quantised in the shader later.
				var t := d / glass_radius
				var glow := Color(1.0, 0.86, 0.55).lerp(Color(0.65, 0.36, 0.12), t * t)
				img.set_pixel(x, y, _grain(glow, 0.02))
			elif d < shell_radius:
				img.set_pixel(x, y, _grain(Color(0.24, 0.22, 0.21), 0.03))
			else:
				img.set_pixel(x, y, Color(0.24, 0.22, 0.21, 0.0))
	img.generate_mipmaps()
	return img
