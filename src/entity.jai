
// TODO: 

INVALID_ENTITY_ID : u32 : 0;
INVALID_ENTITY_INDEX : u32 : 0;
INVALID_CAMERA_INDEX : u8 : 0;
INVALID_CREATURE_INDEX : u16 : 0;

boot_entities :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        init(*spawn_entity_mutex);
        entity_max_ct := 32767;
        entity_max_mesh_array_count_sum := 65535;
        creature_max_ct := 32767;
        {
            scope_set_allocator(program_runtime_allocator);

            entity_patch_layer = alloc_array(*Entity_Patch_Info, entity_max_ct);
            entity_physics_core = alloc_array(Entity_Physics_Core, entity_max_ct);
            entity_mesh_arrays = alloc_array([]*Mesh, entity_max_ct);
            // todo: nesting allocator
            creature_interface = alloc_array(*Entity_Creature, creature_max_ct);

            set_capacity(*entities, entity_max_ct);
            set_capacity(*creatures, creature_max_ct);
            set_capacity(*entity_physics_properties, entity_max_ct);
        }
        lock_allocation(*entities);
        lock_allocation(*creatures);
        lock_allocation(*entity_physics_properties);

        // 0 is invalid index
        request_item(*entites);

        return true;
    } else {
        return true;
    }
}

Entity_Type :: enum_flags u32 {
    CAMERA_FLAG::1;
    STATIC_MESH_FLAG;
    CREATURE_FLAG;
    STATIC_MESH_CREATURE :: #run (Entity_Type.STATIC_MESH_FLAG | Entity_Type.CREATURE_FLAG);
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

Entity_Physics_Properties_Template :: enum u8 {
    DEFAULT::1;
}
ENTITY_PHYSICS_PROPERTIES_TEMPLATE_COUNT :: #run (enum_highest_value(Entity_Physics_Properties_Template) + 1);

Entity_Physics_Properties :: struct {
    template: Entity_Physics_Properties_Template = 0;
    mass := 1.0;
}

Entity_Camera :: struct {
    projection := Camera_Projection.NONE;
    using settings: union {
        orthographic: Camera_Settings_Orthographic = ---;
        perspective: Camera_Settings_Perspective = ---;
    }
}

Entity_Patch_Info :: struct {
    type: Entity_Type = 0;
    using subtype: Entity_Subtype;
    camera: u8 = INVALID_CAMERA_INDEX;
    using ref: Entity_Ref;
    physics_properties: u16;
    meshes: u16;
    creature: u16 = INVALID_CREATURE_INDEX;
}

Entity :: struct {
    type: Entity_Type = 0;
    using subtype: Entity_Subtype;
    using camera: *Camera;
    using ref: Entity_Ref;
    using physics_core: *Entity_Physics_Core;
    physics_properties: *Entity_Physics_Properties;
    meshes: []*Mesh;
    creature: *Entity_Creature;
}

Entity_Ref :: struct {
    eindex: u32 = INVALID_ENTITY_INDEX;
    eid: u32 = INVALID_ENTITY_ID;
}

Creature_Type :: enum u16 {
    CREATURE::1;
}

// One-Big-Struct approach to creatures
Entity_Creature :: struct {
    type: Creature_Type;
}

get_entity :: inline (e: *Entity, ref: Entity_Ref) {
    patch_info := entity_patch_layer[ref.eindex];
    assert(patch_info.eid == ref.eid);
    get_entity_at(e, ref.eindex);
}

get_entity_at :: (using e: *Entity, i: s64) {
    patch_info := entity_patch_layer[i];
    entity_index := patch_info - entities.data;
    assert(is_item_in_use(*entities, entity_index));
    e.* = .{
        type = patch_info.type,
        subtype = patch_info.subtype,
        eid = patch_info.eid,
        eindex = patch_inf.eindex,
        physics_core = *entity_physics_core[i],
        physics_properties = *entity_physics_properties[patch_info.physics_properties],
        meshes = entity_mesh_arrays[i]
    };
    if (patch_info.type & .CREATURE_FLAG) != 0 {
        assert(patch_info.creature != INVALID_CREATURE_INDEX);
        creature = creature_interface[patch_info.creature];
    } else {
        assert(patch_info.creature == INVALID_CREATURE_INDEX);
    }
    if (patch_info.type & .CAMERA_FLAG) != 0 {
        assert(patch_info.camera != INVALID_CAMERA_INDEX);
        camera = *cameras[patch_info.camera];
    } else {
        assert(patch_info.camera == INVALID_CAMERA_INDEX);
    }
}

is_creature_type :: (t: Entity_Type) -> bool {
    if t == {
    case .STATIC_MESH_CREATURE;
        return true;
    }
    return false;
}


spawn_entity :: (t: Entity_Type, subtype: Entity_Subtype, physics := Entity_Physics_Core.{}, phys_properties: *Entity_Physics_Properties, make_physics_properties_dynamic := false) -> Entity_Ref {
    scope_lock_mutex(*spawn_entity_mutex);
    i := request_item(*entities);
    assert(i >= 0);

    entity_physics_core[i] = physics;

    mesh_array := *entity_mesh_arrays[i];
    mesh_array.count = 0;
    mesh_array.data = null;

    entity_id_counter += 1;
    new_id := entity_id_counter;

    e := get_item(*entities, i);
    e.* = .{
        type = t,
        subtype = subtype,
        ref = .{xx i, xx new_id},
    };

    phys_props_index := phys_properties - entity_physics_properties.items.data;
    assert(is_item_in_use(*entity_physics_properties, phys_props_index));
    phys_props := get_item(*entity_physics_properties, phys_props_index);
    use_index: s64 = phys_props_index;

    if make_physics_properties_dynamic {
        use_index = request_item(*entity_physics_properties);   
        phys_props = get_item(*entity_physics_properties, use_index);
        phys_props.* = phys_properties.*;
    }
    e.physics_properties = xx use_index;

    return e.ref;
}

entities: Pool(Entity_Patch_Info);
entity_patch_layer: []*Entity_Patch_Info;
// default entity data
entity_physics_core: []Entity_Physics_Core;
entity_mesh_arrays: [][]*Mesh;
entity_mesh_array_allocator: Nesting_Allocator;
// type-specific entity data
creature_interface: []*Entity_Creature;
creatures: Pool(Entity_Creature);
cameras: [256]Camera;
entity_physics_properties: Pool(Entity_Physics_Properties);

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

rotate :: inline (e: *Entity, axis: Vector3, angle_degrees: float32) {
    rotate(*e.orientation, axis, angle_degrees);
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
