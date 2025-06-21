
#insert #run define_id_refs(
    "Entity",
    "Whatever"
);

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

define_id_refs :: (names: ..string) -> string {
    builder: String_Builder;
    id_counter: s64;
    for name : names {
        uppercase_name := to_upper(name);
        print_to_builder(*builder, 
        #string HERE
%_REF_TYPE :: %; 
%_Ref :: ID_Ref(%_REF_TYPE);
        HERE,
            uppercase_name, id_counter, name, uppercase_name
        );
    }
    return builder_to_string(*builder);
}