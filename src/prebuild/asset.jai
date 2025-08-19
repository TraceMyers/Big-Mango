
Asset_Reference :: struct {
    path: string;
    name_hash: u64;
}

Asset_Type :: enum u32 {
    MESH :: 0x1;
}

Asset_Meta_Data :: struct {
    meta_data_version : s32 = 1;
    type: Asset_Type;
    version: s32;
}

create_assets_file :: () -> bool {
    asset_directory := tprint("%\\%", get_working_directory(), "assets");
    make_directory_if_it_does_not_exist(asset_directory);

    naked_reference_builder: String_Builder;
    asset_type_array_strings: [..]string;

    obj_success, obj_array := create_asset_type_references("obj", asset_directory, *naked_reference_builder);
    if !obj_success {
        return false;
    }
    array_add(*asset_type_array_strings, obj_array);

    mesh_success, mesh_array := create_asset_type_references("mesh", asset_directory, *naked_reference_builder);
    if !mesh_success {
        return false;
    }
    array_add(*asset_type_array_strings, mesh_array);

    file_path := "src/assets.jai";
    whole_file_builder: String_Builder;
    print_to_builder(*whole_file_builder, "%\n", builder_to_string(*naked_reference_builder));
    for asset_type_array_strings {
        if it_index == asset_type_array_strings.count - 1 {
            print_to_builder(*whole_file_builder, "%", it);
        } else {
            print_to_builder(*whole_file_builder, "%\n", it);
        }
    }

    write_entire_file(file_path, *whole_file_builder);
    return true;
}

create_asset_type_references :: (extension_name: string, asset_directory: string, ref_builder: *String_Builder) -> bool, string {
    HASH_SEED :: 1;

    files := find_all_files_with_extension(asset_directory, extension_name);
    end_assets_path_index := asset_directory.count+1;

    log("generating % asset references. % files found.", extension_name, files.count);

    names : [..]string;
    hashes : [..]u64;
    path_indices : [..]s64;
    defer array_free(names);
    defer array_free(hashes);
    defer array_free(path_indices);

    for *files {
        filename_with_ext := path_filename(it.*);
        filename := path_strip_extension(filename_with_ext);
        array_add(*names, copy_string(filename));
        array_add(*hashes, get_asset_hash(it.*));
        array_add(*path_indices, it_index);
    }
    for i : 0..hashes.count-2 {
        for j : i+1..hashes.count-1 {
            if hashes[i] == hashes[j] {
                log_hash_collision(files, names, hashes, path_indices, i, j);
                return false, "";
            }
        }
    }
    for i : 0..names.count-1 {
        name := names[i];
        for c : 0..name.count-1 {
            name[c] = to_upper(name[c]);
        }
    }

    upper_extension_name := copy_string(extension_name);
    for *upper_extension_name {
        it.* = to_upper(it.*);
    }

    runtime_proc_name := tprint("load_%_asset_reference_pointers", extension_name);
    type_array_name := tprint("%_ASSET_REFERENCES", upper_extension_name);

    asset_type_array_builder: String_Builder;
    print_to_builder(*asset_type_array_builder, "%: [%]*Asset_Reference;\n", type_array_name, names.count);
    print_to_builder(*asset_type_array_builder, "% :: () {\n", runtime_proc_name);

    for i : 0..names.count-1 {
        full_path := files[path_indices[i]];
        path := slice(full_path, end_assets_path_index, full_path.count-end_assets_path_index);
        upper_name := names[i];
        hash := hashes[i];
        asset_name := tprint("%_%", upper_extension_name, upper_name);
        print_to_builder(ref_builder, "% :: Asset_Reference.{\"%\", %};\n", asset_name, path, hash);
        print_to_builder(*asset_type_array_builder, "\t%[%] = *%;\n", type_array_name, i, asset_name);
    }

    print_to_builder(*asset_type_array_builder, "}\n");

    return true, builder_to_string(*asset_type_array_builder);
}

get_asset_hash :: (asset_path: string) -> u64 {
    filename_with_ext := path_filename(asset_path);
    return native_XXH64(filename_with_ext.data, xx filename_with_ext.count, 0xdeadbeef);
}

log_hash_collision :: (
    asset_paths: []string, asset_names: [..]string, asset_hashes: [..]u64, path_indices: [..]s64, i: s64, j: s64
) {
        log(
#string END
hash collision between files:
name: %, full path: %, hash: %
name: %, full_path: %, hash: %
exiting 
END,
        asset_names[i], asset_paths[path_indices[i]], asset_hashes[i],
        asset_names[j], asset_paths[path_indices[j]], asset_hashes[j],
    );
}