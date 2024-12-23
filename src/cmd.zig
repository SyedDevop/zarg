const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CmdName = enum {
    root,
    length,
    area,
    history,
    delete,
    completion,
    volume,
    temp,
    config,

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
pub const HistoryType = enum { lenght, area, mian };

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
pub const Cmd = struct {
    name: CmdName,
    usage: []const u8,
    example: ?[]const u8 = null,
    info: ?[]const u8 = null,
    min_arg: u8 = 1,
    options: ?[]const Arg = null,
};
const rootCmd = Cmd{
    .name = .root,
    .usage = "m [OPTIONS] \"EXPRESSION\"",
    .options = &.{
        .{
            .long = "--interactive",
            .short = "-i",
            .info = "Start interactive mode to evaluate expressions based on previous results.",
            .value = .{ .bool = null },
        },
    },
};
const cmdList: []const Cmd = &.{
    .{
        .name = .length,
        .usage = "m lenght [OPTIONS] \"FROM_UNIT:VALUE:TO_UNIT\"",
        .example =
        \\Examples of Usage:
        \\    m length "mm:1:m"   - Converts 1 millimeter to meters.
        \\    m length "mm?1?m"   - Converts 1 millimeter to meters (with ? as a separator).
        \\    m length "mm 1 m"   - Converts 1 millimeter to meters.
        \\    m length "1 mm m"   - Converts 1 millimeter to meters.
        \\
        \\Notes:
        \\  - This command accepts any separator other than numbers or letters between units and values.
        \\  - The first unit specified is considered the starting unit (FROM_UNIT), and the last unit is the target (TO_UNIT).
        ,
        .info = "This command convert values between different units of length.",
        .options = &.{
            .{
                .long = "--unit",
                .short = "-u",
                .info = "Displays all the support units.",
                .value = .{ .bool = null },
            },
        },
    },
    .{
        .name = .volume,
        .usage = "m volume [OPTIONS] \"FROM_UNIT:VALUE:TO_UNIT\"",
        .example =
        \\Notes:
        \\  - This command accepts any separator other than numbers or letters between units and values.
        \\  - The first unit specified is considered the starting unit (FROM_UNIT), and the last unit is the target (TO_UNIT).
        ,
        .info = "This command convert values between different units of volume.",
        .options = &.{
            .{
                .long = "--unit",
                .short = "-u",
                .info = "Displays all the support units.",
                .value = .{ .bool = null },
            },
        },
    },
    .{
        .name = .temp,
        .usage = "m temp [OPTIONS] \"FROM_UNIT:VALUE:TO_UNIT\"",
        .example =
        \\Notes:
        \\  - This command accepts any separator other than numbers or letters between units and values.
        \\  - The first unit specified is considered the starting unit (FROM_UNIT), and the last unit is the target (TO_UNIT).
        ,
        .info = "This command convert values between different units of Temperature.",
        .options = &.{
            .{
                .long = "--unit",
                .short = "-u",
                .info = "Displays all the support units.",
                .value = .{ .bool = null },
            },
        },
    },
    .{
        .name = .area,
        .usage = "m area [OPTIONS] \"FROM_UNIT:VALUE:TO_UNIT\"",
        .info = "This command convert values between different units of area.",
        .options = null,
    },
    .{
        .name = .delete,
        .min_arg = 0,
        .usage = "m delete [ID] [OPTIONS]",
        .info = "This command delete the expressions for given [ID].",
        .options = &.{
            .{
                .long = "--all",
                .short = "-a",
                .info = "Delete all the entries.",
                .value = .{ .bool = false },
            },
            .{
                .long = "--range",
                .short = "-r",
                .info = "Delete range of the entries. |uasge: 10..15 |",
                .value = .{ .str = null },
            },
        },
    },
    .{
        .name = .history,
        .min_arg = 0,
        .usage = "m history [OPTIONS] ",
        .info = "This command displays the history of previously evaluated expressions. By default, it shows the main history log.",
        .options = &.{
            .{
                .long = "--type",
                .short = "-t",
                .info = "Specifies the type of history to display. Options include: 'main', 'length' and 'area'. The default is . all",
                .value = .{ .str = null },
            },
            .{
                .long = "--all",
                .short = "-a",
                .info = "Display all the entries.",
                .value = .{ .bool = false },
            },
            .{
                .long = "--show-id",
                .short = "-id",
                .info = "Display Id for the entries.",
                .value = .{ .bool = false },
            },
            .{
                .long = "--earlier",
                .short = "-e",
                .info = "Display history entries from the earliest to the most recent. Defaults to showing recent entries.",
                .value = .{ .bool = false },
            },
            .{
                .long = "--limit",
                .short = "-l",
                .info = "Limit the number of history entries displayed. Default is 5.",
                .value = .{ .num = 5 },
            },
        },
    },
    .{
        .name = .completion,
        .min_arg = 0,
        .usage = "m completion ",
        .info = "This command Generate the autocompletion script for gitpuller for the specified shell.",
        .options = null,
    },
    .{
        .name = .config,
        .min_arg = 0,
        .usage = "m config [OPTIONS]",
        .info = "This command configurer you z_math.",
        .options = &.{
            .{
                .long = "--db-path",
                .short = "-dp",
                .info = "Print the dp path.",
                .value = .{ .bool = false },
            },
        },
    },
};

pub const Cli = struct {
    const Self = @This();
    alloc: Allocator,

    name: []const u8,
    description: ?[]const u8 = null,
    process_name: []const u8 = "",

    computed_args: ArgsList,
    subCmds: []const Cmd,
    rootCmd: Cmd,
    cmd: Cmd,
    data: []const u8 = "",

    version: []const u8,

    errorMess: []u8,

    pub fn init(allocate: Allocator, name: []const u8, description: ?[]const u8, version: []const u8) !Self {
        return .{
            .alloc = allocate,
            .name = name,
            .description = description,
            .subCmds = cmdList,
            .rootCmd = rootCmd,
            .cmd = rootCmd,
            .version = version,
            .computed_args = ArgsList.init(allocate),
            .errorMess = try allocate.alloc(u8, 255),
        };
    }
    pub fn parse(self: *Self) !void {
        const args = try std.process.argsAlloc(self.alloc);
        defer std.process.argsFree(self.alloc, args);

        var idx: usize = 1;
        const cmdEnum = if (args.len == 1) CmdName.root else std.meta.stringToEnum(CmdName, args[idx]);
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

    fn getCmd(self: Self, cmd: ?CmdName) Cmd {
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

test "Parse Strings" {
    _ = .{
        .{ .{ "--len", "=", "60" }, true },
        .{ .{ "--len", "60" }, true },
        .{ .{ "--len=", "60" }, true },
        .{ .{"--len=60"}, true },
        .{ .{ "--len", "=60" }, true },
        .{ .{"--len"}, true },
        .{ .{"--len60"}, true },
        .{ .{"--len="}, true },
        .{ .{ "--len", "=" }, true },
    };
}
