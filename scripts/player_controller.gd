extends CharacterBody3D

#Plan:
#Ability to grab static objects
#Diggable terrain
#Fix hand rotating objects

#Render Arms?

#I'm seriously considering multiplayer

enum GRAB_MODE{ONLY_DROP, ONLY_GRAB, GRAB_OR_DROP}

var mirror_mode: bool = false
var hand_swap_y_z: bool = false
var left_handed: bool = false

@onready var arms: Array = [$Camera3D/LeftArm, $Camera3D/RightArm]
var hands: Array = []

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	arms[0].set_meta("MirrorInMirrorMode", not left_handed)
	arms[1].set_meta("MirrorInMirrorMode", left_handed)
	$"../CanvasLayer/VersionLabel".text = "Version " + FileAccess.open("res://build/version.txt", FileAccess.READ).get_as_text()
	var hand_index: int = 0
	for arm in arms:
		move_hand.call_deferred(arm, hand_index)
		arm.get_node("ReturnTimer").connect("timeout", _on_return_timer_timeout.bind(arm))
		arm.set_meta("hand_index", hand_index)
		hand_index += 1

var is_ready: bool = false

func move_hand(arm, hand_index):
	var hand = arm.get_node("Hand")
	hands.append(hand)
	hand.name = "hand" + str(hand_index)
	arm.remove_child(hand)
	get_parent().add_child(hand)
	hand.set_owner(get_parent())
	hand.global_position = arm.get_node("HandDestination").global_position
	
	is_ready = true

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

const SPRINT_MULTIPLIER = 3

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED * (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1)
		velocity.z = direction.z * SPEED * (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1))
		velocity.z = move_toward(velocity.z, 0, SPEED * (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1))
	
	if is_ready:
		update_hands()
	move_and_slide()
	
	if Input.is_action_just_pressed("reload"):
		for arm in arms:
			hands[arm.get_meta("hand_index")].get_node("MeshInstance3D").material_override.albedo_color = Color.WHITE
		get_tree().reload_current_scene()
	
	if Input.is_action_just_pressed("toggle_ui"):
		$"../CanvasLayer".visible = not $"../CanvasLayer".visible
	
	$"../SpeedometerCanvas/Label".text = str(int(velocity.length())) + " speed"

func update_hands():
	if Input.is_action_just_pressed("toggle_mirror_mode"):
		mirror_mode = not mirror_mode
		$"../SpeedometerCanvas/MirrorLine".visible = mirror_mode
	
	if Input.is_action_just_pressed("toggle_hand_y_z_swap"):
		hand_swap_y_z = not hand_swap_y_z
		for arm in arms:
			hands[arm.get_meta("hand_index")].get_node("MeshInstance3D").material_override.albedo_color = Color.DARK_BLUE if hand_swap_y_z else Color.WHITE
	
	if Input.is_action_just_released("drop"):
		for arm in arms:
			if Input.is_action_pressed(arm.get_meta("MainAction")) or mirror_mode or not using_any_hands():
				toggle_grab(hands[arm.get_meta("hand_index")], GRAB_MODE.ONLY_DROP)
	
	for arm in arms:
		var hand: Node3D = hands[arm.get_meta("hand_index")]
		var destination: Vector3 = arm.get_node("HandDestination").global_position
		hand.velocity = hand.position.direction_to(destination) * hand.position.distance_to(destination) * 60
		if not is_empty_hand(hand):
			var held_object_location: Vector3 = get_node(hand.get_node("Generic6DOFJoint3D").node_b).position + hand.get_meta("grab_offset")
			#hand.velocity += hand.position.direction_to(held_object_location) * hand.position.distance_to(held_object_location) * 60
		if hand.position != arm.global_position and abs(hand.position.direction_to(arm.global_position).y) != 1:
			hand.look_at(arm.global_position)
		hand.move_and_slide()
		
		velocity -= hand.position.direction_to(destination) * hand.position.distance_to(destination) * 0.5
		
		var timer: Timer = arm.get_node("ReturnTimer")
		if Input.is_action_pressed(arm.get_meta("MainAction")) or not is_empty_hand(hands[arm.get_meta("hand_index")]) or (mirror_mode and using_any_hands()):
			timer.stop()
			arm.set_meta("ReturningHome", false)
		elif timer.is_stopped():
			timer.start()
		
		if arm.get_meta("ReturningHome"):
			arm.get_node("HandDestination").position.z = lerp(arm.get_node("HandDestination").position.z, -1.5, 0.05)
			arm.rotation = lerp(arm.rotation, Vector3.ZERO, 0.05)

func _on_return_timer_timeout(arm: Node3D) -> void:
	arm.set_meta("ReturningHome", true)

func _input(event):
	if event is InputEventMouseButton:
		if event.double_click:
			if event.button_index == MOUSE_BUTTON_LEFT:
				toggle_grab(hands[arms[0].get_meta("hand_index")])
			if event.button_index == MOUSE_BUTTON_RIGHT:
				toggle_grab(hands[arms[1].get_meta("hand_index")])
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			for arm in arms:
				if Input.is_action_pressed(arm.get_meta("MainAction")) or (mirror_mode and using_any_hands()) or not using_any_hands():
					move_arm_hand_unit(arm, Vector3(0.0, 0.0, 0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1))
	if event is InputEventMouseMotion:
		var camera_drag_amount: Vector2 = Vector2.ZERO
		for arm in arms:
			if Input.is_action_pressed(arm.get_meta("MainAction")) or (mirror_mode and using_any_hands()):
				camera_drag_amount += move_arm_hand_unit(arm, Vector3(event.relative.x * -0.0015, event.relative.y * 0.0015, 0.0))
		
		if using_any_hands():
			rotation.y += camera_drag_amount.y * 0.6
			$Camera3D.rotation.x += camera_drag_amount.x * 0.4
		else:
			rotation.y += event.relative.x * -0.005
			$Camera3D.rotation.x += event.relative.y * -0.0015
		$Camera3D.rotation.x = clamp($Camera3D.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

func move_arm_hand_unit(arm: Node3D, movement: Vector3):
	arm.get_node("ReturnTimer").stop()
	arm.set_meta("ReturningHome", false)
	if hand_swap_y_z:
		arm.get_node("HandDestination").position.z += movement.y
		arm.rotation.x += movement.z
	else:
		arm.get_node("HandDestination").position.z -= movement.z
		arm.rotation.x -= movement.y
	var camera_drag_amount: Vector2 = Vector2.ZERO
	arm.rotation.y += movement.x * (-1 if mirror_mode and arm.get_meta("MirrorInMirrorMode") else 1)
	
	var range_limit = 65
	
	camera_drag_amount.x = arm.rotation.x - clamp(arm.rotation.x, deg_to_rad(-range_limit), deg_to_rad(range_limit))
	camera_drag_amount.y = arm.rotation.y - clamp(arm.rotation.y, deg_to_rad(-range_limit), deg_to_rad(range_limit))
	arm.rotation.x = clamp(arm.rotation.x, deg_to_rad(-range_limit), deg_to_rad(range_limit))
	arm.rotation.y = clamp(arm.rotation.y, deg_to_rad(-range_limit), deg_to_rad(range_limit))
	arm.get_node("HandDestination").position.z = clamp(arm.get_node("HandDestination").position.z, -2, 0)
	return camera_drag_amount

func using_any_hands() -> bool:
	for arm in arms:
		if Input.is_action_pressed(arm.get_meta("MainAction")):
			return true
	return false

func is_empty_hand(hand) -> bool:
	return hand.get_node("Generic6DOFJoint3D").node_b.is_empty()

func toggle_grab(hand: Node3D, grab_mode: GRAB_MODE = GRAB_MODE.GRAB_OR_DROP):
	if grab_mode == GRAB_MODE.ONLY_DROP or (grab_mode == GRAB_MODE.GRAB_OR_DROP and not is_empty_hand(hand)):
		if not is_empty_hand(hand) and get_node(hand.get_node("Generic6DOFJoint3D").node_b) is RigidBody3D:
			get_node(hand.get_node("Generic6DOFJoint3D").node_b).gravity_scale = 1
		hand.get_node("Generic6DOFJoint3D").node_b = ""
		return
	
	for body in hand.get_node("Area3D").get_overlapping_bodies():
		if not body.is_in_group("player") and not body.is_in_group("hand"):
			hand.get_node("Generic6DOFJoint3D").node_b = body.get_path()
			hand.set_meta("grab_offset", hand.global_position - body.global_position)
			if body is RigidBody3D:
				body.gravity_scale = 0
				body.linear_velocity = Vector3.ZERO
				body.angular_velocity = Vector3.ZERO
