const std = @import("std");
const slice = @import("slice.zig");
const util = @import("utils.zig");
const Allocator = std.mem.Allocator;
const RawArgs = slice.RawArgs;

//TODO: Create a proper error logger.
//TODO: Check for Duplicate arguments.
//TODO: Nested Subcommands
//TODO: Code lean up reduce the Duplicate code.

pub const ArgValue = union(enum) {
    str: ?[]const u8,
    bool: ?bool,
    num: ?i32,
    list: ?[][]const u8,

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

pub const ArgsList = std.ArrayList(Arg);

fn isHelpOption(opt: []const u8) bool {
    return (std.mem.eql(u8, "-h", opt) or std.mem.eql(u8, "--help", opt));
}
fn isVersionOption(opt: []const u8) bool {
    return (std.mem.eql(u8, "-v", opt) or std.mem.eql(u8, "--version", opt));
}

pub fn Cmd(comptime CmdEnum: type) type {
    return struct {
        name: CmdEnum,
        usage: []const u8,
        example: ?[]const u8 = null,
        info: ?[]const u8 = null,

        /// Minimum arguments required.
        /// default is 1.
        min_arg: u8 = 1,

        /// Minimum position arguments required.
        /// default is 0
        min_pos_arg: u8 = 0,

        options: ?[]const Arg = null,
    };
}

pub const CliParseError = error{
    InsufficientArguments,
    ShowHelp,
    ShowVersion,
    ValueRequired,
    UnknownOption,
    MinPosArg,
    NumberStringGroupedFlagInLast,
};
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

        /// pos_args (Positional arguments) interleaved with commands and flags.
        pos_args: ?[][]const u8 = null,

        /// Rest of the arguments after '--'.
        rest_args: ?[][]const u8 = null,

        version: []const u8,

        err_msg: []u8 = undefined,
        err_msg_buf: [255]u8 = undefined,

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

        /// This function return formatted Error message for CliParseError.
        ///
        /// @import you need to Free the message your self.
        pub fn getErrorMessage(self: *const Self, err: anyerror) !?[]u8 {
            return switch (err) {
                CliParseError.InsufficientArguments => try std.fmt.allocPrint(self.alloc, "Not enough arguments provided. Please check the command usage.", .{}),
                CliParseError.ValueRequired => try std.fmt.allocPrint(self.alloc, "A value is required for option '{s}'.", .{self.err_msg}),
                CliParseError.UnknownOption => try std.fmt.allocPrint(self.alloc, "Unrecognized option '{s}'. Use '--help' to list available options.", .{self.err_msg}),
                CliParseError.NumberStringGroupedFlagInLast => try std.fmt.allocPrint(self.alloc, "The grouped flag {s} must be the final flag in the group.", .{self.err_msg}),
                CliParseError.MinPosArg => try std.fmt.allocPrint(self.alloc, "The command '{s}' requires at least {d} positional argument(s).", .{ @tagName(self.running_cmd.name), self.running_cmd.min_pos_arg }),

                CliParseError.ShowVersion => {
                    std.debug.print("{s} {s}", .{ self.name, self.version });
                    return null;
                },
                CliParseError.ShowHelp => {
                    try self.help();
                    return null;
                },

                else => try std.fmt.allocPrint(self.alloc, "An unknown error occurred during argument parsing.", .{}),
            };
        }

        pub fn printParseError(self: *const Self, err: anyerror) !void {
            if (try self.getErrorMessage(err)) |message| {
                defer self.alloc.free(message);
                std.debug.print("\x1B[1;38;5;197m[Error]: \x1B[0m{s}\n \x1B[0m", .{message});
            }
        }

        pub fn parse(self: *Self) !void {
            const args = try std.process.argsAlloc(self.alloc);
            defer std.process.argsFree(self.alloc, args);

            var argList = try RawArgs.initCapacity(self.alloc, args.len);
            defer argList.deinit();
            try argList.appendSlice(args);

            try self.parseAllArgs(&argList);
        }

        pub fn parseAllArgs(self: *Self, args: *RawArgs) !void {
            self.executable_name = try self.alloc.dupe(u8, args.orderedRemove(0));
            const cmdEnum = std.meta.stringToEnum(CmdEnum, if (args.items.len > 0) args.items[0] else "");
            const cmd = self.getCmd(cmdEnum);
            if (self.cmds[0].name != cmd.name) _ = args.orderedRemove(0);
            self.running_cmd = cmd;

            if (args.items.len < self.running_cmd.min_arg) return CliParseError.InsufficientArguments;

            var pos_arg_list = std.ArrayList([]const u8).init(self.alloc);
            errdefer {
                for (pos_arg_list.items) |pos_arg| self.alloc.free(pos_arg);
                pos_arg_list.deinit();
            }

            while (args.items.len > 0) {
                const arg = args.items[0];
                if (arg[0] == '-') {
                    if (std.mem.eql(u8, arg, "--")) {
                        const rest_args = try self.alloc.alloc([]const u8, args.items.len - 1);
                        for (args.items[1..], 0..) |rest, i| {
                            rest_args[i] = try self.alloc.dupe(u8, rest);
                        }
                        self.rest_args = rest_args;
                        break;
                    }
                    if (isHelpOption(arg)) return CliParseError.ShowHelp;
                    if (isVersionOption(arg)) return CliParseError.ShowVersion;
                    try self.parseFlag(args);
                } else {
                    const copy = try self.alloc.dupe(u8, arg);
                    try pos_arg_list.append(copy);
                    _ = args.orderedRemove(0);
                }
            }
            if (pos_arg_list.items.len < self.running_cmd.min_pos_arg) return CliParseError.MinPosArg;
            self.pos_args = try pos_arg_list.toOwnedSlice();
        }

        fn parseFlag(self: *Self, args: *RawArgs) !void {
            if (self.running_cmd.options == null) return;

            const opts = self.running_cmd.options.?;
            const arg = args.items[0];

            if (std.mem.startsWith(u8, arg, "--")) {
                const kv_arg = try parseKVArg(args.items);
                // try kError: The grouped fliv_arg.print();
                var found_arg = false;

                //TODO: Maybe this for loop can be a hash map.
                for (opts) |opt| {
                    if (std.mem.eql(u8, opt.long, kv_arg.key)) {
                        if (kv_arg.value == null) {
                            self.err_msg = try std.fmt.bufPrint(&self.err_msg_buf, "{s}", .{kv_arg.key});
                            return CliParseError.ValueRequired;
                        }
                        try slice.removeRangeInclusiveSafe(args, 0, kv_arg.count);
                        var copy_opt = opt;
                        switch (opt.value) {
                            .bool => {
                                const lower_value = try self.alloc.dupe(u8, kv_arg.value.?);
                                defer self.alloc.free(lower_value);
                                _ = std.ascii.lowerString(lower_value, lower_value);
                                copy_opt.value = .{ .bool = std.mem.eql(u8, lower_value, "true") };
                                try self.computed_args.append(copy_opt);
                            },
                            .str => {
                                copy_opt.is_alloc = true;
                                copy_opt.value = .{ .str = try self.alloc.dupe(u8, kv_arg.value.?) };
                                try self.computed_args.append(copy_opt);
                            },
                            .num => {
                                const num = std.fmt.parseInt(i32, kv_arg.value.?, 10) catch |e| switch (e) {
                                    error.InvalidCharacter => null,
                                    else => return e,
                                };
                                copy_opt.value = .{ .num = num };
                                try self.computed_args.append(copy_opt);
                            },
                            .list => util.logLocMessage("TODO: List Not implemented", @src()),
                        }
                        found_arg = true;
                        break;
                    }
                }

                if (!found_arg) {
                    self.err_msg = try std.fmt.bufPrint(&self.err_msg_buf, "{s}", .{kv_arg.key});
                    return CliParseError.UnknownOption;
                }
            } else if (std.mem.startsWith(u8, arg, "-")) {
                const short_flags = arg[1..];
                var j: usize = 0;

                while (j < short_flags.len) : (j += 1) {
                    const short_flag = short_flags[j .. j + 1];
                    var found_arg = false;
                    for (opts) |opt| {
                        if (std.mem.eql(u8, opt.short[1..], short_flag)) {
                            var copy_opt = opt;
                            switch (opt.value) {
                                .bool => {
                                    copy_opt.value = .{ .bool = true };
                                    try self.computed_args.append(copy_opt);
                                },
                                else => {
                                    if (j < short_flags.len - 1) {
                                        self.err_msg = try std.fmt.bufPrint(&self.err_msg_buf, "'-{s}' is invalid — the flag '{s}'", .{ short_flags, opt.short });
                                        return CliParseError.NumberStringGroupedFlagInLast;
                                    }

                                    const kv_arg = try parseKVArg(args.items);
                                    // try kv_arg.print();
                                    if (kv_arg.value == null) {
                                        self.err_msg = std.fmt.bufPrint(&self.err_msg_buf, "{s}", .{kv_arg.key}) catch unreachable;
                                        return CliParseError.ValueRequired;
                                    }
                                    try slice.removeRangeSafe(args, 1, kv_arg.count);
                                    switch (opt.value) {
                                        .str => {
                                            copy_opt.is_alloc = true;
                                            copy_opt.value = .{ .str = try self.alloc.dupe(u8, kv_arg.value.?) };
                                            try self.computed_args.append(copy_opt);
                                        },
                                        .num => {
                                            const num = std.fmt.parseInt(i32, kv_arg.value.?, 10) catch |e| switch (e) {
                                                error.InvalidCharacter => null,
                                                else => return e,
                                            };
                                            copy_opt.value = .{ .num = num };
                                            try self.computed_args.append(copy_opt);
                                        },
                                        .list => @panic("TODO: List Not implemented"),
                                        .bool => unreachable,
                                    }
                                },
                            }
                            found_arg = true;
                            break;
                        }
                    }
                    if (!found_arg) {
                        self.err_msg = try std.fmt.bufPrint(&self.err_msg_buf, "-{s}", .{short_flag});
                        return CliParseError.UnknownOption;
                    }
                }
                try slice.removeRange(args, 0, 1);
            }
        }

        fn getCmd(self: Self, cmd: ?CmdEnum) CmdT {
            if (cmd == null) return self.cmds[0];
            for (self.cmds) |value| if (value.name == cmd) return value;
            return self.cmds[0];
        }

        /// Returns the positional argument at the given index if available.
        ///
        /// if the positional argument at the given index is not available, returns null
        /// if the positional arguments are not available, returns null
        pub fn getPosArg(self: *const Self, pos_index: usize) ?[]const u8 {
            if (self.pos_args == null) return null;
            if (pos_index >= self.pos_args.?.len) return null;
            return self.pos_args.?[pos_index];
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
            try stdout.print("  {s} {s}\n\n", .{ std.fs.path.basename(self.executable_name), cmd_opt.usage });
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

        pub fn deinitPosArgs(self: *Self) void {
            if (self.pos_args) |pos_args| {
                for (pos_args) |pos_arg| self.alloc.free(pos_arg);
                self.alloc.free(pos_args);
            }
        }

        pub fn deinitRestArgs(self: *Self) void {
            if (self.rest_args) |rest_args| {
                for (rest_args) |rest_arg| self.alloc.free(rest_arg);
                self.alloc.free(rest_args);
            }
        }

        pub fn deinit(self: *Self) void {
            for (self.computed_args.items) |*item| if (item.is_alloc) try item.value.free(self.alloc);
            self.computed_args.deinit();
            self.deinitPosArgs();
            self.deinitRestArgs();
            self.alloc.free(self.executable_name);
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
        std.debug.print("KeyValueArg: key:{s:4} Val:{?s} Con:{d}\n", .{ self.key, self.value, self.count });
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

// BUG : the count of KeyValueArc can be wrong if the starting section is just
// text. For current use case this this will work because we check if its a
// flag before parsing.

/// Parses command-line style key/value arguments.
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
        .{ .input = &.{ "--option", "LOAD_OP=10" }, .expected_key = "--option", .expected_value = "LOAD_OP=10", .expected_count = 1 },
        .{ .input = &.{ "--option", "=", "LOAD_OP=10" }, .expected_key = "--option", .expected_value = "LOAD_OP=10", .expected_count = 2 },
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
        // .{ .input = &.{ "asdad", "--value" }, .expected_key = "--value", .expected_value = null, .expected_count = 1 },
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
