extends WorldEnvironment

onready var progress = $container/progress
onready var mesh_original = $planet/Planet.mesh

func _ready():
	
	seed(OS.get_ticks_msec())
	
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	make_planet()

func _input(event):
	
	if event.is_action_pressed("ui_accept"):
		if !progress.visible:
			make_planet()
	
func make_planet():
		
	var surf = MeshDataTool.new()
	surf.create_from_surface(mesh_original, 0)
	
	# the tree (pos, normal) pairs
	var tree_pairs = []
	
	#show the progress bar
	progress.show()
	
	var max_iterations = 145  
	for j in range(max_iterations):
		
		# wait a frame to prevent freezing the game
		yield(get_tree(), "idle_frame")
		
		# show progress in the progress bar
		progress.max_value = max_iterations
		progress.value = j
		
		var dir = Vector3(rand_range(-1,1), rand_range(-1,1), rand_range(-1,1)).normalized()
		
		# push/pull all vertices (this is the slow part)
		for i in range(surf.get_vertex_count()):
			var v = surf.get_vertex(i)
			var norm = surf.get_vertex_normal(i)
			
			var dot = norm.normalized().dot(dir)
			var sharpness = 50  # how sharp the edges are
			dot = exp(dot*sharpness) / (exp(dot*sharpness) + 1) - 0.5 # sigmoid function
			
			v += dot * norm * 0.01
			
			surf.set_vertex(i, v)
	
	var min_dist = 0.9 # deep sea
	var max_dist = 1.1 # mountains
	var vegetation_dist = 1.03 # ideal height for vegetation to grow
	var beach_dist = 1 # beach level
	
	#finally set uv.x according to distance to center, which colors the terrain depending on elevation
	
	for i in range(surf.get_vertex_count()):
		var v = surf.get_vertex(i)
		var dist = v.length() 
		var dist_normalized = range_lerp(dist, min_dist, max_dist, 0, 1) # bring dist to 0..1 range
		
		var uv = Vector2(dist_normalized, 0)
		surf.set_vertex_uv(i, uv)


	#also recalculate face normals (TODO smooth 'em!)
	
	for i in range(surf.get_face_count()):
		
		var v1i = surf.get_face_vertex(i,0)
		var v2i = surf.get_face_vertex(i,1)
		var v3i = surf.get_face_vertex(i,2)
		
		var v1 = surf.get_vertex(v1i)
		var v2 = surf.get_vertex(v2i)
		var v3 = surf.get_vertex(v3i)
		
		# calculate normal for this face
		var norm = -(v2 - v1).normalized().cross((v3 - v1).normalized()).normalized()
		
		surf.set_vertex_normal(v1i, norm)
		surf.set_vertex_normal(v2i, norm)
		surf.set_vertex_normal(v3i, norm)
	
	
	# place trees
	
	for i in range(surf.get_vertex_count()):
	
		var v = surf.get_vertex(i)
		var dist = v.length() 
		
		var norm = surf.get_vertex_normal(i)
		
		# place tree with chance depending on difference between ideal height and current vertex height
		var chance = 1 / (1 + pow(abs(dist - vegetation_dist) * 10, 2) * 10000)
		var is_underwater = dist <= beach_dist

		if not is_underwater and rand_range(0,1) < chance:
			tree_pairs.push_back([v, norm])

	# commit the mesh
	var mmesh = ArrayMesh.new() 
	surf.commit_to_surface(mmesh)
	$planet/Planet.mesh = mmesh
	
	# --------  place trees in the scene -------------
	
	# get the tree mesh from tree.dae and intialize the multimesh, used for quickly drawing lots of trees
	var tree = preload("res://tree.dae").instance()
	var tree_mesh = tree.get_node("tree").mesh
	var multimesh = $planet/trees.multimesh
	multimesh.mesh = tree_mesh
	multimesh.instance_count = tree_pairs.size()
	 
	for i in tree_pairs.size():
		
		# extract the (pos, normal) pair
		var tree_pair = tree_pairs[i]
		var pos = $planet.to_global(tree_pair[0])
		var normal = tree_pair[1]
		
		# orient the tree to the face normal and randomly rotate it along the normal
		var y = normal
		var x = normal.cross(Vector3(0,1,0)).normalized() # NOTE this will go wrong if the normal is exactly (0, 1, 0)
		var z = x.cross(y).normalized()
		var basis = Basis(x, y, z).rotated(y, rand_range(0, 2*PI))
		
		# scale the tree randomly
		basis = basis.scaled(Vector3(1,1,1) * rand_range(0.01,0.03) / 2)
		
		# set the transform of the multimesh at this index
		multimesh.set_instance_transform(i, Transform(basis, pos))
		
	# hide the progress bar
	progress.hide()


func _process(delta):
	
	# rotate cam
	$cam_root.rotate_y(delta / 3)
