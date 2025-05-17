const std = @import("std");
const zarg = @import("zarg");

const Cli = zarg.cli;
const Color = zarg.color;

const USAGE =
    \\Example to use zarg
    \\------------------
;
const CmdType = zarg.Cmd(UserCmd);

const rootCmd: CmdType = .{
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
};

const xmd = [_]CmdType{
    .{
        .name = .add,
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
        .init(allocator, "", "", "", rootCmd, &xmd);

    defer cli.deinit();

    try cli.parse();
    const input = cli.data;
    std.debug.print("The Input is {s}", .{input});

    std.debug.print("The Command is Root {?s}", .{@tagName(cli.cmd.name)});
    // switch (cli.cmd.name) {
    //     .root => {
    //         const p = try cli.getStrArg("-p");
    //         std.debug.print("The Command is Root {?s}", .{p});
    //     },
    //     else => {},
    // }
}
