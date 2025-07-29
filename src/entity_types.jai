
Entity_Patch_Info :: struct {
    using type_union: Entity_Type_Flags_Union;
    using ref: Entity_Ref;
    physics_properties: u16;
    meshes: u16;
    device: u16 = INVALID_DEVICE_INDEX;
    camera: u8 = INVALID_CAMERA_INDEX;
    flags: Entity_Patch_Flags = 0;
}

Entity :: struct {
    using type_union: Entity_Type_Flags_Union;
    using camera: *Entity_Camera;
    using ref: Entity_Ref;
    using body: *Collision_Body;
    using movement: *Entity_Movement;
    using angular_body: *Angular_Body;
    compressed_axes: *Compressed_Axes;
    physics_properties: *Physics_Properties;
    meshes: []Entity_Mesh;
    device: *Entity_Device;
    name: string;
    generation: s32 = -1;
}

// ----------------------------------------------------------------------------------------------------------------- flags

Entity_Type_Flags :: enum_flags u32 {
    CAMERA::1;
    STATIC_MESH;
    DEVICE;
}

Entity_Type :: enum u32 {
    CAMERA :: Entity_Type_Flags.CAMERA;
    STATIC_MESH :: Entity_Type_Flags.STATIC_MESH;
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
    DYNAMIC_PHYSICS_PROPERTIES;
    JUST_SPAWNED;
    COLLIDING_WITH_SOMETHING;
}

Entity_Type_Flags_Union :: union {
    type: Entity_Type = 0;
    type_flags: Entity_Type_Flags = ---;
}

// -------------------------------------------------------------------------------------------------------- component flags

Entity_Device_Type :: enum u16 {
    DEVICE;
    BUTTON;
}

// ------------------------------------------------------------------------------------------------------------- components

Entity_Movement_Flags :: enum_flags u32 {
    MOVED_BY_PHYSICS;
    JUMP_QUEUED;
    ON_GROUND;
    ACCELERATE_IN_3D;
}

Entity_Movement :: struct {
    linear_input: Vector3;
    jump_queued_at_time: float;
    movement_flags: Entity_Movement_Flags;
}

ENTITY_MOVEMENT_PER_FRAME_FLAGS : Entity_Movement_Flags : .ON_GROUND;

Entity_Mesh_Collection :: struct {
    allocation_ref: Nested_Allocation_Ref;
    mesh_count: s32;
}

Entity_Name_Allocation :: struct {
    allocation_ref: Nested_Allocation_Ref;
    count: s32;
}

Trigger_Volume_Allocation :: struct {
    allocation_ref: Nested_Allocation_Ref;
    count: s32;
}

Entity_Mesh :: struct {
    data: *Mesh;
    albedo: Mesh_Albedo;
}

Angular_Body :: struct {
    orientation: Quaternion = QUATERNION_IDENTITY;
    angular_velocity: Vector3;
}

Trigger_Volume_Proc :: #type (owner: *Entity, guest: *Entity);

Trigger_Volume :: struct {
    position: Vector3;
    orientation: Quaternion;
    shape: Collision_Shape;
    on_enter: Trigger_Volume_Proc;
    on_exit: Trigger_Volume_Proc;
    overlap_mode: enum u8 {
        VOLUME_WITH_AABB;
        VOLUME_WITH_VOLUME;
    };
    flags: enum_flags u8 {
        POSITION_IS_ABSOLUTE :: 0x1; // else relative
        ORIENTATION_IS_ABSOLUTE; // else relative
    };
    // just for whatever. might as well make use of the padding.
    extra_data: [6]u8;
}

Entity_Device :: struct {
    type: Entity_Device_Type;
}
