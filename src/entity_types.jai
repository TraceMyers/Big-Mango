
Entity_Patch_Info :: struct {
    type: Entity_Type;
    using patch: Entity_Patch_Type_Union;
    using ref: Entity_Ref;
    physics_properties: u16;
    meshes: u16;
    camera: u8 = INVALID_CAMERA_INDEX;
    flags: Entity_Flags = 0;
}

Entity :: struct {
    type: Entity_Type;
    using patch: Entity_Patch_Type_Union;
    using camera: *Entity_Camera;
    using ref: Entity_Ref;
    using body: *Collision_Body;
    using movement: *Entity_Movement;
    using angular_body: *Angular_Body;
    compressed_axes: *Compressed_Axes;
    physics_properties: *Physics_Properties;
    meshes: []Entity_Mesh;
    name: string;
    generation: s32 = -1;
    using data: *Entity_Data;
}

// ----------------------------------------------------------------------------------------------------------------- flags

// keep this below 16 flags. it's the law.
Entity_Patch_Flags :: enum_flags u16 {
    CAMERA;
    STATIC_MESH;
}

Entity_Patch_Type :: enum u16 {
    CAMERA :: Entity_Patch_Flags.CAMERA;
    STATIC_MESH :: Entity_Patch_Flags.STATIC_MESH;
}

Entity_Patch_Type_Union :: union {
    patch_type: Entity_Patch_Type = 0;
    patch_flags: Entity_Patch_Flags = ---;
}

ALL_ENTITY_PATCH_FLAGS :: #run -> Entity_Patch_Flags {
    ti := type_info(Entity_Patch_Flags);
    all: Entity_Patch_Flags;
    for ti.names {
        all |= xx ti.values[it_index];
    }
    return all;
}

Entity_Flags :: enum_flags u32 {
    DYNAMIC_PHYSICS_PROPERTIES;
    JUST_SPAWNED;
    COLLIDING_WITH_SOMETHING;
}

Entity_Type :: enum u16 {
    // parts of the world that don't move and aren't interactable
    STATIC_ENVIRONMENT;
    // parts of the world that may move but aren't interactable
    DYNAMIC_ENVIRONMENT;
    CAMERA;
    PERSON;
}

// ------------------------------------------------------------------------------------------------------------- components

Entity_Movement_Flags :: enum_flags u32 {
    MOVED_BY_PHYSICS;
    JUMP_QUEUED;
    ON_GROUND;
    ACCELERATE_IN_3D;
    CONTROL_ATTACHED_CAMERA;
    MOVE_RELATIVE_TO_CAMERA;
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

AI :: struct {
    update: ai_update_proc;

    input_oscillation_timer: float;
    input_oscillation_max_time: float;
    input_direction := Direction.UP;
}

// one-big-struct for everything else, until a component is begging to be split off
Entity_Data :: struct {
    ai: AI;
    attached_camera: Entity_Ref;
}