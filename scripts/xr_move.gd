#############################################
# Joystick locomotion. Left stick to move, right stick to rotate
# Now uses a CharacterBody3D so movement respects collision.
#############################################

extends Node3D
class_name XRMovement

## Kill switch. Turn it off for cutscenes, menus, whatever
@export var enabled := true

## Stick action from the action map. "primary" is the thumbstick.
@export var stick_action := "primary"

@export_group("Nodes")
## Head
@export_node_path("XRCamera3D") var camera: NodePath
## Controller that moves you (left by convention)
@export_node_path("XRController3D") var move_controller: NodePath
## Controller that rotates you (right by convention)
@export_node_path("XRController3D") var turn_controller: NodePath

@export_group("Parameters")
@export var move_speed := 2.0 ## m/s
@export_range(0.0, 0.9) var deadzone := 0.2 ## for stick drift
@export var gravity := 9.8
## Jump detection stuff
@export var jump_velocity := 4.5
@export var jump_detection_threshold := .2  ## m/s upward head speed to count as a jump

@export var turn_speed := 90.0  ## degrees per second, replaces snap_degrees

var _prev_camera_y := 0.0

var _origin: XROrigin3D = null
var _body: CharacterBody3D = null
var _camera: XRCamera3D = null
var _move_controller: XRController3D = null
var _turn_controller: XRController3D = null

func _ready() -> void:
	_origin = get_parent() as XROrigin3D
	if _origin == null:
		push_error("XRMovement|FATAL: this node must be a child of an XROrigin3D")
		set_physics_process(false)
		return

	_body = _origin.get_parent() as CharacterBody3D
	if _body == null:
		push_error("XRMovement|FATAL: XROrigin3D's parent must be a CharacterBody3D")
		set_physics_process(false)
		return

	_camera = get_node_or_null(camera) as XRCamera3D
	_move_controller = get_node_or_null(move_controller) as XRController3D
	_turn_controller = get_node_or_null(turn_controller) as XRController3D
	
	if _camera:
		_prev_camera_y = _camera.transform.origin.y

var _smoothed_vertical_speed := 0.0
@export_range(0.0, 1.0) var smoothing := 0.3  ## lower = smoother/slower to react, higher = more responsive/noisier

func _detect_physical_jump(delta: float) -> void:
	if _camera == null:
		return

	var current_y := _camera.transform.origin.y
	var raw_speed := (current_y - _prev_camera_y) / delta
	_prev_camera_y = current_y

	# Exponential moving average to smooth out jitter
	_smoothed_vertical_speed = lerp(_smoothed_vertical_speed, raw_speed, smoothing)

	#print("smoothed speed: ", _smoothed_vertical_speed, " | on floor: ", _body.is_on_floor())

	if _body.is_on_floor() and _smoothed_vertical_speed > jump_detection_threshold:
		#print("JUMP TRIGGERED")
		_body.velocity.y = jump_velocity
		
func _physics_process(delta: float) -> void:
	if not enabled:
		return

	# 2. Apply gravity
	_apply_gravity(delta)

	# 3. Apply joystick-driven horizontal velocity
	_slide(delta)

	# 4. Handle snap turning
	_smooth_turn(delta)
	
	_detect_physical_jump(delta)   # <-- physical jump detection

	# 5. Actually move, respecting collisions
	_body.move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not _body.is_on_floor():
		_body.velocity.y -= gravity * delta
	else:
		_body.velocity.y = 0.0


func _slide(delta: float) -> void:
	if _move_controller == null:
		return

	var stick := _move_controller.get_vector2(stick_action)
	if stick.length() < deadzone:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
		return

	# Get head rotation and throw away the y component.
	var basis := _camera.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0

	# Keep the direction a unit vector as well. Otherwise diagonal movement is faster, a bug
	# you've probably seen in other games
	var direction := (right.normalized() * stick.x + forward.normalized() * stick.y).limit_length(1.0)
	_body.velocity.x = direction.x * move_speed
	_body.velocity.z = direction.z * move_speed




func _smooth_turn(delta: float) -> void:
	if _turn_controller == null:
		return

	var stick := _turn_controller.get_vector2(stick_action)
	if absf(stick.x) < deadzone:
		return

	var angle := deg_to_rad(turn_speed) * delta * -stick.x

	var pivot := _camera.global_position
	pivot.y = _origin.global_position.y

	var t := _origin.global_transform
	t = t.translated(-pivot)
	t = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * t
	t = t.translated(pivot)
	_origin.global_transform = t
