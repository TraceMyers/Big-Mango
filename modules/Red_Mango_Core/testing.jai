Test_Proc :: #type () -> bool, string;

test_condition :: ($condition: Code, loc := #caller_location) #expand {
    if !(#insert condition) {
        `return false, tprint("FAIL    : % | [cond] % @ %", #procedure_name(), #run code_string(condition), loc);
    }
}

return_test_success :: () -> bool, string #expand {
    `return true, tprint("SUCCESS : %", #procedure_name());
}

run_tests :: (header: string, tests: []Test_Proc) {
    passed_test_ct := 0;
    log("\nrunning tests: %", header);
    for tests {
        // in release, causes crash on log, i think due to optimizations around temp allocations
        // auto_release_temp();
        passed_test, log_str := it();
        passed_test_ct += cast(s64)passed_test;
        log(log_str);
    }
    log("passed % / % tests\n   ", passed_test_ct, tests.count);
}
