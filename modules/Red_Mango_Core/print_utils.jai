
_fib16 :: (int_val: $T, min_digits := 0) -> FormatInt #expand {
    return FormatInt.{value=int_val, base=16, minimum_digits=min_digits};
}
