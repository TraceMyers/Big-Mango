
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

operator - :: (a: Vector2, scalar: float32) -> Vector2 {
    return .{a.x - scalar, a.y - scalar};
}

operator + :: (a: Vector2, scalar: float32) -> Vector2 {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: (a: Vector3, scalar: float32) -> Vector3 {
    return .{a.x - scalar, a.y - scalar, a.z - scalar};
}

operator + :: (a: Vector3, scalar: float32) -> Vector3 {
    return .{a.x + scalar, a.y + scalar, a.z + scalar};
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Vector2i :: struct {
    x: s32;
    y: s32;
}

operator + :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x + b.x, a.y + b.y};
}

operator - :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x - b.x, a.y - b.y};
}

operator * :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x * b.x, a.y * b.y};
}

operator / :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x / b.x, a.y / b.y};
}

operator + :: inline (a: Vector2i, scalar: s32) -> Vector2i #symmetric {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: inline (a: Vector2i, scalar: s32) -> Vector2i {
    return .{a.x - scalar, a.y - scalar};
}

operator - :: inline (scalar: s32, a: Vector2i) -> Vector2i {
    return .{scalar - a.x, scalar - a.y};
}

operator * :: inline (a: Vector2i, scalar: s32) -> Vector2i #symmetric {
    return .{a.x * scalar, a.y * scalar};
}

operator / :: inline (a: Vector2i, scalar: s32) -> Vector2i {
    return .{a.x / scalar, a.y / scalar};
}

operator / :: inline (scalar: s32, a: Vector2i) -> Vector2i {
    return .{scalar / a.x, scalar / a.y};
}

operator == :: inline (a: Vector2i, b: Vector2i) -> bool {
    return (a.x == b.x) && (a.y == b.y);
}

to_vector2 :: inline (v: Vector2i) -> Vector2 {
    return .{xx v.x, xx v.y};
}

to_vector2i :: inline (v: Vector2) -> Vector2i {
    return .{xx v.x, xx v.y};
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Vector3i :: struct {
    x: s32;
    y: s32;
    z: s32;

#overlay(x) xy: Vector2i = ---;
#overlay(y) yz: Vector2i = ---;
}

operator + :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x + b.x, a.y + b.y, a.z + b.z};
}

operator - :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x - b.x, a.y - b.y, a.z - b.z};
}

operator * :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x * b.x, a.y * b.y, a.z * b.z};
}

operator / :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x / b.x, a.y / b.y, a.z / b.z};
}

operator + :: inline (a: Vector3i, scalar: s32) -> Vector3i #symmetric {
    return .{a.x + scalar, a.y + scalar, a.z + scalar};
}

operator - :: inline (a: Vector3i, scalar: s32) -> Vector3i {
    return .{a.x - scalar, a.y - scalar, a.z - scalar};
}

operator - :: inline (scalar: s32, a: Vector3i) -> Vector3i {
    return .{scalar - a.x, scalar - a.y, scalar - a.z};
}

operator * :: inline (a: Vector3i, scalar: s32) -> Vector3i #symmetric {
    return .{a.x * scalar, a.y * scalar, a.z * scalar};
}

operator / :: inline (a: Vector3i, scalar: s32) -> Vector3i {
    return .{a.x / scalar, a.y / scalar, a.z / scalar};
}

operator / :: inline (scalar: s32, a: Vector3i) -> Vector3i {
    return .{scalar / a.x, scalar / a.y, scalar / a.z};
}

operator == :: inline (a: Vector3i, b: Vector3i) -> bool {
    return (a.x == b.x) && (a.y == b.y) && (a.z == b.z);
}

to_vector3 :: inline (v: Vector3i) -> Vector3 {
    return .{xx v.x, xx v.y, xx v.z};
}

to_vector3i :: inline (v: Vector3) -> Vector3i {
    return .{xx v.x, xx v.y, xx v.z};
}

abs :: inline (a: Vector3i) -> Vector3i {
    return .{abs(a.x), abs(a.y), abs(a.z)};
}

sum :: inline (a: Vector3i) -> s32 {
    return a.x + a.y + a.z;
}

vector :: inline (scalar: float) -> Vector3 {
    return Vector3.{scalar, scalar, scalar};
}

max :: (a: Vector3) -> float {
    return max(a.x, max(a.y, a.z));
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Vector2d :: struct {
    x: float64;
    y: float64;
}

operator + :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x + b.x, a.y + b.y};
}

operator - :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x - b.x, a.y - b.y};
}

operator * :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x * b.x, a.y * b.y};
}

operator / :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x / b.x, a.y / b.y};
}

operator + :: inline (a: Vector2d, scalar: float64) -> Vector2d #symmetric {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: inline (a: Vector2d, scalar: float64) -> Vector2d {
    return .{a.x - scalar, a.y - scalar};
}

operator - :: inline (scalar: float64, a: Vector2d) -> Vector2d {
    return .{scalar - a.x, scalar - a.y};
}

operator * :: inline (a: Vector2d, scalar: float64) -> Vector2d #symmetric {
    return .{a.x * scalar, a.y * scalar};
}

operator / :: inline (a: Vector2d, scalar: float64) -> Vector2d {
    return .{a.x / scalar, a.y / scalar};
}

operator / :: inline (scalar: float64, a: Vector2d) -> Vector2d {
    return .{scalar / a.x, scalar / a.y};
}

operator == :: inline (a: Vector2d, b: Vector2d) -> bool {
    return (a.x == b.x) && (a.y == b.y);
}

to_vector2 :: inline (v: Vector2d) -> Vector2 {
    return .{xx v.x, xx v.y};
}

to_vector2d2 :: inline (v: Vector2) -> Vector2d {
    return .{xx v.x, xx v.y};
}