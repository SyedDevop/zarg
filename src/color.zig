const std = @import("std");
const Allocator = std.mem.Allocator;

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

    const Self = @This();
    pub fn toU5(self: Self) u5 {
        return @bitCast(self);
    }

    pub fn fromU5(bits: u5) Self {
        return @bitCast(bits);
    }

    /// Returns true iff this font style contains no attributes
    pub fn isDefault(self: Self) bool {
        return self.toU5() == 0;
    }
};

pub const FontStyle = packed struct {
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

    const Self = @This();
    pub fn toU12(self: Self) u12 {
        return @bitCast(self);
    }

    pub fn fromU12(bits: u12) Self {
        return @bitCast(bits);
    }

    /// Returns true iff this font style contains no attributes
    pub fn isDefault(self: Self) bool {
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

pub const Colors = union(enum) {
    /// 4-bit ANSI color (0–15).
    /// Includes both standard (0–7) and bright (8–15) ANSI colors.
    Ansi4: u4,

    /// 8-bit extended ANSI color (0–255).
    /// - 0–15: Standard and bright ANSI colors (same as Ansi3 and Ansi4).
    /// - 16–231: 6×6×6 RGB color cube.
    /// - 232–255: Grayscale colors.
    Ansi8: u8,

    /// 24-bit true color (RGB).
    /// Allows specifying full 16.7 million colors (8 bits per channel).
    RGB: struct {
        r: u8,
        g: u8,
        b: u8,
    },
    pub fn toRGB(r: u8, g: u8, b: u8) Colors {
        return .{ .RGB = .{ .r = r, .g = g, .b = b } };
    }

    pub fn hexToRGB(hex: u24) Colors {
        const r: u8 = @intCast((hex >> 8 * 2) & 0xff);
        const g: u8 = @intCast((hex >> 8 * 1) & 0xff);
        const b: u8 = @intCast((hex >> 8 * 0) & 0xff);
        return .{ .RGB = .{ .r = r, .g = g, .b = b } };
    }

    pub fn toAnsi4(a: u4) Colors {
        return .{ .Ansi4 = a };
    }

    pub fn toAnsi8(a: u8) Colors {
        return .{ .Ansi8 = a };
    }

    /// Converts a 24-bit integer to a terminal color.
    ///
    /// - If the value is in the range `0–15`, it is treated as a 4-bit ANSI color (`Ansi4`).
    /// - If the value is in the range `16–255`, it is treated as an 8-bit extended ANSI color (`Ansi8`).
    /// - If the value is `256` or greater, it is interpreted as a 24-bit RGB color in `0xRRGGBB` format.
    ///
    /// This is a convenient helper when decoding color values from packed integers.
    pub fn toColor(c: u24) Colors {
        if (c < 16) {
            return .{ .Ansi4 = @intCast(c) };
        } else if (c < 256) {
            return .{ .Ansi8 = @intCast(c) };
        } else return Colors.hexToRGB(c);
    }
};

pub const Style = struct {
    fontStyle: FontStyle = .{},
    bgColor: ?Colors = null,
    fgColor: ?Colors = null,
    padding: Padding = .{},
    controlCode: ControlCode = .{},
};

const esc = "\x1B";
const line_feed = "\x0A";
const csi = esc ++ "[";

const reset = csi ++ "0m";

pub const Zcolor = struct {
    alloc: Allocator,

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
        };
    }
    fn prepare(writer: anytype, style: Style) !void {
        try writer.writeAll(csi);
        if (!style.controlCode.isDefault()) {
            inline for (std.meta.fields(@TypeOf(style.controlCode))) |field| {
                if (@field(style.controlCode, field.name)) {
                    const code = control_codes.get(field.name).?;
                    try writer.writeAll(code);
                }
            }
        }
        if (!style.fontStyle.isDefault()) {
            inline for (std.meta.fields(@TypeOf(style.fontStyle))) |field| {
                if (@field(style.fontStyle, field.name)) {
                    const code = font_style_codes.get(field.name).?;
                    try writer.writeAll(code);
                    try writer.writeAll(";");
                }
            }
        }
        if (style.bgColor) |color| {
            switch (color) {
                .RGB => |c| try writer.print("48;2;{d};{d};{d}", .{ c.r, c.g, c.b }),
                .Ansi4, .Ansi8 => |p| try writer.print("48;5;{d}", .{p}),
            }
        }
        if (writer.context.getLast() != ';') {
            try writer.writeAll(";");
        }
        if (style.fgColor) |color| {
            switch (color) {
                .RGB => |c| try writer.print("38;2;{d};{d};{d}", .{ c.r, c.g, c.b }),
                .Ansi4, .Ansi8 => |p| try writer.print("38;5;{d}", .{p}),
            }
        }
        try writer.writeAll("m");
    }
    pub fn render(self: Self, text: []const u8, style: Style) ![]u8 {
        var code = std.ArrayList(u8).init(self.alloc);
        var writer = code.writer();
        if (style.padding.up > 0) {
            try writer.print("\x1B[{d}B", .{style.padding.up});
        }
        if (style.padding.left > 0) {
            try writer.print("\x1B[{d}C", .{style.padding.left});
        }
        try prepare(writer, style);
        try code.appendSlice(text);
        try code.appendSlice(reset);
        if (style.padding.down > 0) {
            try writer.print("\x1B[{d}B", .{style.padding.down});
        }
        if (style.padding.right > 0) {
            try writer.print("\x1B[{d}C", .{style.padding.right});
        }
        return code.toOwnedSlice();
    }

    pub fn fmtRender(self: Self, comptime text: []const u8, args: anytype, style: Style) ![]u8 {
        const fmt = try std.fmt.allocPrint(self.alloc, text, args);
        defer self.alloc.free(fmt);
        const print_text = try self.render(fmt, style);
        return print_text;
    }

    pub fn fmtPrintln(self: Self, comptime text: []const u8, args: anytype, style: Style) !void {
        const print_text = try self.fmtRender(text, args, style);
        defer self.alloc.free(print_text);
        std.debug.print("{s}\n", .{print_text});
    }

    pub fn fmtPrint(self: Self, comptime text: []const u8, args: anytype, style: Style) !void {
        const print_text = try self.fmtRender(text, args, style);
        defer self.alloc.free(print_text);
        std.debug.print("{s}", .{print_text});
    }

    pub fn print(self: Self, text: []const u8, style: Style) !void {
        const print_text = try self.render(text, style);
        defer self.alloc.free(print_text);
        std.debug.print("{s}", .{print_text});
    }
};
