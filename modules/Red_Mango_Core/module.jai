
// #module_parameters()(
//     FORE_X := 1.0,      FORE_Y := 0.0,      FORE_Z := 0.0,
//     RIGHT_X := 0.0,     RIGHT_Y := -1.0,    RIGHT_Z := 0.0,
//     UP_X := 0.0,        UP_Y := 0.0,        UP_Z := 1.0
// ); 

FORE_X :: 0.0;      FORE_Y :: 1.0;      FORE_Z :: 0.0;
RIGHT_X :: 1.0;     RIGHT_Y :: 0.0;    RIGHT_Z :: 0.0;
UP_X :: 0.0;        UP_Y :: 0.0;        UP_Z :: 1.0;

#load "meta.jai";
#load "testing.jai";
#load "bit_array.jai";
#load "math.jai";
#load "print_utils.jai";
#load "vector.jai";
#load "number_interpretation.jai";
#load "logging.jai";
#load "array_utils.jai";
#load "serialize.jai";
#load "string.jai";
#load "encode_text.jai";
#load "scope.jai";
#load "pool.jai";
#load "super_allocator.jai";
#load "gp_allocator.jai";
#load "bit_ops.jai";
#load "bump_allocator.jai";
#load "file.jai";
#load "no_allocator.jai";
#load "color.jai";
#load "common_types.jai";
#load "flag_array.jai";
#load "thread_utils.jai";

// useful token to represent an index to an array, the elements of which are uniquely id'd. so, you use
// the index to get the element, and the id to verify that the element is the expected one. this approach
// is very valuable for a balance of performance and safety in many situations.
// the TYPE constant field takes up no space in the struct. this is to avoid mixing up ID_Ref's from different systems.
// example: 
// ENTITY_REF_TYPE :: 0;
// NAV_REF_TYPE :: 1;
// Entity_Ref :: ID_Ref(ENTITY_REF_TYPE);
// Nav_Ref :: ID_Ref(NAV_REF_TYPE);
ID_Ref :: struct($type_constant: s64) {
    index: s32;
    id: u32;
    TYPE_ID :: type_constant;
}

ID_Ref64 :: struct($type_constant: s64) {
    index: s64;
    id: u64;
    TYPE_ID :: type_constant;
}

RUN_TESTS :: true;
SAFE_TEXT_ENCODING :: true;
SERIALIZE_DEBUG :: false;
BIN_POOL_DEBUG :: false;

MANGO_FORE  :: Vector3.{FORE_X, FORE_Y, FORE_Z};
MANGO_RIGHT :: Vector3.{RIGHT_X, RIGHT_Y, RIGHT_Z};
MANGO_UP    :: Vector3.{UP_X, UP_Y, UP_Z};

#scope_module // -------------------------------------------------------------------------------------------- { MODULE }

Allocator_Identifier :: enum u8 {
    SUPER_ALLOCATOR :: 1;
    GP_ALLOCATOR_16;
    GP_ALLOCATOR_32;
    GP_ALLOCATOR_64;
    GP_ALLOCATOR_128;
    GP_ALLOCATOR_256;
    GP_ALLOCATOR_512;
    GP_ALLOCATOR_1024;
    GP_ALLOCATOR_2048;
    GP_ALLOCATOR_SUPER_MED;   
    GP_ALLOCATOR_SUPER_LRG;
}

ALLOCATOR_VALIDATION_PATTERN : u8 : 0x70;

Allocation_Header :: struct {
    using metadata: union {
        id: Allocator_Identifier;
        // when an allocation is valid, the upper 4 bits are stamped with a specific bit pattern.
        // this is intentionally placed at byte 0 of the struct because the lowest byte of data is the one most likely to change, and so (naively speaking) most likely to change when trashed.
        bit_pattern: u8 = ---;
    }
    using specific: union {
        super: struct {
            inner_chunk: u8;
            inner_chunk_count: u16;
            outer_chunk: u16;
            list: s16;
        };
        gp: struct {
            list: s32=---;
        };
    };

}

ALLOCATION_HEADER_SPACE :: #run ceil_to_pow2_multiple(size_of(Allocation_Header), 8);

#import "Basic";
#import "Math";
#import "File";
#import "File_Utilities";
#import "Thread";
#import "String";
#import "Bit_Operations";
#import "Random";
Program_Print :: #import "Program_Print";
Compiler :: #import "Compiler";

#if RUN_TESTS {
    #load "tests.jai";
    #import "Random";
    // used to just #run the code, but it's helpful to compile the code before running it - not just because
    // the #run may fail, but because allocators are different / appear to be in a different state at compile time 
    // than in a compiled program, leading to crashes in one and not the other.
    // could just make build script for it, but this is fine.

    main :: () {
        k: struct {
            a := 32;
            b := 53.0;
        }
        print("%", k);
        tests := Test_Proc.[
            bit_array_test,
            text_encoding_test,
            math_test,
            array_utils_test,
            pool_test,
            misc_test,
            // nesting_allocator_test,
            // bump_allocator_test,
            serializer_test,
            super_allocator_test,
            gp_allocator_test,
        ];
        run_tests("red mango module", tests);
    }
}
