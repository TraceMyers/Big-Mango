
SMALLISH_NUMBER     :: 0.003;
SMALL_NUMBER        :: 0.0001;
VERY_SMALL_NUMBER   :: 0.000001;

INV_PI          :: 1.0 / PI;
INV_2_PI        :: 1.0 / (2.0 * PI);

COS_0           :: 1.0;
COS_PI_OVER_128 :: 0.9996988;
COS_PI_OVER_64  :: 0.9987955;
COS_PI_OVER_32  :: 0.9951847;
COS_PI_OVER_28  :: 0.9937122;
COS_PI_OVER_24  :: 0.9914449;
COS_PI_OVER_20  :: 0.9876883;
COS_PI_OVER_16  :: 0.9807853;
COS_PI_OVER_12  :: 0.9659258;
COS_PI_OVER_8   :: 0.9238795;
COS_PI_OVER_7   :: 0.9009689;
COS_PI_OVER_6   :: 0.8660254;
COS_PI_OVER_5   :: 0.8090170;
COS_PI_OVER_4   :: 0.7071067;
COS_PI_OVER_3   :: 0.5;
COS_PI_OVER_2   :: 0.0;

QUATERNION_IDENTITY :: Quaternion.{0,0,0,1};
VectorTypes :: Type.[Vector2, Vector3, Vector4, Quaternion];  // Used for type restriction in normalize().
Vector2Types :: Type.[Vector2, Int_Vector2];
VectorAndFloatTypes :: Type.[Vector2, Vector3, Vector4, Quaternion, float32, float64];  // Used for type restriction in normalize().

Ray3 :: struct {
    origin: Vector3;
    direction: Vector3;
}

div_ceil :: inline (a: $Int_Type, b: Int_Type) -> Int_Type 
#modify {
    return is_int_type(Int_Type);
} {
    assert(a >= 0 && b > 0);
    return ((a - 1) / b) + 1;
}

ceil_to_multiple :: inline (a: $Int_Type, b: Int_Type) -> Int_Type
#modify {
    return is_int_type(Int_Type);
} {
    assert(a >= 0 && b > 0);
    return div_ceil(a, b) * b;
}

floor_to_multiple :: inline (a: $Int_Type, b: Int_Type) -> Int_Type
#modify {
    return is_int_type(Int_Type);
} {
    assert(a >= 0 && b > 0);
    return (a / b) * b;
}

round :: (a: float64, $Int_Type := s32) -> Int_Type 
#modify {
    return is_int_type(Int_Type);
} {
    if a < min_value(Int_Type).(float64) {
        return min_value(Int_Type);
    }
    rounded_toward_zero := a.(Int_Type);
    if a > 0 && rounded_toward_zero < 0 { // overflow on cast
        return max_value(Int_Type);
    }
    diff := a - cast(float64)rounded_toward_zero;
    if diff > 0.5 {
        return rounded_toward_zero + 1;
    } else if diff < -0.5 {
        return rounded_toward_zero - 1;
    } else {
        return rounded_toward_zero;
    }
}

// cast between int and normalized or non-normalized floats with optional rounding on float->int
alter_cast :: inline (number: $In_Type, $Out_Type: Type, $NORMALIZED_FLOAT := false, $ROUND_TO_INT := true) -> Out_Type
#modify {
    float_to_int := is_float_type(In_Type) && is_int_type(Out_Type);
    int_to_float := is_int_type(In_Type) && is_float_type(Out_Type);
    return float_to_int || int_to_float;
} {
    MIN_IN :: #run min_value(In_Type);
    MAX_IN :: #run max_value(In_Type);
    IN_DIFF :: MAX_IN - MIN_IN;
    MIN_OUT :: #run min_value(Out_Type);
    MAX_OUT :: #run max_value(Out_Type);
    OUT_DIFF :: MAX_OUT - MIN_OUT;
    IN_IS_FLOAT :: #run type_info(In_Type).type == .FLOAT;
    OUT_IS_FLOAT :: #run type_info(Out_Type).type == .FLOAT;
    FLOAT_TO_INT :: IN_IS_FLOAT && !OUT_IS_FLOAT;
    INT_TO_FLOAT :: !IN_IS_FLOAT && OUT_IS_FLOAT;

    #if NORMALIZED_FLOAT {
        #if FLOAT_TO_INT {
            #if ROUND_TO_INT {
                return round(MIN_OUT.(float64) + (MAX_OUT.(float64) - MIN_OUT.(float64)) * xx number, Out_Type);
            } else {
                return xx (MIN_OUT.(float64) + (MAX_OUT.(float64) - MIN_OUT.(float64)) * xx number);
            }
        } else #if INT_TO_FLOAT {
            return xx clamp((number.(float64) - MIN_IN.(float64)) / IN_DIFF.(float64), 0.0, 1.0);
        }
    } else {
        if number < MIN_OUT {
            return MIN_OUT;
        } else if number > MAX_OUT {
            return MAX_OUT;
        } else {
            #if FLOAT_TO_INT && ROUND_TO_INT {
                return round(number, Out_Type);
            } 
            return xx number;
        }
    }
    return xx 0;
}

respace :: (v: float, in_range: Vector2, out_range: Vector2, $do_clamp := true) -> float {
    norm_val: float = ---;
    if in_range.y > in_range.x {
        in_range_width := in_range.y - in_range.x;
        #if do_clamp {
            norm_val = (clamp(v, in_range.x, in_range.y) - in_range.x) / in_range_width;
        } else {
            norm_val = (v - in_range.x) / in_range_width;
        }
    } else {
        in_range_width := in_range.x - in_range.y;
        #if do_clamp {
            norm_val = 1.0 - (clamp(v, in_range.y, in_range.x) - in_range.y) / in_range_width;
        } else {
            norm_val = 1.0 - (v - in_range.y) / in_range_width;
        }
    }
    out_range_width := out_range.y - out_range.x;
    return out_range.x + out_range_width * norm_val;
}

is_normalized :: (v: $Vec_Type, tolerance := 0.0001) -> bool {
    return abs(length_squared(v) - 1.0) < tolerance;
}

increment_wrap :: inline (val: $T, min: T, max: T) -> T {
    val += 1;
    if val > max {
        val = min;
    }
    return val;
}

decrement_wrap :: inline (val: $T, min: T, max: T) -> T {
    val -= 1;
    if val < min {
        val = max;
    }
    return val;
}

add_wrap :: (val: $T, add_amt: T, min: T, max: T) -> T 
#modify {
    return is_int_type(T);
} {
    assert(val >= min && val <= max && max >= min);
    sum := val + add_amt;
    min_max_diff := (max - min) + 1;
    if sum > max {
        sum_max_diff := sum - (max + 1); // adding one makes the rest simpler
        remainder := sum_max_diff % min_max_diff;
        return min + remainder;
    } else if sum < min {
        min_sum_diff := (min - 1) - sum;
        remainder := min_sum_diff % min_max_diff;
        return max - remainder;
    } else {
        return sum;
    }
}

is_power_of_two :: inline (val: s64) -> bool {
    return val > 0 && (val & (val - 1)) == 0;
}

is_power_of_two :: inline (val: u64) -> bool {
    return val > 0 && (val & (val - 1)) == 0;
}

sort_range :: (in_vec: Int_Vector2) -> Int_Vector2 {
    return .{min(in_vec.x, in_vec.y), max(in_vec.x, in_vec.y)};
}

ordered_ranges_overlap :: inline (range_1: $T/Vector2Types, range_2: T) -> bool {
    return range_2.y >= range_1.x && range_2.x <= range_1.y;
}

// either inclusive min and max OR inclusive min and exclusive max. 
value_in_unordered_range :: inline (val: s32, range: Int_Vector2, $mode := enum{INCLUSIVE; EXCLUSIVE_MAX;}.INCLUSIVE) -> bool {
    #if mode == .INCLUSIVE {
        return (val >= min(range.x, range.y)) & (val <= max(range.x, range.y));
    } else { // EXCLUSIVE_MAX
        // if the range x and y are on either side of the value, one difference will be negative and the other positive, causing their xor to be negative. inspired by build engine (duke3d)
        return ((val - range.x) ^ (val - range.y)) < 0;
    }
}

make_quat :: (forward: Vector3, up: Vector3) -> Quaternion {
    right := cross(forward, up);
    assert(is_normalized(forward,   SMALL_NUMBER));
    assert(is_normalized(right,     SMALL_NUMBER));
    assert(is_normalized(up,        SMALL_NUMBER));
    rot_matrix := Matrix3.{
        right.x, forward.x, up.x,
        right.y, forward.y, up.y,
        right.z, forward.z, up.z,
    };
    return get_rotation(rot_matrix);
}

set_orientation :: (out_orientation: *Quaternion, forward: Vector3, up: Vector3) {
    out_orientation.* = make_quat(forward, up);
}

get_axes :: (orientation: Quaternion, forward: *Vector3, up: *Vector3, right: *Vector3) {
    forward.* = fore_direction(*orientation);
    up.* = up_direction(*orientation);
    right.* = normalize(cross(forward, up));
}

rotate :: (in_out_orientation: *Quaternion, axis: Vector3, angle: float32) {
    assert(is_normalized(axis));
    ht := angle * 0.5;
    sin_ht := sin(ht);
    cos_ht := cos(ht);
    rot_quat := Quaternion.{xyz=axis*sin_ht, w=cos_ht};
    in_out_orientation.* = rot_quat * in_out_orientation.*;
    assert(!is_nan_is_inf(in_out_orientation.x) && !is_nan_is_inf(in_out_orientation.y) && !is_nan_is_inf(in_out_orientation.z) && !is_nan_is_inf(in_out_orientation.z));
}

rotate :: inline (v: Vector3, axis: Vector3, angle: float32) -> Vector3 {
    assert(is_normalized(axis));
    ht := angle * 0.5;
    sin_ht := sin(ht);
    cos_ht := cos(ht);
    rot_quat := Quaternion.{xyz=axis*sin_ht, w=cos_ht};
    return normalize(rotate(v, rot_quat));
}

right_direction :: inline (q: *Quaternion) -> Vector3 {
    return rotate(MANGO_RIGHT, q);
}

right_direction_xy :: inline (q: *Quaternion) -> Vector3 {
    right_3d := right_direction(q);
    right_3d.z = 0;
    return normalize(right_3d);
}

fore_direction_xy :: inline (q: *Quaternion) -> Vector3 {
    fore_3d := fore_direction(q);
    fore_3d.z = 0;
    return normalize(fore_3d);
}

up_direction :: inline (q: *Quaternion) -> Vector3 {
    return rotate(MANGO_UP, q);
}

fore_direction :: inline (q: *Quaternion) -> Vector3 {
    return rotate(MANGO_FORE, q);
}

distance_squared :: inline (q1: Quaternion, q2: Quaternion) -> float {
    diff := Vector4.{
        q1.x - q2.x,
        q1.y - q2.y,
        q1.z - q2.z,
        q1.w - q2.w,
    };
    return length_squared(diff);
}

distance :: inline (q1: Quaternion, q2: Quaternion) -> float {
    diff := Vector4.{
        q1.x - q2.x,
        q1.y - q2.y,
        q1.z - q2.z,
        q1.w - q2.w,
    };
    return length(diff);
}

interp_rotate :: (origin: Quaternion, target: Quaternion, norm: float32) -> Quaternion {
    assert(norm >= 0.0 && norm <= 1.0);
    // small distances can be lerped without being able to tell the difference
    dp := dot(origin, target);
    use_target := ifx dp < 0 then -target else target;
    rot_dist_sq := distance_squared(origin, use_target);
    if rot_dist_sq <= 0.0001 {
        return target;
    }
    if rot_dist_sq < 0.15 {
         return lerp(origin, use_target, norm);
    } else return slerp(origin, use_target, norm);
}

interp_rotate :: (origin: Quaternion, target: Quaternion, speed: float32, delta_time: float32) -> Quaternion {
    rot_dist := speed * delta_time;
    cos_ht := abs(dot(origin, target));
    // todo: prob don't need to do acos here and in slerp
    t := 2.0 * acos(cos_ht);
    if abs(rot_dist) >= t {
        return target;
    } 
    return interp_rotate(origin, target, rot_dist / t);
}

// todo do these work???
// ------------------
smoothstep :: (a: float, b: float, x: float) -> float {
    denom_1 := (b - a) * (b - a);
    denom_2 := denom_1 * (b - a);
    numerator_1 := (x - a) * (x - a);
    numerator_2 := numerator_1 * (x - a);
    return 3.0 * (numerator_1 / denom_1) - 2.0 * (numerator_2 / denom_2);
}

smoothstep :: (a: $T/VectorTypes, b: T, x: float32) -> T {
    out_vec: T = ---;
    out_vec.x = smoothstep(a.x, b.x, x);
    out_vec.y = smoothstep(a.y, b.y, x);
    #if out_vec.component.count >= 3 {
        out_vec.z = smoothstep(a.z, b.z, x);
    }
    #if out_vec.component.count == 4 {
        out_vec.w = smoothstep(a.w, b.w, x);
    }
    return out_vec;
}
// ------------------

smoothstep :: (x: float) -> float {
    return 3.0 * x * x - 2.0 * x * x * x;
}

exponential_interp :: (a: $T/VectorAndFloatTypes, b: T, speed: float32, delta_time: float32) -> T {
    move_factor := min(speed * delta_time, 1.0);
    return a + (b - a) * move_factor;
}

closest_point_on_each_line_segment :: (a1: *Vector3, a2: *Vector3, b1: *Vector3, b2: *Vector3, closest_point_a: *Vector3, closest_point_b: *Vector3) {
    a_diff := a2.* - a1.*;
    b_diff := b2.* - b1.*;
    w := a1.* - b1.*;

    a := dot(a_diff, a_diff);         // always >= 0
    b := dot(a_diff, b_diff);
    c := dot(b_diff, b_diff);         // always >= 0
    d := dot(a_diff, w);
    e := dot(b_diff, w);
    sc, sN, sD := a*c - b*b;  // sc = sN / sD, sD >= 0
    tc, tN, tD := a*c - b*b;  // tc = tN / tD, tD >= 0

    // compute the line parameters of the two closest points
    if sD < VERY_SMALL_NUMBER {            // the lines are almost parallel
        end_diff := a2.* - b2.*;
        beg_dist_sq := length_squared(w);
        end_dist_sq := length_squared(end_diff);
        if end_dist_sq < beg_dist_sq {
            sN = 1.0;              // force using point B on segment AB
            sD = 1.0;              // to prevent possible division by 0.0 later
        } else {
            sN = 0.0;              // force using point A on segment AB
            sD = 1.0;              // to prevent possible division by 0.0 later
        }
        tN = e;
        tD = c;
    } else {                     // get the closest points on the infinite lines
        sN = (b*e - c*d);
        tN = (a*e - b*d);
        if (sN < 0.0) {        // sc < 0 => the s=0 edge is visible
            sN = 0.0;          // compute shortest connection of A to segment CD
            tN = e;
            tD = c;
        } else if (sN > sD) {    // sc > 1  => the s=1 edge is visible
            sN = sD;           // compute shortest connection of B to segment CD
            tN = e + b;
            tD = c;
        }
    }

    if (tN < 0.0) {            // tc < 0 => the t=0 edge is visible
        tN = 0.0;             
        // recompute sc for this edge
        if (-d < 0.0) {          // compute shortest connection of C to segment AB
            sN = 0.0;
        } else if (-d > a) {
            sN = sD;
        } else {
            sN = -d;
            sD = a;
        }
    }
    else if (tN > tD) {      // tc > 1  => the t=1 edge is visible
        tN = tD;
        // recompute sc for this edge
        if ((-d + b) < 0.0) {  // compute shortest connection of D to segment AB
            sN = 0;
        } else if ((-d + b) > a) {
            sN = sD;
        } else {
            sN = (-d +  b);
            sD = a;
        }
    }
    // finally do the division to get sc and tc
    sc = ifx abs(sN) < VERY_SMALL_NUMBER then 0.0 else sN / sD;
    tc = ifx abs(tN) < VERY_SMALL_NUMBER then 0.0 else tN / tD;

    closest_point_a.* = a1 + (sc * a_diff);
    closest_point_b.* = b1 + (tc * b_diff);  
}

// copied from https://stackoverflow.com/questions/66979936/closest-two-3d-point-between-two-line-segment-of-varied-magnitude-in-different-p so I'm not wasting time figuring out the 3d version
distance_between_line_segments :: (a1: *Vector3, a2: *Vector3, b1: *Vector3, b2: *Vector3, closest_point_a: *Vector3, closest_point_b: *Vector3) -> float {
    closest_point_on_each_line_segment(a1, a2, b1, b2, closest_point_a, closest_point_b);
	return distance(closest_point_a.*, closest_point_b.*);
}

distance_squared_between_line_segments :: (a1: *Vector3, a2: *Vector3, b1: *Vector3, b2: *Vector3, closest_point_a: *Vector3, closest_point_b: *Vector3) -> float {
    closest_point_on_each_line_segment(a1, a2, b1, b2, closest_point_a, closest_point_b);
	return distance_squared(closest_point_a.*, closest_point_b.*);
}

line_projection_norm_dist :: inline (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3, out_toward_end: *Vector3) -> t: float {
    out_toward_end.* = seg_end.* - seg_beg.*;
    toward_pt  := point.* - seg_beg.*;
    scaled_cos_t := dot(out_toward_end.*, toward_pt);
    segment_dist_sq := dot(out_toward_end.*, out_toward_end.*);
    return scaled_cos_t / segment_dist_sq;
}

closest_point_on_line_and_segment :: (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3, out_point_on_line: *Vector3, out_point_on_segment: *Vector3) -> norm_dist: float {
    toward_end: Vector3 = ---;
    norm_dist := line_projection_norm_dist(point, seg_beg, seg_end, *toward_end);
    out_point_on_line.* = seg_beg.* + toward_end * norm_dist;
    clamped_norm_dist := clamp(norm_dist, 0, 1);
    out_point_on_segment.* = seg_beg.* + toward_end * clamped_norm_dist;
    return norm_dist;
}

closest_point_on_line_segment :: (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3) -> Vector3, float {
    toward_end: Vector3 = ---;
    norm_dist := line_projection_norm_dist(point, seg_beg, seg_end, *toward_end);
    clamped_norm_dist := clamp(norm_dist, 0, 1);
    return seg_beg.* + toward_end * clamped_norm_dist, clamped_norm_dist;
}

closest_point_on_line :: (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3) -> Vector3, float {
    toward_end: Vector3 = ---;
    norm_dist := line_projection_norm_dist(point, seg_beg, seg_end, *toward_end);
    return seg_beg.* + toward_end * norm_dist, norm_dist;
}

closest_point_on_line :: inline (point: *Vector3, ray: *Ray3) -> Vector3, float {
    line_beg := ray.origin;
    line_end := ray.origin + ray.direction;
    point, norm_dist := closest_point_on_line(point, *line_beg, *line_end);
    return point, norm_dist;
}

distance_from_line_segment :: inline (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3) -> float {
    closest_point := closest_point_on_line_segment(point, seg_beg, seg_end);
    return distance(closest_point, point.*);
}

distance_squared_from_line_segment :: inline (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3) -> float {
    closest_point := closest_point_on_line_segment(point, seg_beg, seg_end);
    return distance_squared(closest_point, point.*);
}

distance_from_line :: inline (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3) -> float {
    closest_point := closest_point_on_line(point, seg_beg, seg_end);
    return distance(closest_point, point.*);
}

distance_squared_from_line :: inline (point: *Vector3, seg_beg: *Vector3, seg_end: *Vector3) -> float {
    closest_point := closest_point_on_line(point, seg_beg, seg_end);
    return distance_squared(closest_point, point.*);
}

distance_from_line :: inline (point: *Vector3, ray: *Ray3) -> float {
    closest_point := closest_point_on_line(point, ray);
    return distance(closest_point, point.*);
}

distance_squared_from_line :: inline (point: *Vector3, ray: *Ray3) -> float {
    closest_point := closest_point_on_line(point, ray);
    return distance_squared(closest_point, point.*);
}

// don't use this procedure if the input value is too large! makes large error.
// recommended max somewhere in 2000-5000
mod_two_pi :: inline (x: float) -> float {
    assert(x >= 0);

    // old-timey division from before cpus could divide. my brain is foggy rn but it involves the divisor being in the lower bits and using int multiplication. conveniently gives the remainder as a byproduct.

    x_fixed := (x * FIXED_ONE).(u64);
    prod := x_fixed * RECIP_TWO_PI_FIXED_32;
    quotient := prod >> 32;

    remainder_fixed := x_fixed - (quotient * TWO_PI_FIXED);
    if remainder_fixed < 0 {
        remainder_fixed += TWO_PI_FIXED;
    } else if remainder_fixed >= TWO_PI_FIXED {
        remainder_fixed -= TWO_PI_FIXED;
    }

    out_val := remainder_fixed.(float) * INV_FIXED_ONE;

    assert(out_val >= 0 && out_val < 2.0 * PI);
    return out_val;
}

// gives value and sign in [-pi/2, pi/2] for fast_sin and fast_cos
convert_to_fast_trig_range :: inline (x: float32) -> x1: float32, sin_sign: float32, cos_sign: float32 {
    pos_x, sin_sign, cos_sign : float32 = ---;
    if sign(x) == 1.0 {
        pos_x = x;
        sin_sign = 1.0;
        cos_sign = 1.0;
    } else {
        pos_x = x * -1.0;
        sin_sign = sign(x);
        cos_sign = -sin_sign;
    }

    // get value in [0, 2pi)
    x1 := mod_two_pi(pos_x);
    // map to [-pi/2, pi/2)
    if x1 > (3 * PI * 0.5) {
        x1 -= 2.0 * PI;
    } else if x1 > PI {
        x1 = (PI * 0.5 - (x1 - (3.0 * PI * 0.5)));
        sin_sign *= -1.0;
    } else if x1 > PI * 0.5 {
        x1 = PI - x1;    
        cos_sign *= -1.0;
    }

    return x1, sin_sign, cos_sign;
}

// test shows ~25-50% reduction in time (maybe depending on branch misses) from using sin and cos separately. inputs are recommended to stay within domain (-5000,5000) to keep max error below 0.035 and median error ~0.0001, due to limitations with mod_two_pi()
// todo: bring the error down
sin_cos :: inline (x: float32) -> sin_x: float32, cos_x: float32 {
    x1, sin_sign, cos_sign := convert_to_fast_trig_range(x); 
    x2 := x1 * x1;
	pos_val_sin := (((((-0.000000023889859 * x2 + 0.0000027525562) * x2 - 0.00019840874) * x2 + 0.0083333310) * x2 - 0.16666667) * x2 + 1.0) * x1;
	pos_val_cos := ((((-0.00000026051615 * x2 + 0.000024760495) * x2 - 0.0013888378) * x2 + 0.041666638) * x2 - 0.5) * x2 + 1.0;
    return pos_val_sin * sin_sign, pos_val_cos * cos_sign;
}

sign :: inline (x: float32) -> float32 {
    return ifx x < 0 then -1.0 else 1.0;
}

project_point_onto_plane :: inline (point: Vector3, point_on_plane: Vector3, plane_normal: Vector3) -> Vector3, float {
    assert(is_normalized(plane_normal, SMALLISH_NUMBER));
    diff := point - point_on_plane;
    // distance along the plane normal
    scaled_cos_t := dot_product(plane_normal, diff);
    return point - plane_normal * scaled_cos_t, scaled_cos_t;
}

reflection_component :: inline (vector: Vector3, normal: Vector3) -> float {
    return 2.0 * dot(vector, -normal);
}

reflect :: inline (vector: Vector3, normal: Vector3) -> Vector3 {
    return vector + reflection_component(vector, normal) * normal; 
}

deg2rad :: inline (deg: float) -> rad: float {
    return deg * (PI / 180.0);
}

rad2deg :: inline (rad: float) -> deg: float {
    return rad * (180.0 / PI);
}

toggle :: inline (b: *bool) {
    b.* = !b.*;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// precalculated fixed point math values for sin_cos
FIXED_SHIFT : u64 : 14; // seems to maximize precision over the whole sin_cos process
FIXED_ONE : u64 : 1 << FIXED_SHIFT;
INV_FIXED_ONE :: 1.0 / FIXED_ONE.(float);
TWO_PI_FIXED : u64 : xx (PI * 2.0 * FIXED_ONE.(float));
RECIP_TWO_PI_FIXED_32 :: (1 << 32) / TWO_PI_FIXED;