extends CharacterBody3D

const GRAVITY = 14.0

var respawn_position

const BASE_SPEED = 5.0
const MAX_SPEED = 10.0
const ACCELERATION = 1.0

const BASE_JUMP = 6.0
const JUMP_BOOST = 2.0

const BASE_WALLKICK = 6.0
const WALLKICK_HORIZONTAL = 4.0
const MAX_WALLKICKS = 2
var wallkicks = 0
var last_wall_normal

const COYOTE_TIME = 0.25
var coyote_timer = 0.0
const WALL_COYOTE_TIME = 0.25
var wall_coyote_timer = 0.0

const SENSITIVITY = 0.03

const BOB_AMPLITUDE = 0.08
const BOB_FREQUENCY = 2.0
var t_bob = 0.0

var speed = 0.0
var speed_boost = 0.0

const CROUCH_UNCROUCH_SPEED = 5.0
var height_target = 2.0
var crouching = false
var sliding = false

const LEDGEGRAB_HEIGHT = 8.0

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var footsteps = $FootstepsSFX
@onready var jumpSfx = $JumpSFX
@onready var slideSfx = $SlideSFX
@onready var ledgeSfx = $LedgegrabSFX
@onready var collider = $CollisionShape3D
@onready var uncrouch_checker = $UncrouchChecker
@onready var camera_ray = $Head/Camera3D/CameraRay
@onready var ledge_checker = $LedgeChecker

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation_degrees.x = clamp(camera.rotation_degrees.x, -80, 80)

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	footsteps.stream_paused = true
	slideSfx.stream_paused = true
	respawn_position = transform

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		wallkicks = 0
	else:
		coyote_timer -= delta
	
	if is_on_wall_only():
		wall_coyote_timer = WALL_COYOTE_TIME
		last_wall_normal = get_wall_normal()
	else:
		wall_coyote_timer -= delta
	
	# Handle jump.
	if Input.is_action_just_pressed("Jump") and (is_on_floor() or coyote_timer > 0):
		velocity.y = BASE_JUMP + (JUMP_BOOST * smoothstep(BASE_SPEED, MAX_SPEED, speed))
		coyote_timer = 0.0
		jumpSfx.play()
	
	# Handle wallkick.
	if Input.is_action_just_pressed("Jump") and (is_on_wall_only() or (wall_coyote_timer > 0 and not is_on_floor())) and wallkicks < MAX_WALLKICKS:
		velocity += last_wall_normal * WALLKICK_HORIZONTAL
		velocity.y = BASE_WALLKICK
		wall_coyote_timer = 0.0
		wallkicks += 1
		jumpSfx.play()
	
	if Input.is_action_just_pressed("Crouch"):
		height_target = 1.0
		if speed_boost > 1:
			sliding = true
		else:
			crouching = true
	
	if not Input.is_action_pressed("Crouch") and not uncrouch_checker.is_colliding():
		height_target = 2.0
		crouching = false
		sliding = false
	
	if sliding and (velocity.length() < 0.1 or speed_boost < 0.5):
		sliding = false
		crouching = true
	
	if Input.is_action_just_pressed("Respawn") or position.y < -100:
		transform = respawn_position
		velocity = Vector3.ZERO
		speed_boost = 0.0
	
	if Input.is_action_just_pressed("PrimaryFire") and camera_ray.is_colliding():
		var hit_normal = camera_ray.get_collision_normal()
		ledge_checker.global_position = camera_ray.get_collision_point() + Vector3(0.0, 0.75, 0.0) + hit_normal * -0.1
		ledge_checker.force_raycast_update()
		if ledge_checker.is_colliding():
			velocity = hit_normal * -2.0
			velocity.y = LEDGEGRAB_HEIGHT
			speed_boost = 0.0
			ledgeSfx.play()
	
	collider.shape.height = move_toward(collider.shape.height, height_target, delta * CROUCH_UNCROUCH_SPEED)
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("Left", "Right", "Forward", "Back")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	speed_boost = clamp(speed_boost, 0.0, MAX_SPEED - BASE_SPEED)
	speed = BASE_SPEED + speed_boost
	if is_on_floor():
		if sliding:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 2.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 2.0)
			speed_boost = lerp(speed_boost, 0.0, delta * ACCELERATION * 1.5)
		else:
			if direction:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
				if not crouching:
					speed_boost += delta * ACCELERATION
				else:
					speed_boost = 0.0
			else:
				velocity.x = lerp(velocity.x, direction.x * speed, delta * 10.0)
				velocity.z = lerp(velocity.z, direction.z * speed, delta * 10.0)
				speed_boost = 0.0
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 1.5)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 1.5)
	
	if is_on_wall():
		speed_boost = lerp(speed_boost, 0.0, delta * ACCELERATION * 3.0)
	
	
	t_bob += delta * velocity.length() * float(is_on_floor()) * float(!sliding)
	camera.transform.origin = Headbob(t_bob)
	
	if is_on_floor() and velocity.length() > 0.1 and not sliding:
		footsteps.stream_paused = false
		footsteps.pitch_scale = velocity.length() / 5.0
	else:
		footsteps.stream_paused = true
	
	if is_on_floor() and velocity.length() > 0.5 and sliding:
		slideSfx.stream_paused = false
		slideSfx.pitch_scale = velocity.length() / 10.0
	else:
		slideSfx.stream_paused = true
		slideSfx.seek(0.0)
	
	move_and_slide()

func Headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQUENCY) * BOB_AMPLITUDE
	pos.x = cos(time * BOB_FREQUENCY / 2) * BOB_AMPLITUDE
	return pos
