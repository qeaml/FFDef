major: u32,
minor: u32,
patch: u32,

const Self = @This();

pub const current = Self{ .major = 1, .minor = 0, .patch = 0 };
