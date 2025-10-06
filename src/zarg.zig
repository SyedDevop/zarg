const std = @import("std");
pub const Cli = @import("cmd.zig");
pub const Style = @import("term/style/style.zig");
pub const Term = @import("term/term.zig");
pub const Keys = @import("term/key.zig");
pub const Clear = @import("term/clear.zig");

// pub usingnamespace @import("z_color.zig");
// pub usingnamespace @import("cmd.zig");
// pub usingnamespace @import("term/term.zig");
// pub usingnamespace @import("term/clear.zig");

test {
    _ = @import("cmd.zig");
    _ = @import("slice.zig");
}
