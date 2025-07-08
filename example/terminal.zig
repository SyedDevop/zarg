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
    _ = terminal;
    const color = ZColor.Zcolor.init(allocator);
    _ = color;
}
