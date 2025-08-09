
// todo: figure out & test rectifying the cell allocations

_collision_grid :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        init_collision_grid(.{}, .{100, 100}, .{25, 25});
    }
    return true;
}

init_collision_grid :: (center: Vector2, dimensions: Int_Vector2, cell_dimensions: Vector2) {
    flt_dimensions := to_vector2(dimensions);
    half_world_dimensions := (flt_dimensions * cell_dimensions) * 0.5;
    collision_grid_origin = center - half_world_dimensions;
    collision_grid_dimensions = dimensions;
    collision_cell_dimensions = cell_dimensions;
    inv_collision_cell_dimensions = 1.0 / cell_dimensions;
    cell_count := dimensions.x * dimensions.y;
    program_runtime_allocate(*collision_grid, cell_count);
    program_runtime_allocate(*collision_grid_cell_flags, cell_count);
    memset(collision_grid_cell_flags.data, 0, cell_count * size_of(Collision_Grid_Cell_Flags));

    na_chunk_list_size := 4096 * 16;
    max_data_size := ENTITY_MAX_COUNT * size_of(s16) * 8;
    program_runtime_initialize(*collision_grid_allocator, na_chunk_list_size, max_data_size);
}

world_to_collision_grid_position :: inline (world_pos: Vector2) -> Int_Vector2 {
    diff := world_pos - collision_grid_origin;
    diff *= inv_collision_cell_dimensions;
    ivec := to_int_vector2(diff);
    return clamp(ivec, .{}, collision_grid_dimensions-1);
}

collision_grid_index :: inline (pos: Int_Vector2) -> s32 {
    y_part := pos.y * collision_grid_dimensions.x;
    x_part := pos.x;
    return x_part + y_part;
}

collision_grid_index_to_grid_position :: inline (i: s32) -> Int_Vector2 {
    y_part := i / collision_grid_dimensions.x;
    x_part := i - y_part * collision_grid_dimensions.x;
    return .{x_part, y_part};
}

rectify_collision_cell_allocation :: (grid_index: s32) {
    alloc := *collision_grid[grid_index];
    ref := *alloc.allocation_ref;
    if alloc.inline_allocation.zero_if_inline == 0 then return;
    collision_assert(basic_validity_check(alloc.allocation_ref));
    array: []s16 = ---;
    array.data = ref.data.(*s16) + 1;
    array.count = ref.data.(*s16).*;
    allocated_count := ref.info.inner_chunk_count * 4;
    // leave room for the count value at the beginning of the array. (not <=)
    collision_assert(array.count < allocated_count);
    // if we could copy the data to the inline array and have room for n adds, then we should
    switch_back_to_inline_alloc_buffer := alloc.inline_allocation.array.count >> 1;
    if array.count <= alloc.inline_allocation.array.count - switch_back_to_inline_alloc_buffer {
        alloc_ref_copy := alloc.allocation_ref;
        memset(alloc, 0, size_of(Collision_Grid_Allocation));
        memcpy(alloc.inline_allocation.array.data, alloc_ref_copy.data.(*u16) + 1, array.count);   
        alloc.inline_allocation.count = xx array.count;
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
        collision_assert(out_array.count <= alloc.inline_allocation.array.count);
    } else {
        collision_assert(basic_validity_check(alloc.allocation_ref));
        ref := *alloc.allocation_ref;
        out_array.data = ref.data.(*s16) + 1;
        out_array.count = ref.data.(*s16).*;
        allocated_count := ref.info.inner_chunk_count * 4;
        // leave room for the count value at the beginning of the array.  (not <=)
        collision_assert(out_array.count < allocated_count);
    }
    return out_array;
}

remove_from_collision_cell :: inline (entity_index: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) {
    alloc := *collision_grid[grid_index];

    // mark this cell as altered so that its allocation can be rectified later
    if (collision_grid_cell_flags[grid_index] & .JUST_ALTERED) == 0 {
        altered_cells := data.(*[..]s32);
        array_add(altered_cells, grid_index);
        collision_grid_cell_flags[grid_index] |= .JUST_ALTERED;
    }

    if alloc.inline_allocation.zero_if_inline == 0 {
        count := *alloc.inline_allocation.count;
        collision_assert(count.* <= alloc.inline_allocation.array.count);
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

add_to_collision_cell :: inline (entity_index: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) {
    alloc := *collision_grid[grid_index];

    // mark this cell as altered so that its allocation can be rectified later
    if (collision_grid_cell_flags[grid_index] & .JUST_ALTERED) == 0 {
        altered_cells := data.(*[..]s32);
        array_add(altered_cells, grid_index);
        collision_grid_cell_flags[grid_index] |= .JUST_ALTERED;
    }

    add_to_heap_alloc := false;
    if alloc.inline_allocation.zero_if_inline == 0 {
        count := *alloc.inline_allocation.count;
        if count.* == alloc.inline_allocation.array.count {
            // the inline allocation is too small to hold this add, so grab a heap alloc, copy into it, and make sure the new value is added to the end
            new_allocation_ref := na_alloc(*collision_grid_allocator, 16 * size_of(s16));
            collision_assert(basic_validity_check(new_allocation_ref));
            {
                using alloc.inline_allocation;
                memcpy(new_allocation_ref.data.(*u16) + 1, array.data, array.count * size_of(s16));
            }
            new_allocation_ref.data.(*u16).* = xx count.*;
            alloc.allocation_ref = new_allocation_ref;
            add_to_heap_alloc = true;
        } else {
            collision_assert(count.* >= 0 && count.* < alloc.inline_allocation.array.count);
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

remove_from_collision_cell_do_remove :: inline (array: []s16, remove_index: s16) #expand {
    matched_count: s8 = 0;
    #if BUILDVAR_COLLISION_DEBUG {
        collision_assert(`count.* > 0);
    }
    for 0..`count.*-1 {
        if array[it] == remove_index {
            array[it] = array[`count.*-1];
            #if BUILDVAR_COLLISION_DEBUG {
                collision_assert(matched_count == 0);
                matched_count += 1;
            } else {
                matched_count += 1;
                break;
            }
        }
    }
    `count.* -= matched_count;
}

find_overlaps_in_cell :: (self_index: s16, x: s64, y: s64, grid_index: s32, self_swept_aabb: AABB, data: *void) { 
    find_overlaps_data := data.(*Find_Overlaps_Data);
    iteration_collision_overlaps := find_overlaps_data.collision_overlaps;

    cell := get_collision_cell(grid_index);

    for other_index : cell {
        // to guarantee no duplicate pairs, higher-indexed entities collect overlaps with lower-indexed entities (also don't overlap with self)
        // this has the added benefit of making sure the 'other' entity here has done their grid iteration first, giving it the chance to set its' 'skip' flag.
        if self_index >= other_index && !lfa_is_set(*entity_flags[other_index], .SKIPPED_GRID_ITERATE) { 
            continue;
        }
        if (entity_collision_channels[self_index] & entity_collision_channels[other_index]) == 0 {
            continue;
        }
        
        // check if we've already tried to find an overlap with the other guy
        if bit_is_set(*find_overlaps_data.already_overlapped, other_index) {
            continue;
        }
        set_bit(*find_overlaps_data.already_overlapped, other_index);

        other_body := *entity_collision_bodies[other_index];
        other_aabb := get_aabb_at(other_index);
        // other_displacement := other_body.velocity * delta_time;
        // other_swept_aabb := sweep_aabb(other_aabb, other_displacement);
        if is_overlap_aabb_aabb(self_swept_aabb, other_aabb) {
            pair: Contact_Pair = ---;
            if get_physics_properties_at(self_index).mass == IMMOVABLE_ENTITY_MASS {
                pair = .{a=xx other_index, b=self_index};
            } else {
                pair = .{a=self_index, b=xx other_index};
            }
            array_add(iteration_collision_overlaps, pair);
        }
    }
}

collision_grid_iterate :: (entity_index: s16, time_step: float, data: *void, $inner_loop_proc: (entity_a: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void)) -> grid_pos_min: Int_Vector2, grid_pos_max: Int_Vector2 {
    scope_timer();
    self_body := *entity_collision_bodies[entity_index];
    self_aabb := get_aabb_at(entity_index);

    // account for velocity
    self_displacement := self_body.velocity * time_step;
    self_swept_aabb := sweep_aabb(.{self_aabb.center, self_aabb.extent}, self_displacement);

    grid_pos_min := world_to_collision_grid_position(self_swept_aabb.center.xy - self_swept_aabb.extent.xy);
    grid_pos_max := world_to_collision_grid_position(self_swept_aabb.center.xy + self_swept_aabb.extent.xy);
    for x : grid_pos_min.x..grid_pos_max.x {
        for y : grid_pos_min.y..grid_pos_max.y {
            grid_index := collision_grid_index(.{x.(s32), y.(s32)});
            inner_loop_proc(entity_index, x, y, grid_index, self_swept_aabb, data);
        }
    }
    return grid_pos_min, grid_pos_max;
}

collision_grid_iterate :: (entity_index: s16, data: *void, grid_pos_min: Int_Vector2, grid_pos_max: Int_Vector2, swept_aabb: AABB, $inner_loop_proc: (entity_a: s16, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void)) {
    for x : grid_pos_min.x..grid_pos_max.x {
        for y : grid_pos_min.y..grid_pos_max.y {
            grid_index := collision_grid_index(.{x.(s32), y.(s32)});
            inner_loop_proc(entity_index, x, y, grid_index, swept_aabb, data);
        }
    }
}

draw_collision_grid :: (at_height: float, color: Color4f) {
    scope_timer();
    for x : 0..collision_grid_dimensions.x {
        top := collision_grid_origin + Vector2.{x.(float), 0} * collision_cell_dimensions;
        bottom := top;
        bottom.y += collision_cell_dimensions.y * collision_grid_dimensions.y.(float);
        draw_line(Vector3.{xy=top,z=at_height}, Vector3.{xy=bottom,z=at_height}, color);
    }
    for y : 0..collision_grid_dimensions.y {
        left := collision_grid_origin + Vector2.{0, y.(float)} * collision_cell_dimensions;
        right := left;
        right.x += collision_cell_dimensions.x * collision_grid_dimensions.x.(float);
        draw_line(Vector3.{xy=left,z=at_height}, Vector3.{xy=right,z=at_height}, color);
    }
}