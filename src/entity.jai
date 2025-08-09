
// NOTE: no need for a patch layer on data that is parallel to entities. setting indexes on the patch infos would
// be the same exact process, just on a second layer for no reason. well, except for references to entities...
// but, maybe that could be sorted out with the id? not sure of the cost there.

INVALID_ENTITY_ID : u32 : 0;
INVALID_ENTITY_INDEX : u32 : U32_MAX;
INVALID_CAMERA_INDEX : u8  : U8_MAX;
// Entity_Physics_Properties :: Physics_Properties_Dynamic;

ENTITY_MAX_COUNT :: 20_000;
CAMERA_MAX_COUNT :: 64;
ENTITY_MESHES_MAX_COUNT :: 8;
ENTITY_NAME_MAX_CHAR_COUNT :: 64;
LINEAR_IMPULSES_MAX_COUNT :: 128;

_entities :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        program_runtime_reserve(*entity_patch_infos, ENTITY_MAX_COUNT);
        program_runtime_reserve(*entity_deletion_queue, ENTITY_MAX_COUNT);

        program_runtime_allocate(*entity_patch_layer,                   ENTITY_MAX_COUNT);
        program_runtime_allocate(*entities_patched,                     ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_collision_bodies,              ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_movements,                     ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_compressed_axes,               ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_mesh_collections,              ENTITY_MAX_COUNT);
        program_runtime_allocate(*name_allocations,                     ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_trigger_volume_allocations,    ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_collision_channels,            ENTITY_MAX_COUNT);
        program_runtime_allocate(*collision_cell_hashes,                ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_datas,                         ENTITY_MAX_COUNT);
        program_runtime_allocate(*inv_inertia_tensors,                  ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_flags,                         ENTITY_MAX_COUNT);
        program_runtime_allocate(*linear_impulse_allocations,           ENTITY_MAX_COUNT);

        program_runtime_initialize(*cameras, CAMERA_MAX_COUNT);
        program_runtime_initialize(*dynamic_entity_physics_properties, ENTITY_MAX_COUNT);

        na_chunk_list_size := 4096 * 16;
        na_chunk_list_size_large := 4096 * 32;

        mesh_ptrs_array_data_size := ENTITY_MAX_COUNT * ENTITY_MESHES_MAX_COUNT * size_of(Entity_Mesh);
        program_runtime_initialize(*entity_mesh_array_allocator, na_chunk_list_size, mesh_ptrs_array_data_size);
        entity_name_data_size := ENTITY_MAX_COUNT * ENTITY_NAME_MAX_CHAR_COUNT;
        program_runtime_initialize(*entity_name_allocator, na_chunk_list_size, entity_name_data_size);
        entity_trigger_volumes_data_size := ENTITY_MAX_COUNT * size_of(Trigger_Volume);
        program_runtime_initialize(*entity_trigger_volumes_allocator, na_chunk_list_size_large, entity_trigger_volumes_data_size);
        linear_impulse_array_data_size := ENTITY_MAX_COUNT * size_of(Linear_Physics_Impulse) * 2;
        program_runtime_initialize(*linear_impulse_allocator, na_chunk_list_size_large, linear_impulse_array_data_size);

        entity_id_counter = 1;

        return true;
    } else {
        return true;
    }
}

get_entity :: inline (ref: Entity_Ref) -> *Entity {
    i := entity_patch_layer[ref.index];
    assert(entity_patch_infos[i].id == ref.id);
    return get_entity_at(i);
}

get_entity_if_valid :: inline (ref: Entity_Ref) -> *Entity {
    if !is_null(ref) {
        i := entity_patch_layer[ref.index];
        if entity_patch_infos[i].id == ref.id {
            return get_entity(ref);
        }
    }
    return null;
}

is_null :: inline (ref: Entity_Ref) -> bool {
    return ref.id == 0;
}

// when using this procedure outside this file, it's important to observe the lifetime of an index w.r.t entities. to access entities in a way that is always safe, store and get with an Entity_Ref.
get_entity_at :: (i: s64) -> *Entity {
    e := *entities_patched[i];
    if e.generation != game_frame_count {
        patch_info := *entity_patch_infos[i];

        e.* = .{
            type = patch_info.type,
            patch = patch_info.patch,
            ref = patch_info.ref,
            body = *entity_collision_bodies[i],
            movement = *entity_movements[i],
            compressed_axes = *entity_compressed_axes[i],
            meshes = get_entity_meshes(patch_info),
            flags = *entity_flags[i],
            collision_channels = *entity_collision_channels[i],
            name = get_entity_name(patch_info),
            data = *entity_datas[i]
        };

        if (patch_info.patch_flags & .CAMERA) != 0 {
            assert(patch_info.camera != INVALID_CAMERA_INDEX);
            e.camera = *cameras.items[patch_info.camera];
        } else {
            assert(patch_info.camera == INVALID_CAMERA_INDEX);
        }

        if lfa_is_set(e.flags, .DYNAMIC_PHYSICS_PROPERTIES) {
            e.physics_properties = *dynamic_entity_physics_properties[patch_info.physics_properties];
        } else {
            e.physics_properties = *PHYSICS_PROPERTIES_TEMPLATES[patch_info.physics_properties];
        }

        e.generation = game_frame_count;
    }
    return e;
}

entity_ref :: inline (i: s64) -> Entity_Ref {
    return entity_patch_infos[i].ref;
}

spawn_entity :: (in_type: Entity_Type, name := "", location := Vector3.{}, orientation := QUATERNION_IDENTITY, physics_properties_template := Physics_Properties_Template.CAPSULE_MAN, make_physics_properties_dynamic := false) -> *Entity {
    // scope_lock_mutex(*spawn_entity_mutex);

    t: Entity_Patch_Type;
    if in_type == {
    case .STATIC_ENVIRONMENT; 
        t = .STATIC_MESH;
    case .DYNAMIC_ENVIRONMENT;
        t = .STATIC_MESH;
    case .CAMERA;
        t = .CAMERA;
    case .PERSON;
        t = .STATIC_MESH;
    }

    i := entity_patch_infos.count.(u16);
    e := array_add(*entity_patch_infos);
    assert(i >= 0 && i < ENTITY_MAX_COUNT);

    entity_patch_layer[i] = i;
    entity_movements[i] = .{};
    entity_collision_bodies[i] = .{center=location, orientation=orientation};
    compress_axes(*orientation, *entity_compressed_axes[i]);
    collision_cell_hashes[i] = -1;
    entity_datas[i] = .{};

    mesh_collection := *entity_mesh_collections[i];
    assert(mesh_collection.count == 0 && mesh_collection.allocation_ref.data == null);

    assert(entity_id_counter < U32_MAX);
    new_id := entity_id_counter;
    entity_id_counter += 1;

    e.* = .{
        type = in_type,
        patch_type = t,
        ref = .{xx i, xx new_id},
    };

    lfa_set(*entity_flags[i], .JUST_SPAWNED);

    if make_physics_properties_dynamic {
        phys_props_index := request_item(*dynamic_entity_physics_properties);   
        assert(phys_props_index < ENTITY_MAX_COUNT);
        phys_props := *dynamic_entity_physics_properties[phys_props_index];
        phys_props.template = physics_properties_template;
        phys_props.base = PHYSICS_PROPERTIES_TEMPLATES[physics_properties_template];
        lfa_set(*entity_flags[i], .DYNAMIC_PHYSICS_PROPERTIES);
        e.physics_properties = xx phys_props_index;
    } else {
        e.physics_properties = xx physics_properties_template;
    }

    phys_props := get_entity_physics_properties(e.ref);
    entity_collision_channels[i] = phys_props.default_collision_channels;

    if (e.patch_flags & .CAMERA) != 0 {
        index := request_item(*cameras);
        assert(index >= 0 && index < CAMERA_MAX_COUNT);
        e.camera = xx index;
        cameras[e.camera] = .{};
    }

    set_entity_name(e.ref, name);

    // default the patched version of the entity (if not, the entity's generation will be 0, so it won't get updated)
    entities_patched[e.index] = .{};
    return get_entity(e.ref);
}

entity_frame_turnover :: () {
    scope_timer();
    flush_entity_deletion_queue();
    compress_entity_axes();
    frame_refresh_patch_infos();
}

flush_entity_deletion_queue :: () {
    if entity_deletion_queue.count == 0 {
        return;
    }
    for entity_deletion_queue {
        delete_entity(it);
    }
    array_reset_keeping_memory(*entity_deletion_queue);
}

compress_entity_axes :: () {
    entity_count := get_entity_count();
    for 0..entity_count-1 {
        compress_axes(*entity_collision_bodies[it].orientation, *entity_compressed_axes[it]);
    }
}

frame_refresh_patch_infos :: () {
    entity_count := get_entity_count();
    for *e : entity_patch_infos {
        lfa_unset_multiple(*entity_flags[it_index], .[.COLLIDING_WITH_SOMETHING, .JUST_SPAWNED]);
        e.frame_counter += 1;
    }
}

set_global_entities :: () {
    context.camera_1 = get_entity(context.camera_1.ref);
    context.camera_2 = get_entity(context.camera_2.ref);
    context.player_entity = get_entity(context.player_entity.ref);
}

queue_entity_deletion :: (ref: Entity_Ref) {
    for entity_deletion_queue {
        if it.index == ref.index && it.id == ref.id {
            return;
        }
    }
    array_add(*entity_deletion_queue, ref);
}

delete_entity :: (ref: Entity_Ref) {
    i := entity_patch_layer[ref.index];
    assert(entity_patch_infos[i].id == ref.id);
    delete_entity(i);
}

set_body_shape_and_mass :: (ref: Entity_Ref, shape: Collision_Shape, mass := 1.0) {
    i := entity_patch_layer[ref.index];
    assert(entity_patch_infos[i].id == ref.id);

    body := get_body_at(i);
    body.shape = shape;

    assert(mass >= 0);
    if mass == 0 {
        body.inv_mass = 0;
    } else {
        body.inv_mass = 1 / mass;
    }

    invert_success: bool;

    if shape.type == {
    case .SPHERE;
        using shape.sphere;
        uniform_inertia := (2.0 / 5.0) * mass * square(radius);
        invert_success, inv_inertia_tensors[i] = inverse(Matrix3.{_11=uniform_inertia, _22=uniform_inertia, _33=uniform_inertia});
    case .CAPSULE;
        inv_inertia_tensors[i] = .{};
    case .RECT;
        using shape.rect;
        ONE_OVER_TWELVE :: 1.0 / 12.0;
        // rects are default facing along the y axis
        Y_DEPTH_SQ := VERY_SMALL_NUMBER;
        moment_xx := mass * (square(shape.half_height) + Y_DEPTH_SQ) * ONE_OVER_TWELVE;
        moment_yy := mass * (square(half_width) + square(shape.half_height)) * ONE_OVER_TWELVE;
        moment_zz := mass * (square(half_width) + Y_DEPTH_SQ) * ONE_OVER_TWELVE;
        invert_success, inv_inertia_tensors[i] = inverse(Matrix3.{_11=moment_xx, _22=moment_yy, _33=moment_zz});
    case .BOX; #through;
    case .AABB;
        using shape.box;
        ONE_OVER_TWELVE :: 1.0 / 12.0;
        moment_xx := mass * (square(shape.half_height) + square(half_length)) * ONE_OVER_TWELVE;
        moment_yy := mass * (square(half_width) + square(shape.half_height)) * ONE_OVER_TWELVE;
        moment_zz := mass * (square(half_width) + square(half_length)) * ONE_OVER_TWELVE;
        invert_success, inv_inertia_tensors[i] = inverse(Matrix3.{_11=moment_xx, _22=moment_yy, _33=moment_zz});
    case .HALF_SPACE;
        inv_inertia_tensors[i] = .{};
    }

    assert(invert_success);
}

// this should only be called a certain point in the frame. probably in exactly one place, inside a loop.
delete_entity :: (i: s64) {
    defer entity_patch_infos.count -= 1;
    e := *entity_patch_infos[i];

    remove_entity_from_collision_grid(e.ref);

    // todo: ideally find a good way to patch up holes in the pools on the spot.
    if (e.patch_flags & .CAMERA) != 0 {
        assert(e.camera >= 0 && e.camera < CAMERA_MAX_COUNT);
        return_item(*cameras, e.camera);
    }
    if lfa_is_set(*entity_flags[i], .DYNAMIC_PHYSICS_PROPERTIES) {
        assert(e.physics_properties >= 0 && e.physics_properties <= ENTITY_MAX_COUNT);
        return_item(*dynamic_entity_physics_properties, e.physics_properties);
    }

    assert(basic_validity_check(*name_allocations[i].allocation_ref));
    na_free(*entity_name_allocator, *name_allocations[i].allocation_ref);
    name_allocations[i] = .{};

    last_entity_index := entity_patch_infos.count-1;
    if i == last_entity_index {
        return;
    }

    entity_patch_layer[last_entity_index] = xx i;
    entity_patch_infos[i]       = entity_patch_infos[last_entity_index];
    entity_collision_bodies[i]  = entity_collision_bodies[last_entity_index];
    entity_movements[i]         = entity_movements[last_entity_index];
    entity_compressed_axes[i]   = entity_compressed_axes[last_entity_index];
    entity_mesh_collections[i]  = entity_mesh_collections[last_entity_index];
    name_allocations[i]         = name_allocations[last_entity_index];
    entity_datas[i]             = entity_datas[last_entity_index];
}

// spawn helpers

spawn_entity_human :: (name := "", location := Vector3.{}, orientation := QUATERNION_IDENTITY, physics_properties_template := Physics_Properties_Template.CAPSULE_MAN, make_physics_properties_dynamic := false) -> *Entity {
    entity := spawn_entity(.PERSON, name, location, orientation, physics_properties_template, make_physics_properties_dynamic);
    lfa_set(entity.flags, .MOVED_BY_PHYSICS);
    return entity;
}

// patchwork entity system:
// - all entities just use the base Entity as their type. use runtime typing.
// - base data is indexed
// - a unit's Entity_Type decides the base patch set.
// - the unit's current state (over all data) determines what extra, probably temporary, patches it has.
// - Entity itself has index fields, each corresponding to a patch the entity may have
// - the entity-patch indirection layer is this:
//      - entities index to the indirection layer array with a uint16 index. (max 65536 of the same patch)
//      - the indirection layer array is a pool of indices whose locations within the pool stay fixed until deallocated
//      - the pool of patches is indexed by the indirection layer index to get a pointer to the patch itself.
// - pooled patches are managed to remove gaps, in order to optimize iterating over the patches as well as allocating new patches. it's possible to move them due to the entity-patch indirection layer.
// - this system works best when the bulk of computation related to components is done by looping over those components in moderate isolation.

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// methods

set_orientation :: (e: *Entity, forward: Vector3, right: Vector3) {
    set_orientation(*e.orientation, forward, right);
    compress_axes(*e.orientation, e.compressed_axes);
}

rotate :: (e: *Entity, axis: Vector3, angle: float32) {
    rotate(*e.orientation, axis, angle);
    compress_axes(*e.orientation, e.compressed_axes);
}

up_direction_at :: inline (i: s64) -> Vector3 {
    return linear_decompress_norm_vector3(entity_compressed_axes[i].up);
}

up_direction :: inline (e: *Entity) -> Vector3 {
    return linear_decompress_norm_vector3(e.compressed_axes.up);
}

fore_direction :: inline (e: *Entity) -> Vector3 {
    return linear_decompress_norm_vector3(e.compressed_axes.fore);
}

right_direction :: inline (e: *Entity) -> Vector3 {
    return linear_decompress_norm_vector3(e.compressed_axes.right);
}

right_direction_xy :: inline (e: *Entity) -> Vector3 {
    right_3d := right_direction(e);
    right_3d.z = 0;
    return normalize(right_3d);
}

interp_rotate :: (e: *Entity, target: Quaternion, norm: float32) {
    e.orientation = interp_rotate(e.orientation, target, norm);
    compress_axes(*e.orientation, e.compressed_axes);
}

interp_rotate :: (e: *Entity, target: Quaternion, speed: float32, delta_time: float32) {
    e.orientation = interp_rotate(e.orientation, target, speed, delta_time);
    compress_axes(*e.orientation, e.compressed_axes);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

get_entity_count :: inline () -> s64 {
    return entity_patch_infos.count;
}

get_entity_patch_info :: inline (ref: Entity_Ref) -> *Entity_Patch_Info {
    i := entity_patch_layer[ref.index];
    patch_info := *entity_patch_infos[i];
    assert(ref.id == patch_info.id);

    return patch_info;
}

get_entity_physics_properties :: inline (ref: Entity_Ref) -> *Physics_Properties {
    i := entity_patch_layer[ref.index];
    assert(entity_patch_infos[i].id == ref.id);

    return get_physics_properties_at(i);
}

set_entity_name :: (ref: Entity_Ref, name: string) {
    i := entity_patch_layer[ref.index];
    assert(ref.id == entity_patch_infos[i].id);

    if basic_validity_check(*name_allocations[i].allocation_ref) {
        na_free(*entity_name_allocator, *name_allocations[i].allocation_ref);
    } else {
        assert(name_allocations[i].count == 0);
    }

    use_name: string;
    if name.count > 0 {
        use_name = tprint("eid % / %", ref.id, name);
    } else {
        use_name = tprint("eid %", ref.id, name);
    }
    assert(use_name.count <= ENTITY_NAME_MAX_CHAR_COUNT);

    name_allocations[i].allocation_ref = na_alloc(*entity_name_allocator, use_name.count);
    name_allocations[i].count = xx use_name.count;
    e_name := get_entity_name(*entity_patch_infos[i]);
    assert(e_name.count == use_name.count);
    memcpy(e_name.data, use_name.data, e_name.count);
}

get_entity_name :: (patch_info: *Entity_Patch_Info) -> string {
    i := entity_patch_layer[patch_info.index];
    assert(basic_validity_check(name_allocations[i].allocation_ref));
    return get_entity_name_at(i);
}

get_entity_name_at :: (i: s64) -> string {
    allocation: string;
    allocation.data = name_allocations[i].allocation_ref.data;
    allocation.count = name_allocations[i].count;
    return allocation;
}

set_entity_meshes :: (ref: Entity_Ref, meshes: ..Entity_Mesh) {
    assert(meshes.count > 0 && meshes.count <= ENTITY_MESHES_MAX_COUNT);
    patch_info := get_entity_patch_info(ref);

    mesh_collection := *entity_mesh_collections[ref.index];
    if mesh_collection.count < meshes.count {
        if basic_validity_check(*mesh_collection.allocation_ref) {
            na_free(*entity_mesh_array_allocator, *mesh_collection.allocation_ref);
        } else {
            assert(mesh_collection.count == 0);
        }
        mesh_collection.allocation_ref = na_alloc(*entity_mesh_array_allocator, meshes.count * size_of(Entity_Mesh));
        assert(basic_validity_check(*mesh_collection.allocation_ref));
    }

    mesh_collection.count = xx meshes.count;
    new_meshes := get_entity_meshes(patch_info);
    assert(new_meshes.count == meshes.count);    
    for meshes {
        new_meshes[it_index] = it;
    }
}

get_entity_meshes :: (patch_info: *Entity_Patch_Info) -> []Entity_Mesh {
    i := entity_patch_layer[patch_info.index];
    return get_entity_meshes_at(i);
}

get_entity_meshes_at :: (i: s64) -> []Entity_Mesh {
    mesh_collection := *entity_mesh_collections[i];
    meshes: []Entity_Mesh;
    meshes.data = mesh_collection.allocation_ref.data;
    meshes.count = mesh_collection.count;
    return meshes;
}

add_linear_impulse :: inline (e: *Entity, force: Vector3, duration := DEFAULT_LINEAR_IMPULSE_DURATION) {
    i := entity_patch_layer[e.ref.index];
    add_linear_impulse_at(i, force, duration);
}

add_linear_impulse_at :: (i: s64, force: Vector3, duration := DEFAULT_LINEAR_IMPULSE_DURATION) {
    assert(lfa_is_set(*entity_flags[i], .MOVED_BY_PHYSICS));
    assert(duration > 0);
    if duration > 1.0 {
        // if this log becomes common, either it's okay and the log should be deleted, or it's not and probably I should keep this from spamming
        rm_warning("long duration (%) impulse being applied to entity %", duration, get_entity_name_at(i));
    }
    allocation := *linear_impulse_allocations[i];
    if allocation.count >= allocation.allocated {
        assert(allocation.count < LINEAR_IMPULSES_MAX_COUNT); // may eventually have to reckon with this?
        assert(allocation.count == allocation.allocated);
        new_allocated_count := max(min(allocation.allocated * 2, LINEAR_IMPULSES_MAX_COUNT), 4);
        old_allocation: *Linear_Physics_Impulse = allocation.allocation_ref.data;
        new_allocation_ref := na_alloc(*linear_impulse_allocator, new_allocated_count * size_of(Linear_Physics_Impulse));
        memset(new_allocation_ref.data, 0, new_allocated_count * size_of(Linear_Physics_Impulse));
        if allocation.count > 0 {
            memcpy(new_allocation_ref.data, old_allocation, allocation.count * size_of(Linear_Physics_Impulse));
            na_free(*linear_impulse_allocator, *allocation.allocation_ref);
        }
        allocation.allocation_ref = new_allocation_ref;
        allocation.allocated = new_allocated_count;
    }
    allocation.count += 1;
    impulses := get_linear_impulses_at(i);
    impulses[impulses.count-1] = .{force=force, time_remaining=duration};
    assert(impulses.count == allocation.count);
}

clear_completed_impulses_at :: (i: s64) {
    impulses := get_linear_impulses_at(i);
    new_count : s32 = xx impulses.count;
    for #v2 < 0..impulses.count-1 {
        // trying to avoid potential (?) float error situation, since the delta value for the timer is clamped.
        if impulses[it].time_remaining <= VERY_SMALL_NUMBER {
            if new_count > 1 {
                impulses[it] = impulses[impulses.count-1];
            }
            new_count -= 1;
        }
    }
    linear_impulse_allocations[i].count = new_count;
}

// ---------------------------------------------------------------------------------------------------

get_linear_impulses_at :: inline (e: s64) -> []Linear_Physics_Impulse {
    allocation := *linear_impulse_allocations[e];
    array: []Linear_Physics_Impulse = ---;
    array.data = allocation.allocation_ref.data;
    array.count = allocation.count;
    return array;
}

get_physics_properties_at :: inline (e: s64) -> *Physics_Properties {
    i := entity_patch_layer[e];
    patch_info := *entity_patch_infos[i];
    if lfa_is_set(*entity_flags[i], .DYNAMIC_PHYSICS_PROPERTIES) {
        return *dynamic_entity_physics_properties[patch_info.physics_properties];
    } else {
        return *PHYSICS_PROPERTIES_TEMPLATES[patch_info.physics_properties];
    }
}

// I made these because I was accidentally copying instead of getting pointers to the array values too much

get_movement_at :: inline (i: s64) -> *Entity_Movement {
    return *entity_movements[i];
}

get_body_at :: inline (i: s64) -> *Collision_Body {
    return *entity_collision_bodies[i];
}

get_compressed_axes_at :: inline (i: s64) -> *Compressed_Axes {
    return *entity_compressed_axes[i];
}

get_axes_at :: inline (i: s64) -> Axes {
    axes: Axes = ---;
    decompress_axes(*entity_compressed_axes[i], *axes);
    return axes;
}

get_position_offset_from_entity_at :: (i: s64, fore_offset := 0.0, up_offset := 0.0, right_offset := 0.0) -> Vector3 {
    axes := get_axes_at(i);
    return entity_collision_bodies[i].center + axes.fore * fore_offset + axes.up * up_offset + axes.right * right_offset;
}

get_position_offset_from_entity :: (entity: *Entity, fore_offset := 0.0, up_offset := 0.0, right_offset := 0.0) -> Vector3{
    axes := get_axes_at(entity_patch_layer[entity.ref.index]);
    return entity.center + axes.fore * fore_offset + axes.up * up_offset + axes.right * right_offset;
}

get_frame_counter_at :: inline (i: s64) -> s32 {
    return entity_patch_infos[i].frame_counter;
}

// ---------------------------------------------------------------------------------------------------

// all arrays parallel to entity_patch_infos array
entity_patch_infos: [..]Entity_Patch_Info;
entity_datas : []Entity_Data;
entities_patched: []Entity;
entity_patch_layer: []u16;
// default entity data
entity_collision_bodies: []Collision_Body;
entity_movements: []Entity_Movement;
entity_compressed_axes: []Compressed_Axes;
entity_mesh_collections: []Nested_Allocation;
entity_trigger_volume_allocations: []Nested_Allocation;
entity_collision_channels: []Collision_Channels;
inv_inertia_tensors: []Matrix3;
name_allocations: []Nested_Allocation;
collision_cell_hashes: []s64;
entity_flags: []Long_Flag_Array(Entity_Flags);
linear_impulse_allocations: []Nested_Dynamic_Allocation;

entity_deletion_queue: [..]Entity_Ref;

entity_mesh_array_allocator: Nesting_Allocator(8);
entity_name_allocator: Nesting_Allocator(8);
TRIGGER_VOLUMES_ALLOCATOR_MIN_ALLOC_SIZE :: #run ceil_to_pow2(size_of(Trigger_Volume)) >> 1;
entity_trigger_volumes_allocator: Nesting_Allocator(TRIGGER_VOLUMES_ALLOCATOR_MIN_ALLOC_SIZE);
linear_impulse_allocator: Nesting_Allocator(16);

// type-specific entity data

cameras: Pool(Entity_Camera);
dynamic_entity_physics_properties: Pool(Physics_Properties_Dynamic);

spawn_entity_mutex: Mutex;
entity_id_counter: u32;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }
