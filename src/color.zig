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
        return Padding{ .left = start, .right = end };
    }
    pub fn block(start: u8, end: u8) Padding {
        return Padding{ .up = start, .down = end };
    }
    pub fn all(p: u8) Padding {
        return Padding{ .up = p, .down = p, .left = p, .right = p };
    }
};
pub const Colors = union(enum) {
    RGB: struct {
        r: u8,
        g: u8,
        b: u8,
    },
    Plate: u8,
    pub fn toRGB(r: u8, g: u8, b: u8) Colors {
        return .{ .RGB = .{ .r = r, .g = g, .b = b } };
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
                .Plate => |p| try writer.print("48;5;{d}", .{p}),
            }
        }
        if (writer.context.getLast() != ';') {
            try writer.writeAll(";");
        }
        if (style.fgColor) |color| {
            switch (color) {
                .RGB => |c| try writer.print("38;2;{d};{d};{d}", .{ c.r, c.g, c.b }),
                .Plate => |p| try writer.print("38;5;{d}", .{p}),
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
