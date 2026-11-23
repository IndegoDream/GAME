extends SceneTree
## Dev's effects check (r116): loads every shader, particle preset and sound in assets/own/ the way the game would.
## Each shader is put on a mesh/rect for two frames so the engine compiles it; compile errors print as SHADER ERROR
## right after that shader's "OWNFX SHADER <file>" line.
## Prints "OWNFX DONE <shaders> shaders <particles> particles <sounds> sounds, <bad> bad" and a line per problem.
## run: godot --headless --path . --script res://tools/own_fx_check.gd
func _init() -> void:
	_run()

func _run() -> void:
	var bad := 0
	var ns := 0
	var np := 0
	var na := 0
	var base := "res://assets/own/"
	for f in DirAccess.get_files_at(base + "shaders"):
		if not f.ends_with(".gdshader"):
			continue
		var sh = load(base + "shaders/" + f)
		if sh == null or not (sh is Shader) or String(sh.code).length() < 40:
			print("OWNFX BAD shader ", f)
			bad += 1
			continue
		var m := ShaderMaterial.new()
		m.shader = sh
		print("OWNFX SHADER ", f)
		if sh.get_mode() == Shader.MODE_CANVAS_ITEM:
			var cr := ColorRect.new()
			cr.material = m
			root.add_child(cr)
			await process_frame
			await process_frame
			cr.queue_free()
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = SphereMesh.new()
			mi.material_override = m
			root.add_child(mi)
			await process_frame
			await process_frame
			mi.queue_free()
		var uniforms = sh.get_shader_uniform_list()
		if uniforms.size() == 0:
			print("OWNFX BAD shader has no uniforms ", f)
			bad += 1
			continue
		ns += 1
	for f in DirAccess.get_files_at(base + "fx"):
		if not f.ends_with(".tscn"):
			continue
		var ps = load(base + "fx/" + f)
		if ps == null:
			print("OWNFX BAD scene ", f)
			bad += 1
			continue
		var n = ps.instantiate()
		if not (n is GPUParticles3D) or n.lifetime <= 0.0 or n.amount > 64 or n.process_material == null or n.draw_pass_1 == null:
			print("OWNFX BAD particles ", f)
			bad += 1
		else:
			np += 1
		n.free()
	for f in DirAccess.get_files_at(base + "sfx"):
		if not f.ends_with(".wav"):
			continue
		var fa := FileAccess.open(base + "sfx/" + f, FileAccess.READ)
		if fa == null or fa.get_length() < 1000:
			print("OWNFX BAD sound ", f)
			bad += 1
			continue
		var head := fa.get_buffer(12)
		if head.slice(0, 4).get_string_from_ascii() != "RIFF":
			print("OWNFX BAD wav header ", f)
			bad += 1
			continue
		na += 1
	print("OWNFX DONE %d shaders %d particles %d sounds, %d bad" % [ns, np, na, bad])
	quit()
