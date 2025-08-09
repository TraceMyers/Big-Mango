

// ----------------------------------------------------------------------------------------------------------------- flags

// Long_Flag_Array flags.
Entity_Flags :: enum {
    // spawning
    JUST_SPAWNED;
    // physics
    DYNAMIC_PHYSICS_PROPERTIES;
    PHYSICS_DRIVEN_ROTATION;
    APPLY_GRAVITY;
    // collisions
    COLLIDING_WITH_SOMETHING;
    CHANGED_CELL_OCCUPATIONS;
    SKIPPED_GRID_ITERATE;
    // movement
    MOVED_BY_PHYSICS;
    JUMP_QUEUED;
    ON_GROUND;
    ACCELERATE_IN_3D;
    CONTROL_ATTACHED_CAMERA;
    MOVE_RELATIVE_TO_CAMERA;
    // debug draw
    DRAW_COLLIDER_HEIGHT_LINE;
}

Entity_Component_Flags :: enum_flags u32 {
    CAMERA;
    DYNAMIC_PHYSICS_PROPERTIES;
}

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

Entity_Type :: enum u16 {
    // parts of the world that don't move and aren't interactable
    STATIC_ENVIRONMENT;
    // parts of the world that may move but aren't interactable
    DYNAMIC_ENVIRONMENT;
    CAMERA;
    PERSON;
}

// ------------------------------------------------------------------------------------------------------------- components

Entity_Movement :: struct {
    linear_input: Vector3;
}

ENTITY_MOVEMENT_PER_FRAME_FLAGS :: Entity_Flags.[.ON_GROUND];

Entity_Mesh :: struct {
    data: *Mesh;
    albedo: Mesh_Albedo;
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
    holding_entity: Entity_Ref;
}

Linear_Physics_Impulse :: struct {
    force: Vector3;
    time_remaining: float;
}