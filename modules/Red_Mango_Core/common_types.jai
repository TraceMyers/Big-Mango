
Pair :: struct($T: Type) {
    a: T;
    b: T;
}

operator == :: inline (pair_1: Pair($T), pair_2: Pair(T)) -> bool {
    return pair_1.a == pair_2.a && pair_1.b == pair_2.b;
}

operator == :: inline (pair_1: Pair(s16), pair_2: Pair(s16)) -> bool {
    return pair_1.a == pair_2.a && pair_1.b == pair_2.b;
}