
// ai_update_proc :: #type (entity: *Entity);

entity_ai_updates :: () {
    // entity_ct := get_entity_count();
    // for 0..entity_ct-1 {
    //     e := get_entity_at(it);
    //     if e.ai.update != null {
    //         e.ai.update(e);
    //     }
    // }
}

scratch_ai_update :: (entity: *Entity) {
    log("e! %", entity.*);
    // {
        // using entity.ai;
        // input_oscillation_timer += delta_time;
        // if input_oscillation_timer >= input_oscillation_max_time {
        //     input_oscillation_timer -= input_oscillation_max_time;
        //     if input_direction == .UP {
        //         input_direction = .DOWN;
        //     } else if input_direction == .DOWN {
        //         input_direction = .UP;
        //     } else if input_direction == .RIGHT {
        //         input_direction = .LEFT;
        //     } else if input_direction == .LEFT {
        //         input_direction = .RIGHT;
        //     } else if input_direction == .FORE {
        //         input_direction = .BACK;
        //     } else {
        //         input_direction = .FORE;
        //     }
        // }
    // }

    // entity.linear_input = world_direction(entity.ai.input_direction);
}