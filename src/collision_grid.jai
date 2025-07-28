
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

rectify_collision_cell_allocation :: (grid_index: s32) {
    alloc := *collision_grid[grid_index];
    if alloc.inline_allocation.zero_if_inline == 0 then return;
    collision_assert(basic_validity_check(alloc.allocation_ref));
    array: []s16 = ---;
    array.data = ref.data.(*s16) + 1;
    array.count = ref.data.(*s16).*;
    allocated_count := ref.info.inner_chunk_count * 4;
    // leave room for the count value at the beginning of the array. (not <=)
    collision_assert(array.count < allocated_count);
    // if we could copy the data to the inline array and have room for n adds, then we should
    switch_back_to_inline_alloc_buffer := alloc.inline_data.array.count >> 1;
    if array.count <= alloc.inline_allocation.array.count - switch_back_to_inline_alloc_buffer {
        alloc_ref_copy := alloc.allocation_ref;
        memset(alloc, 0, size_of(Collision_Grid_Allocation));
        memcpy(alloc.inline_allocation.array.data, alloc_ref_copy.data.(*u16) + 1, array.count);   
        alloc.inline_allocation.count = array.count;
        alloc.inline_allocation.zero_if_inline = 0;
        na_free(*collision_grid_allocator, *alloc_ref_copy);
    }
}

get_collision_cell :: inline (grid_index: s32) -> []s16 {
    alloc := *collision_grid[grid_index];
    out_array : []s16 = ---;
    if alloc.inline_allocation.zero_if_inline == 0 {
        out_array.data = alloc.inline_allocation.array.data;
        out_array.count = alloc.inline_allocation.count;
        collision_assert(out_array.count <= alloc_inline_allocation.array.count);
    } else {
        collision_assert(basic_validity_check(alloc.allocation_ref));
        out_array.data = ref.data.(*s16) + 1;
        out_array.count = ref.data.(*s16).*;
        allocated_count := ref.info.inner_chunk_count * 4;
        // leave room for the count value at the beginning of the array.  (not <=)
        collision_assert(out_array.count < allocated_count);
    }
    return out_array;
}

remove_from_collision_cell :: (entity_index: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) {
    alloc := *collision_grid[grid_index];
    if alloc.inline_allocation.zero_if_inline == 0 {
        count := *alloc.inline_allocation.count;
        collision_assert(count.* <= alloc_inline_allocation.array.count);
        remove_from_collision_cell_do_remove(alloc.inline_allocation.array, entity_index);
    } else {
        collision_assert(basic_validity_check(alloc.allocation_ref));
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
    if alloc.inline_allocation.zero_if_inline == 0 {
        count := *alloc.inline_allocation.count;
        if count == alloc_inline_allocation.array.count {
            // the inline allocation is too small to hold this add, so grab a heap alloc, copy into it, and make sure the new value is added to the end
            new_allocation_ref := na_alloc(*collision_grid_allocator, 16 * size_of(s16));
            collision_assert(basic_validity_check(new_allocation_ref));
            {
                using alloc.inline_allocation;
                memcpy(new_allocation_ref.data.(*u16) + 1, array.data, array.count * size_of(s16));
            }
            new_allocation_ref.data.(*u16).* = count;
            alloc.allocation_ref = new_allocation_ref;
            add_to_heap_alloc = true;
        } else {
            collision_assert(count.* >= 0 && count.* < alloc_inline_allocation.array.count);
            alloc.inline_allocation.array[count.*] = entity_index;
            count.* += 1;
        }
    } else add_to_heap_alloc = true;

    if add_to_heap_alloc {
        collision_assert(basic_validity_check(alloc.allocation_ref));
        count := alloc.allocation_ref.data.(*s16);
        array: []s16 = ---;
        array.data = alloc.allocation_ref.data.(*s16) + 1;
        array.count = count.*;
        allocated_count := alloc.allocation_ref.info.inner_chunk_count * 4;
        used_count := array.count + 1; // include the s16 at the head, which tells us how many are allocated after it
        collision_assert(used_count <= allocated_count);
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
    array_reset_keeping_memory(*context.collision_overlaps);
    entity_collision_grid_iterate(entity_index, null, find_overlaps_in_cell);
}

find_overlaps_in_cell :: inline (entity_a: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) { 
    cell := get_collision_cell(grid_index);
    for cell {
        // to guarantee no duplicate pairs, lower-indexed entities collect overlaps with higher-indexed entities (also don't overlap with self)
        if it >= entity_a then continue;
        p_b := *packed_colliders[it];
        displacement_b := p_b.velocity * delta_time;
        swept_aabb_b := sweep_aabb(p_b.aabb, displacement_b);
        if is_overlap_aabb_aabb(swept_aabb_a, swept_aabb_b) {
            array_add_if_unique(*context.collision_overlaps, it);
        }
    }
}

entity_collision_grid_iterate :: (entity_index: s16, data: *void, $inner_loop_proc: (entity_a: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void)
) {
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
