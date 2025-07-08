const std = @import("std");
pub const ZColor = @import("z_color.zig");
pub const cli = @import("cmd.zig");
pub const term = @import("term/term.zig");
pub const clear = @import("term/clear.zig");

pub usingnamespace @import("color.zig");
pub usingnamespace @import("cmd.zig");
pub usingnamespace @import("term/term.zig");
pub usingnamespace @import("term/clear.zig");

test {
    _ = @import("cmd.zig");
    _ = @import("slice.zig");
}
