const std = @import("std");
const zarg = @import("zarg");

const Cli = zarg.cli;
const Color = zarg.color;

const USAGE =
    \\Example to use zarg
    \\------------------
;
const CmdType = zarg.Cmd(UserCmd);

const xmd = [_]CmdType{
    .{
        .name = .root,
        .usage = "m [OPTIONS] \"EXPRESSION\"",
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
    .{
        .name = .add,
        .usage = "m [OPTIONS] \"EXPRESSION\"",
        .options = &.{
            .{
                .long = "--a",
                .short = "-a",
                .info = "",
                .value = .{ .num = null },
            },
            .{
                .long = "--b",
                .short = "-b",
                .info = "",
                .value = .{ .num = null },
            },
        },
        .min_arg = 0,
    },
    .{
        .name = .list,
        .usage = "m [OPTIONS] \"EXPRESSION\"",
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

pub const UserCmd = enum {
    root,
    add,
    remove,
    list,
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var cli = try zarg.Cli(UserCmd)
        .init(allocator, "", "", "", &xmd);

    defer cli.deinit();

    try cli.parse();
    const input = cli.data;
    std.debug.print("The Input is {s}\n", .{input});

    std.debug.print("The Command is |{?s}|", .{@tagName(cli.running_cmd.name)});
    switch (cli.running_cmd.name) {
        .add => {
            const a = if (try cli.getNumArg("-a")) |a| a else 0;
            const b = if (try cli.getNumArg("-b")) |b| b else 0;
            std.debug.print("The Command is add(a:{d},b:{d})  {d}", .{ a, b, a + b });
        },
        else => {},
    }
}
