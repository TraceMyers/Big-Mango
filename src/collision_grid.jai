
COLLISION_GRID_DIMENSIONS :: Int_Vector2.{600, 600};
COLLISION_GRID_CELL_DIMENSIONS :: Vector2.{60, 60};
COLLISION_GRID_ORIGIN :: #run Vector2.{0,0} - ((to_vector2(COLLISION_GRID_DIMENSIONS) * COLLISION_GRID_CELL_DIMENSIONS) / 2);

// todo: figure out & test rectifying the cell allocations

world_to_collision_grid_position :: inline (world_pos: Vector2) -> Int_Vector2 {
    INV_COLLISION_GRID_CELL_DIMENSIONS :: #run (1 / COLLISION_GRID_CELL_DIMENSIONS);
    diff := world_pos - COLLISION_GRID_ORIGIN;
    diff *= INV_COLLISION_GRID_CELL_DIMENSIONS;
    ivec := to_int_vector2(diff);
    return clamp(ivec, .{}, COLLISION_GRID_DIMENSIONS-1);
}

collision_grid_index :: inline (pos: Int_Vector2) -> s32 {
    y_part := pos.y * COLLISION_GRID_DIMENSIONS.x;
    x_part := pos.x;
    return x_part + y_part;
}

collision_grid_index_to_grid_position :: inline (i: s32) -> Int_Vector2 {
    y_part := i / COLLISION_GRID_DIMENSIONS.x;
    x_part := i - y_part * COLLISION_GRID_DIMENSIONS.x;
    return .{x_part, y_part};
}

rectify_collision_cell_allocation :: (grid_index: s32) {
    using context.world;
    alloc := *collision_grid[grid_index];
    if alloc.inline_allocation.zero_if_inline == 0 then return;

    ref := *alloc.dynamic_array.allocation.ref;
    collision_assert(basic_validity_check(ref.*));

    dynamic_array := alloc.dynamic_array.field;
    collision_assert(dynamic_array.count <= alloc.dynamic_array.allocation.count);

    // if we could copy the data to the inline array and have room for n adds, then we should
    half_inline_count := alloc.inline_allocation.array.count >> 1;

    if dynamic_array.count <= half_inline_count {
        alloc_ref_copy := alloc.dynamic_array.allocation.ref;
        memset(alloc, 0, size_of(Collision_Grid_Allocation));
        memcpy(alloc.inline_allocation.array.data, dynamic_array.data, dynamic_array.count);   
        alloc.inline_allocation.count = xx dynamic_array.count;
        na_free(*collision_grid_allocator, *alloc_ref_copy);
        alloc.inline_allocation.zero_if_inline = 0;
    }
}

get_collision_cell :: inline (grid_index: s32) -> []Entity_Ref {
    using context.world;
    alloc := *collision_grid[grid_index];
    if alloc.inline_allocation.zero_if_inline == 0 {
        out_array : []Entity_Ref = ---;
        out_array.data = alloc.inline_allocation.array.data;
        out_array.count = alloc.inline_allocation.count;
        collision_assert(out_array.count <= alloc.inline_allocation.array.count);
        return out_array;
    } else {
        collision_assert(basic_validity_check(alloc.dynamic_array.allocation.ref));
        return alloc.dynamic_array.field;
    }
}

remove_from_collision_cell :: (entity_ref: Entity_Ref, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) {
    using context.world;
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
        remove_from_collision_cell_do_remove(alloc.inline_allocation.array, entity_ref, count);
    } else {
        count := *alloc.dynamic_array.field.count;
        collision_assert(basic_validity_check(alloc.dynamic_array.allocation.ref));
        remove_from_collision_cell_do_remove(alloc.dynamic_array.field, entity_ref, *alloc.dynamic_array.field.count);
    }
}

add_to_collision_cell :: (ref: Entity_Ref, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void) {
    using context.world;
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
            new_dynamic_array: type_of(alloc.dynamic_array);
            array_resize(*new_dynamic_array, *collision_grid_allocator, ceil_to_pow2(alloc.inline_allocation.count*2));
            new_dynamic_array.field.count = alloc.inline_allocation.count;
            collision_assert(basic_validity_check(new_dynamic_array.allocation.ref));
            memcpy(new_dynamic_array.field.data, alloc.inline_allocation.array.data, alloc.inline_allocation.count * size_of(Entity_Ref));
            alloc.dynamic_array = new_dynamic_array;
            alloc.inline_allocation.zero_if_inline = 0xff;
            add_to_heap_alloc = true;
        } else {
            collision_assert(count.* >= 0 && count.* < alloc.inline_allocation.array.count);
            alloc.inline_allocation.array[count.*] = ref;
            count.* += 1;
        }
    } else add_to_heap_alloc = true;

    if add_to_heap_alloc {
        collision_assert(basic_validity_check(alloc.dynamic_array.allocation.ref));
        array_add(*alloc.dynamic_array, *collision_grid_allocator, ref);
    }
}

remove_from_collision_cell_do_remove :: (array: []Entity_Ref, remove_ref: Entity_Ref, count: *$T) {
    matched_count: s8 = 0;
    #if BUILDVAR_COLLISION_DEBUG {
        collision_assert(count.* > 0);
    }
    for 0..count.*-1 {
        if array[it] == remove_ref {
            array[it] = array[count.*-1];
            #if BUILDVAR_COLLISION_DEBUG {
                // collision_assert(matched_count == 0);
                matched_count += 1;
            } else {
                matched_count += 1;
                break;
            }
        }
    }
    count.* -= matched_count;
    assert(count.* >= 0);
}

find_overlaps_in_cell :: (self_ref: Entity_Ref, x: s64, y: s64, grid_index: s32, self_swept_aabb: AABB, data: *void) { 
    using context.world;
    find_overlaps_data := data.(*Find_Overlaps_Data);
    iteration_collision_overlaps := find_overlaps_data.collision_overlaps;

    self := get_entity(self_ref);
    cell := get_collision_cell(grid_index);
    self_is_event_volume := is_set(*self.flags, .USES_EVENT_VOLUME);

    for other_ref : cell {
        // to guarantee no duplicate pairs, higher-indexed entities collect overlaps with lower-indexed entities (also don't overlap with self)
        // this has the added benefit of making sure the 'other' entity here has done their grid iteration first, giving it the chance to set its' 'skip' flag.
        other := get_entity(other_ref);

        if self_is_event_volume {
            if (self.overlap_channels & other.overlap_channels) == 0 {
                continue;
            }
        } else {
            if self_ref.index >= other_ref.index { 
                continue;
            }
            if (self.collision_channels & other.collision_channels) == 0 {
                continue;
            }
        }
        
        // check if we've already tried to find an overlap with the other guy
        if bit_is_set(*find_overlaps_data.already_overlapped, other_ref.index) {
            continue;
        }
        set_bit(*find_overlaps_data.already_overlapped, other_ref.index);

        other_aabb := get_aabb(other);
        if is_overlap_aabb_aabb(self_swept_aabb, other_aabb) {
            pair: Contact_Pair = ---;
            if self_is_event_volume {
                pair = .{a=self_ref,  b=other_ref};
            } else {
                if self.physics_properties.mass == IMMOVABLE_ENTITY_MASS {
                    pair = .{a=other_ref, b=self_ref};
                } else {
                    pair = .{a=self_ref,  b=other_ref};
                }
            }
            array_add(iteration_collision_overlaps, pair);
        }
    }
}

collision_grid_iterate :: (entity_ref: Entity_Ref, time_step: float, data: *void, $inner_loop_proc: (entity_a: Entity_Ref, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void)) -> grid_pos_min: Int_Vector2, grid_pos_max: Int_Vector2 {
    using context.world;
    self := get_entity(entity_ref);
    self_aabb := get_aabb(self);

    // account for velocity
    self_displacement := self.velocity * time_step;
    self_swept_aabb := sweep_aabb(.{self_aabb.center, self_aabb.extent}, self_displacement);

    grid_pos_min := world_to_collision_grid_position(self_swept_aabb.center.xy - self_swept_aabb.extent.xy);
    grid_pos_max := world_to_collision_grid_position(self_swept_aabb.center.xy + self_swept_aabb.extent.xy);
    for x : grid_pos_min.x..grid_pos_max.x {
        for y : grid_pos_min.y..grid_pos_max.y {
            grid_index := collision_grid_index(.{x.(s32), y.(s32)});
            inner_loop_proc(entity_ref, x, y, grid_index, self_swept_aabb, data);
        }
    }
    return grid_pos_min, grid_pos_max;
}

collision_grid_iterate :: (entity_ref: Entity_Ref, data: *void, grid_pos_min: Int_Vector2, grid_pos_max: Int_Vector2, swept_aabb: AABB, $inner_loop_proc: (entity_a: Entity_Ref, x: s64, y: s64, grid_index: s32, swept_aabb_a: AABB, data: *void)) {
    using context.world;
    for x : grid_pos_min.x..grid_pos_max.x {
        for y : grid_pos_min.y..grid_pos_max.y {
            grid_index := collision_grid_index(.{x.(s32), y.(s32)});
            inner_loop_proc(entity_ref, x, y, grid_index, swept_aabb, data);
        }
    }
}

draw_collision_grid :: (at_height: float, color: Color4f) {
    using context.world;
    scope_timer();
    for x : 0..COLLISION_GRID_DIMENSIONS.x {
        top := COLLISION_GRID_ORIGIN + Vector2.{x.(float), 0} * COLLISION_GRID_CELL_DIMENSIONS;
        bottom := top;
        bottom.y += COLLISION_GRID_CELL_DIMENSIONS.y * COLLISION_GRID_DIMENSIONS.y.(float);
        draw_line(Vector3.{xy=top,z=at_height}, Vector3.{xy=bottom,z=at_height}, color, layer=1);
    }
    for y : 0..COLLISION_GRID_DIMENSIONS.y {
        left := COLLISION_GRID_ORIGIN + Vector2.{0, y.(float)} * COLLISION_GRID_CELL_DIMENSIONS;
        right := left;
        right.x += COLLISION_GRID_CELL_DIMENSIONS.x * COLLISION_GRID_DIMENSIONS.x.(float);
        draw_line(Vector3.{xy=left,z=at_height}, Vector3.{xy=right,z=at_height}, color, layer=1);
    }
}