
SMALLISH_NUMBER     :: 0.003;
SMALL_NUMBER        :: 0.0001;
VERY_SMALL_NUMBER   :: 0.000001;
SMALLEST_OF_NUMBERS :: 0.00000003; // (not really)

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
    sin_ht, cos_ht := sin_cos(ht);
    rot_quat := Quaternion.{xyz=axis*sin_ht, w=cos_ht};
    in_out_orientation.* = rot_quat * in_out_orientation.*;
    normalize_or_identity(in_out_orientation);
    // assert(!is_nan_is_inf(in_out_orientation.x) && !is_nan_is_inf(in_out_orientation.y) && !is_nan_is_inf(in_out_orientation.z) && !is_nan_is_inf(in_out_orientation.z));
}

rotate :: inline (v: Vector3, axis: Vector3, angle: float32, $do_normalize := true) -> Vector3 {
    assert(is_normalized(axis));
    ht := angle * 0.5;
    sin_ht, cos_ht := sin_cos(ht);
    rot_quat := Quaternion.{xyz=axis*sin_ht, w=cos_ht};
    out_vec := rotate(v, rot_quat);
    if do_normalize {
        return normalize(out_vec);
    } else {
        return out_vec;
    }
}

right_direction :: inline (q: *Quaternion, $do_normalize := true) -> Vector3 {
    vec := rotate(MANGO_RIGHT, q);
    #if do_normalize {
        normalize(*vec);
    }
    return vec;
}

up_direction :: inline (q: *Quaternion, $do_normalize := true) -> Vector3 {
    vec := rotate(MANGO_UP, q);
    #if do_normalize {
        normalize(*vec);
    }
    return vec;
}

fore_direction :: inline (q: *Quaternion, $do_normalize := true) -> Vector3 {
    vec := rotate(MANGO_FORE, q);
    #if do_normalize {
        normalize(*vec);
    }
    return vec;
}

right_direction_xy :: inline (q: *Quaternion) -> Vector3 {
    right_3d := right_direction(q, false);
    right_3d.z = 0;
    return normalize(right_3d);
}

fore_direction_xy :: inline (q: *Quaternion) -> Vector3 {
    fore_3d := fore_direction(q, false);
    fore_3d.z = 0;
    return normalize(fore_3d);
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
    if rot_dist_sq <= VERY_SMALL_NUMBER {
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
    } else return interp_rotate(origin, target, rot_dist / t);
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

closest_point_on_each_line_segment_old :: (a1: *Vector3, a2: *Vector3, b1: *Vector3, b2: *Vector3, closest_point_a: *Vector3, closest_point_b: *Vector3) {
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

closest_point_on_each_line_segment :: (a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3, closest_pt_a: *Vector3, closest_pt_b: *Vector3) -> s: float, t: float {
    // from Real Time Collision Detection, by Christer Ericson
    a_diff          := a2 - a1;
    b_diff          := b2 - b1;
    b_to_a_diff     := a1 - b1;
    a_len_sq        := length_squared(a_diff);
    b_len_sq        := length_squared(b_diff);
    cos_t           := dot(b_diff, b_to_a_diff);

    // normalized distance along each segement where the respective closest points lie
    s, t: float = ---;

    MAX_ERROR :: SMALL_NUMBER;
    if a_len_sq <= MAX_ERROR {
        if b_len_sq <= MAX_ERROR {
            s, t = 0;
            closest_pt_a.* = a1;
            closest_pt_b.* = b1;
            return s, t;
        } else {
            s = 0;
            t = clamp(cos_t / b_len_sq, 0, 1);
        }
    } else {
        cos_p := dot(a_diff, b_to_a_diff);
        if b_len_sq <= MAX_ERROR {
            t = 0;
            s = clamp(-cos_p / a_len_sq, 0, 1);
        } else {
            // |a| |b| cos(q)
            scaled_cos_diffs := dot(a_diff, b_diff);
            // |a|^2 |b|^2 - (|a| |b| cos(q))^2 = (1 - cos(q)^2) |a|^2 |b|^2)
            denom := a_len_sq * b_len_sq - scaled_cos_diffs * scaled_cos_diffs; // book says always nonnegative

            if denom > MAX_ERROR {
                s = clamp((scaled_cos_diffs * cos_t - cos_p * b_len_sq) / denom, 0, 1);
            } else {
                // segments parallel
                // not from book; actually, everybody seems to get this wrong. both the book and some guy on stack overflow seem to think that picking an arbitrary value for s (like 0) here is fine, but this doesn't give a valuable answer in cases where the segments are non-overlapping along their parallel axis.
                // example: a1-------a2        b1--------b2
                // these two are parallel, but s should be 1 because a2 is closer to both b1 and b2
                // it's not pointless to make this distinction. i have found cases where it is important.
                b_to_a_dist_sq_1 := length_squared(a1 - b1);
                b_to_a_dist_sq_2 := length_squared(a2 - b2);    
                b_to_a_dist_sq_3 := length_squared(a1 - b2);    
                b_to_a_dist_sq_4 := length_squared(a2 - b1);
                min_dist_sq: float = ---;
                if b_to_a_dist_sq_1 < b_to_a_dist_sq_2 {
                    min_dist_sq = b_to_a_dist_sq_1;
                    s = 0;
                } else {
                    min_dist_sq = b_to_a_dist_sq_2;
                    s = 1;
                }
                if b_to_a_dist_sq_3 < min_dist_sq {
                    min_dist_sq = b_to_a_dist_sq_3;
                    s = 0;
                }
                if b_to_a_dist_sq_4 < min_dist_sq {
                    s = 1;
                }
            }

            t = (scaled_cos_diffs * s + cos_t) / b_len_sq;

            if t < 0 {
                t = 0;
                s = clamp(-cos_p / a_len_sq, 0, 1);
            } else if t > 1 {
                t = 1;
                s = clamp((scaled_cos_diffs - cos_p) / a_len_sq, 0, 1);
            }
        }
    }

    closest_pt_a.* = a1 + a_diff * s;
    closest_pt_b.* = b1 + b_diff * t;
    return s, t;
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

closest_point_on_line_segment_from_aabb_at_origin_if_intersection :: (segment_a: Vector3, segment_b: Vector3, box_extent: Vector3) -> Vector3, bool {
    segment_diff := segment_b - segment_a;
    t_min := 0.0;
    t_max := 1.0;

    for 0..2 {
        if abs(segment_diff.component[it]) < VERY_SMALL_NUMBER {
            // if the segment is roughly or exactly parallel to this axis, the difference is tiny or 0
            if segment_a.component[it] < -box_extent.component[it] || segment_a.component[it] > box_extent.component[it] {
                // no overlap, no intersection
                return .{}, false;
            }
        } else {
            inv_segment_dist_along_axis := 1.0 / segment_diff.component[it];
            // get the norm projections of the boxes' axis extent along the line of the segment
            t1 := (-box_extent.component[it] - segment_a.component[it]) * inv_segment_dist_along_axis;
            t2 := ( box_extent.component[it] - segment_a.component[it]) * inv_segment_dist_along_axis;

            if t1 > t2 then t1, t2 = t2, t1;

            // narrow the range where the segment could possibly be passing through the box
            t_min = max(t_min, t1);
            t_max = min(t_max, t2);

            if t_min > t_max {
                // it's a miss
                return .{}, false;
            }
        }
    }

    intersection_segment_a := segment_a + segment_diff * t_min;
    intersection_segment_b := segment_a + segment_diff * t_max;

    origin := Vector3.{};
    return closest_point_on_line_segment(*origin, *intersection_segment_a, *intersection_segment_b), true;
}

// my own super special home-cooked algorithm that might work. let's hope.
closest_point_on_line_segment_from_aabb_at_origin :: (segment_a: Vector3, segment_b: Vector3, box_extent: Vector3) -> Vector3 {
    a_clamped, b_clamped: Vector3 = ---;
    a_clamp_record, b_clamp_record: Int_Vector3 = ---;

    origin := Vector3.{};
    closest_pt_on_seg_if_intersection, success := closest_point_on_line_segment_from_aabb_at_origin_if_intersection(segment_a, segment_b, box_extent);
    if success {
        return closest_pt_on_seg_if_intersection;
    }

    a_clamped.x, a_clamp_record.x = informed_clamp(segment_a.x, -box_extent.x, box_extent.x);
    a_clamped.y, a_clamp_record.y = informed_clamp(segment_a.y, -box_extent.y, box_extent.y);
    a_clamped.z, a_clamp_record.z = informed_clamp(segment_a.z, -box_extent.z, box_extent.z);

    b_clamped.x, b_clamp_record.x = informed_clamp(segment_b.x, -box_extent.x, box_extent.x);
    b_clamped.y, b_clamp_record.y = informed_clamp(segment_b.y, -box_extent.y, box_extent.y);
    b_clamped.z, b_clamp_record.z = informed_clamp(segment_b.z, -box_extent.z, box_extent.z);   

    // if no axes were clamped, the segment would be at least partly inside the box, and it should have already returned
    assert(a_clamp_record != .{});
    assert(b_clamp_record != .{});

    return_point_closest_to_projection :: () #expand {
        a_dist_sq := distance_squared(`a_clamped, `segment_a);
        b_dist_sq := distance_squared(`b_clamped, `segment_b);
        if a_dist_sq < b_dist_sq {
            `return segment_a;
        } else if b_dist_sq < a_dist_sq {
            `return segment_b;
        } else {
            `return `segment_a + (`segment_b - `segment_a) * 0.5;
        }
    }

    if a_clamp_record == b_clamp_record {
        // clamped to same face, edge, or point. in this case, just pick the point closest to its projection
        return_point_closest_to_projection();
    }

    // pathfind to the edge or face where the closest point must be
    abs_a_clamp_record := abs(a_clamp_record);
    abs_b_clamp_record := abs(b_clamp_record);

    if abs_a_clamp_record.x == abs_b_clamp_record.x && abs_a_clamp_record.x == 1 {
        // both on pos or neg x face
        return_point_closest_to_projection();
    } else if abs_a_clamp_record.y == abs_b_clamp_record.y && abs_a_clamp_record.y == 1 {
        // both on pos or neg y face
        return_point_closest_to_projection();
    } else if abs_a_clamp_record.z == abs_b_clamp_record.z && abs_a_clamp_record.z == 1 {
        // both on pos or neg z face
        return_point_closest_to_projection();
    } 

    aabb_points: [8]Vector3 = ---;
    get_aabb_points(.{.{}, box_extent}, *aabb_points);

    a_clamped_to_a_diff := segment_a - a_clamped;
    shortest_dist_sq := FLOAT32_MAX;
    closest_point_on_segment: Vector3;

    for Box_Edges {
        edge_pt_0 := *aabb_points[it.a];
        edge_pt_1 := *aabb_points[it.b];

        edge_pt_0_diff := edge_pt_0 - a_clamped;
        edge_pt_1_diff := edge_pt_1 - a_clamped;

        cos_t := dot(a_clamped_to_a_diff, edge_pt_0_diff);
        cos_p := dot(a_clamped_to_a_diff, edge_pt_1_diff);

        // if clamped segment -> box edge is in the same direction as clamped segment -> segment
        // essentially looking for the edge where if we made an oddly shaped plane with the four points being the two segment points and the two clamped segment points, where *might* that intersect a box edge?
        if cos_t >= 0 && cos_p >= 0 {
            closest_pt_seg, closest_pt_box: Vector3 = ---;
            closest_point_on_each_line_segment(*segment_a, *segment_b, edge_pt_0, edge_pt_1, *closest_pt_seg, *closest_pt_box);
            dist_sq := distance_squared(closest_pt_seg, closest_pt_box);
            if dist_sq < shortest_dist_sq {
                dist_sq = shortest_dist_sq;
                closest_point_on_segment = closest_pt_seg;
            }
        }
    }

    // shouldn't happen I think, but I'm not an expert here
    if shortest_dist_sq == FLOAT32_MAX {
        closest_point_on_segment = segment_a + (segment_b - segment_a) * 0.5;
    }

    return closest_point_on_segment;
}

clamp :: inline (point: Vector3, extrema: Vector3) -> Vector3 {
    return .{
        clamp(point.x, -extrema.x, extrema.x),
        clamp(point.y, -extrema.y, extrema.y),
        clamp(point.z, -extrema.z, extrema.z),
    };
}

clamp :: inline (point: Vector3, min: float, max: float) -> Vector3 {
    return .{
        clamp(point.x, min, max),
        clamp(point.y, min, max),
        clamp(point.z, min, max),
    };
}

informed_clamp :: inline (x: float, min: float, max: float) -> float, s32 {
    if x < min {
        return min, -1;
    } else if x > max {
        return max, 1;
    } else {
        return x, 0;
    }
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

AABB :: struct {
    center: Vector3;
    extent: Vector3;
#place center;
    offset: Vector3;
}

Box_Point :: enum u8 {
    LOW_LOWER_LEFT;
    LOW_LOWER_RIGHT;
    LOW_UPPER_LEFT;
    LOW_UPPER_RIGHT;
    HIGH_LOWER_LEFT;
    HIGH_LOWER_RIGHT;
    HIGH_UPPER_LEFT;
    HIGH_UPPER_RIGHT;
}

Box_Edge :: struct {
    a: Box_Point;
    b: Box_Point;
}

Box_Edges :: Box_Edge.[
    .{.LOW_LOWER_LEFT, .LOW_LOWER_RIGHT},
    .{.LOW_LOWER_LEFT, .LOW_UPPER_LEFT},
    .{.LOW_UPPER_RIGHT, .LOW_LOWER_RIGHT},
    .{.LOW_UPPER_RIGHT, .LOW_UPPER_LEFT},
    .{.LOW_LOWER_LEFT, .HIGH_LOWER_LEFT},
    .{.LOW_LOWER_RIGHT, .HIGH_LOWER_RIGHT},
    .{.LOW_UPPER_LEFT, .HIGH_UPPER_LEFT},
    .{.LOW_UPPER_RIGHT, .HIGH_UPPER_RIGHT},
    .{.HIGH_LOWER_LEFT, .HIGH_LOWER_RIGHT},
    .{.HIGH_LOWER_LEFT, .HIGH_UPPER_LEFT},
    .{.HIGH_UPPER_RIGHT, .HIGH_LOWER_RIGHT},
    .{.HIGH_UPPER_RIGHT, .HIGH_UPPER_LEFT}
];

get_aabb_points :: (aabb: AABB, out_points: *[8]Vector3) {
    out_points.*[Box_Point.LOW_LOWER_LEFT]     = aabb.center - aabb.extent;
    out_points.*[Box_Point.LOW_LOWER_RIGHT]    = aabb.center + Vector3.{ aabb.extent.x, -aabb.extent.y, -aabb.extent.z}; 
    out_points.*[Box_Point.LOW_UPPER_LEFT]     = aabb.center + Vector3.{-aabb.extent.x,  aabb.extent.y, -aabb.extent.z}; 
    out_points.*[Box_Point.LOW_UPPER_RIGHT]    = aabb.center + Vector3.{ aabb.extent.x,  aabb.extent.y, -aabb.extent.z}; 
    out_points.*[Box_Point.HIGH_LOWER_LEFT]    = aabb.center + Vector3.{-aabb.extent.x, -aabb.extent.y,  aabb.extent.z};
    out_points.*[Box_Point.HIGH_LOWER_RIGHT]   = aabb.center + Vector3.{ aabb.extent.x, -aabb.extent.y,  aabb.extent.z}; 
    out_points.*[Box_Point.HIGH_UPPER_LEFT]    = aabb.center + Vector3.{-aabb.extent.x,  aabb.extent.y,  aabb.extent.z};
    out_points.*[Box_Point.HIGH_UPPER_RIGHT]   = aabb.center + aabb.extent;
} 

get_box_points :: inline (position: Vector3, length_vec: Vector3, height_vec: Vector3, width_vec: Vector3, out_points: *[8]Vector3) {
    out_points.*[Box_Point.LOW_LOWER_LEFT]     = position - length_vec - height_vec - width_vec;
    out_points.*[Box_Point.LOW_LOWER_RIGHT]    = position - length_vec - height_vec + width_vec;
    out_points.*[Box_Point.LOW_UPPER_LEFT]     = position + length_vec - height_vec - width_vec;
    out_points.*[Box_Point.LOW_UPPER_RIGHT]    = position + length_vec - height_vec + width_vec;
    out_points.*[Box_Point.HIGH_LOWER_LEFT]    = position - length_vec + height_vec - width_vec;
    out_points.*[Box_Point.HIGH_LOWER_RIGHT]   = position - length_vec + height_vec + width_vec;
    out_points.*[Box_Point.HIGH_UPPER_LEFT]    = position + length_vec + height_vec - width_vec;
    out_points.*[Box_Point.HIGH_UPPER_RIGHT]   = position + length_vec + height_vec + width_vec;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// precalculated fixed point math values for sin_cos
FIXED_SHIFT : u64 : 14; // seems to maximize precision over the whole sin_cos process
FIXED_ONE : u64 : 1 << FIXED_SHIFT;
INV_FIXED_ONE :: 1.0 / FIXED_ONE.(float);
TWO_PI_FIXED : u64 : xx (PI * 2.0 * FIXED_ONE.(float));
RECIP_TWO_PI_FIXED_32 :: (1 << 32) / TWO_PI_FIXED;