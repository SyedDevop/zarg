const std = @import("std");
const builtins = @import("builtin");
const Allocator = std.mem.Allocator;

pub const CmdName = enum {
    root,

    pub fn getCmdNameList(alloc: Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(alloc);
        inline for (@typeInfo(CmdName).Enum.fields) |field| {
            if (field.value == 0) continue;
            try result.appendSlice(field.name);
            try result.append(' ');
        }

        return result.toOwnedSlice(); // Return only the filled portion of the array
    }
};

pub const ArgValue = union(enum) {
    str: ?[]const u8,
    bool: ?bool,
    num: ?i32,

    pub fn free(self: *ArgValue, allocator: Allocator) !void {
        switch (self.*) {
            .str => |str| if (str) |s| allocator.free(s),
            else => {},
        }
    }
};
pub const Arg = struct {
    long: []const u8,
    short: []const u8,
    info: []const u8,
    value: ArgValue,
    is_alloc: bool = false,
};
pub const ArgError = error{};

pub const ArgsList = std.ArrayList(Arg);

pub fn isHelpOption(opt: []const u8) bool {
    return (std.mem.eql(u8, "-h", opt) or std.mem.eql(u8, "--help", opt));
}
pub fn isVersionOption(opt: []const u8) bool {
    return (std.mem.eql(u8, "-v", opt) or std.mem.eql(u8, "--version", opt));
}

pub fn Cmd(comptime CmdEnum: type) type {
    return struct {
        name: CmdEnum,
        usage: []const u8,
        example: ?[]const u8 = null,
        info: ?[]const u8 = null,
        min_arg: u8 = 1,
        options: ?[]const Arg = null,
    };
}

const cmdList: []const Cmd = &.{};
pub fn Cli(comptime CmdEnum: type) type {
    comptime {
        if (@typeInfo(CmdEnum) != .Enum) {
            @compileError("CmdEnum must be an enum type; Found  " ++ @typeName(CmdEnum));
        }
    }
    const CmdT = Cmd(CmdEnum);
    return struct {
        pub const Self = @This();
        alloc: Allocator,

        name: []const u8,
        description: ?[]const u8 = null,
        process_name: []const u8 = "",

        computed_args: ArgsList,
        subCmds: []const CmdT,
        rootCmd: CmdT,
        cmd: CmdT,
        data: []const u8 = "",

        version: []const u8,

        errorMess: []u8,

        pub fn init(
            allocate: Allocator,
            program_name: []const u8,
            description: ?[]const u8,
            version: []const u8,
            root: CmdT,
            comptime sub_commands: []const CmdT,
        ) !Self {
            comptime {
                const enum_fields = @typeInfo(CmdEnum).Enum.fields;
                for (enum_fields) |field| {
                    var found = false;
                    for (sub_commands) |sb_cmd| {
                        if (@intFromEnum(sb_cmd.name) == field.value) {
                            if (found) {
                                @compileError("Duplicate sub command found with name: " ++ field.name);
                            }
                            found = true;
                        }
                    }

                    //TODO : Should root and sub commands be in same list
                    // If not this will cause a compile error.
                    // For just printing the a warning.

                    if (!found) {
                        //@compileError("Sub Command not found: " ++ field.name);
                        //@compileLog("Sub Command not found: " ++ field.name);
                    }
                }
            }
            return .{
                .alloc = allocate,
                .name = program_name,
                .description = description,
                .subCmds = sub_commands,
                .rootCmd = root,
                .cmd = root,
                .version = version,
                .computed_args = ArgsList.init(allocate),
                .errorMess = try allocate.alloc(u8, 255),
            };
        }
        pub fn parse(self: *Self) !void {
            const args = try std.process.argsAlloc(self.alloc);
            defer std.process.argsFree(self.alloc, args);

            var idx: usize = 1;
            const cmdEnum = if (args.len == 1) self.rootCmd.name else std.meta.stringToEnum(CmdEnum, args[idx]);
            const cmd = self.getCmd(cmdEnum);

            self.cmd = cmd;
            self.process_name = try self.alloc.dupe(u8, args[0]);
            if (cmd.name != .root) {
                idx += 1;
            }
            if (args.len < idx + cmd.min_arg) {
                std.debug.print("\x1b[1;31m[Error]: Insufficient arguments provided.\x1b[0m\n\n", .{});
                try self.help();
                std.process.exit(0);
            }

            if (self.cmd.options) |opt| {
                for (opt) |arg| {
                    if (idx < args.len and (std.mem.eql(u8, arg.long, args[idx]) or std.mem.eql(u8, arg.short, args[idx]))) {
                        var copy_arg = arg;
                        switch (arg.value) {
                            .bool => {
                                copy_arg.value = .{ .bool = true };
                                try self.computed_args.append(copy_arg);
                            },
                            .str => {
                                if (idx + 1 >= args.len) {
                                    std.debug.print("Error: value reqaired after '{s}'", .{args[idx]});
                                    std.process.exit(1);
                                }
                                idx += 1;
                                copy_arg.is_alloc = true;
                                copy_arg.value = .{ .str = try self.alloc.dupe(u8, args[idx]) };
                                try self.computed_args.append(copy_arg);
                            },
                            .num => {
                                if (idx + 1 >= args.len) {
                                    std.debug.print("Error: value reqaired after '{s}'", .{args[idx]});
                                    std.process.exit(1);
                                }
                                idx += 1;
                                const num = std.fmt.parseInt(i32, args[idx], 10) catch |e| switch (e) {
                                    error.InvalidCharacter => null,
                                    else => return e,
                                };
                                copy_arg.value = .{ .num = num };
                                try self.computed_args.append(copy_arg);
                            },
                        }
                        idx += 1;
                    } else {
                        // NOTE: If an argument has a default value and is not provided,
                        // add it to computed_args.
                        switch (arg.value) {
                            .bool => |b| if (b != null) try self.computed_args.append(arg),
                            .str => |s| if (s != null) try self.computed_args.append(arg),
                            .num => |n| if (n != null) try self.computed_args.append(arg),
                        }
                    }
                }
            }

            if (idx >= args.len) return;
            if (isHelpOption(args[idx])) {
                try self.help();
                std.process.exit(0);
            } else if (isVersionOption(args[idx])) {
                std.debug.print("Z Math {s}", .{self.version});
                std.process.exit(0);
            }

            var argList = std.ArrayList(u8).init(self.alloc);
            defer argList.deinit();
            for (args[idx..]) |arg| {
                try argList.appendSlice(arg);
                try argList.append(' ');
            }
            self.data = try argList.toOwnedSlice();
        }

        fn getCmd(self: Self, cmd: ?CmdEnum) CmdT {
            if (cmd == null) return self.rootCmd;
            for (self.subCmds) |value| {
                if (value.name == cmd) return value;
            }
            return self.rootCmd;
        }

        pub fn getStrArg(self: Self, arg_name: []const u8) !?[]const u8 {
            for (self.computed_args.items) |arg| {
                if (std.mem.eql(u8, arg.long, arg_name) or std.mem.eql(u8, arg.short, arg_name)) {
                    if (arg.value != .str) {
                        return error.ArgIsNotStr;
                    }
                    return arg.value.str;
                }
            }
            return null;
        }

        pub fn getNumArg(self: Self, arg_name: []const u8) !?i32 {
            for (self.computed_args.items) |arg| {
                if (std.mem.eql(u8, arg.long, arg_name) or std.mem.eql(u8, arg.short, arg_name)) {
                    if (arg.value != .num) {
                        return error.ArgIsNotNum;
                    }
                    return arg.value.num;
                }
            }
            return null;
        }
        pub fn getBoolArg(self: Self, arg_name: []const u8) !bool {
            for (self.computed_args.items) |arg| {
                if (std.mem.eql(u8, arg.long, arg_name) or std.mem.eql(u8, arg.short, arg_name)) {
                    if (arg.value != .bool) {
                        return error.ArgIsNotBool;
                    }
                    if (arg.value.bool) |val| {
                        return val;
                    } else {
                        return false;
                    }
                }
            }
            return false;
        }

        pub fn help(self: Self) !void {
            const padding = 20;
            const stdout = std.io.getStdOut().writer();
            if (self.description) |dis| {
                try stdout.print("Z Math {s}\n{s}\n\n", .{ self.version, dis });
            }
            const cmd_opt = self.cmd;
            try stdout.print("USAGE: \n", .{});
            try stdout.print("  {s}\n\n", .{cmd_opt.usage});
            if (cmd_opt.info) |info| {
                try stdout.print("INFO: \n", .{});
                try stdout.print("  {s}\n\n", .{info});
            }
            if (cmd_opt.example) |ex| {
                try stdout.print("EXAMPLE: \n", .{});
                try stdout.print("  {s}\n\n", .{ex});
            }
            try stdout.print("OPTIONS: \n", .{});
            if (cmd_opt.options) |opt| {
                for (opt) |value| {
                    var opt_len: usize = 0;
                    opt_len += value.short.len;
                    try stdout.print(" {s},", .{value.short});

                    opt_len += value.long.len;
                    try stdout.print(" {s}", .{value.long});

                    for (0..(padding - opt_len)) |_| {
                        try stdout.print(" ", .{});
                    }
                    try stdout.print("{s}\n", .{value.info});
                }
            }
            try stdout.print(" -h, --help            Help message.\n", .{});
            try stdout.print(" -v, --version         App version.\n", .{});
            try stdout.print("\n", .{});
            if (cmd_opt.name != .root) return;
            try stdout.print("COMMANDS: \n", .{});
            for (self.subCmds) |value| {
                if (value.info) |info| {
                    const name = @tagName(value.name);
                    try stdout.print(" {s}", .{name});
                    for (0..(padding - name.len)) |_| {
                        try stdout.print(" ", .{});
                    }
                    try stdout.print("{s}\n", .{info});
                }
            }
        }
        pub fn deinit(self: *Self) void {
            for (self.computed_args.items) |*item| if (item.is_alloc) try item.value.free(self.alloc);
            self.computed_args.deinit();
            self.alloc.free(self.data);
            self.alloc.free(self.errorMess);
            self.alloc.free(self.process_name);
        }
    };
}

const KeyValueArg = struct {
    key: []const u8,
    value: ?[]const u8 = null,
};

/// Splits a single argument of form "key=value" into KeyValueArg,
/// or returns just the key if no '=' is found.
fn splitKeyValue(arg: []const u8) KeyValueArg {
    return if (std.mem.indexOf(u8, arg, "=")) |idx| .{
        .key = arg[0..idx],
        .value = if (idx + 1 < arg.len) arg[idx + 1 ..] else null,
    } else .{
        .key = arg,
        .value = null,
    };
}
/// Parses command-line style key/value arguments.
/// Supports:
///   --opt=value
///   --opt value
///   --opt = value
///   --opt =value
///   --opt= value
fn parseKVArg(cmds: []const []const u8) !KeyValueArg {
    if (cmds.len == 0) return error.EmptyArg;
    const startsWith = std.mem.startsWith;
    const eql = std.mem.eql;

    // Initialize from the first part
    var result = splitKeyValue(cmds[0]);
    switch (cmds.len) {
        1 => return result,
        2 => {
            const second = cmds[1];
            if (eql(u8, second, "=")) return result;
            result.value = if (startsWith(u8, second, "=")) second[1..] else second;
            return result;
        },
        else => {
            const second = cmds[1];
            if (!std.mem.eql(u8, second, "=")) return error.InvalidArgStyle;
            result.value = cmds[2];
            return result;
        },
    }
    unreachable;
}

const TestCase = struct {
    input: []const []const u8,
    expected_key: []const u8,
    expected_value: ?[]const u8,
};
test "parseKeyValueArgs valid inputs" {
    const strEql = std.testing.expectEqualStrings;
    const deepEql = std.testing.expectEqualDeep;

    const cases = [_]TestCase{
        .{ .input = &.{ "--option", "=", "value" }, .expected_key = "--option", .expected_value = "value" },
        .{ .input = &.{"--option=value"}, .expected_key = "--option", .expected_value = "value" },
        .{ .input = &.{ "--option", "value" }, .expected_key = "--option", .expected_value = "value" },
        .{ .input = &.{ "--option", "=value" }, .expected_key = "--option", .expected_value = "value" },
        .{ .input = &.{ "--option=", "value" }, .expected_key = "--option", .expected_value = "value" },
        .{ .input = &.{"--option"}, .expected_key = "--option", .expected_value = null },
        .{ .input = &.{"--option="}, .expected_key = "--option", .expected_value = null },
        .{ .input = &.{ "--option", "=" }, .expected_key = "--option", .expected_value = null },
    };

    for (cases) |test_case| {
        const result = try parseKVArg(test_case.input);
        try strEql(test_case.expected_key, result.key);
        try deepEql(test_case.expected_value, result.value);
    }
}

test "parseKeyValueArgs invalid inputs" {
    const expectError = std.testing.expectError;

    const TestCaseError = struct {
        input: []const []const u8,
        expected_error: anyerror,
    };

    const cases = [_]TestCaseError{
        .{ .input = &.{}, .expected_error = error.EmptyArg },
        .{ .input = &.{ "--option", "value1", "value2" }, .expected_error = error.InvalidArgStyle },
    };

    for (cases) |test_case| {
        const result = parseKVArg(test_case.input);
        try expectError(test_case.expected_error, result);
    }
}
test "parseKeyValueArgs additional edge cases" {
    const strEql = std.testing.expectEqualStrings;
    const deepEql = std.testing.expectEqualDeep;

    const cases = [_]TestCase{
        .{ .input = &.{"="}, .expected_key = "", .expected_value = null },
        .{ .input = &.{"=value"}, .expected_key = "", .expected_value = "value" },
        .{ .input = &.{"key=="}, .expected_key = "key", .expected_value = "=" },
        .{ .input = &.{"key=hello=r"}, .expected_key = "key", .expected_value = "hello=r" },
        .{ .input = &.{"key==extra"}, .expected_key = "key", .expected_value = "=extra" },
        .{ .input = &.{ " ", "=" }, .expected_key = " ", .expected_value = null },
        .{ .input = &.{ " key ", "=", " value " }, .expected_key = " key ", .expected_value = " value " },
        .{ .input = &.{"1=2"}, .expected_key = "1", .expected_value = "2" },
        .{ .input = &.{ "#!$", "=", "@!%" }, .expected_key = "#!$", .expected_value = "@!%" },
        .{ .input = &.{ "--", "=" }, .expected_key = "--", .expected_value = null },
        .{ .input = &.{ "--=", "value" }, .expected_key = "--", .expected_value = "value" },
        // .{ .input = &.{ "--12=23", "=", "11" }, .expected_key = "--12", .expected_value = "23" },
    };

    for (cases) |test_case| {
        const result = try parseKVArg(test_case.input);
        // std.debug.print("Key {s} Value{any}", .{ result.key, result.value });
        try strEql(test_case.expected_key, result.key);
        try deepEql(test_case.expected_value, result.value);
    }
}
