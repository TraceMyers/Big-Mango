
Collision_Channels :: enum_flags u64 {
    DEFAULT;
}
ALL_COLLISION_CHANNELS :: #run collect_flags(Collision_Channels);

Overlap_Channels :: enum_flags u64 {
    DEFAULT;
}
ALL_OVERLAP_CHANNELS :: #run collect_flags(Overlap_Channels);

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

Contact_Pair :: struct {
    a: Entity_Ref;
    b: Entity_Ref;
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
    bidirectional_collision: bool;
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

Collision_Grid_Item :: Entity_Ref;

Collision_Grid_Allocation :: union {
    dynamic_array: Nested_Array(Collision_Grid_Item, COLLISION_GRID_ALLOCATOR_MIN_SIZE) = ---;
    inline_allocation: struct {
        array: [5]Collision_Grid_Item;
        count: s32;
        zero_if_inline: u8;
    };
}