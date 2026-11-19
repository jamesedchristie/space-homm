extends TestCase
## Ship models: every species flies a design for every ship unit, warships
## have their own species designs, and squadrons shrink with the hull.

const WARSHIPS := ["interceptor", "frigate", "destroyer", "cruiser"]

var _data: DataRegistry


func before_each() -> void:
	_data = Fixtures.registry()


func _ship_units() -> Array[String]:
	var out: Array[String] = []
	for id: String in _data.units:
		var tags: Array = _data.units[id].get("tags", [])
		if "ship" in tags or "station" in tags:
			out.append(id)
	return out


func test_every_species_resolves_a_model_for_every_ship_unit() -> void:
	var styles: Array[String] = [""]
	for sp: String in _data.species:
		styles.append(sp)
	assert_true(_ship_units().size() >= 9, "ship and station units found")
	for style in styles:
		for variant: String in ["", "raider"]:
			for id in _ship_units():
				var model := Unit3D.model_id_for(_data, _data.units[id], style, variant)
				assert_true(_data.models.has(model), "%s/%s/%s -> known model '%s'" % [style, variant, id, model])


func test_species_have_their_own_warships() -> void:
	for sp: String in ["veltari", "kesh", "sorn"]:
		for cls: String in WARSHIPS:
			var model := Unit3D.model_id_for(_data, _data.units[cls], sp)
			assert_eq(model, "%s_%s" % [_data.units[cls]["visual"]["model"], sp], "%s flies its own %s" % [sp, cls])
	# Humans fly the shared (Terran) designs; raiders their salvaged ones.
	assert_eq(Unit3D.model_id_for(_data, _data.units["frigate"], "human"), "frigate")
	assert_eq(Unit3D.model_id_for(_data, _data.units["frigate"], "kesh", "raider"), "frigate_raider")
	assert_eq(Unit3D.model_id_for(_data, _data.units["cruiser"], "kesh", "raider"), "cruiser_kesh", "no raider cruiser: species design")


func test_species_models_build() -> void:
	for sp: String in ["", "veltari", "kesh", "sorn"]:
		for cls: String in WARSHIPS:
			var id := Unit3D.model_id_for(_data, _data.units[cls], sp)
			var model := ModelFactory.build(_data, id, Color.RED, sp)
			var box := ModelFactory.bounds(model)
			assert_true(box.size.x > 0.5, "%s has a body (%s)" % [id, box])
			model.free()


func test_squadron_sizes() -> void:
	assert_eq(Squadron.size_of(_data.units["interceptor"]), 5)
	assert_eq(Squadron.size_of(_data.units["frigate"]), 3)
	assert_eq(Squadron.size_of(_data.units["destroyer"]), 2)
	assert_eq(Squadron.size_of(_data.units["cruiser"]), 1, "capital ships fly alone")
	assert_eq(Squadron.size_of(_data.units["defense_platform"]), 1)
	for n in range(1, 7):
		assert_eq(Squadron.slots(n).size(), n)
		assert_eq(Squadron.lags(n).size(), n)


func test_squadron_count_follows_hull() -> void:
	assert_eq(Squadron.craft_count(5, 60, 60), 5)
	assert_eq(Squadron.craft_count(5, 49, 60), 5, "ceil: a scratched craft still flies")
	assert_eq(Squadron.craft_count(5, 36, 60), 3)
	assert_eq(Squadron.craft_count(5, 1, 60), 1, "at least one while alive")
	assert_eq(Squadron.craft_count(5, 0, 60), 0)
	assert_eq(Squadron.craft_count(3, 40, 120), 1)
	assert_eq(Squadron.craft_count(3, 41, 120), 2)
	assert_eq(Squadron.craft_count(2, 190, 190), 2)
	assert_eq(Squadron.craft_count(1, 5, 280), 1)
	var last := 99
	for hull in range(120, 0, -1):
		var count := Squadron.craft_count(3, hull, 120)
		assert_true(count <= last, "never grows as the hull falls")
		last = count
