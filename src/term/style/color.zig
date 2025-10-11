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

inline fn prepareComptime(
    comptime color: Colors,
    comptime plane: Plane,
) []const u8 {
    return switch (color) {
        .RGB => |c| {
            const code: *const [16]u8 = switch (plane) {
                .bg => BG_CODE ++ RGB_CODE,
                .fg => FG_CODE ++ RGB_CODE,
            };
            return std.fmt.comptimePrint(code, .{ c.r, c.g, c.b });
        },
        .Ansi4, .Ansi8 => |p| {
            const code: *const [8]u8 = switch (plane) {
                .bg => BG_CODE ++ @"8BIT_CODE",
                .fg => FG_CODE ++ @"8BIT_CODE",
            };
            return std.fmt.comptimePrint(code, .{p});
        },
    };
}

pub fn renderComptime(
    comptime text: []const u8,
    comptime fg: ?Colors,
    comptime bg: ?Colors,
) []const u8 {
    std.debug.assert(fg != null or bg != null);
    const fg_color: []const u8 = if (fg) |f| prepareComptime(f, .fg) else "";
    comptime var bg_color: []const u8 = if (bg) |b| prepareComptime(b, .bg) else "";

    if (bg != null and fg != null) {
        bg_color = ";" ++ bg_color;
    }

    return std.fmt.comptimePrint("\x1B[{s}{s}m{s}\x1B[0m", .{
        fg_color,
        bg_color,
        text,
    });
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
        if (bg != null) try writer.writeByte(';');
    }
    if (bg) |b| {
        try Self.prepare(b, .bg, false, writer);
    }
    try writer.writeByte('m');
    try writer.writeAll(text);
    try writer.writeAll("\x1B[0m");
}

const testing = std.testing;

test "combined fg Comptime" {

    // Some implementations emit two separate sequences, others combine into one. We accept both.
    const expected1: []const u8 = "\x1B[38;5;2mhello\x1B[0m"; // combined (rare)

    const actual =
        comptime blk: {
            const color_text = Self.renderComptime("hello", .toAnsi8(2), null);
            if (color_text.len == 0) @compileError("Expected at least one sequence");
            break :blk color_text;
        };
    try testing.expectEqualSlices(u8, expected1, actual); // will fail and print diff
}

test "combined bg Comptime" {

    // Some implementations emit two separate sequences, others combine into one. We accept both.
    const expected1: []const u8 = "\x1B[48;5;2mhello\x1B[0m"; // combined (rare)

    const actual =
        comptime blk: {
            const color_text = Self.renderComptime("hello", null, .toAnsi8(2));
            if (color_text.len == 0) @compileError("Expected at least one sequence");
            break :blk color_text;
        };
    try testing.expectEqualSlices(u8, expected1, actual); // will fail and print diff
}

test "combined fg/bg Comptime" {

    // Some implementations emit two separate sequences, others combine into one. We accept both.
    const expected1: []const u8 = "\x1B[38;5;2;48;2;1;1;1mhello\x1B[0m"; // combined (rare)
    const expected2: []const u8 = "\x1B[38;5;2m\x1B[48;2;1;1;1mhello\x1B[0m"; // separate sequences

    const actual =
        comptime blk: {
            const color_text = Self.renderComptime("hello", .toAnsi8(2), .toRGB(1, 1, 1));
            if (color_text.len == 0) @compileError("Expected at least one sequence");
            break :blk color_text;
        };
    if (!std.mem.eql(u8, actual, expected1) and !std.mem.eql(u8, actual, expected2)) {
        try testing.expectEqualSlices(u8, expected1, actual); // will fail and print diff
    }
}

test "fg 8-bi" {
    var buf: [100]u8 = undefined;
    var fb = std.Io.Writer.fixed(&buf);

    try Self.render("hello", .toAnsi4(1), null, &fb);
    const expected = "\x1B[38;5;1mhello\x1B[0m";
    try fb.flush();
    const actual = buf[0..fb.end];
    try testing.expectEqualSlices(u8, expected, actual);
}

test "fg 24-bit (rgb)" {
    var buf: [100]u8 = undefined;
    var fb = std.Io.Writer.fixed(&buf);
    try Self.render("hello", .toRGB(1, 2, 3), null, &fb);
    const expected: []const u8 = "\x1B[38;2;1;2;3mhello\x1B[0m";
    try fb.flush();
    const actual = buf[0..fb.end];
    try testing.expectEqualSlices(u8, expected, actual);
}

test "bg 24-bit (rgb)" {
    var buf: [100]u8 = undefined;
    var fb = std.Io.Writer.fixed(&buf);

    try Self.render("hello", null, .toRGB(10, 20, 30), &fb);
    const expected: []const u8 = "\x1B[48;2;10;20;30mhello\x1B[0m";
    try fb.flush();
    const actual = buf[0..fb.end];
    try testing.expectEqualSlices(u8, expected, actual);
}

test "combined fg/bg" {
    var buf: [100]u8 = undefined;
    var fb = std.Io.Writer.fixed(&buf);

    try Self.render("hello", .toAnsi8(2), .toRGB(1, 1, 1), &fb);

    // Some implementations emit two separate sequences, others combine into one. We accept both.
    const expected1: []const u8 = "\x1B[38;5;2;48;2;1;1;1mhello\x1B[0m"; // combined (rare)
    const expected2: []const u8 = "\x1B[38;5;2m\x1B[48;2;1;1;1mhello\x1B[0m"; // separate sequences

    try fb.flush();
    const actual = buf[0..fb.end];
    if (!std.mem.eql(u8, actual, expected1) and !std.mem.eql(u8, actual, expected2)) {
        try testing.expectEqualSlices(u8, expected1, actual); // will fail and print diff
    }
}

test "empty string" {
    var buf: [1024]u8 = undefined;
    var fb = std.Io.Writer.fixed(&buf);

    try Self.render("", .toAnsi8(1), null, &fb);

    const expected: []const u8 = "\x1B[38;5;1m\x1B[0m"; // just open and reset
    try fb.flush();
    const actual = buf[0..fb.end];
    try testing.expectEqualSlices(u8, expected, actual);
}

test "unicode content" {
    var buf: [1024]u8 = undefined;
    var fb = std.Io.Writer.fixed(&buf);

    const msg = "héllø 🌍";
    try Self.render(msg, .toAnsi8(4), null, &fb);

    const expectedPrefix: []const u8 = "\x1B[38;5;4m";
    try fb.flush();
    const actual = buf[0..fb.end];

    // Expect prefix, suffix reset, and that the payload contains the UTF-8 bytes of msg
    try testing.expectEqualSlices(u8, expectedPrefix, actual[0..expectedPrefix.len]);
    try testing.expectEqualSlices(u8, "\x1B[0m", actual[actual.len - 4 .. actual.len]);
    // Validate the middle payload equals the UTF-8 encoded msg
    try testing.expectEqualSlices(u8, msg, actual[expectedPrefix.len .. actual.len - 4]);
}
