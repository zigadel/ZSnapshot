// ZSnapshot/src/errors.zig — central error set (kept similar to ZTable)
pub const Error = error{
    OutOfMemory,
    InvalidFormat,
    Unsupported,
    Bounds,
    TypeMismatch,
    CrcMismatch,
};
