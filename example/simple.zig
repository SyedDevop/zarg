const std = @import("std");
const zarg = @import("zarg");

const Cli = zarg.Cli;
const Color = zarg.ZColor;

const USAGE =
    \\Example to use zarg
    \\------------------
;
const CmdType = Cli.Cmd(UserCmd);

const xmd = [_]CmdType{
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
    CmdType{
        .name = .add,
        .usage = " [OPTIONS] \"EXPRESSION\"",
        .info = "Add two numbers.",
        .min_pos_arg = 1,
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
                .long = "--path",
                .short = "-p",
                .info = "Prints the the path to the executable.",
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
            .{
                .long = "--l",
                .short = "-l",
                .info = "",
                .value = .{ .list = null },
            },
        },
        .min_arg = 0,
    },
    .{
        .name = .list,
        .usage = "m [OPTIONS] \"EXPRESSION\"",
        .info = "List the names of the directories in the current directory.",
        .options = &.{
            .{
                .long = "--print",
                .short = "-p",
                .info = "PPrints the result of the expression.Prints the result of the expression.Prints the result of the expression.rints the result of the expression.",
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

fn printVersion(version_call: Cli.VersionCallFrom) []const u8 {
    return switch (version_call) {
        .version => "Game  on \n V1000",
        .help => "V 1.0.0.0",
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var cli = try Cli.CliInit(UserCmd)
        .init(allocator, "Z Sim", USAGE, .{ .fun = &printVersion }, &xmd);
    defer cli.deinit();

    cli.parse() catch |err| {
        try cli.printParseError(err);
        return;
    };
    const color = Color.Zcolor.init(allocator);
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(allocator);
    var text_w = text.writer(allocator);

    var header_style = Color.Style{
        .fontStyle = .{
            .doublyUnderline = true,
            .italic = true,
        },
        .fgColor = .toColor(245),
    };

    try header_style.render("The Question is:\n", &text_w);
    header_style.fontStyle.bold = true;
    header_style.fontStyle.doublyUnderline = false;
    header_style.fontStyle.italic = false;

    try header_style.render("The Answer is:\n", &text_w);
    std.debug.print("{s}\n", .{text.items});

    const body = try color.fmtRender("{d}", .{56_00}, .{
        .fontStyle = .{ .bold = true, .crossedout = true },
        .padding = .inLine(50, 0),
        .fgColor = .toColor(50),
    });
    defer allocator.free(body);

    std.debug.print("{s}\n", .{body});

    std.debug.print("The Command is     |{t}|\n", .{cli.running_cmd.name});
    std.debug.print("The Input is       |{?any}|\n", .{cli.pos_args});
    std.debug.print("The Rest Input is  |{?any}|\n", .{cli.rest_args});
    switch (cli.running_cmd.name) {
        .add => {
            const a = if (try cli.getNumArg("-a")) |a| a else 0;
            const b = if (try cli.getNumArg("-b")) |b| b else 0;
            const c = if (try cli.getNumArg("-c")) |c| c else 0;
            if (try cli.getBoolArg("-p")) {
                std.debug.print("{s}\n", .{cli.executable_name});
                return;
            } else if (cli.getPosArg(0)) |pos| {
                std.debug.print("This is lit {s}\n", .{pos});
            }
            for (cli.computed_args.items) |v| {
                switch (v.value) {
                    .str => |s| std.debug.print("<str > Computed args V:{?s} L:{s} S:{s} \n", .{ s, v.long, v.short }),
                    .bool => |bo| std.debug.print("<bool> Computed args V:{?any}  L:{s} S:{s} \n", .{ bo, v.long, v.short }),
                    .num => |n| std.debug.print("<num > Computed args V:{?d} L:{s} S:{s} \n", .{ n, v.long, v.short }),
                    .list => |l| std.debug.print("<list> Computed args V:{?any} L:{s} S:{s} \n", .{ l, v.long, v.short }),
                }
            }
            std.debug.print("The Command is add(a:{d}, b:{d}, c:{d})  {d}\n", .{ a, b, c, a + b + c });
        },
        else => {},
    }
}
