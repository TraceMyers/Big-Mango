
rm_error :: (fmt: string, args: ..Any, log_location := true, caller_loc := #caller_location) #expand {
    log_context := #procedure_name();
    report_impl(fmt, ..args, log_context=log_context, log_location, caller_loc, "ERROR");
}

rm_warning :: (fmt: string, args: ..Any, log_location := true, caller_loc := #caller_location) #expand {
    log_context := #procedure_name();
    report_impl(fmt, ..args, log_context=log_context, log_location, caller_loc, "WARNING");
}

rm_log :: (fmt: string, args: ..Any, log_location := false, caller_loc := #caller_location, header := "LOG") #expand {
    log_context := #procedure_name();
    report_impl(fmt, ..args, log_context=log_context, log_location, caller_loc, header);
}

rm_log_ints :: ($vars: ..Code, base := 10, minimum_digits := 1, log_location := false, caller_loc := #caller_location, header := "LOG") #expand {
    #insert -> string {
        builder: String_Builder;
        print_to_builder(*builder, "FMT :: \"");
        for vars {
            print_to_builder(*builder, "%: \%, ", code_string(it));
        }
        print_to_builder(*builder, "\";\n");
        print_to_builder(*builder, "rm_log(FMT, ");
        for vars {
            print_to_builder(*builder, "FormatInt.{value=`%, base=base, minimum_digits=minimum_digits}, ", code_string(it));
        }
        print_to_builder(*builder, "log_location=log_location, caller_loc=caller_loc, header=header);\n");
        return builder_to_string(*builder);
    };
}

// have the logging system call this proc with the finalized text, if set
rm_log_passthrough_callback: (log_text: string);
// doesn't log to stdout at all - only sends text to the passthrough callback
call_rm_log_passthrough_only := false;

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

report_impl :: (
    fmt: string, 
    args: ..Any, 
    log_context: string, 
    log_location: bool, 
    caller_loc: Source_Code_Location, 
    header: string
) {
    auto_release_temp();

    MAX_HEADER_COUNT :: 8;
    MAX_CONTEXT_COUNT :: 30;
    BRACKETS_COUNT :: 4;
    END_LEAD_SPACE :: 1;
    LEAD_BUFFER_SIZE :: MAX_HEADER_COUNT + MAX_CONTEXT_COUNT + BRACKETS_COUNT;

    lead_buffer := talloc(LEAD_BUFFER_SIZE);
    lead_buffer_string := string.{0, xx lead_buffer};
    print_lead_item_to_buffer_string(*lead_buffer_string, header, MAX_HEADER_COUNT);
    print_lead_item_to_buffer_string(*lead_buffer_string, log_context, MAX_CONTEXT_COUNT);

    use_location: string;
    if log_location {
        use_location = tprint("\n>%", caller_loc);
    }

    msg := tprint(fmt, ..args);
    fully_processed_text := tprint("% % %", lead_buffer_string, msg, use_location);

    if rm_log_passthrough_callback {
        rm_log_passthrough_callback(fully_processed_text);
    }
    if !call_rm_log_passthrough_only {
        log(fully_processed_text);
    }
}

print_char_to_buffer_string :: inline (bufstr: *string, char: u8) {
    bufstr.count += 1;
    bufstr.*[bufstr.count-1] = char;
}

print_lead_item_to_buffer_string :: inline (bufstr: *string, lead_item: string, $MAX_COUNT: s64) {
    print_char_to_buffer_string(bufstr, #char "[");
    remain_space := MAX_COUNT - lead_item.count;
    for c : 0..lead_item.count-1 {
        if c >= MAX_COUNT then break;
        else if remain_space < 0 && (c == MAX_COUNT-2 || c == MAX_COUNT-1) {
            print_char_to_buffer_string(bufstr, #char ".");
        } else {
            print_char_to_buffer_string(bufstr, lead_item[c]);
        }
    }
    print_char_to_buffer_string(bufstr, #char "]");

    for i : 0..remain_space-1 {
        print_char_to_buffer_string(bufstr, #char " ");
    }
}