
#run {
    set_build_options_dc(.{do_output=false});
    options := get_build_options();
    args := options.compile_time_command_line;
    if !generate_bindings(args) {
        compiler_set_workspace_status(.FAILED);
    }
}

generate_bindings :: (args: []string) -> bool {
    using options: Generate_Bindings_Options;    
    
    array_add(*libpaths, "lib/windows/x64");
    array_add(*libnames, "zlib");
    array_add(*include_paths, "include");

    array_add(*source_files, "zlib.h");
    array_add(*source_files, "zconf.h");
    array_add(*source_files, "zutil.h");
    array_add(*source_files, "gzguts.h");
    array_add(*extra_clang_arguments, "-x", "c++", "-DWIN32_LEAN_AND_MEAN");

    visitor = zlib_visitor;
    strip_flags |= .INLINED_FUNCTIONS; // ?

    return generate_bindings(options, "windows.jai");
}

zlib_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    return .RECURSE;
}

#import "Basic";
#import "Compiler";
#import "Bindings_Generator";
#import "String";
