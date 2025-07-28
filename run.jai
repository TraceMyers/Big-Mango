
// ---------------------------------------------------------------------------------------------------------------------------
// --- config
// ---------------------------------------------------------------------------------------------------------------------------

RESET_ALL_BREAKPOINTS_FROM_VSCODE :: true;
EXPORT_VSCODE_BREAKPOINTS_TO_FILE :: true;

// ---------------------------------------------------------------------------------------------------------------------------
// --- local settings
// ---------------------------------------------------------------------------------------------------------------------------

VSCODE_SQL_DB_LOCATION_FOR_PROJECT :: "C:\\Users\\cauti\\AppData\\Roaming\\Code\\User\\workspaceStorage\\3d64ae3c42a87bc23230bc22a0e0e93c\\state.vscdb";

// ---------------------------------------------------------------------------------------------------------------------------

process_ended := false;

#run {
    set_build_options_dc(.{do_output=false});

    #if EXPORT_VSCODE_BREAKPOINTS_TO_FILE {
        export_vscode_breakpoints();
    }

    // run_thread: Thread;
    // thread_init(*run_thread, run_debugger_thread);
    // defer thread_deinit(*run_thread);
    // thread_start(*run_thread);

    #if RESET_ALL_BREAKPOINTS_FROM_VSCODE {
        sleep_milliseconds(500);
        run_command("raddbg", "--ipc", "clear_breakpoints");
        sleep_milliseconds(100);

        breakpoint_file_text, success := read_entire_file("tools/rad_debugger_interfacing/exported_breakpoints.txt");
        if success {
            send_add_breakpoint_command_to_raddbg :: (line: *string, line_index: s64, in_data: *void) {
                MIN_CHARACTERS_FOR_VALID_LINE :: 10;
                whitespace_stripped := trim(line.*);
                if whitespace_stripped.count < MIN_CHARACTERS_FOR_VALID_LINE then return;
                log("sending breakpoint to raddbg: %", whitespace_stripped);
                run_command("raddbg", "--ipc", "goto_line", "0");
                run_command("raddbg", "--ipc", "add_breakpoint", whitespace_stripped);
                sleep_milliseconds(100);
                // run_command("raddbg", "--ipc", "disable_breakpoint", whitespace_stripped);
                // sleep_milliseconds(100);
                // run_command("raddbg", "--ipc", "enable_breakpoint", whitespace_stripped);
                // sleep_milliseconds(100);
            }
            process_per_line(breakpoint_file_text, send_add_breakpoint_command_to_raddbg, null);
        } else {
            log("failed reading breakpoints file");
        }
        // sleep_milliseconds(500);
        // run_command("raddbg", "--ipc", "launch_and_run");
    }

    // while !process_ended {
    //     sleep_milliseconds(500);
    // }
}

// run_debugger_thread :: (t: *Thread) -> s64 {
//     run_command("raddbg", "-q", "bin/game");
//     process_ended = true;
//     return 0;
// }

export_vscode_breakpoints :: () {
    // anatomy of a set of breakpoints in a file in vscode:
    //
    // debug.breakpoint[
    // {"id":"40ea04da-37e1-47cb-90d0-36359150cb04","enabled":true,"uri":{"$mid":1,"fsPath":"d:\\dev\\homemade\\games\\Big-Mango\\src\\game.jai","_sep":1,"external":"file:///d%3A/dev/homemade/games/Big-Mango/src/game.jai","path":"/d:/dev/homemade/games/Big-Mango/src/game.jai","scheme":"file"},"lineNumber":19},
    // {"id":"1033894f-81f7-40c0-a26d-682f3bc742a2","enabled":true,"uri":{"$mid":1,"fsPath":"d:\\dev\\homemade\\games\\Big-Mango\\src\\game.jai","_sep":1,"external":"file:///d%3A/dev/homemade/games/Big-Mango/src/game.jai","path":"/d:/dev/homemade/games/Big-Mango/src/game.jai","scheme":"file"},"lineNumber":31},
    // {"id":"1d5bf266-9326-49ba-9bd9-0ef3191c021f","enabled":true,"uri":{"$mid":1,"fsPath":"d:\\dev\\homemade\\games\\Big-Mango\\src\\input.jai","_sep":1,"external":"file:///d%3A/dev/homemade/games/Big-Mango/src/input.jai","path":"/d:/dev/homemade/games/Big-Mango/src/input.jai","scheme":"file"},"lineNumber":28},
    // ]

    copy_file(VSCODE_SQL_DB_LOCATION_FOR_PROJECT, "tools/rad_debugger_interfacing/local_vscode_db");
    database_text, success := read_entire_file("tools/rad_debugger_interfacing/local_vscode_db");

    if !success {
        log("unable to export vscode breakpoints. can't find or open file %", VSCODE_SQL_DB_LOCATION_FOR_PROJECT);
        return;
    }

    breakpoints: [..]string; 

    collect_breakpoints :: (line: *string, line_index: s64, data: *void) {
        breakpoints := data.(*[..]string);

        i := 0;
        sanity_iter_max := 10_000;
        line_remaining := line.*;

        curly_braced_objects: [..]Curly_Braced_Object;
        defer clear_curly_braced_objects(*curly_braced_objects);

        while i < sanity_iter_max {
            defer i += 1;

            split_success, left, remain := split_from_left(line_remaining, "debug.breakpoint");
            if !split_success then return;
            if remain.count < 8 then return;
            if remain[0] != "[" then return;
            line_remaining = remain;

            // maybe multiple breakpoints (i think only if in same file)
            maybe_breakpoints_data, advance_count, success := get_substring_between_identifiers(line_remaining, #char "[", #char "]");
            if !success then return;

            array_reset_keeping_memory(*curly_braced_objects);

            collect_curly_braced_objects(maybe_breakpoints_data, *curly_braced_objects);

            infos: [..]Breakpoint_Info;
            for *curly_braced_objects {
                info := array_add(*infos);
                collect_breakpoint_from_curly_node(it, 0, info);
            }

            for info : infos {
                if info.fully_qualified_path.count > 0 && info.line_number.count > 0 && info.enabled {
                    array_add_if_unique(breakpoints, tprint("%:%", info.fully_qualified_path, info.line_number));
                }
            }

            advance_string(*line_remaining, advance_count);
        }
    }

    process_per_line(database_text, collect_breakpoints, *breakpoints);

    if breakpoints.count == 0 then return;

    builder: String_Builder;
    for breakpoints {
        if it_index == breakpoints.count-1 {
            print_to_builder(*builder, "%", it);
        } else {
            print_to_builder(*builder, "%\n", it);
        }
    }

    write_entire_file("tools/rad_debugger_interfacing/exported_breakpoints.txt", *builder);
}

get_substring_between_identifiers :: (str: string, begin_identifier: u8, end_identifier: u8) -> substring: string, traversed_ct: s64, success: bool {
    begin := find_index_from_left(str, begin_identifier);
    if begin == -1 then return "", 0, false;
    begin += 1;
    if begin >= str.count-1 then return "", 0, false;
    end := -1;

    begin_identifier_ct := 1;
    end_identifier_ct := 0;
    for begin..str.count-1 {
        if str[it] == begin_identifier {
            begin_identifier_ct += 1;
        } else if str[it] == end_identifier {
            end_identifier_ct += 1;
        }
        if end_identifier_ct == begin_identifier_ct {
            end = it;
            break;
        }
    }

    if end == -1 then return "", 0, false;
    substr := string.{end-begin, str.data+begin};
    total_traversed_char_ct := end;
    return substr, total_traversed_char_ct, true;
}

process_per_line :: (str: string, per_line_proc: (line: *string, line_index: s64, in_data: *void), in_data: *void) -> line_count: s64 {
    line_count: s64;
    left, right: string;
    right = str;
    success: bool;
    while true {
        prev_right := right;
        success, left, right = split_from_left(right, #char "\n");
        if !success {
            if prev_right.count > 0 {
                per_line_proc(*prev_right, line_count, in_data); 
                line_count += 1;
            }
            break;
        }
        if left.count > 0 && left[left.count-1] == #char "\r" {
            left.count -= 1;
        }
        per_line_proc(*left, line_count, in_data); 
        line_count += 1;
    }
    return line_count;
}

// it's fine
Curly_Braced_Object :: struct {
    self: string;
    children: [..]Curly_Braced_Object;
    free_self: bool;
}

advance_string :: (str: *string, by: s64) {
    str.data += by;
    str.count -= by;
}

collect_curly_braced_objects :: (str: string, out_objects: *[..]Curly_Braced_Object) {
    i := 0;
    sanity_iter_max := 100;

    while i < sanity_iter_max {
        defer i += 1;
        maybe_object_str, advance_count, success := get_substring_between_identifiers(str, #char "{", #char "}");
        if !success then return;

        obj := Curly_Braced_Object.{self=maybe_object_str};

        collect_curly_braced_objects(maybe_object_str, *obj.children);
        if obj.children.count > 0 {
            obj_with_children_removed: String_Builder;
            self_ptr := obj.self.data;
            for obj.children {
                diff_to_child := it.self.data - self_ptr;
                if diff_to_child > 0 {
                    print_to_builder(*obj_with_children_removed, "%", string.{diff_to_child, self_ptr});
                }
                self_ptr += diff_to_child + it.self.count;
            }
            remain_char_ct := obj.self.count - (self_ptr - obj.self.data);
            if remain_char_ct > 0 {
                print_to_builder(*obj_with_children_removed, "%", string.{remain_char_ct, self_ptr});
            }
            obj.self = builder_to_string(*obj_with_children_removed);
            obj.free_self = true;
        }

        array_add(out_objects, obj);
        advance_string(*str, advance_count);
    }
} 

clear_curly_braced_objects :: (objects: *[..]Curly_Braced_Object, depth := 0) {
    if depth > 10 then return;
    for *(objects.*) {
        if it.children.count > 0 {
            clear_curly_braced_objects(*it.children, depth + 1);
        }
        array_reset(*it.children);
        if it.free_self { // please
            free(it.self.data);
            it.self.data = null;
            it.self.count = 0;
        }
    }
}

for_each_in_tree :: (objects: *[..] Curly_Braced_Object, proc: (obj: *Curly_Braced_Object, depth: s64, data: *void), data: *void, depth := 0)  {
    if depth > 10 then return;
    for *(objects.*) {
        proc(it, depth, data);
        if it.children.count > 0 {
            for_each_in_tree(*it.children, proc, data, depth + 1);
        }
    }
}

log_curly_node :: (obj: *Curly_Braced_Object, depth: s64, data: *void) {
    log("\n depth: %, curly node: %", depth, obj.self);
}

Breakpoint_Info :: struct {
    fully_qualified_path: string;
    line_number: string;
    enabled: bool;
}

collect_breakpoint_from_curly_node :: (obj: *Curly_Braced_Object, depth: s64, data: *void) {
    info := data.(*Breakpoint_Info);

    obj_items := split(obj.self, ",");
    defer array_reset(*obj_items);
    for obj_items {
        success, key, value := split_from_left(it, #char ":");
        if !success then continue;
        // don't worry about freeing. this is a script and it'll all go back to the os in the end
        // i'm only freeing in places where i'm worried about maybe being a ram hog for no good reason.
        key_no_quotes := replace(trim(key), "\"", "");
        value_no_quotes := replace(trim(value), "\"", "");

        if key_no_quotes == "lineNumber" {
            if info.line_number.count > 0 {
                log("warning: trying to set the line number field of a break point object, but it has already been set to %", info.line_number);
            } else {
                info.line_number = value_no_quotes;
            }
        } else if key_no_quotes == "fsPath" {
            if info.fully_qualified_path.count > 0 {
                log("warning: trying to set the fully qualified path field of a break point object, but it has already been set to %", info.fully_qualified_path);
            } else {
                info.fully_qualified_path = value_no_quotes;
            }
        } else if key_no_quotes == "enabled" {
            info.enabled = ifx value_no_quotes == "true" then true else false;
        }
    }
    for *obj.children {
        collect_breakpoint_from_curly_node(it, depth+1, data);
    }
}

#import "Process";
#import "Basic";
#import "File";
#import "Compiler";
#import "File_Utilities";
#import "String";
#import "Math";
#import "Thread";