
call :: inline (handle: Proc_Handle, volume: *Entity, notify: *Entity, overlapping: *Entity) {
    call_impl(handle, Event_Volume_Overlap_Proc, volume, notify, overlapping);
}

Proc_Handle_Gen :: struct {
    proc_name: string;
    proc_type: Type;
    handle: s32;
}

// manually numbering the handles in case any ever need to be removed, it just continues to work
PROCEDURES_FOR_HANDLE_GENERATION :: Proc_Handle_Gen.[
    .{"on_gadget_event_volume_begin_overlap",   Event_Volume_Overlap_Proc, 1},
    .{"on_gadget_event_volume_end_overlap",     Event_Volume_Overlap_Proc, 2}
];

generate_procedure_handles :: () -> string {
    builder: String_Builder;
    print_to_builder(*builder, "Proc_Handle :: enum u16 {\n");
    handle_max: s32;
    for PROCEDURES_FOR_HANDLE_GENERATION {
        handle_name := to_upper_copy(it.proc_name);
        print_to_builder(*builder, "\t% :: %;\n", handle_name, it.handle);
        handle_max = max(handle_max, it.handle);
    }
    print_to_builder(*builder, "};\n\n");
    print_to_builder(*builder, "PROCEDURES: [%]*void;", handle_max + 1);
    return builder_to_string(*builder);
}
#insert #run generate_procedure_handles();

load_handle_procedure_array :: () {
    #insert -> string {
        builder: String_Builder;
        for PROCEDURES_FOR_HANDLE_GENERATION {
            handle_name := to_upper_copy(it.proc_name);
            print_to_builder(*builder, "PROCEDURES[Proc_Handle.%] = xx %;\n", handle_name, it.proc_name);
        }
        return builder_to_string(*builder);
    }
}

call_impl :: (handle: Proc_Handle, $proc_type: Type, $args: ..Code) #expand {
    assert(handle != 0);
    generate_body :: ($args: ..Code) -> string {
        builder: String_Builder; 
        print_to_builder(*builder, "(cast(proc_type) PROCEDURES[handle])(");
        for args {
            if it_index == args.count - 1 {
                print_to_builder(*builder, "`%);", code_string(it));
            } else {
                print_to_builder(*builder, "`%, ", code_string(it));
            }
        }
        return builder_to_string(*builder);
    }
    #insert #run generate_body(..args);
}