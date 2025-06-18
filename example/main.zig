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
            .{
                .long = "--c",
                .short = "-c",
                .info = "",
                .value = .{ .num = 10 },
            },
            .{
                .long = "--print",
                .short = "-p",
                .info = "Prints the result of the expression.",
                .value = .{ .bool = null },
            },
            .{
                .long = "--eee",
                .short = "-e",
                .info = "Prints the result of the expression.",
                .value = .{ .bool = null },
            },
            .{
                .long = "--fffff",
                .short = "-f",
                .info = "Prints the result of the expression.",
                .value = .{ .bool = null },
            },
            .{
                .long = "--ggggg",
                .short = "-g",
                .info = "Prints the result of the expression.",
                .value = .{ .bool = null },
            },
            .{
                .long = "--o",
                .short = "-o",
                .info = "Prints the result of the expression.",
                .value = .{ .str = null },
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
        .init(allocator, "Z Math", "", "v1.0.0", &xmd);
    defer cli.deinit();

    try cli.parse();

    std.debug.print("The Command is     |{?s}|\n", .{@tagName(cli.running_cmd.name)});
    std.debug.print("The Input is       |{?s}|\n", .{cli.pos_args});
    std.debug.print("The Rest Input is  |{?s}|\n", .{cli.rest_args});
    switch (cli.running_cmd.name) {
        .add => {
            const a = if (try cli.getNumArg("-a")) |a| a else 0;
            const b = if (try cli.getNumArg("-b")) |b| b else 0;
            const c = if (try cli.getNumArg("-c")) |c| c else 0;
            for (cli.computed_args.items) |v| {
                switch (v.value) {
                    .str => |s| std.debug.print("<str > Computed args V:{?s} L:{s} S:{s} \n", .{ s, v.long, v.short }),
                    .bool => |bo| std.debug.print("<bool> Computed args V:{?}  L:{s} S:{s} \n", .{ bo, v.long, v.short }),
                    .num => |n| std.debug.print("<num > Computed args V:{?d} L:{s} S:{s} \n", .{ n, v.long, v.short }),
                }
            }
            std.debug.print("The Command is add(a:{d}, b:{d}, c:{d})  {d}\n", .{ a, b, c, a + b + c });
        },
        else => {},
    }
}
