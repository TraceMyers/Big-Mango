
// Flag_Array flags.
Entity_Flags :: enum {
    // ========================================================================== static type description
    USES_CAMERA;
    USES_AI;
    USES_EVENT_VOLUME;
    USES_GADGET;
    IS_PRIMITIVE_SHAPE;

    // ========================================================================== behavior description
    PHYSICS_DRIVEN_ROTATION;
    APPLY_GRAVITY;
    ACCELERATE_IN_3D;
    APPLY_AIR_FRICTION;
    PLAYER_ENTITY_THINK;
    CAN_INTERACT_WITH_GADGETS_IN_PROXIMITY;
    EVENT_VOLUME_OFFSET_IS_LOCAL;
    MOVED_BY_PHYSICS;
    GADGET_ALWAYS_ACTIVE;
    GADGET_FORCE_INTERACTIONS_AS_PARENT;
    GADGET_ALLOW_PARENT_TO_FORCE_INTERACTIONS;
    DOES_NOT_DIE_TO_Z_FLOOR;
    CAN_BE_HELD;
    BUILD_MODE_IGNORE_CLICK_RAYCAST;

    // ========================================================================== reset per frame
    COLLIDING_WITH_SOMETHING;
    CHANGED_CELL_OCCUPATIONS;

    // ========================================================================== events / uncertain lifetime
    USE_INTERACTION_QUEUED;
    GADGET_EVENT_VOLUME_IS_OVERLAPPED;
    GADGET_WORKING;

    // ========================================================================== one time
    JUST_SPAWNED;
    QUEUED_FOR_DELETION;

    // ========================================================================== debug / development settings
    DRAW_COLLIDER_HEIGHT_LINE;
    NEVER_SHOW_COLLIDER_MESH;
}
