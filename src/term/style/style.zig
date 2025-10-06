const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
pub const Color = @import("./color.zig");
const Colors = Color.Colors;

//NOTE: 8-bit and 24-bit Terminal colors.
//       ↓>> this selects bit mode 5 is 8-bit 2 is 24-bit.
// - [48;5;64m >> this is color code 0..255 for 8-bit or 0..255;0..255;0..255; as (r,g,b) for 24-bit
//    ↑>> this sets background color or foreground color fg is 38 bg is 48.

pub const ControlCode = packed struct {
    bell: bool = false,
    backspace: bool = false,
    tab: bool = false,
    formFeed: bool = false,
    carriageReturn: bool = false,

    const This = @This();
    pub fn toU5(self: This) u5 {
        return @bitCast(self);
    }

    pub fn fromU5(bits: u5) This {
        return @bitCast(bits);
    }

    /// Returns true iff this font style contains no attributes
    pub fn isDefault(self: This) bool {
        return self.toU5() == 0;
    }
};

pub const Font = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    slowblink: bool = false,
    rapidblink: bool = false,
    reverse: bool = false,
    hidden: bool = false,
    crossedout: bool = false,
    fraktur: bool = false,
    doublyUnderline: bool = false,
    overline: bool = false,

    const This = @This();
    pub fn toU12(self: This) u12 {
        return @bitCast(self);
    }

    pub fn fromU12(bits: u12) This {
        return @bitCast(bits);
    }

    /// Returns true iff this font style contains no attributes
    pub fn isDefault(self: This) bool {
        return self.toU12() == 0;
    }
};
const control_codes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "bell", "\x07" },
    .{ "backspace", "\x08" },
    .{ "tab", "\x09" },
    .{ "formFeed", "\x0C" },
    .{ "carriageReturn", "\x0D" },
});
const font_style_codes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "bold", "1" },
    .{ "dim", "2" },
    .{ "italic", "3" },
    .{ "underline", "4" },
    .{ "slowblink", "5" },
    .{ "rapidblink", "6" },
    .{ "reverse", "7" },
    .{ "hidden", "8" },
    .{ "crossedout", "9" },
    .{ "fraktur", "20" },
    .{ "doublyUnderline", "21" },
    .{ "overline", "53" },
});
pub const Padding = struct {
    left: u8 = 0,
    right: u8 = 0,
    up: u8 = 0,
    down: u8 = 0,
    pub fn inLine(start: u8, end: u8) Padding {
        return .{ .left = start, .right = end };
    }
    pub fn block(start: u8, end: u8) Padding {
        return .{ .up = start, .down = end };
    }
    pub fn all(p: u8) Padding {
        return .{ .up = p, .down = p, .left = p, .right = p };
    }
};

pub const Black = Colors{ .Ansi4 = 0 };
pub const Red = Colors{ .Ansi4 = 1 };
pub const Green = Colors{ .Ansi4 = 2 };
pub const Yellow = Colors{ .Ansi4 = 3 };
pub const Blue = Colors{ .Ansi4 = 4 };
pub const Magenta = Colors{ .Ansi4 = 5 };
pub const Cyan = Colors{ .Ansi4 = 6 };
pub const White = Colors{ .Ansi4 = 7 };

pub const BrightBlack = Colors{ .Ansi4 = 8 };
pub const BrightRed = Colors{ .Ansi4 = 9 };
pub const BrightGreen = Colors{ .Ansi4 = 10 };
pub const BrightYellow = Colors{ .Ansi4 = 11 };
pub const BrightBlue = Colors{ .Ansi4 = 12 };
pub const BrightMagenta = Colors{ .Ansi4 = 13 };
pub const BrightCyan = Colors{ .Ansi4 = 14 };
pub const BrightWhite = Colors{ .Ansi4 = 15 };

const esc = "\x1B";
const line_feed = "\x0A";
const csi = esc ++ "[";

const reset_code = csi ++ "0m";

fontStyle: Font = .{},
bgColor: ?Colors = null,
fgColor: ?Colors = null,
padding: Padding = .{},
controlCode: ControlCode = .{},

const Self = @This();

fn prepare(self: *const Self, writer: *Writer) !void {
    var ansi_code_closed: bool = false;
    try writer.writeAll(csi);
    if (!self.controlCode.isDefault()) {
        inline for (std.meta.fields(@TypeOf(self.controlCode))) |field| {
            if (@field(self.controlCode, field.name)) {
                const code = control_codes.get(field.name).?;
                try writer.writeAll(code);
            }
        }
    }

    if (!self.fontStyle.isDefault()) {
        inline for (std.meta.fields(@TypeOf(self.fontStyle))) |field| {
            if (@field(self.fontStyle, field.name)) {
                const code = font_style_codes.get(field.name).?;
                try writer.writeAll(code);
                try writer.writeAll(";");
                ansi_code_closed = true;
            }
        }
    }
    if (self.bgColor) |color| {
        try Color.prepare(color, .bg, false, writer);
        try writer.writeAll(";");
        ansi_code_closed = true;
    }

    if (!ansi_code_closed) {
        try writer.writeAll(";");
    }

    if (self.fgColor) |color| {
        try Color.prepare(color, .fg, false, writer);
    }

    try writer.writeByte('m');
}

pub fn render(self: *const Self, text: []const u8, writer: *Writer) !void {
    try self.padUpAndLeft(writer);

    try self.prepare(writer);
    try writer.writeAll(text);
    try writer.writeAll(reset_code);

    try self.padDownAndRight(writer);
}

pub fn fmtRender(self: *const Self, comptime text: []const u8, args: anytype, writer: anytype) !void {
    try self.padUpAndLeft(writer);

    try self.prepare(writer);
    try writer.print(text, args);
    try writer.writeAll(reset_code);

    try self.padDownAndRight(writer);
}

fn padUpAndLeft(self: *const Self, writer: anytype) !void {
    if (self.padding.up > 0) try writer.print("\x1B[{d}B", .{self.padding.up});
    if (self.padding.left > 0) try writer.print("\x1B[{d}C", .{self.padding.left});
}

fn padDownAndRight(self: *const Self, writer: anytype) !void {
    if (self.padding.down > 0) try writer.print("\x1B[{d}B", .{self.padding.down});
    if (self.padding.right > 0) try writer.print("\x1B[{d}C", .{self.padding.right});
}

pub fn reset(self: *Self) void {
    self.fontStyle = .{};
    self.controlCode = .{};
    self.bgColor = null;
    self.fgColor = null;
    self.padding = .{};
}
