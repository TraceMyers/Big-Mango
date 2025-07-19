
// todo: it's convenient to clamp positions to the bounds of the collision grid so that the game doesn't have to crash
// when things go outside the bounds (and it's convenient for aabb projection), but some handling needs to be done to make sure that doesn't happen often. otherwise,
// a situation might occur where entities that are pretty far apart are bunched up into the edge cells, overpopulating them.

boot_collision :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        overlaps.allocator = temp;
        init_collision_grid(.{}, .{2000,2000}, .{10,10});
    }
}

COLLISION_DEBUG :: true;
AABB_OVERLAP_BUFFER :: 1.0;

Capsule_Collider :: struct {
    half_height: float;
    radius: float;
}

Box_Collider :: struct {
    half_height: float;
    half_width: float;
    half_length: float;
#place half_height;
    extent: Vector3 = ---;
}

Rect_Collider :: struct {
    half_height: float;
    half_width: float;
#place half_height;
    extent: Vector2 = ---;
}

Sphere_Collider :: struct {
    radius: float;
}

AABB_Collider :: struct {
    half_height: float;
    half_width: float;
    half_length: float;
#place half_height;
    extent: Vector3 = ---;
}

Half_Space_Collider :: struct {}

Collider :: struct {
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
        sphere: Sphere_Collider = ---;
        capsule: Capsule_Collider = ---;
        rect: Rect_Collider = ---;
        box: Box_Collider = ---;
        aabb: AABB_Collider = ---;
    };
}

Packed_Collider :: struct {
    collider: Entity_Collider;
    orientation: Quaternion;
    velocity: Vector3;
    using aabb: AABB;
    using axes: Compressed_Axes;
}

// parallel arrays; keeping entity indexes separate both to avoid unnecessary padding and to avoid cache pollution during solving
Collision_Family :: struct {
    members: []Packed_Collider;
    entities: []s16;
}

pack_collider :: inline (collider: Collider, position: Vector3, orientation: Quaternion, velocity: Vector3, p: *Packed_Collider) {
    p.collider = collider;
    p.velocity = velocity;
    p.mass = linear_compress_float_16bit(mass, 0, MAX_MASS);
    p.center = position;
    set_packed_collider_orientation(p, orientation);
}

set_packed_collider_orientation :: inline (p: *Packed_Collider, new_orientation: Quaternion) {
    p.orientation = new_orientation;
    fore_axis, up_axis, right_axis: Vector3 = ---;
    get_axes(orientation, *fore_axis, *up_axis, *right_axis);
    p.extent = get_aabb_extent(collider, fore_axis, up_axis, right_axis);
    p.fore = linear_compress_norm_vector3(fore_axis);
    p.up = linear_compress_norm_vector3(up_axis);
    p.right = linear_compress_norm_vector3(right_axis);
}

get_aabb_extent :: (collider: Collider, axis_fore: Vector3, axis_up: Vector3, axis_right: Vector3) -> Vector3 {
    if #complete collider.type == {
    case .SPHERE;
        using collider.sphere;
        return .{radius, radius, radius};
    case .CAPSULE;
        using collider.capsule;
        segment_half_len := half_height - radius;
        segment_point := axis_up * segment_half_len;
        return abs(segment_point) + Vector3.{radius,radius,radius};
    case .RECT;
        using collider.rect;
        abs_point_1 := abs(axis_up * half_height + axis_right * half_width);
        abs_point_2 := abs(axis_up * half_height - axis_right * half_width);
        return max(abs_point_1, abs_point_2);
    case .BOX;
        using collider.box;
        height_vec := abs(axis_up * half_height);
        length_vec := abs(axis_fore * half_length);
        width_vec  := abs(axis_right * half_width);
        return max(height_vec, max(length_vec, width_vec));
    case .AABB;
        using collider.aabb;
        return .{half_width, half_length, half_height};
    case .HALF_SPACE;
        // you *can* have plane bounds in the case where the plane exactly aligns with an axis, but in that case
        // its bounds have area 0, which isn't useful for collision pruning.
        return .{FLOAT32_MAX, FLOAT32_MAX, FLOAT32_MAX};
    }
}

get_bounding_sphere_radius :: (collider: Collider) -> float {
    if #complete collider.type == {
    case .SPHERE;
        using collider.sphere;
        return radius;
    case .CAPSULE;
        using collider.capsule;
        return half_height; 
    case .RECT;
        using collider.rect;
        return sqrt(square(half_width) + square(half_height));
    case .BOX;
        using collider.box;
        return sqrt(square(half_width) + square(half_length) + square(half_height));
    case .AABB;
        using collider.aabb;
        return sqrt(square(half_width) + square(half_length) + square(half_height));
    case .HALF_SPACE;
        return FLOAT32_MAX;
    }
}

get_aabb :: inline (collider: Collider, position: Vector3, orientation: Quaternion, out_aabb: *AABB)  {
    axis_fore, axis_up, axis_right: Vector3 = ---;
    get_axes(orientation, *axis_fore, *axis_up, *axis_right);
    get_aabb(collider, position, axis_fore, axis_up, axis_right, out_aabb);
}

get_aabb :: inline (collider: Collider, position: Vector3, axis_fore: Vector3, axis_up: Vector3, axis_right: Vector3, out_aabb: *AABB) {
    out_aabb.center = position;
    out_aabb.extent = get_aabb_extent(collider, axis_fore, axis_up, axis_right);
}

Collision_Result :: struct {
    contact_norm_time: float;
    contact_depth: float;
    contact_point: Vector3;
    contact_normal: Vector3;
    is_contact: bool;
    do_move: bool;
}

Collision_Grid_Allocation :: union {
    inline_allocation: struct {
        array: [7]s16;
        count: s8;
        zero_if_inline: u8;
    };
    allocation_ref: Nested_Allocation_Ref = ---;
}

collision_grid: []Collision_Grid_Allocation;
collision_grid_allocator: Nesting_Allocator(8);
collision_grid_origin: Vector2;
collision_grid_dimensions: Int_Vector2;
collision_cell_dimensions: Vector2;
inv_collision_cell_dimensions: Vector2;
// todo: one per thread
overlaps: [..]u16;

packed_colliders: []Packed_Collider;

init_collision_grid :: (center: Vector2, dimensions: Int_Vector2, cell_dimensions: Vector2) {
    flt_dimensions := to_vector2(dimensions);
    half_world_dimensions := (flt_dimensions * cell_dimensions) * 0.5;
    collision_grid_origin = center - half_world_dimensions;
    collision_grid_dimensions = dimensions;
    collision_cell_dimensions = cell_dimensions;
    inv_collision_cell_dimensions = 1.0 / cell_dimensions;
    cell_count := dimensions.x * dimensions.y;
    program_runtime_allocate(*collision_grid, cell_count);

    na_chunk_list_size := 4096 * 16;
    max_data_size := ENTITY_MAX_COUNT * size_of(s16) * 8;
    program_runtime_initialize(*collision_grid_allocator, na_chunk_list_size, max_data_size);

    program_runtime_allocate(*packed_colliders, ENTITY_MAX_COUNT);
}

// world size: 2000 x 2000
// cell size: 10 x 10 
// world cell counts: 200 x 200 = 80_000

world_to_collision_grid_position :: inline (world_pos: Vector2) -> Int_Vector2 {
    diff := world_pos - collision_grid_origin;
    diff *= inv_collision_cell_dimensions;
    ivec := to_int_vector2(diff);
    return clamp(ivec, .{}, collision_grid_dimensions);
}

// uses tiling to improve cache efficiency
collision_grid_index :: inline (pos: Int_Vector2) -> s32 {
    y_part := pos.y * collision_grid_dimensions.x;
    x_part := pos.x;
    return x_part + y_part;
}

clear_collision_cell :: (grid_index: s32) {
    alloc := *collision_grid[grid_index];
    if alloc.zero_if_inline != 0 {
        assert(basic_validity_check(alloc.allocation_ref));

    }
    alloc.* = .{}
}

get_collision_cell :: inline (grid_index: s32) -> []s16 {
    alloc := *collision_grid[grid_index];
    out_array : []s16 = ---;
    if alloc.zero_if_inline == 0 {
        out_array.data = alloc.inline_allocation.array.data;
        out_array.count = alloc.inline_allocation.count;
        assert(out_array.count <= alloc_inline_allocation.array.count);
    } else {
        assert(basic_validity_check(alloc.allocation_ref));
        out_array.data = ref.data.(*s16) + 1;
        out_array.count = ref.data.(*s16).*;
        allocated_count := ref.info.inner_chunk_count * 4;
        assert(out_array.count < allocated_count);
    }
    return out_array;
}

remove_from_collision_cell :: (entity_index: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) {
    alloc := *collision_grid[grid_index];
    if alloc.zero_if_inline == 0 {
        count := *alloc.inline_allocation.count;
        #if COLLISION_DEBUG then assert(count.* <= alloc_inline_allocation.array.count);
        remove_from_collision_cell_do_remove(alloc.inline_allocation.array, entity_index);
    } else {
        #if COLLISION_DEBUG then assert(basic_validity_check(alloc.allocation_ref));
        count := alloc.allocation_ref.data.(*s16);
        array: []s16 = ---;
        array.data = alloc.allocation_ref.data.(*s16) + 1;
        array.count = count.*;
        remove_from_collision_cell_do_remove(array, entity_index);
    }
}

add_to_collision_cell :: (entity_index: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) {
    alloc := *collision_grid[grid_index];
    add_to_heap_alloc := false;
    if alloc.zero_if_inline == 0 {
        count := *alloc.inline_allocation.count;
        if count == alloc_inline_allocation.array.count {
            // the inline allocation is too small to hold this add, so grab a heap alloc, copy into it, and make sure the new value is added to the end
            new_allocation_ref := na_alloc(*collision_grid_allocator, 16 * size_of(s16));
            #if COLLISION_DEBUG then assert(basic_validity_check(new_allocation_ref));
            {
                using alloc.inline_allocation;
                memcpy(new_allocation_ref.data, array.data, array.count * size_of(s16));
            }
            alloc.allocation_ref = new_allocation_ref;
            add_to_heap_alloc = true;
        } else {
            #if COLLISION_DEBUG then assert(count.* >= 0 && count.* < alloc_inline_allocation.array.count);
            alloc.inline_allocation.array[count.*] = entity_index;
            count.* += 1;
        }
    } else add_to_heap_alloc = true;

    if add_to_heap_alloc {
        #if COLLISION_DEBUG then assert(basic_validity_check(alloc.allocation_ref));
        count := alloc.allocation_ref.data.(*s16);
        array: []s16 = ---;
        array.data = alloc.allocation_ref.data.(*s16) + 1;
        array.count = count.*;
        allocated_count := alloc.allocation_ref.info.inner_chunk_count * 4;
        used_count := array.count + 1; // include the s16 at the head, which tells us how many are allocated after it
        #if COLLISION_DEBUG then assert(used_count <= allocated_count);
        if used_count == allocated_count {
            // resize to make room + copy old into new
            new_allocation_ref := na_alloc(*collision_grid_allocator, used_count * 2 * size_of(s16));
            memcpy(new_allocation_ref.data, alloc.allocation_ref.data, used_count * size_of(s16));
            na_free(*collision_grid_allocator, *alloc.allocation_ref);
            alloc.allocation_ref = new_allocation_ref;
            count = alloc.allocation_ref.data.(*s16);
            array.data = alloc.allocation_ref.data.(*s16) + 1;
            array.count = count.*;
        }
        array.count += 1;
        array[array.count-1] = entity_index;
        count.* += 1;
    }
}

add_collider_to_grid :: (entity_index: s16, collider: Collider, position: Vector3, orientation: Quaternion, displacement: Vector3) {
    pack_collider(collider, position, orientation, *packed_colliders[entity_index]);
    entity_collision_grid_iterate(entity_index, null, add_collision_to_cell);
}

remove_from_collision_cell_do_remove :: (array: []s16, remove_index: s16) #expand {
    #if COLLISION_DEBUG {
        found_match := false;
        assert(`count.* > 0);
    }
    for 0..`count.*-1 {
        if array[it] == remove_index {
            array[it] = array[count.*-1];
            #if COLLISION_DEBUG {
                assert(!found_match);
                found_match = true;
            } else {
                break;
            }
        }
    }
    `count.* -= 1;
}

collect_overlaps :: (entity_index: s16) {
    // temp code. not sure how I want this data
    array_reset_keeping_memory(*overlaps);
    entity_collision_grid_iterate(entity_index, null, find_overlaps_in_cell);
}

find_overlaps_in_cell :: inline (entity_a: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) { 
    cell := get_collision_cell(grid_index);
    for cell {
        // to guarantee no duplicate pairs, higher indexed entities collect overlaps with lower-indexed entities (also don't overlap with self)
        if it <= entity_a then continue;
        p_b := *packed_colliders[it];
        displacement_b := p_b.velocity * delta_time;
        swept_aabb_b := sweep_aabb(p_b.aabb, displacement_b);
        if is_overlap_aabb_aabb(swept_aabb_a, swept_aabb_b) {
            array_add_if_unique(*overlaps, it);
        }
    }
}

entity_collision_grid_iterate :: (entity_index: s16, data: *void, $inner_loop_proc: (entity_a: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void)) {
    p_self := *packed_colliders[entity_index];
    self_displacement := p_self.velocity * delta_time;
    // account for velocity
    self_swept_aabb := sweep_aabb(.{p_self.aabb.center, p_self.aabb.extent + AABB_OVERLAP_BUFFER}, self_displacement);
    grid_pos_min := world_to_collision_grid_position(self_swept_aabb.center - swept_aabb.extent);
    grid_pos_max := world_to_collision_grid_position(self_swept_aabb.center + swept_aabb.extent);
    for x : grid_pos_min.x..grid_pos_max.x {
        for y : grid_pos_min.y..grid_pos_max.y {
            grid_index := collision_grid_index(.{x.(s32), y.(s32)});
            inner_loop_proc(entity_index, x, y, grid_index, self_swept_aabb, data);
        }
    }
}