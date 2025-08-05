const std = @import("std");
const zarg = @import("zarg");

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

pub fn main() !void {
    var stdout = std.io.getStdOut();
    const sto_writer = stdout.writer();

    var stdin = std.io.getStdIn();
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
    var raw = try terminal.rawModePosix(std.io.getStdOut().handle);
    defer {
        raw.disableRawMode() catch {};
    }
    const clear = zarg.Clear;
    try clear.all_move_curser_top(sto_writer);
    const color = ZColor.Zcolor.init(allocator);
    _ = color;
    try stdout.writeAll("Press Q or Ctr+q to quit \r\n");
    try sto_writer.print("{?any}", .{try terminal.getSize(std.io.getStdOut())});

    while (true) {
        var buf: [1]u8 = undefined;
        const bytes_read = stdin.read(&buf) catch |err| {
            try sto_writer.print("\nError Getting the input: {s}\n", .{@errorName(err)});
            return err;
        };
        if (bytes_read == 0) continue;
        try sto_writer.print("Read {s}-{x}-{d} bytes \r\n", .{ buf, buf, buf });
        if (buf[0] == 'q' or buf[0] == 'Q' or buf[0] == 0x11) { // Q key
            try sto_writer.print("\nBye!\n", .{});
            return;
        }
    }
}
