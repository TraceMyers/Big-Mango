
update_thinks :: () {
    for *e : entities {
        if e.think_proc != null {
            e.think_proc(e);
        }
    }
}

player_entity_think :: (e: *Entity) {
    holding_entity := try_get_entity(*e.holding_entity);
    if is_set(*e.flags, .USE_INTERACTION_QUEUED) {
        if holding_entity != null {
            set(*holding_entity.flags, .MOVED_BY_PHYSICS);
            set(*holding_entity.flags, .APPLY_GRAVITY);
            holding_entity.collision_channels = .DEFAULT;
            add_linear_impulse(holding_entity, .{look_direction(e) * 10_000.0 * holding_entity.physics_properties.mass, 1./100.0});
            e.holding_entity = .{};
        } else {
            request: Raycast_Request;
            result: Raycast_Result;
            request.ray = .{look_origin(e), look_direction(e)};
            if raycast(*request, *result) && !is_null(result.hit_entity) && result.hit_entity != e.ref {
                e.holding_entity = get_entity(result.hit_entity).ref;
            }
        }
        unset(*e.flags, .USE_INTERACTION_QUEUED);
    }
    holding_entity = try_get_entity(*e.holding_entity);
    if holding_entity != null {
        look_dir := look_direction(e);
        right_dir := normalize(cross(look_dir, WORLD_UP));
        up_dir := normalize(cross(look_dir, -right_dir));
        // todo: restore physics
        unset(*holding_entity.flags, .MOVED_BY_PHYSICS);
        unset(*holding_entity.flags, .APPLY_GRAVITY);
        holding_entity.collision_channels = 0;
        holding_entity.center = look_origin(e) + look_direction(e) * 15.0;
        holding_entity.velocity = .{};
        holding_entity.angular_velocity = .{};
    }
}