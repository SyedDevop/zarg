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
    //TODO : Do i need this,
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

fn shift(comptime T: type, xs: *[]T) !T {
    if (xs.len == 0) {
        return error.EmptySlice;
    }
    const first = xs.*[0];
    xs.ptr += 1;
    xs.len -= 1;
    return first;
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

        computed_args: ArgsList,
        cmds: []const CmdT,
        running_cmd: CmdT,

        name: []const u8,
        description: ?[]const u8 = null,
        executable_name: []const u8 = undefined,

        /// Data after the commands and flags.
        data: []const u8 = "",

        /// Rest of the data after --.
        rest: ?[]const []const u8 = null,

        version: []const u8,

        /// The First command is always the root command
        pub fn init(
            allocate: Allocator,
            name: []const u8,
            description: ?[]const u8,
            version: []const u8,
            comptime commands: []const CmdT,
        ) !Self {
            comptime {
                if (commands.len <= 0) @compileError("You need to provided At list one command.");
                const enum_fields = @typeInfo(CmdEnum).Enum.fields;
                for (enum_fields) |field| {
                    var found = false;
                    for (commands) |sb_cmd| {
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
                .name = name,
                .description = description,
                .cmds = commands,
                .running_cmd = commands[0],
                .version = version,
                .computed_args = ArgsList.init(allocate),
            };
        }
        pub fn parse(self: *Self) !void {
            const args = try std.process.argsAlloc(self.alloc);
            defer std.process.argsFree(self.alloc, args);
            std.debug.print("All the cmds |{s}|\n", .{args});
            try self.parseAllArgs(args);
        }
        pub fn parseAllArgs(self: *Self, args: []const []const u8) !void {
            var idx: usize = 0;
            self.executable_name = args[idx];
            idx += 1;
            const cmd = self.getCmd(std.meta.stringToEnum(CmdEnum, if (args.len > idx) args[idx] else ""));
            self.running_cmd = cmd;
            idx += 1;

            if (args.len < idx + self.running_cmd.min_arg) return error.InsufficientArguments;

            if (self.running_cmd.options) |opt| {
                for (opt) |arg| {
                    if (idx < args.len) {
                        const kv_arg = try parseKVArg(args[idx..]);
                        if (std.mem.eql(u8, arg.long, kv_arg.key) or std.mem.eql(u8, arg.short, kv_arg.key)) {
                            var copy_arg = arg;
                            switch (arg.value) {
                                .bool => {
                                    copy_arg.value = .{ .bool = true };
                                    try self.computed_args.append(copy_arg);
                                },
                                .str => {
                                    if (kv_arg.value == null) return error.ValueRequired;
                                    idx += kv_arg.count;
                                    copy_arg.is_alloc = true;
                                    copy_arg.value = .{ .str = try self.alloc.dupe(u8, kv_arg.value.?) };
                                    try self.computed_args.append(copy_arg);
                                },
                                .num => {
                                    if (kv_arg.value == null) return error.ValueRequired;
                                    idx += kv_arg.count;
                                    const num = std.fmt.parseInt(i32, kv_arg.value.?, 10) catch |e| switch (e) {
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
            if (cmd == null) return self.cmds[0];
            for (self.cmds) |value| {
                if (value.name == cmd) return value;
            }
            return self.cmds[0];
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
            const cmd_opt = self.running_cmd;
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
            for (self.cmds) |value| {
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
            // self.alloc.free(self.process_name);
        }
    };
}
/// Represents a parsed key-value argument
///
/// Fields:
/// - `key`: The key portion of the argument, e.g., `"--opt"`
/// - `value`: The optional value portion, or `null` if not present
/// - `count`: Number of additional arguments consumed beyond the key itself
///            during parsing (e.g., to extract a separate `=`, value, or both)
pub const KeyValueArg = struct {
    key: []const u8,
    value: ?[]const u8 = null,
    count: u2,

    fn print(self: *const KeyValueArg) !void {
        std.debug.print("KeyValueArg: key:{s} Val:{?s} Con:{d}\n", .{ self.key, self.value, self.count });
    }
};

/// Splits a single argument of form "key=value" into KeyValueArg,
/// or returns just the key if no '=' is found.
pub fn splitKeyValue(arg: []const u8) KeyValueArg {
    return if (std.mem.indexOf(u8, arg, "=")) |idx| .{
        .key = arg[0..idx],
        .value = if (idx + 1 < arg.len) arg[idx + 1 ..] else null,
        .count = 0,
    } else .{
        .key = arg,
        .value = null,
        .count = 0,
    };
}
/// Parses command-line style key/value arguments.
/// Supports:
///   --opt=value
///   --opt value
///   --opt = value
///   --opt =value
///   --opt= value
pub fn parseKVArg(cmds: []const []const u8) !KeyValueArg {
    if (cmds.len == 0) return error.EmptyArg;
    const startsWith = std.mem.startsWith;
    const eql = std.mem.eql;

    var result = splitKeyValue(cmds[0]);
    if (cmds.len == 1 or result.value != null) return result;

    for (cmds[1..@min(cmds.len, 3)], 1..) |section, i| {
        if (eql(u8, section, "=")) continue;
        result.value = if (startsWith(u8, section, "=")) section[1..] else section;
        result.count = @truncate(i);
        break;
    }
    return result;
}

const TestCase = struct {
    input: []const []const u8,
    expected_key: []const u8,
    expected_value: ?[]const u8,
    expected_count: u3,
};
test "parseKeyValueArgs valid inputs" {
    const strEql = std.testing.expectEqualStrings;
    const deepEql = std.testing.expectEqualDeep;

    const cases = [_]TestCase{
        .{ .input = &.{ "--option", "value1", "value2" }, .expected_key = "--option", .expected_value = "value1", .expected_count = 1 },
        .{ .input = &.{ "--option", "=value1", "value2" }, .expected_key = "--option", .expected_value = "value1", .expected_count = 1 },
        .{ .input = &.{ "--option", "=", "value" }, .expected_key = "--option", .expected_value = "value", .expected_count = 2 },
        .{ .input = &.{"--option=value"}, .expected_key = "--option", .expected_value = "value", .expected_count = 0 },
        .{ .input = &.{ "--option", "value" }, .expected_key = "--option", .expected_value = "value", .expected_count = 1 },
        .{ .input = &.{ "--option", "=value" }, .expected_key = "--option", .expected_value = "value", .expected_count = 1 },
        .{ .input = &.{ "--option=", "value" }, .expected_key = "--option", .expected_value = "value", .expected_count = 1 },
        .{ .input = &.{"--option"}, .expected_key = "--option", .expected_value = null, .expected_count = 0 },
        .{ .input = &.{"--option="}, .expected_key = "--option", .expected_value = null, .expected_count = 0 },
        .{ .input = &.{ "--option", "=" }, .expected_key = "--option", .expected_value = null, .expected_count = 0 },
    };

    for (cases, 0..) |test_case, i| {
        const result = try parseKVArg(test_case.input);
        try strEql(test_case.expected_key, result.key);
        try deepEql(test_case.expected_value, result.value);
        std.testing.expectEqual(test_case.expected_count, result.count) catch |err| {
            if (err == error.TestExpectedEqual) {
                std.debug.print("The Failed test case is index |{d}|\n", .{i});
                return error.TestExpectedEqual;
            }
        };
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
        .{ .input = &.{"="}, .expected_key = "", .expected_value = null, .expected_count = 0 },
        .{ .input = &.{"=value"}, .expected_key = "", .expected_value = "value", .expected_count = 0 },
        .{ .input = &.{"key=="}, .expected_key = "key", .expected_value = "=", .expected_count = 0 },
        .{ .input = &.{"key=hello=r"}, .expected_key = "key", .expected_value = "hello=r", .expected_count = 0 },
        .{ .input = &.{"key==extra"}, .expected_key = "key", .expected_value = "=extra", .expected_count = 0 },
        .{ .input = &.{ " ", "=" }, .expected_key = " ", .expected_value = null, .expected_count = 0 },
        .{ .input = &.{ " key ", "=", " value " }, .expected_key = " key ", .expected_value = " value ", .expected_count = 2 },
        .{ .input = &.{"1=2"}, .expected_key = "1", .expected_value = "2", .expected_count = 0 },
        .{ .input = &.{ "#!$", "=", "@!%" }, .expected_key = "#!$", .expected_value = "@!%", .expected_count = 2 },
        .{ .input = &.{ "--", "=" }, .expected_key = "--", .expected_value = null, .expected_count = 0 },
        .{ .input = &.{ "--=", "value" }, .expected_key = "--", .expected_value = "value", .expected_count = 1 },
        .{ .input = &.{ "asdad", "--value" }, .expected_key = "--value", .expected_value = null, .expected_count = 1 },
        // .{ .input = &.{ "asdad", "--value", "=" }, .expected_key = "--value", .expected_value = null, .expected_count = 1 },
        // .{ .input = &.{ "--12=23", "=", "11" }, .expected_key = "--12", .expected_value = "23" },
    };

    for (cases, 0..) |test_case, i| {
        const result = try parseKVArg(test_case.input);
        // std.debug.print("Key {s} Value{any}", .{ result.key, result.value });
        try strEql(test_case.expected_key, result.key);
        try deepEql(test_case.expected_value, result.value);
        std.testing.expectEqual(test_case.expected_count, result.count) catch |err| {
            if (err == error.TestExpectedEqual) {
                std.debug.print("The Failed test case is index |{d}|\n", .{i});
                return error.TestExpectedEqual;
            }
        };
    }
}
