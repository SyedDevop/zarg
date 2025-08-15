const std = @import("std");
const zarg = @import("zarg");

const os = std.os;
const win = os.windows;
const winK = win.kernel32;
const builtin = @import("builtin");
const Cli = zarg.Cli;
const ZColor = zarg.ZColor;

const USAGE =
    \\Example to use zarg terminal
    \\------------------
;
const CmdType = Cli.Cmd(UserCmd);
const cli_cmds = [_]CmdType{
    CmdType{
        .name = .root,
        .usage = " [OPTIONS] \"EXPRESSION\"",
        .options = &.{
            .{
                .long = "--print",
                .short = "-p",
                .info = "Prints the result of the expression.",
                .value = .{ .str = null },
            },
        },
        .min_arg = 0,
    },
};

pub const UserCmd = enum { root };

fn printVersion(version_call: Cli.VersionCallFrom) []const u8 {
    return switch (version_call) {
        .version => "Z Terminal V1.0.0",
        .help => "V1.0.0",
    };
}
var print_log: bool = true;
fn printNibble(ch: u8, level: usize) void {
    if (!print_log) return;
    const pritt_c = if (std.ascii.isPrint(ch)) ch else ' ';
    std.debug.print("readByte::{d} c={c} x={x:3} d={d}\r\n", .{ level, pritt_c, ch, ch });
}

fn readByte(reader: anytype) !?u8 {
    return reader.readByte() catch |err| switch (err) {
        error.EndOfStream => null,
        else => return err,
    };
}

pub extern "kernel32" fn GetNumberOfConsoleInputEvents(
    hConsoleInput: win.HANDLE,
    lpcNumberOfEvents: win.DWORD_PTR,
) callconv(.winapi) win.BOOL;

fn waitForInput(input_handle: std.fs.File.Handle, fd: ?std.posix.pollfd, time: i32) !usize {
    return switch (builtin.os.tag) {
        .windows => switch (winK.WaitForSingleObject(input_handle, time)) {
            win.WAIT_OBJECT_0 => {
                var num_events: u32 = 0;
                if (winK.GetNumberOfConsoleInputEvents(input_handle, &num_events) == 0) return 0;
                return num_events;
            },
            else => 0,
        },
        else => {
            var fds = [1]std.posix.pollfd{fd.?};
            return try std.posix.poll(&fds, time);
        },
    };
}

pub fn main() !void {
    var stdout = std.io.getStdOut();
    const sto_writer = stdout.writer();

    const stdin = std.io.getStdIn();
    // const sti_writer = stdin.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var cli = try Cli.CliInit(UserCmd)
        .init(allocator, "Z Terminal", USAGE, .{ .fun = &printVersion }, &cli_cmds);
    defer cli.deinit();

    cli.parse() catch |err| {
        try cli.printParseError(err);
        return;
    };

    const terminal = zarg.Term;
    const mouse = terminal.MouseMode{ .normal = true };

    var raw = try terminal.rawMode(stdin.handle);
    defer {
        raw.disableRawMode() catch {};
    }
    const fds: ?std.posix.pollfd = if (builtin.os.tag != .windows)
        .{ .fd = stdin.handle, .events = std.posix.POLL.IN, .revents = 0 }
    else
        null;

    const clear = zarg.Clear;
    try clear.all_move_curser_top(sto_writer);
    const color = ZColor.Zcolor.init(allocator);
    _ = color;
    try stdout.writeAll("Press Q or Ctr+q to quit \r\n");
    try sto_writer.print("{?any}\n\r", .{try terminal.getSize(std.io.getStdOut())});

    try mouse.enableMouseEvent(sto_writer);
    defer mouse.disableMouseEvent(sto_writer) catch {};

    // var index: usize = 0;
    while (true) {
        const data = try waitForInput(raw.handle, fds, 1);
        if (data == 0) continue;
        const in_reader = stdin.reader();
        const c0 = try in_reader.readByte();
        printNibble(c0, 1);
        switch (c0) {
            '\x1b' => {
                if (try waitForInput(raw.handle, fds, 30) <= 0) {
                    std.debug.print("Esc\r\n", .{});
                    continue;
                }
                const c1 = try in_reader.readByte();
                printNibble(c1, 2);
                switch (c1) {
                    '[' => try parseCsi(in_reader),
                    'O' => {
                        const c2 = try readByte(in_reader);
                        if (c2 == null) return;
                        printNibble(c2.?, 22);
                        switch (c2.?) {
                            'P' => std.debug.print("f1 \r\n", .{}),
                            'Q' => std.debug.print("f2 \r\n", .{}),
                            'R' => std.debug.print("f3 \r\n", .{}),
                            'S' => std.debug.print("f4 \r\n", .{}),
                            else => {},
                        }
                    },
                    else => {},
                }
            },

            // Ctrl omitting m.
            // d(1..26) of h(01..1A) ascii code this is control key code
            // for Ctrl + a..z.
            '\x01'...'\x0C', '\x0E'...'\x1A' => {
                if (c0 + '\x60' == 'i') {
                    std.debug.print("Tab \r\n", .{});
                    continue;
                }
                std.debug.print("Control {c}\r\n", .{c0 + '\x60'});
            },
            '\x7f' => std.debug.print("Back Space \r\n", .{}),
            '\x0d' => std.debug.print("Enter \r\n", .{}),
            else => {
                std.debug.print("{c}\r\n", .{c0});
            },
        }
        if (c0 == 'p') {
            print_log = print_log != true;
        }
        if (c0 == 'c') {
            try zarg.Clear.all_move_curser_top(sto_writer);
        }
        if (c0 == 'q' or c0 == 'Q' or c0 == 0x11) { // Q key
            try sto_writer.print("\nBye!\n", .{});
            return;
        }
    }
}

fn parseCsi(reader: anytype) !void {
    const c0 = try readByte(reader);
    if (c0 == null) return;
    printNibble(c0.?, 3);

    switch (c0.?) {
        'A' => std.debug.print("Up    \r\n", .{}),
        'B' => std.debug.print("Down  \r\n", .{}),
        'C' => std.debug.print("Right \r\n", .{}),
        'D' => std.debug.print("Left  \r\n", .{}),
        'F' => std.debug.print("End  \r\n", .{}),
        'H' => std.debug.print("Home  \r\n", .{}),
        '\x31' => {
            const c1 = try readByte(reader);
            if (c1 == null) return;
            printNibble(c1.?, 4);

            switch (c1.?) {
                '0' => {
                    var buf = [4]u8{ 0, 0, 0, 0 };
                    const rest = try reader.readAll(&buf);
                    if (std.mem.eql(u8, "5;5u", buf[0..rest])) {
                        std.debug.print("Ctrl + i\r\n", .{});
                    }
                },

                '5' => std.debug.print("f5 \r\n", .{}),
                '7' => std.debug.print("f6 \r\n", .{}),
                '8' => std.debug.print("f7 \r\n", .{}),
                '9' => std.debug.print("f8 \r\n", .{}),
                ';' => {
                    const c2 = try readByte(reader);
                    if (c2 == null) return;
                    printNibble(c2.?, 41);
                    switch (c2.?) {
                        '2' => {
                            const c3 = try readByte(reader);
                            if (c3 == null) return;
                            printNibble(c3.?, 411);
                            switch (c3.?) {
                                'A' => std.debug.print("shift + Up    \r\n", .{}),
                                'B' => std.debug.print("shift + Down  \r\n", .{}),
                                'C' => std.debug.print("shift + Right \r\n", .{}),
                                'D' => std.debug.print("shift + Left  \r\n", .{}),
                                else => {},
                            }
                        },
                        '3' => {
                            const c3 = try readByte(reader);
                            if (c3 == null) return;
                            printNibble(c3.?, 412);
                            switch (c3.?) {
                                'A' => std.debug.print("Alt + Up    \r\n", .{}),
                                'B' => std.debug.print("Alt + Down  \r\n", .{}),
                                'C' => std.debug.print("Alt + Right \r\n", .{}),
                                'D' => std.debug.print("Alt + Left  \r\n", .{}),
                                else => {},
                            }
                        },
                        '4' => {
                            const c3 = try readByte(reader);
                            if (c3 == null) return;
                            printNibble(c3.?, 413);
                            switch (c3.?) {
                                'A' => std.debug.print("Alt + Shift + Up    \r\n", .{}),
                                'B' => std.debug.print("Alt + Shift + Down  \r\n", .{}),
                                'C' => std.debug.print("Alt + Shift + Right \r\n", .{}),
                                'D' => std.debug.print("Alt + Shift + Left  \r\n", .{}),
                                else => {},
                            }
                        },
                        '5' => {
                            const c3 = try readByte(reader);
                            if (c3 == null) return;
                            printNibble(c3.?, 413);
                            switch (c3.?) {
                                'A' => std.debug.print("Ctrl + Up    \r\n", .{}),
                                'B' => std.debug.print("Ctrl + Down  \r\n", .{}),
                                'C' => std.debug.print("Ctrl + Right \r\n", .{}),
                                'D' => std.debug.print("Ctrl + Left  \r\n", .{}),
                                else => {},
                            }
                        },
                        '6' => {
                            const c3 = try readByte(reader);
                            if (c3 == null) return;
                            printNibble(c3.?, 414);
                            switch (c3.?) {
                                'A' => std.debug.print("Ctrl + shift + Up    \r\n", .{}),
                                'B' => std.debug.print("Ctrl + shift + Down  \r\n", .{}),
                                'C' => std.debug.print("Ctrl + shift + Right \r\n", .{}),
                                'D' => std.debug.print("Ctrl + shift + Left  \r\n", .{}),
                                else => {},
                            }
                        },
                        '7' => {
                            const c3 = try readByte(reader);
                            if (c3 == null) return;
                            printNibble(c3.?, 414);
                            switch (c3.?) {
                                'A' => std.debug.print("Ctrl + Alt + Up    \r\n", .{}),
                                'B' => std.debug.print("Ctrl + Alt + Down  \r\n", .{}),
                                'C' => std.debug.print("Ctrl + Alt + Right \r\n", .{}),
                                'D' => std.debug.print("Ctrl + Alt + Left  \r\n", .{}),
                                else => {},
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        },
        '2' => {
            const c2 = try readByte(reader);
            if (c2 == null) return;
            printNibble(c2.?, 6);
            switch (c2.?) {
                '0' => std.debug.print("f9 \r\n", .{}),
                '1' => std.debug.print("f10 \r\n", .{}),
                '3' => std.debug.print("f11 \r\n", .{}),
                '4' => std.debug.print("f12 \r\n", .{}),
                '~' => std.debug.print("Insert \r\n", .{}),
                else => {},
            }
            _ = try readByte(reader);
        },
        '3' => std.debug.print("Delete   \r\n", .{}),
        '5' => std.debug.print("Up   page\r\n", .{}),
        '6' => std.debug.print("down page\r\n", .{}),
        'M' => {},
        else => {},
    }
}
