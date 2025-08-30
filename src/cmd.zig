const Allocator = std.mem.Allocator;

const slice = @import("slice.zig");
const RawArgs = slice.RawArgs;
const util = @import("utils.zig");

const std = @import("std");
//TODO: Create a proper error logger.
//TODO: Check for Duplicate arguments.
//TODO: Nested Subcommands
//TODO: Code lean up reduce the Duplicate code.

const MaxArgStrLens = struct {
    short: usize = 3,
    long: usize = 10,
    info: usize = 40,
    cmd: usize = 5,
};

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

    pub fn isNull(self: ArgValue) bool {
        return switch (self) {
            .str => |str| return str == null,
            .bool => |b| return b == null,
            .num => |n| return n == null,
            .list => |l| return l == null,
        };
    }
};

/// Indicates the context in which the version string is being requested,
/// such as for a `--version` or `--help` display.
pub const VersionCallFrom = enum { version, help };

const VersionType = union(enum) {
    str: []const u8,
    fun: *const fn (_: VersionCallFrom) []const u8,
};

pub const Arg = struct {
    long: []const u8,
    short: []const u8,
    info: []const u8,
    value: ArgValue,
    //TODO : Do i need this,
    is_alloc: bool = false,

    fn getValueType(self: *const Arg) []const u8 {
        return switch (self.value) {
            .str => "<str >",
            .list => "<list>",
            .num => "<num >",
            .bool => "",
        };
    }
};

const DEFAULT_ARGS = [2]Arg{
    .{
        .long = "--help",
        .short = "-h",
        .info = "Show this help message and exit.",
        .value = ArgValue{ .bool = null },
    },
    .{
        .long = "--version",
        .short = "-v",
        .info = "Print version information and exit.",
        .value = ArgValue{ .bool = null },
    },
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

        /// Print the Help if the minimum position argument are not met.
        print_help_for_min_pos_arg: bool = false,

        options: ?[]const Arg = null,
    };
}

pub const ComputedArgs = struct {
    const Self = @This();
    data: ArgsList,
    alloc: Allocator,

    pub fn getStrArg(self: Self, arg_name: []const u8) !?[]const u8 {
        for (self.data.items) |arg| {
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
        for (self.data.items) |arg| {
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
        for (self.data.items) |arg| {
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
    pub fn append(self: *Self, arg: Arg) !void {
        try self.data.append(self.alloc, arg);
    }

    pub fn deinit(self: *Self) void {
        for (self.data.items) |*item| if (item.is_alloc) try item.value.free(self.alloc);
        self.data.deinit(self.alloc);
    }
};

pub const CliParseError = error{
    InsufficientArguments,
    ShowHelp,
    ShowVersion,
    ValueRequired,
    UnknownOption,
    MinPosArg,
    NumberStringGroupedFlagInLast,
};
pub fn CliInit(comptime CmdEnum: type) type {
    comptime {
        if (@typeInfo(CmdEnum) != .@"enum") {
            @compileError("CmdEnum must be an enum type; Found  " ++ @typeName(CmdEnum));
        }
    }
    const CmdT = Cmd(CmdEnum);
    return struct {
        pub const Self = @This();

        alloc: Allocator,

        computed_args: ComputedArgs,
        cmds: []const CmdT,
        running_cmd: CmdT,

        name: []const u8,
        description: ?[]const u8 = null,
        executable_name: []const u8 = undefined,

        /// pos_args (Positional arguments) interleaved with commands and flags.
        pos_args: ?[][]const u8 = null,

        /// Rest of the arguments after '--'.
        rest_args: ?[][]const u8 = null,

        version: VersionType,

        err_msg: []u8 = undefined,
        err_msg_buf: [255]u8 = undefined,

        /// The First command is always the root command
        pub fn init(
            allocate: Allocator,
            name: []const u8,
            description: ?[]const u8,
            version: VersionType,
            comptime commands: []const CmdT,
        ) !Self {
            comptime {
                if (commands.len <= 0) @compileError("You need to provided At list one command.");
                const enum_fields = @typeInfo(CmdEnum).@"enum".fields;
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
                .computed_args = .{
                    .data = .empty,
                    .alloc = allocate,
                },
            };
        }

        inline fn maxCmdStrLens(cmds: []const CmdT) MaxArgStrLens {
            var max = MaxArgStrLens{};
            for (cmds) |cmd| {
                max.cmd = @max(max.cmd, @tagName(cmd.name).len);
            }
            return max;
        }

        inline fn maxStrLens(cmd: *const CmdT) MaxArgStrLens {
            var max = MaxArgStrLens{};
            max.cmd = @max(max.cmd, @tagName(cmd.name).len);
            if (cmd.options) |opts| {
                for (opts) |op| {
                    max.long = @max(max.long, op.long.len);
                    max.short = @max(max.short, op.short.len);
                    max.info = @max(max.info, op.info.len);
                }
            }
            return max;
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
                    switch (self.version) {
                        .str => |v| std.debug.print("{s} {s}", .{ self.name, v }),
                        .fun => |f| std.debug.print("{s}", .{f(.version)}),
                    }
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
                std.debug.print("\x1B[1;38;5;197m[Error]: \x1B[0m{s}\n\n \x1B[0m", .{message});
                if (self.running_cmd.print_help_for_min_pos_arg) try self.help();
            }
        }

        pub fn parse(self: *Self) !void {
            const args = try std.process.argsAlloc(self.alloc);
            defer std.process.argsFree(self.alloc, args);

            var argList = try RawArgs.initCapacity(self.alloc, args.len);
            defer argList.deinit(self.alloc);
            try argList.appendSlice(self.alloc, args);

            try self.parseAllArgs(&argList);
        }

        pub fn parseAllArgs(self: *Self, args: *RawArgs) !void {
            self.executable_name = try self.alloc.dupe(u8, args.orderedRemove(0));
            const cmdEnum = std.meta.stringToEnum(CmdEnum, if (args.items.len > 0) args.items[0] else "");
            const cmd = self.getCmd(cmdEnum);
            if (self.cmds[0].name != cmd.name) _ = args.orderedRemove(0);
            self.running_cmd = cmd;

            if (args.items.len < self.running_cmd.min_arg) return CliParseError.InsufficientArguments;

            var pos_arg_list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (pos_arg_list.items) |pos_arg| self.alloc.free(pos_arg);
                pos_arg_list.deinit(self.alloc);
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
                    try pos_arg_list.append(self.alloc, copy);
                    _ = args.orderedRemove(0);
                }
            }
            if (pos_arg_list.items.len < self.running_cmd.min_pos_arg) return CliParseError.MinPosArg;
            self.pos_args = try pos_arg_list.toOwnedSlice(self.alloc);
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
                        if (kv_arg.value == null and opt.value != .bool and opt.value.isNull()) {
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
                                const num = if (kv_arg.value) |v| std.fmt.parseInt(i32, v, 10) catch |e| switch (e) {
                                    error.InvalidCharacter => null,
                                    else => return e,
                                } else opt.value.num.?;
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
                                    if (kv_arg.value == null and opt.value.isNull()) {
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
                                            const num = if (kv_arg.value) |v| std.fmt.parseInt(i32, v, 10) catch |e| switch (e) {
                                                error.InvalidCharacter => null,
                                                else => return e,
                                            } else opt.value.num.?;
                                            copy_opt.value = .{ .num = num };
                                            try self.computed_args.append(copy_opt);
                                        },
                                        .list => util.logLocMessage("TODO: List Not implemented", @src()),
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
        /// Note:
        ///     ! Important '0' based indexing.
        ///     if the positional argument at the given index is not available, returns null
        ///     if the positional arguments are not available, returns null
        pub fn getPosArg(self: *const Self, pos_index: usize) ?[]const u8 {
            if (self.pos_args == null) return null;
            if (pos_index >= self.pos_args.?.len) return null;
            return self.pos_args.?[pos_index];
        }

        pub fn getAllPosArgAsStr(self: *const Self) !?[]const u8 {
            if (self.pos_args == null) return null;
            var pos_list = std.ArrayList(u8).init(self.alloc);
            for (self.pos_args.?) |pos_arg| {
                try pos_list.appendSlice(self.alloc, pos_arg);
                try pos_list.append(self.alloc, ' ');
            }
            return try pos_list.toOwnedSlice();
        }

        pub fn getStrArg(self: Self, arg_name: []const u8) !?[]const u8 {
            return self.computed_args.getStrArg(arg_name);
        }

        pub fn getNumArg(self: Self, arg_name: []const u8) !?i32 {
            return self.computed_args.getNumArg(arg_name);
        }

        pub fn getBoolArg(self: Self, arg_name: []const u8) !bool {
            return self.computed_args.getBoolArg(arg_name);
        }

        pub fn help(self: Self) !void {
            const stdout = std.fs.File.stdout().deprecatedWriter();
            if (self.description) |dis| {
                const version = switch (self.version) {
                    .str => |s| s,
                    .fun => |f| f(.help),
                };
                try stdout.print("{s} {s}\n{s}\n\n", .{ self.name, version, dis });
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
            const opt_print_fmt = try self.generateArgsPrintFmt(&cmd_opt);
            defer self.alloc.free(opt_print_fmt);
            try stdout.print("{s}\n\n", .{opt_print_fmt});
            // TODO: The cmds will be printed for root cmd the first.
            // Change this in future when sub cmds are supported
            if (cmd_opt.name != self.cmds[0].name) return;
            try stdout.print("COMMANDS: \n", .{});

            const cmd_print_str = try self.generateCmdPrintFmt();
            defer self.alloc.free(cmd_print_str);
            try stdout.print("{s}\n\n", .{cmd_print_str});
        }

        fn generateArgsPrintFmt(self: Self, cmd: *const CmdT) ![]const u8 {
            var cmd_fmt: std.ArrayList(u8) = .empty;
            var cmd_writer = cmd_fmt.writer(self.alloc);
            const max = maxStrLens(cmd);
            if (cmd.options) |opt| {
                for (opt) |value| {
                    for (0..max.short - value.short.len) |_| try cmd_fmt.append(self.alloc, ' ');
                    try cmd_fmt.appendSlice(self.alloc, value.short);
                    try cmd_fmt.appendSlice(self.alloc, ", ");
                    for (0..max.long - value.long.len) |_| try cmd_fmt.append(self.alloc, ' ');
                    try cmd_fmt.appendSlice(self.alloc, value.long);
                    try cmd_writer.print(" {s:6}", .{value.getValueType()});
                    for (0..(2)) |_| try cmd_fmt.append(self.alloc, ' ');
                    try cmd_fmt.appendSlice(self.alloc, value.info);
                    try cmd_fmt.append(self.alloc, '\n');
                }
            }
            for (DEFAULT_ARGS) |value| {
                for (0..max.short - value.short.len) |_| try cmd_fmt.append(self.alloc, ' ');
                try cmd_fmt.appendSlice(self.alloc, value.short);
                try cmd_fmt.appendSlice(self.alloc, ", ");
                for (0..max.long - value.long.len) |_| try cmd_fmt.append(self.alloc, ' ');
                try cmd_fmt.appendSlice(self.alloc, value.long);
                try cmd_writer.print(" {s:6}", .{value.getValueType()});
                for (0..(2)) |_| try cmd_fmt.append(self.alloc, ' ');
                try cmd_fmt.appendSlice(self.alloc, value.info);
                try cmd_fmt.append(self.alloc, '\n');
            }
            return try cmd_fmt.toOwnedSlice(self.alloc);
        }

        fn generateCmdPrintFmt(self: Self) ![]const u8 {
            var cmd_fmt: std.ArrayList(u8) = .empty;
            const max = maxCmdStrLens(self.cmds);
            for (self.cmds) |value| {
                if (value.name == self.cmds[0].name) continue;
                const name = @tagName(value.name);
                const name_pad = max.cmd - name.len;
                for (0..name_pad) |_| try cmd_fmt.append(self.alloc, ' ');
                try cmd_fmt.appendSlice(self.alloc, name);
                try cmd_fmt.appendSlice(self.alloc, ":    ");
                try cmd_fmt.appendSlice(self.alloc, value.info orelse "");
                try cmd_fmt.append(self.alloc, '\n');
            }

            return try cmd_fmt.toOwnedSlice(self.alloc);
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
