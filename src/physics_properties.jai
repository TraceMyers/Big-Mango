
IMMOVABLE_ENTITY_MASS :: 0.0;

PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS :: Enumarray_Create_Info.[
    .{
        "CAPSULE_MAN", .{
            mass = 1,
        }
    },
    .{
        "BOX_MAN", .{
            mass = 2,
        }
    },
    .{
        "SPHERE_MAN", .{
            mass = 2,
        }
    },
    .{
        "GROUND", .{
            mass = IMMOVABLE_ENTITY_MASS,
            body_elasticity = 0
        }
    },
    .{
        "CAMERA", .{
            default_collision_channels=0
        }
    }
];

MAX_MASS :: 8192.0;

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
    body_elasticity := 0.1;
    default_collision_channels: Collision_Channels = .DEFAULT;
}

Physics_Properties_Dynamic :: struct {
    template: Physics_Properties_Template;
    using #as base: Physics_Properties;
}

#insert #run define_enum(..PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS, "Physics_Properties_Template", u16);
#insert #run define_array(..PHYSICS_PROPERTY_TEMPLATE_CREATE_INFOS, "PHYSICS_PROPERTIES_TEMPLATES", Physics_Properties, true);

// the idea here is that two equally elastic things meeting each other should not bounce off of each other AND two inelastic things should not also bounce. this is achieved by mapping input to output like so:
// (0,0) -> 0; (1,1) -> 0; (1,0)-> 1; (0,1) -> 1
collision_bounciness :: (props_a: *Physics_Properties, props_b: *Physics_Properties) -> float {
    a := props_a.body_elasticity;
    b := -props_b.body_elasticity;
    assert(a >= 0 && a <= 1 && b <= 0 && b >= -1);
    return abs(a + b);
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

#import "Basic";
// Program_Print :: #import "Program_Print";
// Compiler :: #import "Compiler";

// _code_string :: ($code: Code, allocator := temp) -> string #expand {
//     builder: String_Builder;
//     builder.allocator = allocator;
//     assert(Program_Print.print_expression(*builder, Compiler.compiler_get_nodes(code)));
//     return builder_to_string(*builder);
// }
