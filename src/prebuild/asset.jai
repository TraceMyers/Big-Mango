
Asset_Reference :: struct {
    path: string;
    name_hash: u64;
}

Asset_Type :: enum u32 {
    MESH :: 0x1;
}

Asset_Meta_Data_V1 :: struct {
    meta_data_version : s32 = 1;
    type: Asset_Type;
    version: s32;
}

create_assets_file :: () -> bool {
    // TODO: relative paths, file watching, etc.
    asset_directory := tprint("%\\%", get_working_directory(), "assets");
    make_directory_if_it_does_not_exist(asset_directory);

    file_builder : String_Builder;
    if !create_asset_type_references("obj", asset_directory, *file_builder) then return false;
    if !create_asset_type_references("mesh", asset_directory, *file_builder) then return false;

    file_path := "src/assets.jai";
    file_string := builder_to_string(*file_builder);
    write_entire_file(file_path, file_string);
    return true;
}

create_asset_type_references :: (extension_name: string, asset_directory: string, file_builder: *String_Builder) -> bool {
    HASH_SEED :: 1;

    files := find_all_files_with_extension(asset_directory, extension_name);
    end_assets_path_index := asset_directory.count+1;

    names : [..]string;
    hashes : [..]u64;
    path_indices : [..]s64;
    defer array_free(names);
    defer array_free(hashes);
    defer array_free(path_indices);

    for *files {
        split_success, _, filename_with_ext := split_from_right(it.*, #char "/");
        if split_success {
            name_success, filename, _ := split_from_right(filename_with_ext, #char ".");
            if name_success {
                for c : 0..it.count-1 {
                    if it.data[c] == #char "\\" {
                        it.data[c] = #char "/";
                    }
                }
                log("file: %", filename);
                array_add(*names, copy_string(filename));
                array_add(*hashes, native_XXH64(filename.data, xx filename.count, seed=HASH_SEED));
                array_add(*path_indices, it_index);
            }
        }
    }
    for i : 0..hashes.count-2 {
        for j : i+1..hashes.count-1 {
            if hashes[i] == hashes[j] {
                log_hash_collision(files, names, hashes, path_indices, i, j);
                return false;
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

    for i : 0..names.count-1 {
        full_path := files[path_indices[i]];
        path := slice(full_path, end_assets_path_index, full_path.count-end_assets_path_index);
        name := names[i];
        hash := hashes[i];
        print_to_builder(
            file_builder, 
            "%_% :: Asset_Reference.{\"%\", %};\n", 
            upper_extension_name, name, path, hash
        );
    }

    return true;
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