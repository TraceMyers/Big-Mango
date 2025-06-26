
// NOTE: no need for a patch layer on data that is parallel to entities. setting indexes on the patch infos would
// be the same exact process, just on a second layer for no reason. well, except for references to entities...
// but, maybe that could be sorted out with the id? not sure of the cost there.

INVALID_ENTITY_ID : u32 : 0;
INVALID_ENTITY_INDEX : u32 : 0;
INVALID_CAMERA_INDEX : u8 : 0;
INVALID_CREATURE_INDEX : u16 : 0;
// Entity_Physics_Properties :: Physics_Properties_Dynamic;

ENTITY_MAX_COUNT :: 32767;
CREATURE_MAX_COUNT :: 32767;
CAMERA_MAX_COUNT :: 256;
ENTITY_MESHES_MAX_COUNT :: 8;

boot_entities :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        {
            scope_set_allocator(program_runtime_allocator);

            entity_patch_layer = alloc_array(*Entity_Patch_Info, ENTITY_MAX_COUNT);
            entity_physics_core = alloc_array(Entity_Physics_Core, ENTITY_MAX_COUNT);
            entity_mesh_collections = alloc_array(Entity_Mesh_Collection, ENTITY_MAX_COUNT);
            creature_interface = alloc_array(*Entity_Creature, CREATURE_MAX_COUNT);
            precalculated_forward_directions = alloc_array(Vector2, CREATURE_MAX_COUNT);

            set_capacity(*entities, ENTITY_MAX_COUNT);
            set_capacity(*creatures, CREATURE_MAX_COUNT);
            set_capacity(*cameras, CAMERA_MAX_COUNT);
            set_capacity(*dynamic_entity_physics_properties, ENTITY_MAX_COUNT);
            set_capacity(*colliders, ENTITY_MAX_COUNT);
        }
        lock_allocation(*entities);
        lock_allocation(*cameras);
        lock_allocation(*creatures);
        lock_allocation(*dynamic_entity_physics_properties);
        lock_allocation(*colliders);

        all_mesh_ptrs_array_data_size := ENTITY_MAX_COUNT * ENTITY_MESHES_MAX_COUNT * size_of(*Mesh);

        maybe_optimal_chunk_list_size := 4096 * 16;
        maybe_optimal_chunk_list_count := div_ceil(all_mesh_ptrs_array_data_size, maybe_optimal_chunk_list_size);

        initialize_nesting_allocator(*entity_mesh_array_allocator, program_runtime_allocator, maybe_optimal_chunk_list_size, maybe_optimal_chunk_list_count);
        entity_mesh_array_allocator.parent_allocator = no_allocator;

        // 0 is invalid index
        null_entity := spawn_entity(ALL_ENTITY_TYPE_FLAGS.(Entity_Type));

        return true;
    } else {
        return true;
    }
}

Entity_Type_Flags :: enum_flags u32 {
    CAMERA::1;
    STATIC_MESH;
    CREATURE;
}

Entity_Type :: enum u32 {
    CAMERA :: Entity_Type_Flags.CAMERA;
    STATIC_MESH :: Entity_Type_Flags.STATIC_MESH;
    STATIC_MESH_CREATURE :: (Entity_Type_Flags.STATIC_MESH | Entity_Type_Flags.CREATURE);
}

ALL_ENTITY_TYPE_FLAGS :: #run -> Entity_Type_Flags {
    ti := type_info(Entity_Type_Flags);
    all: Entity_Type_Flags;
    for ti.names {
        all |= xx ti.values[it_index];
    }
    return all;
}

Entity_Subtype :: union {
    byte: u8 = 0;
    static_mesh_creature_type: Static_Mesh_Creature_Type = ---;
}

Static_Mesh_Creature_Type :: enum u8 {
    DEFAULT::1;
}

Entity_Physics_Core :: struct {
    position: Vector3;
    linear_velocity: Vector3;
    angular_velocity: Vector3;
    orientation: Quaternion;
}

Entity_Patch_Flags :: enum_flags u32 {
    DYNAMIC_PHYSICS_PROPERTIES::1;
}

Entity_Type_Flags_Union :: union {
    type: Entity_Type = 0;
    type_flags: Entity_Type_Flags = ---;
}

Entity_Mesh_Collection :: struct {
    allocation_ref: Nested_Allocation_Ref;
    mesh_count: s32;
}

Entity_Patch_Info :: struct {
    using type_union: Entity_Type_Flags_Union;
    using subtype: Entity_Subtype;
    camera: u8 = INVALID_CAMERA_INDEX;
    using ref: Entity_Ref;
    physics_properties: u16;
    body_collider: u16;
    meshes: u16;
    creature: u16 = INVALID_CREATURE_INDEX;
    flags: Entity_Patch_Flags;
}

Entity :: struct {
    using type_union: Entity_Type_Flags_Union;
    using subtype: Entity_Subtype;
    using camera: *Entity_Camera;
    using ref: Entity_Ref;
    using physics_core: *Entity_Physics_Core;
    physics_properties: *Physics_Properties;
    body_collider: *Entity_Collider;
    meshes: []*Mesh;
    creature: *Entity_Creature;
}

Creature_Type :: enum u16 {
    CREATURE::1;
}

// One-Big-Struct approach to creatures
Entity_Creature :: struct {
    type: Creature_Type;
}

get_entity :: inline (e: *Entity, ref: Entity_Ref) {
    _ := get_entity_patch_info(ref);
    get_entity_at(e, ref.index);
}

get_entity_at :: (using e: *Entity, i: s64) {
    patch_info := *entities[i];
    entity_index := i;
    assert(is_item_in_use(*entities, entity_index));
    e.* = .{
        type = patch_info.type,
        subtype = patch_info.subtype,
        ref = patch_info.ref,
        physics_core = *entity_physics_core[i],
        meshes = get_entity_meshes(patch_info)
    };
    if (patch_info.type_flags & .CREATURE) != 0 {
        assert(patch_info.creature != INVALID_CREATURE_INDEX);
        creature = creature_interface[patch_info.creature];
    } else {
        assert(patch_info.creature == INVALID_CREATURE_INDEX);
    }
    if (patch_info.type_flags & .CAMERA) != 0 {
        assert(patch_info.camera != INVALID_CAMERA_INDEX);
        camera = *cameras.items[patch_info.camera];
    } else {
        assert(patch_info.camera == INVALID_CAMERA_INDEX);
    }

    if (patch_info.flags & .DYNAMIC_PHYSICS_PROPERTIES) != 0 {
        physics_properties = *dynamic_entity_physics_properties[patch_info.physics_properties];
    } else {
        physics_properties = *PHYSICS_PROPERTIES_TEMPLATES[patch_info.physics_properties];
    }
}

is_creature_type :: (t: Entity_Type) -> bool {
    // if t == {
    // case .STATIC_MESH_CREATURE;
    //     return true;
    // }
    return false;
}


spawn_entity :: (t: Entity_Type, subtype := Entity_Subtype.{}, physics := Entity_Physics_Core.{}, physics_properties_template  := Physics_Properties_Template.DEFAULT_MAN, make_physics_properties_dynamic := false) -> Entity_Ref {
    // scope_lock_mutex(*spawn_entity_mutex);
    i := request_item(*entities);
    assert(i >= 0 && i < ENTITY_MAX_COUNT);

    entity_physics_core[i] = physics;

    mesh_collection := *entity_mesh_collections[i];
    assert(mesh_collection.mesh_count == 0 && mesh_collection.allocation_ref.data == null && mesh_collection.allocation_ref.info.bit_pattern == 0);

    assert(entity_id_counter < U32_MAX);
    new_id := entity_id_counter;
    entity_id_counter += 1;

    e := get_item(*entities, i);
    e.* = .{
        type = t,
        subtype = subtype,
        ref = .{xx i, xx new_id},
    };

    if make_physics_properties_dynamic {
        phys_props_index := request_item(*dynamic_entity_physics_properties);   
        assert(phys_props_index < ENTITY_MAX_COUNT);
        phys_props := *dynamic_entity_physics_properties[xx physics_properties_template];
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
    }

    return e.ref;
}

set_entity_meshes :: (ref: Entity_Ref, meshes: ..*Mesh) {
    assert(meshes.count > 0 && meshes.count <= ENTITY_MESHES_MAX_COUNT);
    patch_info := get_entity_patch_info(ref);

    mesh_collection := *entity_mesh_collections[ref.index];
    if mesh_collection.mesh_count < meshes.count {
        if basic_validity_check(*mesh_collection.allocation_ref) {
            na_free(*entity_mesh_array_allocator, *mesh_collection.allocation_ref);
        } else {
            assert(mesh_collection.mesh_count == 0);
        }
        mesh_collection.allocation_ref = na_alloc(*entity_mesh_array_allocator, meshes.count * size_of(*Mesh));
        assert(basic_validity_check(*mesh_collection.allocation_ref));
    }

    mesh_collection.mesh_count = xx meshes.count;
    new_meshes := get_entity_meshes(patch_info);
    assert(new_meshes.count == meshes.count);    
    for meshes {
        new_meshes[it_index] = it;
    }
}

get_entity_meshes :: (patch_info: *Entity_Patch_Info) -> []*Mesh {
    mesh_collection := *entity_mesh_collections[patch_info.index];
    if mesh_collection.mesh_count == 0 {
        return .[];
    }
    assert(basic_validity_check(mesh_collection.allocation_ref));
    meshes: []*Mesh;
    meshes.data = mesh_collection.allocation_ref.data;
    meshes.count = mesh_collection.mesh_count;
    return meshes;
}

entities: Pool(Entity_Patch_Info);
entity_patch_layer: []*Entity_Patch_Info;
// default entity data
entity_physics_core: []Entity_Physics_Core;
entity_mesh_collections: []Entity_Mesh_Collection;
precalculated_forward_directions: []Vector2;
entity_mesh_array_allocator: Nesting_Allocator;
// type-specific entity data
creature_interface: []*Entity_Creature;
creatures: Pool(Entity_Creature);
cameras: Pool(Entity_Camera);
colliders: Pool(Entity_Collider);
dynamic_entity_physics_properties: Pool(Physics_Properties_Dynamic);

spawn_entity_mutex: Mutex;
entity_id_counter: u32;

// patchwork entity system:
// - (almost) all entities just use the base Entity as their type. instead use runtime typing.
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
    patch_info := *entities[ref.index];
    assert(ref.id == patch_info.id);
    return patch_info;
}
