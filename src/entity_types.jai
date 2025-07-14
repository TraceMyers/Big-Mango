
Entity_Patch_Info :: struct {
    using type_union: Entity_Type_Flags_Union;
    camera: u8 = INVALID_CAMERA_INDEX;
    using ref: Entity_Ref;
    physics_properties: u16;
    body_collider: u16;
    meshes: u16;
    creature: u16 = INVALID_CREATURE_INDEX;
    device: u16 = INVALID_DEVICE_INDEX;
    flags: Entity_Patch_Flags;
}

Entity :: struct {
    using type_union: Entity_Type_Flags_Union;
    using camera: *Entity_Camera;
    using ref: Entity_Ref;
    using physics_core: *Entity_Physics_Core;
    physics_properties: *Physics_Properties;
    body_collider: *Entity_Collider;
    meshes: []Entity_Mesh;
    creature: *Entity_Creature;
    device: *Entity_Device;
    name: string;
}

// ----------------------------------------------------------------------------------------------------------------- flags

Entity_Type_Flags :: enum_flags u32 {
    CAMERA::1;
    STATIC_MESH;
    CREATURE;
    DEVICE;
}

Entity_Type :: enum u32 {
    CAMERA :: Entity_Type_Flags.CAMERA;
    STATIC_MESH :: Entity_Type_Flags.STATIC_MESH;
    STATIC_MESH_CREATURE :: (Entity_Type_Flags.STATIC_MESH | Entity_Type_Flags.CREATURE);
    STATIC_MESH_DEVICE  :: (Entity_Type_Flags.STATIC_MESH | Entity_Type_Flags.DEVICE);
}

ALL_ENTITY_TYPE_FLAGS :: #run -> Entity_Type_Flags {
    ti := type_info(Entity_Type_Flags);
    all: Entity_Type_Flags;
    for ti.names {
        all |= xx ti.values[it_index];
    }
    return all;
}

Entity_Patch_Flags :: enum_flags u32 {
    DYNAMIC_PHYSICS_PROPERTIES::1;
}

Entity_Type_Flags_Union :: union {
    type: Entity_Type = 0;
    type_flags: Entity_Type_Flags = ---;
}

// -------------------------------------------------------------------------------------------------------- component flags

Entity_Device_Type :: enum u16 {
    DEVICE :: 1;
}

Entity_Creature_Type :: enum u16 {
    CREATURE :: 1;
} 

// ------------------------------------------------------------------------------------------------------------- components

Entity_Physics_Core_Flags :: enum_flags u32 {
    MOVED_BY_PHYSICS :: 1;
    JUMP_QUEUED;
    ON_GROUND;
}

Entity_Physics_Core :: struct {
    position: Vector3;
    linear_velocity: Vector3;
    angular_velocity: Vector3;
    orientation: Quaternion;
    linear_input: Vector3;
    physics_flags: Entity_Physics_Core_Flags;
    jump_queued_at_time: float;
}

ENTITY_PHYSICS_PER_FRAME_FLAGS : Entity_Physics_Core_Flags : .ON_GROUND;

Entity_Mesh_Collection :: struct {
    allocation_ref: Nested_Allocation_Ref;
    mesh_count: s32;
}

Entity_Name_Allocation :: struct {
    allocation_ref: Nested_Allocation_Ref;
    count: s32;
}

Entity_Mesh :: struct {
    data: *Mesh;
    albedo: Mesh_Albedo;
}

// One-Big-Struct approach to creatures
Entity_Creature :: struct {
    type: Entity_Creature_Type;
}

Entity_Device :: struct {
    type: Entity_Device_Type;
}
