
run_super_allocator_test :: () {
    passed_test, log_str := super_allocator_test_2();
    log(log_str);
}

super_allocator_test_2 :: () -> bool, string {
    MIN_CHUNK_SZ :: 32;
    a: Super_Allocator(MIN_CHUNK_SZ);
    initialize_super_allocator(*a, context.default_allocator);
    scope_set_allocator(a);

    data_1_sz := 129;
    allocated_chunk_ct := div_ceil(data_1_sz, MIN_CHUNK_SZ) + 1; // + 1 for header
    data_1 := alloc(data_1_sz);
    test_condition(data_1 == xx *a.chunk_lists[0][0].inner_chunks[1]);
    test_condition(a.books.flag_list_of_lists[0][0] == ((1 << allocated_chunk_ct) - 1).(u64));

    data_2_sz := 880;
    allocated_chunk_ct += div_ceil(data_2_sz, MIN_CHUNK_SZ) + 1;
    data_2 := alloc(880);
    test_condition(a.books.flag_list_of_lists[0][0] == ((1 << allocated_chunk_ct) - 1).(u64));

    free(data_1);
    free(data_2);

    POINTER_COUNT :: 10000;
    pointers: [..]*void;
    pointers.allocator = temp;
    array_resize(*pointers, POINTER_COUNT);

    total_alloc_seconds: float64;
    total_alloc_seconds_last_100: float64;
    max_time: float64;

    for 0..pointers.count-1 {
        bin_ct := random_get_within_range(1, 64).(s64);
        alloc_sz := bin_ct * a.MIN_ALLOCATION_SIZE;
        t1 := seconds_since_init();
        pointers[it] = alloc(alloc_sz);
        t2 := seconds_since_init();
        total_alloc_seconds += t2 - t1;
        max_time = max(max_time, t2-t1);
        if it >= POINTER_COUNT-100 {
            total_alloc_seconds_last_100 += t2 - t1;
        }
    }
    for 0..pointers.count-1 {
        index := ifx pointers.count > 1 then round(random_get_within_range(0, (pointers.count-1).(float))) else 0;
        if index < 0 {
            index = 0;
        }
        ptr := pointers[index];
        array_ordered_remove_by_index(*pointers, index);
        free(ptr);
    }

    // log("small allocator data");
    // log("%", repr(*a.small_allocator));

    // not real world but whatever
    total_alloc_ms := total_alloc_seconds * 1000.0;
    ms_per_alloc := total_alloc_ms / POINTER_COUNT.(float64);
    us_per_alloc := ms_per_alloc * 1000.0;

    last_100_total_ms := total_alloc_seconds_last_100 * 1000.0;
    last_100_ms_per_alloc := last_100_total_ms / 100.0;
    last_100_us_per_alloc := last_100_ms_per_alloc * 1000.0;

    log("avg alloc time:                        %us", us_per_alloc);
    log("avg alloc time (last 100 allocations): %us", last_100_us_per_alloc);
    log("max time:                              %us", max_time * 1000.0 * 1000.0);

    // total_alloc_seconds = 0;
    // total_alloc_seconds_last_100 = 0;
    // max_time = 0;
    // array_resize(*pointers, POINTER_COUNT);

    // for 0..POINTER_COUNT-1 {
    //     bin_ct: s64;
    //     if random_get_zero_to_one() <= 0.2 {
    //         bin_ct = random_get_within_range(32, 384).(s64);
    //     } else {
    //         bin_ct = random_get_within_range(1, 64).(s64);
    //     }
    //     alloc_sz := bin_ct * a.small_allocator.MIN_ALLOCATION_SIZE;
    //     t1 := seconds_since_init();
    //     refs[it] = nack_alloc(*a, alloc_sz);
    //     t2 := seconds_since_init();
    //     total_alloc_seconds += t2 - t1;
    //     max_time = max(max_time, t2-t1);
    //     if it >= POINTER_COUNT-100 {
    //         total_alloc_seconds_last_100 += t2 - t1;
    //     }
    // }
    // for 0..POINTER_COUNT-1 {
    //     index := ifx refs.count > 1 then round(random_get_within_range(0, (refs.count-1).(float))) else 0;
    //     if index < 0 {
    //         index = 0;
    //     }
    //     ref := refs[index];
    //     array_ordered_remove_by_index(*refs, index);
    //     nack_free(*a, *ref);
    // }

    // // not real world but whatever
    // total_alloc_ms = total_alloc_seconds * 1000.0;
    // ms_per_alloc = total_alloc_ms / POINTER_COUNT.(float64);
    // us_per_alloc = ms_per_alloc * 1000.0;

    // last_100_total_ms = total_alloc_seconds_last_100 * 1000.0;
    // last_100_ms_per_alloc = last_100_total_ms / 100.0;
    // last_100_us_per_alloc = last_100_ms_per_alloc * 1000.0;

    // log("mixed allocations avg alloc time:                        %us", us_per_alloc);
    // log("mixed allocations avg alloc time (last 100 allocations): %us", last_100_us_per_alloc);
    // log("mixed allocations max time:                              %us", max_time * 1000.0 * 1000.0);

    return_test_success();
}