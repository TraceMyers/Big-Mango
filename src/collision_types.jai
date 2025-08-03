
Collision_Channels :: enum_flags u64 {
    DEFAULT;
}

Collision_Shape :: struct {
    type: enum u32 {
        SPHERE;
        CAPSULE;
        RECT;
        BOX;
        AABB;
        HALF_SPACE;
    };
    using data: union {
        half_height: float;
        sphere: Sphere_Shape = ---;
        capsule: Capsule_Shape = ---;
        rect: Rect_Shape = ---;
        box: Box_Shape = ---;
        aabb: AABB_Shape = ---;
    };
}

Collision_Flags :: enum_flags u32 {
    SKIPPED_GRID_ITERATE;
}

// the boundaries of this data are set around whatever is needed to calculate collisions.
// this isn't world object model situation, but I still think "Body" is fitting.
Collision_Body :: struct {
    center: Vector3;
    velocity: Vector3;
    shape: Collision_Shape;
    collision_flags: Collision_Flags = 0;
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
    fore := fore_direction(*quat);
    out_axes.fore   = linear_compress_norm_vector3(fore);
    up := up_direction(*quat);
    out_axes.up     = linear_compress_norm_vector3(up);
    right := right_direction(*quat);
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
    collision_overlaps: *[..]Pair(s16);
    already_overlapped: Bit_Array(1);
}

Contact_Result :: struct {
    a_collider: s16;
    b_collider: s16;
    a_local_space_contact_point: Vector3;
    b_local_space_contact_point: Vector3;
    contact_normal: Vector3; // toward a
    contact_depth_if_time_is_zero: float;
    norm_time: float;
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

// parallel arrays; keeping entity indexes separate both to avoid unnecessary padding and to avoid cache pollution during solving
// Collision_Family :: struct {
//     members: []Packed_Collider;
//     entities: []s16;
// }

Collision_Grid_Allocation :: union {
    inline_allocation: struct {
        array: [7]s16;
        count: s8;
        zero_if_inline: u8;
    };
    allocation_ref: Nested_Allocation_Ref = ---;
}