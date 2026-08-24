const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const cmd = @import("cmd.zig");
const CliInit = cmd.CliInit;
const CliParseError = cmd.CliParseError;
const Arg = cmd.Arg;
const ArgValue = cmd.ArgValue;
const ComputedArgs = cmd.ComputedArgs;
const RawArgs = @import("slice.zig").RawArgs;

const MESSAGE = "Got this message";
const TestCmd = enum {
    root,
    add,
    sub,
    mul,
};

const TestCommands = [_]cmd.Cmd(TestCmd){
    .{
        .name = .root,
        .usage = "[OPTIONS] <COMMAND>",
        .info = "Root command",
        .min_arg = 0,
    },
    .{
        .name = .add,
        .usage = "[OPTIONS] <NUM1> <NUM2>",
        .info = "Add two numbers",
        .min_pos_arg = 0,
        .options = &.{
            .{
                .long = "verbose",
                .short = 'V',
                .info = "Enable verbose output",
                .value = .{ .bool = null },
            },
            .{
                .long = "output",
                .short = 'o',
                .info = "Output file",
                .value = .{ .str = null },
            },
            .{
                .long = "count",
                .short = 'c',
                .info = "Number of times to repeat",
                .value = .{ .num = null },
            },
            .{
                .long = "print",
                .short = 'p',
                .info = "Print result",
                .value = .{ .bool = false },
            },
            .{
                .long = "message",
                .short = 'm',
                .info = "This is message.",
                .value = .{ .str = MESSAGE },
            },
        },
        .min_arg = 0,
    },
    .{
        .name = .sub,
        .usage = "<NUM1> <NUM2>",
        .info = "Subtract two numbers",
        .min_pos_arg = 2,
        .min_arg = 0,
    },
    .{
        .name = .mul,
        .usage = "<NUM1> <NUM2>",
        .info = "Multiply two numbers",
        .min_pos_arg = 0,
        .min_arg = 0,
    },
};

fn createTestCli(allocator: Allocator) !CliInit(TestCmd) {
    return try CliInit(TestCmd).init(
        allocator,
        "test-app",
        "A test application",
        .{ .str = "1.0.0" },
        &TestCommands,
    );
}
fn createArgs(alloc: Allocator, args: []const []const u8) !RawArgs {
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    try raw_args.appendSlice(alloc, args);
    return raw_args;
}

test "default value is correctly updated when argument is provided" {
    const alloc = std.testing.allocator;

    var raw_args = try createArgs(alloc, &.{ "test-app", "add", "--message", "This is the new Message", "-p" });
    defer raw_args.deinit(alloc);

    var cli = try createTestCli(alloc);
    defer cli.deinit();
    try cli.parseAllArgs(&raw_args);

    const message = try cli.getStrArg("message");
    try std.testing.expect(message != null);
    try std.testing.expectEqualStrings("This is the new Message", message.?);

    const print = try cli.getBoolArgOrNull("print");
    try std.testing.expect(print != null);
    try std.testing.expectEqual(true, print);
}

test "check string value is set correctly for default values" {
    const alloc = std.testing.allocator;

    var raw_args = try createArgs(alloc, &.{ "test-app", "add" });
    defer raw_args.deinit(alloc);

    var cli = try createTestCli(alloc);
    defer cli.deinit();
    try cli.parseAllArgs(&raw_args);

    const message = try cli.getStrArg("message");
    try std.testing.expect(message != null);
    try std.testing.expectEqualStrings(MESSAGE, message.?);
}

test "uses default values when arguments are omitted" {
    const alloc = std.testing.allocator;

    var raw_args = try createArgs(alloc, &.{ "test-app", "add" });
    defer raw_args.deinit(alloc);

    var cli = try createTestCli(alloc);
    defer cli.deinit();
    try cli.parseAllArgs(&raw_args);

    const print = try cli.getBoolArgOrNull("print");
    try std.testing.expect(print != null);
    try std.testing.expectEqual(false, print);
}

test "CliInit creates CLI with correct defaults" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    const args = &[_][]const u8{"test-app"};
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    try raw_args.appendSlice(alloc, args);
    try cli.parseAllArgs(&raw_args);
    raw_args.deinit(alloc);

    try expectEqualStrings("test-app", cli.name);
    try expectEqualStrings("1.0.0", cli.version.str);
    cli.deinit();
}

test "parseAllArgs with no arguments returns root command" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{"test-app"};
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqual(TestCmd.root, cli.running_cmd.name);
}

test "parseAllArgs parses subcommand" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqual(TestCmd.add, cli.running_cmd.name);
}

test "parseAllArgs parses positional arguments" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqual(TestCmd.add, cli.running_cmd.name);
    try expectEqualStrings("5", cli.getPosArg(0).?);
    try expectEqualStrings("10", cli.getPosArg(1).?);
}

test "parseAllArgs parses long option with value" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "--output", "file.txt", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqual(TestCmd.add, cli.running_cmd.name);
    const output = try cli.getStrArg("output");
    try expectEqualStrings("file.txt", output.?);
}

test "parseAllArgs parses long option with equals sign" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "--output=result.txt", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const output = try cli.getStrArg("output");
    try expectEqualStrings("result.txt", output.?);
}

test "parseAllArgs parses short option with value" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "-o", "myfile.txt", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const output = try cli.getStrArg("output");
    try expectEqualStrings("myfile.txt", output.?);
}

test "parseAllArgs parses short boolean option" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "-V", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const verbose = try cli.getBoolArg("verbose");
    try expectEqual(true, verbose);
}

test "parseAllArgs parses long boolean option" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "--verbose", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const verbose = try cli.getBoolArg("verbose");
    try expectEqual(true, verbose);
}

test "parseAllArgs parses numeric option" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "--count", "42", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const count = try cli.getNumArg("count");
    try expectEqual(@as(i32, 42), count.?);
}

test "parseAllArgs parses combined short options" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "-Vo", "combined.txt", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const verbose = try cli.getBoolArg("verbose");
    try expectEqual(true, verbose);
    const output = try cli.getStrArg("output");
    try expectEqualStrings("combined.txt", output.?);
}

test "parseAllArgs returns error for unknown option" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "--unknown", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    const result = cli.parseAllArgs(&raw_args);
    try expectError(CliParseError.UnknownOption, result);
}

test "parseAllArgs returns error when value required but not provided" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "--output" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    const result = cli.parseAllArgs(&raw_args);
    try expectError(CliParseError.ValueRequired, result);
}

test "parseAllArgs returns error for insufficient positional args" {
    const alloc = std.testing.allocator;

    const test_commands_local = [_]cmd.Cmd(TestCmd){
        .{
            .name = .root,
            .usage = "[OPTIONS] <COMMAND>",
            .info = "Root command",
            .min_arg = 0,
        },
        .{
            .name = .add,
            .usage = "<NUM1> <NUM2>",
            .info = "Add two numbers",
            .min_pos_arg = 2,
            .min_arg = 0,
        },
    };

    var cli = try CliInit(TestCmd).init(
        alloc,
        "test-app",
        "A test application",
        .{ .str = "1.0.0" },
        &test_commands_local,
    );

    const args = &[_][]const u8{ "test-app", "add", "5" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    try raw_args.appendSlice(alloc, args);

    const result = cli.parseAllArgs(&raw_args);
    try expectError(CliParseError.MinPosArg, result);

    raw_args.deinit(alloc);
    cli.deinit();
}

test "parseAllArgs parses rest args after --" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "--", "--force", "-v", "file.txt" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expect(cli.rest_args != null);
    try expectEqual(@as(usize, 3), cli.rest_args.?.len);
    try expectEqualStrings("--force", cli.rest_args.?[0]);
    try expectEqualStrings("-v", cli.rest_args.?[1]);
    try expectEqualStrings("file.txt", cli.rest_args.?[2]);
}

test "parseAllArgs with help option returns ShowHelp error" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "--help" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    const result = cli.parseAllArgs(&raw_args);
    try expectError(CliParseError.ShowHelp, result);
}

test "parseAllArgs with short help option returns ShowHelp error" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "-h" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    const result = cli.parseAllArgs(&raw_args);
    try expectError(CliParseError.ShowHelp, result);
}

test "parseAllArgs with version option returns ShowVersion error" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "--version" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    const result = cli.parseAllArgs(&raw_args);
    try expectError(CliParseError.ShowVersion, result);
}

test "parseAllArgs with short version option returns ShowVersion error" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "-v" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    const result = cli.parseAllArgs(&raw_args);
    try expectError(CliParseError.ShowVersion, result);
}

test "getPosArg returns null for out of bounds index" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "5" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expect(cli.getPosArg(0) != null);
    try expect(cli.getPosArg(1) == null);
    try expect(cli.getPosArg(100) == null);
}

test "getAllPosArgAsStr concatenates all positional arguments" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "hello", "world", "foo" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const result = try cli.getAllPosArgAsStr();
    try expect(result != null);
    try expectEqualStrings("hello world foo ", result.?);
    alloc.free(result.?);
}

test "ArgValue isNull returns true for null values" {
    const str_val: ArgValue = .{ .str = null };
    const bool_val: ArgValue = .{ .bool = null };
    const num_val: ArgValue = .{ .num = null };
    const list_val: ArgValue = .{ .list = null };
    try expect(str_val.isNull());
    try expect(bool_val.isNull());
    try expect(num_val.isNull());
    try expect(list_val.isNull());
}

test "ArgValue isNull returns false for non-null values" {
    const str_val: ArgValue = .{ .str = "test" };
    const bool_val: ArgValue = .{ .bool = true };
    const num_val: ArgValue = .{ .num = 42 };
    try expect(!str_val.isNull());
    try expect(!bool_val.isNull());
    try expect(!num_val.isNull());
}

test "getStrArg returns error for non-string argument" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "-V", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const result = cli.getStrArg("verbose");
    try expectError(error.ArgIsNotStr, result);
}

test "getNumArg returns error for non-numeric argument" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "-V", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    const result = cli.getNumArg("verbose");
    try expectError(error.ArgIsNotNum, result);
}

test "deinit properly frees allocated memory" {
    const alloc = std.testing.allocator;

    {
        var cli = try createTestCli(alloc);
        const args = &[_][]const u8{ "test-app", "add", "--output", "test.txt", "5", "10" };
        var raw_args = try RawArgs.initCapacity(alloc, args.len);
        try raw_args.appendSlice(alloc, args);
        try cli.parseAllArgs(&raw_args);
        raw_args.deinit(alloc);
        cli.deinit();
    }
}

test "parseAllArgs handles command without options" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "sub", "10", "5" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqual(TestCmd.sub, cli.running_cmd.name);
    try expectEqualStrings("10", cli.getPosArg(0).?);
    try expectEqualStrings("5", cli.getPosArg(1).?);
}

test "parseAllArgs with invalid subcommand defaults to root" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "invalid_cmd", "5", "10" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqual(TestCmd.root, cli.running_cmd.name);
}

test "multiple positional arguments are all accessible" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "add", "a", "b", "c", "d", "e" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqualStrings("a", cli.getPosArg(0).?);
    try expectEqualStrings("b", cli.getPosArg(1).?);
    try expectEqualStrings("c", cli.getPosArg(2).?);
    try expectEqualStrings("d", cli.getPosArg(3).?);
    try expectEqualStrings("e", cli.getPosArg(4).?);
    try expect(cli.getPosArg(5) == null);
}

test "parseAllArgs with only positional arguments on root" {
    const alloc = std.testing.allocator;

    var cli = try createTestCli(alloc);
    defer cli.deinit();

    const args = &[_][]const u8{ "test-app", "hello", "world" };
    var raw_args = try RawArgs.initCapacity(alloc, args.len);
    defer raw_args.deinit(alloc);
    try raw_args.appendSlice(alloc, args);

    try cli.parseAllArgs(&raw_args);

    try expectEqual(TestCmd.root, cli.running_cmd.name);
    try expectEqualStrings("hello", cli.getPosArg(0).?);
    try expectEqualStrings("world", cli.getPosArg(1).?);
}
