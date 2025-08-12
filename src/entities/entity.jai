INVALID_ENTITY_ID : u32 : 0;
INVALID_ENTITY_INDEX : u32 : U32_MAX;
INVALID_CAMERA_INDEX : u8  : U8_MAX;

ENTITY_MAX_COUNT :: 20_000;
CAMERA_MAX_COUNT :: 64;
ENTITY_MESHES_MAX_COUNT :: 8;
ENTITY_NAME_MAX_CHAR_COUNT :: 64;
LINEAR_IMPULSES_MAX_COUNT :: 128;
DEFAULT_LINEAR_IMPULSE_DURATION :: 1.0 / 90.0;
IMMOVABLE_ENTITY_MASS :: 0.0;

NAME_ALLOCATOR_MIN_BLOCK_SIZE :: 8;
MESHES_ALLOCATOR_MIN_BLOCK_SIZE :: 16;
LINEAR_IMPULSES_ALLOCATOR_MIN_BLOCK_SIZE :: 16;
INVALID_COLLISION_CELL_HASH : s64 : -1;

Think_Proc :: #type (*Entity);

Entity :: struct {
    flags: Long_Flag_Array(Entity_Flags);
    using ref: Entity_Ref;
    using camera: Camera;
    using body: Physics_Body;
    using controller: Controller;
    ai: AI;

    think_proc: Think_Proc;

    frame_counter: s32;

    holding_entity: Entity_Ref;
    attached_camera: Entity_Ref;
    // todo: look_forward for anything controllable?

    name: Nested_Array(string, NAME_ALLOCATOR_MIN_BLOCK_SIZE);
    meshes: Nested_Array(Mesh_Instance, MESHES_ALLOCATOR_MIN_BLOCK_SIZE);
    linear_impulses: Nested_Array(Linear_Physics_Impulse, LINEAR_IMPULSES_ALLOCATOR_MIN_BLOCK_SIZE);
}

entities: [..]Entity;
entity_removal_queue: [..]Entity_Ref;
entity_ref_layer: Pool(s32);
entity_id_counter: u32;

name_allocator: Nesting_Allocator(NAME_ALLOCATOR_MIN_BLOCK_SIZE);
meshes_allocator: Nesting_Allocator(MESHES_ALLOCATOR_MIN_BLOCK_SIZE);
linear_impulses_allocator: Nesting_Allocator(LINEAR_IMPULSES_ALLOCATOR_MIN_BLOCK_SIZE);

Entity_Ref :: struct {
    index: s32;
    id: u32;
}

is_null :: (ref: Entity_Ref) -> bool {
    return ref.id == 0;
}

operator == :: inline (a: Entity_Ref, b: Entity_Ref) -> bool {
    return a.index == b.index && a.id == b.id;
}

_entities :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        program_runtime_reserve(*entities, ENTITY_MAX_COUNT);
        program_runtime_initialize(*entity_ref_layer, ENTITY_MAX_COUNT);

        na_chunk_list_size := 4096 * 16;
        na_chunk_list_size_large := 4096 * 32;
        mesh_ptrs_array_data_size := ENTITY_MAX_COUNT * ENTITY_MESHES_MAX_COUNT * size_of(Mesh_Instance);
        program_runtime_initialize(*meshes_allocator, na_chunk_list_size, mesh_ptrs_array_data_size);
        entity_name_data_size := ENTITY_MAX_COUNT * ENTITY_NAME_MAX_CHAR_COUNT;
        program_runtime_initialize(*name_allocator, na_chunk_list_size, entity_name_data_size);
        linear_impulse_array_data_size := ENTITY_MAX_COUNT * size_of(Linear_Physics_Impulse) * 2;
        program_runtime_initialize(*linear_impulses_allocator, na_chunk_list_size_large, linear_impulse_array_data_size);

        entity_removal_queue.allocator = temp;
    }
    return true;
}

entity_frame_turnover :: () {
    flush_entity_removal_queue();
}

look_origin :: (e: *Entity) -> Vector3 {
    attached_camera := try_get_entity(*e.attached_camera);
    // todo: ai look location
    if attached_camera {
        return attached_camera.center;
    } else {
        return e.center;
    }
}

look_direction :: (e: *Entity) -> Vector3 {
    attached_camera := try_get_entity(*e.attached_camera);
    // todo: ai look direction
    if attached_camera {
        return attached_camera.axes.fore;
    } else {
        return e.axes.fore;
    }
}

set_shape_and_mass :: (e: *Entity, shape: Collision_Shape, mass := 1.0) {
    e.shape = shape;
    e.physics_properties.mass = mass;

    assert(mass >= 0);
    if mass == 0 {
        assert(IMMOVABLE_ENTITY_MASS == 0); // just checking...
        assert(mass == IMMOVABLE_ENTITY_MASS);
        e.inv_inertia_tensor = Matrix3_Identity;
        return;
    }

    invert_success: bool;
    if shape.type == {
    case .SPHERE;
        using shape.sphere;
        uniform_inertia := (2.0 / 5.0) * mass * square(radius);
        invert_success, e.inv_inertia_tensor = inverse(Matrix3.{_11=uniform_inertia, _22=uniform_inertia, _33=uniform_inertia});
    case .CAPSULE;
        e.inv_inertia_tensor = .{};
    case .RECT;
        using shape.rect;
        ONE_OVER_TWELVE :: 1.0 / 12.0;
        // rects are default facing along the y axis
        Y_DEPTH_SQ := VERY_SMALL_NUMBER;
        moment_xx := mass * (square(shape.half_height) + Y_DEPTH_SQ) * ONE_OVER_TWELVE;
        moment_yy := mass * (square(half_width) + square(shape.half_height)) * ONE_OVER_TWELVE;
        moment_zz := mass * (square(half_width) + Y_DEPTH_SQ) * ONE_OVER_TWELVE;
        invert_success, e.inv_inertia_tensor = inverse(Matrix3.{_11=moment_xx, _22=moment_yy, _33=moment_zz});
    case .BOX; #through;
    case .AABB;
        using shape.box;
        ONE_OVER_TWELVE :: 1.0 / 12.0;
        moment_xx := mass * (square(shape.half_height) + square(half_length)) * ONE_OVER_TWELVE;
        moment_yy := mass * (square(half_width) + square(shape.half_height)) * ONE_OVER_TWELVE;
        moment_zz := mass * (square(half_width) + square(half_length)) * ONE_OVER_TWELVE;
        invert_success, e.inv_inertia_tensor = inverse(Matrix3.{_11=moment_xx, _22=moment_yy, _33=moment_zz});
    case .HALF_SPACE;
        e.inv_inertia_tensor = .{};
    }

    assert(invert_success);
}

get_entity :: (ref: Entity_Ref) -> *Entity {
    i := entity_ref_layer[ref.index];
    entity := *entities[i];
    assert(entity.id == ref.id);
    return entity;
}

try_get_entity :: inline (ref: *Entity_Ref) -> *Entity {
    if ref.index >= entity_ref_layer.items.count {
        ref.* = .{};
        return null;
    }
    if !is_item_in_use(*entity_ref_layer, ref.index) {
        ref.* = .{};
        return null;
    }
    i := entity_ref_layer[ref.index];
    entity := *entities[i];
    if entity.id != ref.id {
        ref.* = .{};
        return null;
    }
    return entity;
}

set_name :: inline (e: *Entity, name: string) {
    array_set(*e.name, *name_allocator, name);
}

set_meshes :: inline (e: *Entity, meshes: []Mesh_Instance) {
    array_set(*e.meshes, *meshes_allocator, meshes);
}

add_linear_impulse :: inline (e: *Entity, impulse: Linear_Physics_Impulse) {
    array_add(*e.linear_impulses, *linear_impulses_allocator, impulse);
}

remove_linear_impulse_at :: inline (e: *Entity, i: s64) {
    array_unordered_remove_by_index(*e.linear_impulses, *linear_impulses_allocator, xx i);
}

remove_all_linear_impulses :: inline (e: *Entity) {
    if e.linear_impulses.allocation.count > 0 {
        array_resize(*e.linear_impulses, *linear_impulses_allocator, 0);
    }
}

set_orientation :: (e: *Entity, forward: Vector3, up: Vector3) {
    set_orientation(*e.orientation, forward, up);
    e.axes.fore = forward;
    e.axes.up = up;
    e.axes.right = normalize(cross(forward, up));
}

rotate :: (e: *Entity, axis: Vector3, angle: float32) {
    rotate(*e.orientation, axis, angle);
    get_axes(e.orientation, *e.axes.fore, *e.axes.up, *e.axes.right);
}

fore_direction_xy :: inline (e: *Entity) -> Vector2 {
    return normalize(e.axes.fore.xy);
}

right_direction_xy :: inline (e: *Entity) -> Vector2 {
    return normalize(e.axes.right.xy);
}

interp_rotate :: (e: *Entity, target: Quaternion, norm: float32) {
    e.orientation = interp_rotate(e.orientation, target, norm);
    get_axes(e.orientation, *e.axes.fore, *e.axes.up, *e.axes.right);
}

interp_rotate :: (e: *Entity, target: Quaternion, speed: float32, delta_time: float32) {
    e.orientation = interp_rotate(e.orientation, target, speed, delta_time);
    get_axes(e.orientation, *e.axes.fore, *e.axes.up, *e.axes.right);
}

queue_entity_removal :: (ref: Entity_Ref) {
    ref_copy := ref;
    e := try_get_entity(*ref_copy);
    // NOTE: a bug could happen here where if the entity is flagged, (but due to another bug never removed,) it can't be removed.
    // that's probably okay since it might make the failed removal bug more obvious.
    assert(e != null);
    if is_set(*e.flags, .QUEUED_FOR_DELETION) {
        return;
    }
    set(*e.flags, .QUEUED_FOR_DELETION);
    for entity_removal_queue {
        assert(it != e.ref);
    }
    array_add(*entity_removal_queue, e.ref);
}

flush_entity_removal_queue :: () {
    for entity_removal_queue {
        remove_entity(it);
    }
    array_reset(*entity_removal_queue);
}

// ----------------------------------------------------------------------------------------------------------------- flags

// Long_Flag_Array flags.
Entity_Flags :: enum {
    USES_CAMERA;
    USES_AI;
    // spawning
    JUST_SPAWNED;
    // physics
    MOVED_BY_INPUT;
    MOVED_BY_PHYSICS;
    PHYSICS_DRIVEN_ROTATION;
    APPLY_GRAVITY;
    // collisions
    COLLIDING_WITH_SOMETHING;
    CHANGED_CELL_OCCUPATIONS;
    // movement
    ACCELERATE_IN_3D;
    // debug draw
    DRAW_COLLIDER_HEIGHT_LINE;
    QUEUED_FOR_DELETION;
    
    USE_INTERACTION_QUEUED;
}

// ------------------------------------------------------------------------------------------------------------- components

Controller :: struct {
    linear_input: Vector3;
}

Mesh_Instance :: struct {
    data: *Mesh;
    albedo: Mesh_Albedo;
}

AI :: struct {
    input_oscillation_timer: float;
    input_oscillation_max_time: float;
    input_direction := Direction.UP;

    holding_entity: Entity_Ref;
}

Linear_Physics_Impulse :: struct {
    force: Vector3;
    time_remaining := DEFAULT_LINEAR_IMPULSE_DURATION;
}

Physics_Properties :: struct {
    mass := 1.0;
    friction_bias := 0.0;
    // todo: linear accel discrete (or continuous?) function
    friction_multiplier := 1.0;
    linear_acceleration := 190.0;
    accel_opposite_direction_multiplier := 2.0;
    fast_start_speed_max := 5.0;
    fast_start_speed_multiplier := 3.0;
    linear_speed_max := 30.0;
    fall_speed_max := 100.0;
    gravity_accel := 150.0;
    jump_delta_velocity := 50.0;
    elasticity := 0.2;
}

// the boundaries of this data are set around whatever is needed to calculate collisions.
// this isn't world object model situation, but I still think "Body" is fitting.
Physics_Body :: struct {
    collision_channels: Collision_Channels = 0;
    center: Vector3;
    previous_center: Vector3;
    velocity: Vector3;
    shape: Collision_Shape;
    orientation: Quaternion = QUATERNION_IDENTITY;
    angular_velocity: Vector3;
    inv_inertia_tensor: Matrix3;
    collision_cell_hash: s64;
    axes: Axes;
    physics_properties: Physics_Properties;
}
