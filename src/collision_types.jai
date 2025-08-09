
Collision_Channels :: enum_flags u64 {
    DEFAULT;
}

Collision_Shape_Type :: enum u32 {
    NONE;
    SPHERE;
    CAPSULE;
    RECT;
    BOX;
    AABB;
    HALF_SPACE;
}

Collision_Shape :: struct {
    type: Collision_Shape_Type = .NONE;
    using data: union {
        half_height: float;
        sphere: Sphere_Shape = ---;
        capsule: Capsule_Shape = ---;
        rect: Rect_Shape = ---;
        box: Box_Shape = ---;
        aabb: AABB_Shape = ---;
    };
}

TRANSIENT_COLLISION_FLAGS :: Entity_Flags.[.COLLIDING_WITH_SOMETHING, .CHANGED_CELL_OCCUPATIONS, .SKIPPED_GRID_ITERATE];

// the boundaries of this data are set around whatever is needed to calculate collisions.
// this isn't world object model situation, but I still think "Body" is fitting.
Collision_Body :: struct {
    center: Vector3;
    previous_center: Vector3;
    velocity: Vector3;
    shape: Collision_Shape;
    orientation: Quaternion = QUATERNION_IDENTITY;
    angular_velocity: Vector3;
    inv_mass: float;
}

Contact_Pair :: struct {
    a: s16;
    b: s16;
    contact_normal: Vector3;
    contact_tangent: Vector3;
    normal_impulse_sum: float;
    last_tangent_impulse: float;
}

feed_contact_impulse :: inline (pair: *Contact_Pair, normal_magnitude: float, tangent_magnitude: float) -> normal: float, tangent: float {
    old_normal_sum := pair.normal_impulse_sum;
    new_normal_sum := old_normal_sum + normal_magnitude;
    pair.normal_impulse_sum = max(0.0, new_normal_sum);
    out_normal_magnitude := pair.normal_impulse_sum - old_normal_sum;

    FRICTION :: 0.4;
    max_friction := FRICTION * abs(pair.normal_impulse_sum);
    out_tangent_magnitude := clamp(tangent_magnitude, -max_friction, max_friction);
    pair.last_tangent_impulse = out_tangent_magnitude;

    return out_normal_magnitude, out_tangent_magnitude;
}

Compressed_Axes :: struct {
    fore: u64;
    up: u64;
    right: u64;
}

Axes :: struct {
    fore: Vector3;
    up: Vector3;
    right: Vector3;
}

compress_axes :: (quat: Quaternion, out_axes: *Compressed_Axes) {
    fore    := fore_direction(*quat);
    out_axes.fore   = linear_compress_norm_vector3(fore);
    up      := up_direction(*quat);
    out_axes.up     = linear_compress_norm_vector3(up);
    right   := right_direction(*quat);
    out_axes.right  = linear_compress_norm_vector3(right);
}

decompress_axes :: (compressed: *Compressed_Axes, fore: *Vector3, up: *Vector3, right: *Vector3) {
    fore.*  = linear_decompress_norm_vector3(compressed.fore);
    up.*    = linear_decompress_norm_vector3(compressed.up);
    right.* = linear_decompress_norm_vector3(compressed.right);
}

decompress_axes :: inline (compressed: *Compressed_Axes, decompressed: *Axes) {
    decompress_axes(compressed, *decompressed.fore, *decompressed.up, *decompressed.right);
}

Find_Overlaps_Data :: struct {
    collision_overlaps: *[..]Contact_Pair;
    already_overlapped: Bit_Array(1);
}

Contact_Result :: struct {
    point: Vector3;
    normal: Vector3; // toward a
    depth: float;
    // contact_depth_if_time_is_zero: float;
    // norm_time: float;
}

Capsule_Shape :: struct {
    half_height: float;
    radius: float;
}

Box_Shape :: struct {
    half_height: float;
    half_width: float;
    half_length: float;
#place half_height;
    extent: Vector3 = ---;
}

Rect_Shape :: struct {
    half_height: float;
    half_width: float;
#place half_height;
    extent: Vector2 = ---;
}

Sphere_Shape :: struct {
    radius: float;
}

AABB_Shape :: struct {
    half_height: float;
    half_width: float;
    half_length: float;
#place half_height;
    extent: Vector3 = ---;
}

Collision_Grid_Cell_Flags :: enum_flags u8 {
    JUST_ALTERED;
}

Collision_Grid_Allocation :: union {
    inline_allocation: struct {
        array: [7]s16;
        count: s8;
        zero_if_inline: u8; // overlaps with nesting allocation bit pattern & bin. if the allocation_ref has been set, this byte should be nonzero
    };
    allocation_ref: Nested_Allocation_Ref = ---;
}