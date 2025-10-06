const std = @import("std");
const Writer = std.io.Writer;

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

const Self = @This();

pub const BG_CODE = "48;";
pub const FG_CODE = "38;";

const RGB_CODE = "2;{d};{d};{d}";
const @"8BIT_CODE" = "5;{d}";

const Plane = enum { fg, bg };

pub fn prepare(
    color: Colors,
    comptime plane: Plane,
    close_ansi_code: bool,
    writer: *Writer,
) !void {
    switch (color) {
        .RGB => |c| {
            const code: *const [16]u8 = switch (plane) {
                .bg => BG_CODE ++ RGB_CODE,
                .fg => FG_CODE ++ RGB_CODE,
            };
            try writer.print(code, .{ c.r, c.g, c.b });
        },
        .Ansi4, .Ansi8 => |p| {
            const code: *const [8]u8 = switch (plane) {
                .bg => BG_CODE ++ @"8BIT_CODE",
                .fg => FG_CODE ++ @"8BIT_CODE",
            };
            try writer.print(code, .{p});
        },
    }
    if (close_ansi_code) try writer.writeByte('m');
}

pub fn render(
    text: []const u8,
    fg: ?Colors,
    bg: ?Colors,
    writer: *Writer,
) !void {
    if (fg == null and bg == null) return;
    try writer.writeAll("\x1B[");
    if (fg) |f| {
        try Self.prepare(f, .fg, false, writer);
        try writer.writeByte(';');
    }
    if (bg) |b| {
        try Self.prepare(b, .bg, false, writer);
    }
    try writer.writeByte('m');
    try writer.writeAll(text);
    try writer.writeAll("\x1B[0m");
}
