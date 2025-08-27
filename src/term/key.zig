const std = @import("std");
const builtin = @import("builtin");
const winU = @import("win_util.zig");

const os = std.os;
const win = os.windows;
const winK = win.kernel32;
const pollfd = std.posix.pollfd;

const is_windows = builtin.os.tag == .windows;
const Self = @This();
pub const Keys = union(enum) {
    Char: u8,
    Ctrl: u8,

    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    Tab,
    Esc,
    Home,
    End,
    Enter,
    Insert,
    Delete,
    PageUp,
    PageDown,
    BackSpace,

    UpArrow,
    DownArrow,
    RightArrow,
    LeftArrow,

    ShiftUpArrow,
    ShiftDownArrow,
    ShiftRightArrow,
    ShiftLeftArrow,

    AltUpArrow,
    AltDownArrow,
    AltRightArrow,
    AltLeftArrow,

    AltShiftUpArrow,
    AltShiftDownArrow,
    AltShiftRightArrow,
    AltShiftLeftArrow,

    CtrlUpArrow,
    CtrlDownArrow,
    CtrlRightArrow,
    CtrlLeftArrow,

    CtrlShiftUpArrow,
    CtrlShiftDownArrow,
    CtrlShiftRightArrow,
    CtrlShiftLeftArrow,

    // CtrlShiftAltUpArrow,
    // CtrlShiftAltDownArrow,
    // CtrlShiftAltRightArrow,
    // CtrlShiftAltLeftArrow,

    CtrlAltUpArrow,
    CtrlAltDownArrow,
    CtrlAltRightArrow,
    CtrlAltLeftArrow,

    None,

    pub fn isKey(self: Keys, c: u8) bool {
        return switch (self) {
            .Char => |ch| ch == c,
            else => false,
        };
    }

    pub fn isCtrlKey(self: Keys, c: u8) bool {
        return switch (self) {
            .Ctrl => |ct| ct == c,
            else => false,
        };
    }

    pub fn getChar(self: Keys) ?u8 {
        return switch (self) {
            .Char => |c| c,
            else => null,
        };
    }

    pub fn getCtrlChar(self: Keys) ?u8 {
        return switch (self) {
            .Ctrl => |c| c,
            else => null,
        };
    }
};

in_reader: std.Io.Reader,
input_handle: std.fs.File.Handle,
fds: ?[1]pollfd = null,
var stdin_buffer: [1024]u8 = undefined;
pub fn init(input: std.fs.File) Self {
    const fds: ?[1]pollfd = if (is_windows) null else .{.{
        .fd = input.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    return .{
        .input_handle = input.handle,
        .fds = fds,
        .in_reader = input.reader(&stdin_buffer).interface,
    };
}

pub fn printNibble(ch: u8, level: usize) void {
    const pritt_c = if (std.ascii.isPrint(ch)) ch else ' ';
    std.debug.print("readByte::{d} c={c} x={x:3} d={d}\r\n", .{ level, pritt_c, ch, ch });
}

pub fn readByte(self: *Self) !?u8 {
    return self.in_reader.takeByte() catch |err| switch (err) {
        error.EndOfStream => null,
        else => return err,
    };
}

const WaitTime = if (is_windows) u32 else i32;

pub fn waitForInput(self: *Self, time: WaitTime) !usize {
    return switch (builtin.os.tag) {
        .windows => switch (winK.WaitForSingleObject(self.input_handle, time)) {
            win.WAIT_OBJECT_0 => {
                var num_events: u32 = 0;
                if (winU.GetNumberOfConsoleInputEvents(self.input_handle, &num_events) == 0) return 0;
                return num_events;
            },
            else => 0,
        },
        else => try std.posix.poll(&self.fds.?, time),
    };
}

pub fn next(self: *Self) !Keys {
    const data = try self.waitForInput(1);
    if (data == 0) return .None;
    const c0 = try self.readByte();
    if (c0 == null) return .None;
    // printNibble(c0, 1);
    return switch (c0.?) {
        '\x1b' => {
            if (try self.waitForInput(30) <= 0) return .Esc;
            const c1 = try self.readByte();
            if (c1 == null) return .None;
            // printNibble(c1, 2);
            return switch (c1.?) {
                '[' => {
                    const key = try self.parseCsi();
                    //BUG: If Insert button is pressed before Delete button
                    //it is not registering. But the next press is working
                    //properly.
                    if (try self.waitForInput(1) == 1) _ = try self.readByte();
                    return key;
                },
                'O' => {
                    const c2 = try self.readByte();
                    if (c2 == null) return .None;
                    // printNibble(c2.?, 22);
                    return switch (c2.?) {
                        'P' => .F1,
                        'Q' => .F2,
                        'R' => .F3,
                        'S' => .F4,
                        else => .None,
                    };
                },
                else => .None,
            };
        },

        // Ctrl omitting m.
        // d(1..26) of h(01..1A) ascii code this is control key code
        // for Ctrl + a..z.
        '\x01'...'\x0C', '\x0E'...'\x1A' => {
            if (c0.? + '\x60' == 'i') return .Tab;
            return Keys{ .Ctrl = c0.? + '\x60' };
        },
        '\x7f' => .BackSpace,
        '\x0d' => .Enter,
        else => return Keys{ .Char = c0.? },
    };
}

fn parseCsi(self: *Self) !Keys {
    const c0 = try self.readByte();
    if (c0 == null) return .None;
    // printNibble(c0.?, 3);

    return switch (c0.?) {
        'A' => .UpArrow,
        'B' => .DownArrow,
        'C' => .RightArrow,
        'D' => .LeftArrow,
        'F' => .End,
        'H' => .Home,
        '\x31' => {
            const c1 = try self.readByte();
            if (c1 == null) return .None;
            // printNibble(c1.?, 4);
            return switch (c1.?) {
                '0' => {
                    var buf = [4]u8{ 0, 0, 0, 0 };
                    const rest = try self.in_reader.readSliceShort(&buf);
                    if (std.mem.eql(u8, "5;5u", buf[0..rest])) {
                        return Keys{ .Ctrl = 'i' };
                    }
                    return .None;
                },

                '5' => .F5,
                '7' => .F6,
                '8' => .F7,
                '9' => .F8,
                ';' => {
                    const c2 = try self.readByte();
                    if (c2 == null) return .None;
                    // printNibble(c2.?, 41);
                    return switch (c2.?) {
                        '2' => {
                            const c3 = try self.readByte();
                            if (c3 == null) return .None;
                            // printNibble(c3.?, 411);
                            return switch (c3.?) {
                                'A' => .ShiftUpArrow,
                                'B' => .ShiftDownArrow,
                                'C' => .ShiftRightArrow,
                                'D' => .ShiftLeftArrow,
                                else => .None,
                            };
                        },
                        '3' => {
                            const c3 = try self.readByte();
                            if (c3 == null) return .None;
                            // printNibble(c3.?, 412);
                            return switch (c3.?) {
                                'A' => .AltUpArrow,
                                'B' => .AltDownArrow,
                                'C' => .AltRightArrow,
                                'D' => .AltLeftArrow,
                                else => .None,
                            };
                        },
                        '4' => {
                            const c3 = try self.readByte();
                            if (c3 == null) return .None;
                            // printNibble(c3.?, 413);
                            return switch (c3.?) {
                                'A' => .AltShiftUpArrow,
                                'B' => .AltShiftDownArrow,
                                'C' => .AltShiftRightArrow,
                                'D' => .AltShiftLeftArrow,
                                else => .None,
                            };
                        },
                        '5' => {
                            const c3 = try self.readByte();
                            if (c3 == null) return .None;
                            // printNibble(c3.?, 413);
                            return switch (c3.?) {
                                'A' => .CtrlUpArrow,
                                'B' => .CtrlDownArrow,
                                'C' => .CtrlRightArrow,
                                'D' => .CtrlLeftArrow,
                                else => .None,
                            };
                        },
                        '6' => {
                            const c3 = try self.readByte();
                            if (c3 == null) return .None;
                            // printNibble(c3.?, 414);
                            return switch (c3.?) {
                                'A' => .CtrlShiftUpArrow,
                                'B' => .CtrlShiftDownArrow,
                                'C' => .CtrlShiftRightArrow,
                                'D' => .CtrlShiftLeftArrow,
                                else => .None,
                            };
                        },
                        '7' => {
                            const c3 = try self.readByte();
                            if (c3 == null) return .None;
                            // printNibble(c3.?, 414);
                            return switch (c3.?) {
                                'A' => .CtrlAltUpArrow,
                                'B' => .CtrlAltDownArrow,
                                'C' => .CtrlAltRightArrow,
                                'D' => .CtrlAltLeftArrow,
                                else => .None,
                            };
                        },
                        else => .None,
                    };
                },
                else => .None,
            };
        },
        '2' => {
            const c2 = try self.readByte();
            if (c2 == null) return .None;
            // printNibble(c2.?, 6);
            return switch (c2.?) {
                '0' => .F9,
                '1' => .F10,
                '3' => .F11,
                '4' => .F12,
                '~' => .Insert,
                else => .None,
            };
        },
        '3' => .Delete,
        '5' => .PageUp,
        '6' => .PageDown,

        // TODO: add mouse events.
        'M' => .None,
        else => .None,
    };
}
