
#add_context world: *World;

// generate an array containing all of the entity pointers on the context. useful for auto-applying inform logic to them, since the array is updated automatically.
// generate_context_entity_pointer_array :: () -> string {
//     builder: String_Builder;
//     context_type_info := context.base.context_info;

//     print_to_builder(*builder, "**Entity.[\n");
//     for context_type_info.members {
//         member_type := (*it.type).(*Type).*;
//         if member_type == *Entity {
//             print_to_builder(*builder, "\tnull,\n");
//         }
//     }
//     print_to_builder(*builder, "];\n");
//     return builder_to_string(*builder);
// }
// context_entity_pointers := #insert #run generate_context_entity_pointer_array();

// // set pointers to the context entity pointers
// entity_pointer_array_init :: () {
//     #insert -> string {
//         builder: String_Builder;
//         context_type_info := context.base.context_info;
//         array_index := 0;
//         for context_type_info.members {
//             member_type := (*it.type).(*Type).*;
//             if member_type == *Entity {
//                 print_to_builder(*builder, "\tcontext_entity_pointers[%] = *context.%;\n", array_index, it.name);
//                 array_index += 1;
//             }
//         }
//         return builder_to_string(*builder);
//     }
// }
