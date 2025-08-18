INVALID_ENTITY_ID : u32 : 0;
INVALID_ENTITY_INDEX : u32 : U32_MAX;
INVALID_CAMERA_INDEX : u8  : U8_MAX;

ENTITY_MAX_COUNT :: 2_000;
CAMERA_MAX_COUNT :: 64;
ENTITY_MESHES_MAX_COUNT :: 8;
ENTITY_NAME_MAX_CHAR_COUNT :: 64;
LINEAR_IMPULSES_MAX_COUNT :: 128;
DEFAULT_LINEAR_IMPULSE_DURATION :: 1.0 / 90.0;
IMMOVABLE_ENTITY_MASS :: 0.0;
MAX_GADGET_CHILDREN_COUNT :: 256;

EVENT_OVERLAP_ALLOCATOR_MIN_BLOCK_SIZE :: 16;
NAME_ALLOCATOR_MIN_BLOCK_SIZE :: 8;
MESHES_ALLOCATOR_MIN_BLOCK_SIZE :: 16;
LINEAR_IMPULSES_ALLOCATOR_MIN_BLOCK_SIZE :: 16;
GADGET_INTERACTION_ALLOCATOR_MIN_BLOCK_SIZE :: #run ceil_to_pow2(size_of(Gadget_Interaction));
GADGET_CHILD_ALLOCATOR_MIN_BLOCK_SIZE :: #run ceil_to_pow2(size_of(Gadget_Child));

INVALID_COLLISION_CELL_HASH : s64 : -1;

Think_Proc :: #type (*Entity);

Entity :: struct {
    flags: Long_Flag_Array(Entity_Flags);
    using ref: Entity_Ref;
    using camera: Camera;
    using body: Physics_Body;
    using controller: Controller;
    using gadget: Gadget;
    ai: AI;
    event_volume: Event_Volume;

    collision_mesh_albedo: Mesh_Albedo;

    holding_entity: Entity_Ref;
    attached_camera: Entity_Ref;

    name: Nested_Array(string, NAME_ALLOCATOR_MIN_BLOCK_SIZE);
    meshes: Nested_Array(Mesh_Instance, MESHES_ALLOCATOR_MIN_BLOCK_SIZE);
    linear_impulses: Nested_Array(Linear_Physics_Impulse, LINEAR_IMPULSES_ALLOCATOR_MIN_BLOCK_SIZE);

    frame_counter: s32;
}

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

entity_frame_turnover :: () {
    flush_entity_deletion_queue();
    for *e : context.world.entities {
        e.frame_counter += 1;
    }
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
    using context.world;
    i := entity_ref_layer[ref.index];
    entity := *entities[i];
    assert(entity.id == ref.id);
    return entity;
}

try_get_entity :: inline (ref: *Entity_Ref) -> *Entity {
    using context.world;
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
    using context.world;
    array_set(*e.name, *name_allocator, name);
}

set_meshes :: inline (e: *Entity, meshes: []Mesh_Instance) {
    using context.world;
    array_set(*e.meshes, *meshes_allocator, meshes);
}

add_linear_impulse :: inline (e: *Entity, impulse: Linear_Physics_Impulse) {
    using context.world;
    array_add(*e.linear_impulses, *linear_impulses_allocator, impulse);
}

remove_linear_impulse_at :: inline (e: *Entity, i: s64) {
    using context.world;
    array_unordered_remove_by_index(*e.linear_impulses, *linear_impulses_allocator, xx i);
}

add_event_volume_overlap :: (e: *Entity, overlap: Entity_Ref) {
    using context.world;
    assert(e.ref != overlap);
    assert(is_set(*e.flags, .USES_EVENT_VOLUME));
    array_add(*e.event_volume.overlaps, *event_overlap_allocator, .{overlap, collision_frame, collision_frame});
}

remove_event_volume_overlap_at :: inline (e: *Entity, i: s64) {
    using context.world;
    assert(is_set(*e.flags, .USES_EVENT_VOLUME));
    array_unordered_remove_by_index(*e.event_volume.overlaps, *event_overlap_allocator, xx i);
}

add_gadget_interaction :: (e: *Entity, interaction: Gadget_Interaction) {
    using context.world;
    assert(is_set(*e.flags, .USES_GADGET));
    if e.gadget_interactions.field.count >= max_interactions(e.gadget_type) {
        return;
    }
    array_add(*e.gadget_interactions, *gadget_interaction_allocator, interaction);
}

remove_gadget_interaction_at :: inline (e: *Entity, i: s64) {
    using context.world;
    assert(is_set(*e.flags, .USES_GADGET));
    array_ordered_remove_by_index(*e.gadget_interactions, *gadget_interaction_allocator, xx i);
}

remove_all_gadget_interactions :: (e: *Entity) {
    using context.world;
    if e.gadget_interactions.allocation.count > 0 {
        array_resize(*e.gadget_interactions, *gadget_interaction_allocator, 0);
    }
}

remove_all_linear_impulses :: inline (e: *Entity) {
    using context.world;
    if e.linear_impulses.allocation.count > 0 {
        array_resize(*e.linear_impulses, *linear_impulses_allocator, 0);
    }
}

add_gadget_child :: (e: *Entity, child: Gadget_Child) {
    using context.world;
    assert(is_set(*e.flags, .USES_GADGET));
    if e.gadget_children.field.count >= MAX_GADGET_CHILDREN_COUNT {
        return;
    } 
    array_add(*e.gadget_children, *gadget_children_allocator, child);
}

remove_gadget_child_at :: (e: *Entity, i: s64) {
    using context.world;
    assert(is_set(*e.flags, .USES_GADGET));
    array_unordered_remove_by_index(*e.gadget_children, *gadget_children_allocator, xx i);
}

set_orientation :: (e: *Entity, new_orientation: Quaternion) {
    e.orientation = new_orientation;
    get_axes(e.orientation, *e.axes.fore, *e.axes.up, *e.axes.right);
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

interp_rotate :: (e: *Entity, origin: Quaternion, target: Quaternion, norm: float32) {
    e.orientation = interp_rotate(origin, target, norm);
    get_axes(e.orientation, *e.axes.fore, *e.axes.up, *e.axes.right);
}

interp_rotate :: (e: *Entity, origin: Quaternion, target: Quaternion, speed: float32, delta_time: float32) {
    e.orientation = interp_rotate(origin, target, speed, delta_time);
    get_axes(e.orientation, *e.axes.fore, *e.axes.up, *e.axes.right);
}

queue_entity_deletion :: (ref: Entity_Ref) {
    ref_copy := ref;
    e := try_get_entity(*ref_copy);
    // NOTE: a bug could happen here where if the entity is flagged, (but due to another bug never removed,) it can't be removed.
    // that's probably okay since it might make the failed removal bug more obvious.
    assert(e != null);
    if is_set(*e.flags, .QUEUED_FOR_DELETION) {
        return;
    }
    set(*e.flags, .QUEUED_FOR_DELETION);
    for context.world.entity_deletion_queue {
        assert(it.id != e.ref.id);
    }
    array_add(*context.world.entity_deletion_queue, e.ref);
}

flush_entity_deletion_queue :: () {
    for context.world.entity_deletion_queue {
        delete_entity(it);
    }
    array_reset(*context.world.entity_deletion_queue);
}

// ------------------------------------------------------------------------------------------------------------- components

Controller :: struct {
    linear_input: Vector3;
}

Mesh_Instance :: struct {
    data: *Mesh;
    albedo: Mesh_Albedo;
    scale := VECTOR3_ONES;
    offset: Vector3;
    orientation := Quaternion.{};
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
    air_friction_multiplier := 1.0;
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
    ray_channels: Ray_Channels = ALL_RAY_CHANNELS;
    overlap_channels: Overlap_Channels;
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

Gadget_Type :: enum {
    DOOR :: 0x1;
    BUTTON;
}

is_gadget_active :: inline (gadget: *Entity) -> bool {
    return are_any_set(*gadget.flags, .[.GADGET_EVENT_VOLUME_IS_OVERLAPPED, .GADGET_WORKING, .GADGET_ALWAYS_ACTIVE]) || gadget.gadget_interactions.field.count > 0;
}

gadget_can_take_interaction :: (using e: *Entity, interactionist: *Entity, is_parent_to_child_interaction := false) -> bool {
    if is_parent_to_child_interaction {
        if is_set(*e.flags, .GADGET_ALLOW_PARENT_TO_FORCE_INTERACTIONS) || is_set(*interactionist.flags, .GADGET_FORCE_INTERACTIONS_AS_PARENT) {
            return true;
        }
    } 

    if !is_gadget_active(e) {
        return false;
    }
    if gadget_interactions.field.count >= max_interactions(gadget_type) {
        return false;
    }

    interaction_volume := get_entity(*gadget_interaction_volume);
    assert(is_set(*interaction_volume.flags, .USES_EVENT_VOLUME));
    for interaction_volume.event_volume.overlaps.field {
        if it.entity == interactionist.ref {
            return true;
        }
    }
    return false;
}

Gadget_Interaction_Flags :: enum_flags u32 {

}

Gadget_Interaction :: struct {
    using input: struct {
        source_entity: Entity_Ref;
        source_location: Vector3;
        end_time: float;
        flags: Gadget_Interaction_Flags = 0;
    }
    begin_time: float;
}

Gadget_Child :: struct {
    entity: Entity_Ref;
}

// $todo: delays should be combinable. delays irl are serialized one after another.
Gadget_Interaction_Delay :: struct {
    type: enum {
        CONSTANT :: 0x0;
        BY_DISTANCE;
    }
    using value: union {
        constant := 0.0;
        by_distance: struct {
            constant: float = ---;
            time_per_unit: float = ---; // $todo: distance units?
        }
    }
}

get_gadget_interaction_delay_with_gadget :: (e: *Entity, interacting_with: *Entity) -> float {
    assert(is_set(*e.flags, .USES_GADGET));
    assert(is_set(*interacting_with.flags, .USES_GADGET));

    using e.delay_interacting_with_gadgets;

    if #complete type == {
    case .CONSTANT;
        return constant;
    case .BY_DISTANCE;
        return by_distance.constant + distance(e.center, interacting_with.center) * by_distance.time_per_unit;
    }
    return 0;
}

max_interactions :: (type: Gadget_Type) -> s32 {
    if #complete type == {
    case .DOOR;
        return 2;
    case .BUTTON;
        return 2;
    }
}

// a gadget is an interaction point with a box range and functionality attached
// gadgets can have children; when gadgets are interacted with, they try to interact with their children. this allows for creating a network of interactions, or a loop, even.
// the constraints and properties of the interaction are decided by the gadget think proc
Gadget :: struct {
    gadget_type: Gadget_Type;
    using gadget_data: union {
        door: Door;
        button: Button;
    }
    gadget_interaction_volume: Entity_Ref;
    gadget_interactions: Nested_Array(Gadget_Interaction, GADGET_INTERACTION_ALLOCATOR_MIN_BLOCK_SIZE);
    gadget_children: Nested_Array(Gadget_Child, GADGET_CHILD_ALLOCATOR_MIN_BLOCK_SIZE);    
    delay_interacting_with_gadgets: Gadget_Interaction_Delay;
}

Door :: struct {
    pivot_location: Vector3;
    closed_orientation := QUATERNION_IDENTITY;
    pivot_local_offset: Vector3;
    pivot_axis := WORLD_UP;
    rotation_speed := PI / 2;
    rotation_angle := PI / 2;
    rotation_distance: float;
    interaction_location: Vector3;
    state: enum u8 {
        CLOSED;
        OPEN_POSITIVE;
        OPEN_NEGATIVE;
        OPENING_NEGATIVE;
        OPENING_POSITIVE;
        CLOSING_POSITIVE;
        CLOSING_NEGATIVE;
    }
    auto_reset_to_closed: bool;
}

Button :: struct {
    press_distance := 0.28;
    cycle_time_max := 0.3; // how long to complete a full press cycle
    cycle_time_cur: float;
}

// may pass null in for 'overlapping'. that indicates that the entity left the volume on the same frame they were destroyed.
Event_Volume_Overlap_Proc :: #type (volume: *Entity, notify: *Entity, overlapping: *Entity);

Event_Overlap :: struct {
    entity: Entity_Ref;
    begin_overlap_frame: s32;
    last_seen_on_frame: s32;
}

// uses the bounding box of the entity's collision shape for detecting aabb-aabb overlaps. so, pretty imprecise but that's typically fine for a trigger volume, or as I feel like calling it, an event volume. because it's an event.
// if attached_to is not set, the event volume will delete itself.
Event_Volume :: struct {
    on_begin_overlap: Event_Volume_Overlap_Proc;
    on_end_overlap: Event_Volume_Overlap_Proc;
    attached_to: Entity_Ref;
    offset_from_attachment: Vector3;
    overlaps: Nested_Array(Event_Overlap, EVENT_OVERLAP_ALLOCATOR_MIN_BLOCK_SIZE);
}

set_event_volume_center :: inline (volume: *Entity, relative_to: *Entity, offset: Vector3) {
    if is_set(*volume.flags, .EVENT_VOLUME_OFFSET_IS_LOCAL) {
        volume.center = relative_to.center + local_to_world(offset, relative_to.axes);
    } else {
        volume.center = relative_to.center + offset;
    }
}

update_event_volumes :: () {
    using context.world;
    for *e : entities {
        if !is_set(*e.flags, .USES_EVENT_VOLUME) {
            continue;
        }

        using e.event_volume;
        
        attached_to_entity := try_get_entity(*attached_to);
        if attached_to_entity == null {
            queue_entity_deletion(e.ref);     
            continue;
        }
        // attached to an entity, so move with it.
        set_event_volume_center(e, attached_to_entity, offset_from_attachment);
        if overlaps.field.count == 0 {
            continue;
        }

        any_overlaps_can_interact: bool;

        for #v2 < 0..overlaps.field.count-1 {
            overlap := *overlaps.field[it];
            if overlap.begin_overlap_frame == collision_frame {
                if on_begin_overlap != null {
                    other_entity := try_get_entity(*overlap.entity);
                    on_begin_overlap(e, attached_to_entity, other_entity);
                }
            } else if overlap.last_seen_on_frame != collision_frame {
                other_entity := try_get_entity(*overlap.entity);
                remove_event_volume_overlap_at(e, it);
                if on_end_overlap != null {
                    // may pass null in. that indicates that the entity left the volume on the same frame they were destroyed.
                    on_end_overlap(e, attached_to_entity, other_entity);
                }
            }
        }
    }
}
