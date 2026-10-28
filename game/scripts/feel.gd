class_name Feel
## Feel parameters carried over from the 2D prototype (prototype/feel).
## Units: 1 unit = 20 px of the 2D prototype. Times are in seconds.

static var accel := 45.0          # 900 px/s²
static var drag := 2.6            # water resistance; higher stops faster
static var max_speed := 9.5       # 190 px/s
static var turn_rate := 9.0       # rad/s
static var dash_power := 26.0     # 520 px/s
static var dash_cooldown := 1.1
static var bite_reach := 1.6
static var growth := 1.0
static var cam_lag := 5.0
static var look_ahead := 0.35
static var hitstop := 0.06
static var shake := 1.2
static var suction := 1.0
static var chase_give_up := 4.0   # predator gives up after this long without a bite
static var retreat_time := 5.0    # then stays passive this long (sinks to the background layer)

const UNIT_PX := 20.0
const BACK_Z := -22.0             # background layer depth for retreating predators
