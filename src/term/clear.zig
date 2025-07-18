//! Clear screen.
//! Note: Clear doesn't move the cursor, so the cursor will stay at the same position,
//! to move cursor check `Cursor`.

const std = @import("std");
const utils = @import("../utils.zig");

pub const print = struct {
    /// Clear from cursor until end of screen
    pub const screen_from_cursor = utils.comptimeCsi("0J", .{});

    /// Clear from cursor to beginning of screen
    pub const screen_to_cursor = utils.comptimeCsi("1J", .{});

    /// Clear all screen
    pub const all = utils.comptimeCsi("2J", .{});

    /// Clear from cursor to end of line
    pub const line_from_cursor = utils.comptimeCsi("0K", .{});

    /// Clear start of line to the cursor
    pub const line_to_cursor = utils.comptimeCsi("1K", .{});

    /// Clear entire line
    pub const line = utils.comptimeCsi("2K", .{});
};

/// Clear from cursor until end of screen
pub fn screenFromCursor(writer: anytype) !void {
    return std.fmt.format(writer, utils.csi ++ utils.clear_screen_from_cursor, .{});
}

/// Clear from cursor to beginning of screen
pub fn screenToCursor(writer: anytype) !void {
    return std.fmt.format(writer, utils.csi ++ utils.clear_screen_to_cursor, .{});
}

/// Clear all screen
pub fn all(writer: anytype) !void {
    return std.fmt.format(writer, utils.csi ++ utils.clear_all, .{});
}

/// Clear from cursor to end of line
pub fn line_from_cursor(writer: anytype) !void {
    return std.fmt.format(writer, utils.csi ++ utils.clear_line_from_cursor, .{});
}

/// Clear start of line to the cursor
pub fn line_to_cursor(writer: anytype) !void {
    return std.fmt.format(writer, utils.csi ++ utils.clear_line_to_cursor, .{});
}

/// Clear entire line
pub fn entire_line(writer: anytype) !void {
    return std.fmt.format(writer, utils.csi ++ utils.clear_line, .{});
}
