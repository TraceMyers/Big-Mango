
// NOTE: no need for a patch layer on data that is parallel to entities. setting indexes on the patch infos would
// be the same exact process, just on a second layer for no reason. well, except for references to entities...
// but, maybe that could be sorted out with the id? not sure of the cost there.

INVALID_ENTITY_ID : u32 : 0;
INVALID_ENTITY_INDEX : u32 : 0;
INVALID_CAMERA_INDEX : u8 : 0;
INVALID_DEVICE_INDEX : u16 : 0;
// Entity_Physics_Properties :: Physics_Properties_Dynamic;

ENTITY_MAX_COUNT :: 32767;
DEVICE_MAX_COUNT :: 32767;
CAMERA_MAX_COUNT :: 256;
ENTITY_MESHES_MAX_COUNT :: 8;
ENTITY_NAME_MAX_COUNT :: 32;

boot_entities :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        program_runtime_reserve(*entities, ENTITY_MAX_COUNT);
        program_runtime_reserve(*entity_deletion_queue, ENTITY_MAX_COUNT);

        program_runtime_allocate(*entity_patch_layer, ENTITY_MAX_COUNT);
        program_runtime_allocate(*entities_patched, ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_physics_core, ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_mesh_collections, ENTITY_MAX_COUNT * ENTITY_MESHES_MAX_COUNT);
        program_runtime_allocate(*precalculated_fore_directions, ENTITY_MAX_COUNT);
        program_runtime_allocate(*precalculated_up_directions, ENTITY_MAX_COUNT);
        program_runtime_allocate(*name_allocations, ENTITY_MAX_COUNT);
        program_runtime_allocate(*entity_trigger_volume_allocations, ENTITY_MAX_COUNT);

        program_runtime_initialize(*devices, DEVICE_MAX_COUNT);
        program_runtime_initialize(*cameras, CAMERA_MAX_COUNT);
        program_runtime_initialize(*dynamic_entity_physics_properties, ENTITY_MAX_COUNT);

        na_chunk_list_size := 4096 * 16;
        na_chunk_list_size_large := 4096 * 32;

        mesh_ptrs_array_data_size := ENTITY_MAX_COUNT * ENTITY_MESHES_MAX_COUNT * size_of(Entity_Mesh);
        program_runtime_initialize(*entity_mesh_array_allocator, na_chunk_list_size, mesh_ptrs_array_data_size);
        entity_name_data_size := ENTITY_MAX_COUNT * ENTITY_NAME_MAX_COUNT;
        program_runtime_initialize(*entity_name_allocator, na_chunk_list_size, entity_name_data_size);
        entity_trigger_volumes_data_size := ENTITY_MAX_COUNT * size_of(Trigger_Volume);
        program_runtime_initialize(*entity_trigger_volumes_allocator, na_chunk_list_size_large, entity_trigger_volumes_data_size);

        // 0 is invalid index
        null_entity := spawn_entity(0);
        request_item(*cameras);
        request_item(*devices);

        return true;
    } else {
        return true;
    }
}

get_entity :: inline (ref: Entity_Ref) -> *Entity {
    i := entity_patch_layer[ref.index];
    assert(entities[i].id == ref.id);
    return get_entity_at(i);
}

// when using this procedure outside this file, it's important to observe the lifetime of an index w.r.t entities. to access entities in a way that is always safe, store and get with an Entity_Ref.
get_entity_at :: (i: s64) -> *Entity {
    e := *entities_patched[i];
    if e.generation != game_frame_count {
        patch_info := *entities[i];

        e.* = .{
            type = patch_info.type,
            ref = patch_info.ref,
            physics_core = *entity_physics_core[i],
            meshes = get_entity_meshes(patch_info),
            name = get_entity_name(patch_info)
        };

        if (patch_info.type_flags & .CAMERA) != 0 {
            assert(patch_info.camera != INVALID_CAMERA_INDEX);
            e.camera = *cameras.items[patch_info.camera];
        } else {
            assert(patch_info.camera == INVALID_CAMERA_INDEX);
        }
        if (patch_info.type_flags & .DEVICE) != 0 {
            assert(patch_info.device != INVALID_DEVICE_INDEX);
            e.device = *devices.items[patch_info.device];
        } else {
            assert(patch_info.device == INVALID_DEVICE_INDEX);
        }

        if (patch_info.flags & .DYNAMIC_PHYSICS_PROPERTIES) != 0 {
            e.physics_properties = *dynamic_entity_physics_properties[patch_info.physics_properties];
        } else {
            e.physics_properties = *PHYSICS_PROPERTIES_TEMPLATES[patch_info.physics_properties];
        }

        e.generation = game_frame_count;
    }
    return e;
}

spawn_entity :: (t: Entity_Type, name := "", physics := Entity_Physics_Core.{}, physics_properties_template := Physics_Properties_Template.CAPSULE_MAN, make_physics_properties_dynamic := false) -> *Entity {
    // scope_lock_mutex(*spawn_entity_mutex);
    i := entities.count.(u16);
    e := array_add(*entities);
    assert(i >= 0 && i < ENTITY_MAX_COUNT);

    entity_patch_layer[i] = i;
    entity_physics_core[i] = physics;

    mesh_collection := *entity_mesh_collections[i];
    assert(mesh_collection.mesh_count == 0 && mesh_collection.allocation_ref.data == null && mesh_collection.allocation_ref.info.bit_pattern == 0);

    assert(entity_id_counter < U32_MAX);
    new_id := entity_id_counter;
    entity_id_counter += 1;

    e.* = .{
        type = t,
        ref = .{xx i, xx new_id},
    };

    if make_physics_properties_dynamic {
        phys_props_index := request_item(*dynamic_entity_physics_properties);   
        assert(phys_props_index < ENTITY_MAX_COUNT);
        phys_props := *dynamic_entity_physics_properties[phys_props_index];
        phys_props.template = physics_properties_template;
        phys_props.base = PHYSICS_PROPERTIES_TEMPLATES[physics_properties_template];
        e.flags |= .DYNAMIC_PHYSICS_PROPERTIES;
        e.physics_properties = xx phys_props_index;
    } else {
        e.physics_properties = xx physics_properties_template;
    }

    if (e.type_flags & .CAMERA) != 0 {
        index := request_item(*cameras);
        assert(index >= 0 && index < CAMERA_MAX_COUNT);
        e.camera = xx index;
        cameras[e.camera] = .{};
    }

    if (e.type_flags & .DEVICE) != 0 {
        index := request_item(*devices);
        assert(index >= 0 && index < DEVICE_MAX_COUNT);
        e.device = xx index;
        devices[e.device] = .{};
    }

    set_entity_name(e.ref, name);

    // default the patched version of the entity (if not, the entity's generation will be 0, so it won't get updated)
    entities_patched[e.index] = .{};
    return get_entity(e.ref);
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

set_global_entities :: () {
    context.camera_1 = get_entity(context.camera_1.ref);
    context.camera_2 = get_entity(context.camera_2.ref);
    context.player_entity = get_entity(context.player_entity.ref);
}

delete_entity :: (ref: Entity_Ref) {
    i := entity_patch_layer[ref.index];
    assert(entities[i].id == ref.id);
    delete_entity(i);
}

// this should only be called a certain point in the frame. probably in exactly one place, inside a loop.
delete_entity :: (i: s64) {
    defer entities.count -= 1;
    e := *entities[i];

    // todo: ideally find a good way to patch up holes in the pools on the spot.
    if (e.type_flags & .CAMERA) != 0 {
        assert(e.camera >= 0 && e.camera < CAMERA_MAX_COUNT);
        return_item(*cameras, e.camera);
    }
    if (e.type_flags & .DEVICE) != 0 {
        assert(e.device >= 0 && e.device < DEVICE_MAX_COUNT);
        return_item(*devices, e.device);
    }
    if (e.flags & .DYNAMIC_PHYSICS_PROPERTIES) {
        assert(e.physics_properties >= 0 && e.physics_properties <= ENTITY_MAX_COUNT);
        return_item(*dynamic_entity_physics_properties, e.physics_properties);
    }

    assert(basic_validity_check(*name_allocations[i].allocation_ref));
    na_free(*entity_name_allocator, *name_allocations[i].allocation_ref);
    name_allocations[i] = .{};

    last_entity_index := entities.count-1;
    if i == last_entity_index {
        return;
    }

    entity_patch_layer[last_entity_index] = xx i;
    entities[i] = entities[last_entity_index];
    entity_physics_core[i] = entity_physics_core[last_entity_index];
    entity_mesh_collections[i] = entity_mesh_collections[last_entity_index];
    name_allocations[i] = name_allocations[last_entity_index];
}

// spawn helpers

spawn_entity_human :: (name := "", physics := Entity_Physics_Core.{}, physics_properties_template := Physics_Properties_Template.CAPSULE_MAN, make_physics_properties_dynamic := false) -> *Entity {
    entity := spawn_entity(.STATIC_MESH, name, physics, physics_properties_template, make_physics_properties_dynamic);
    entity.physics_flags |= .MOVED_BY_PHYSICS;
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

set_orientation :: inline (e: *Entity, forward: Vector3, right: Vector3) {
    set_orientation(*e.orientation, forward, right);
}

rotate :: inline (e: *Entity, axis: Vector3, angle: float32) {
    rotate(*e.orientation, axis, angle);
}

right_direction :: inline (e: *Entity) -> Vector3 {
    return right_direction(*e.orientation);
}

right_direction_xy :: inline (e: *Entity) -> Vector3 {
    right_3d := right_direction(e);
    right_3d.z = 0;
    return normalize(right_3d);
}

up_direction :: inline (e: *Entity) -> Vector3 {
    return up_direction(*e.orientation);
}

fore_direction :: inline (e: *Entity) -> Vector3 {
    return fore_direction(*e.orientation);
}

interp_rotate :: inline (e: *Entity, target: Quaternion, norm: float32) {
    e.orientation = interp_rotate(e.orientation, target, norm);
}

interp_rotate :: inline (e: *Entity, target: Quaternion, speed: float32, delta_time: float32) {
    e.orientation = interp_rotate(e.orientation, target, speed, delta_time);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

get_entity_patch_info :: inline (ref: Entity_Ref) -> *Entity_Patch_Info {
    i := entity_patch_layer[ref.index];
    patch_info := *entities[i];
    assert(ref.id == patch_info.id);

    return patch_info;
}

get_entity_physics_properties :: inline (ref: Entity_Ref) -> *Physics_Properties {
    i := entity_patch_layer[ref.index];
    assert(entities[i].id == ref.id);

    return get_entity_physics_properties_at(i);
}

set_entity_name :: (ref: Entity_Ref, name: string) {
    i := entity_patch_layer[ref.index];
    assert(ref.id == entities[i].id);

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
    assert(use_name.count <= ENTITY_NAME_MAX_COUNT);

    name_allocations[i].allocation_ref = na_alloc(*entity_name_allocator, use_name.count);
    name_allocations[i].count = xx use_name.count;
    e_name := get_entity_name(*entities[i]);
    assert(e_name.count == use_name.count);
    memcpy(e_name.data, use_name.data, e_name.count);
}

get_entity_name :: (patch_info: *Entity_Patch_Info) -> string {
    i := entity_patch_layer[patch_info.index];
    assert(basic_validity_check(name_allocations[i].allocation_ref));
    allocation: string;
    allocation.data = name_allocations[i].allocation_ref.data;
    allocation.count = name_allocations[i].count;
    return allocation;
}

set_entity_meshes :: (ref: Entity_Ref, meshes: ..Entity_Mesh) {
    assert(meshes.count > 0 && meshes.count <= ENTITY_MESHES_MAX_COUNT);
    patch_info := get_entity_patch_info(ref);

    mesh_collection := *entity_mesh_collections[ref.index];
    if mesh_collection.mesh_count < meshes.count {
        if basic_validity_check(*mesh_collection.allocation_ref) {
            na_free(*entity_mesh_array_allocator, *mesh_collection.allocation_ref);
        } else {
            assert(mesh_collection.mesh_count == 0);
        }
        mesh_collection.allocation_ref = na_alloc(*entity_mesh_array_allocator, meshes.count * size_of(Entity_Mesh));
        assert(basic_validity_check(*mesh_collection.allocation_ref));
    }

    mesh_collection.mesh_count = xx meshes.count;
    new_meshes := get_entity_meshes(patch_info);
    assert(new_meshes.count == meshes.count);    
    for meshes {
        new_meshes[it_index] = it;
    }
}

get_entity_meshes :: inline (patch_info: *Entity_Patch_Info) -> []Entity_Mesh {
    i := entity_patch_layer[patch_info.index];
    return get_entity_meshes_at(i);
}

get_entity_meshes_at :: inline (i: s64) -> []Entity_Mesh {
    mesh_collection := *entity_mesh_collections[i];
    if mesh_collection.mesh_count == 0 {
        return .[];
    }
    assert(basic_validity_check(mesh_collection.allocation_ref));
    meshes: []Entity_Mesh;
    meshes.data = mesh_collection.allocation_ref.data;
    meshes.count = mesh_collection.mesh_count;
    return meshes;
}

// ---------------------------------------------------------------------------------------------------

get_entity_physics_properties_at :: (e: s64) -> *Physics_Properties {
    i := entity_patch_layer[e];
    patch_info := *entities[i];
    if (patch_info.flags & .DYNAMIC_PHYSICS_PROPERTIES) != 0 {
        return *dynamic_entity_physics_properties[patch_info.physics_properties];
    } else {
        return *PHYSICS_PROPERTIES_TEMPLATES[patch_info.physics_properties];
    }
}

// ---------------------------------------------------------------------------------------------------

// all arrays parallel to entities array

entities: [..]Entity_Patch_Info;
entities_patched: []Entity;
entity_patch_layer: []u16;
// default entity data
entity_physics_core: []Entity_Physics_Core;
entity_mesh_collections: []Entity_Mesh_Collection;
entity_trigger_volume_allocations: []Trigger_Volume_Allocation;
precalculated_fore_directions: []Vector3;
precalculated_up_directions: []Vector3;
name_allocations: []Entity_Name_Allocation;
entity_deletion_queue: [..]Entity_Ref;

entity_mesh_array_allocator: Nesting_Allocator(8);
entity_name_allocator: Nesting_Allocator(8);
TRIGGER_VOLUMES_ALLOCATOR_MIN_ALLOC_SIZE :: #run ceil_to_pow2(size_of(Trigger_Volume)) >> 1;
entity_trigger_volumes_allocator: Nesting_Allocator(TRIGGER_VOLUMES_ALLOCATOR_MIN_ALLOC_SIZE);

// type-specific entity data

cameras: Pool(Entity_Camera);
devices: Pool(Entity_Device);
dynamic_entity_physics_properties: Pool(Physics_Properties_Dynamic);

spawn_entity_mutex: Mutex;
entity_id_counter: u32;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }
