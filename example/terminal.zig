const std = @import("std");
const zarg = @import("zarg");

const os = std.os;
const win = os.windows;
const winK = win.kernel32;
const builtin = @import("builtin");
const Cli = zarg.Cli;
const ZColor = zarg.ZColor;

const is_windows = builtin.os.tag == .windows;

var print_log: bool = true;
var stdout_buffer: [1024]u8 = undefined;
var stdin_buffer: [1]u8 = undefined;

pub fn main() !void {
    var stdout = std.fs.File.stdout();

    var sto_writer = stdout.writer(&stdout_buffer).interface;
    const stdin = std.fs.File.stdin();
    var stdin_r = stdin.reader(&stdin_buffer);
    // const sti_writer = stdin.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const terminal = zarg.Term;
    const mouse = terminal.MouseMode{ .normal = true };
    var keys = try zarg.Keys.init(&stdin_r.interface, stdin.handle);

    var raw = try terminal.rawMode(stdin.handle);
    defer {
        raw.disableRawMode() catch {};
    }

    const clear = zarg.Clear;
    try clear.allMoveCurserTop(&sto_writer);
    const color = ZColor.Zcolor.init(allocator);
    _ = color;
    try sto_writer.print("Press Q or Ctr+q to quit \r\n", .{});
    try sto_writer.print("{?any}\n\r", .{try terminal.getSize(stdout)});
    try sto_writer.flush();

    try mouse.enableMouseEvent(&sto_writer);
    defer mouse.disableMouseEvent(&sto_writer) catch {};

    // var index: usize = 0;
    while (true) {
        // const key = try keys.next();
        // if (key == .Esc or
        //     key.isKey('q') or
        //     key.isKey('Q'))
        // {
        //     try sto_writer.print("\rBye!\n", .{});
        //     try sto_writer.flush();
        //     return;
        // }
        // if (key.getChar()) |c| {
        //     try sto_writer.print("{c}", .{c});
        // } else if (key == .Enter) {
        //     try sto_writer.print("\r\n", .{});
        // } else if (key == .BackSpace) {
        //     try clear.clearLeftChar(&sto_writer);
        // }
        switch (try keys.next()) {
            .Ctrl => |ct| switch (ct) {
                'c' => try zarg.Clear.allMoveCurserTop(&sto_writer),
                else => {},
            },
            .Char => |c| switch (c) {
                'p' => print_log = print_log != true,
                'q', 'Q', 0x11 => { // Q key{
                    try sto_writer.print("\rBye!\n", .{});
                    try sto_writer.flush();
                    return;
                },
                else => {
                    try sto_writer.print("{c}", .{c});
                },
            },
            .Enter => {
                try sto_writer.print("\r\n", .{});
            },
            .BackSpace => {
                try clear.clearLeftChar(&sto_writer);
            },
            .Esc => {
                try sto_writer.print("\rBye!\n", .{});
                try sto_writer.flush();
                return;
            },
            .None => {},
            else => |el| {
                try sto_writer.print("{t}\r\n", .{el});
            },
        }
        try sto_writer.flush();
    }
}
