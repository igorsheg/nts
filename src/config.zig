const std = @import("std");

pub const Config = struct {
    notes_dir: []const u8,
    editor: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.notes_dir);
        if (self.editor) |e| self.allocator.free(e);
    }

    pub fn resolveEditor(self: Config) []const u8 {
        if (self.editor) |e| return e;
        if (std.posix.getenv("EDITOR")) |e| return e;
        return "vi";
    }
};

fn getHomeDir() ![]const u8 {
    return std.posix.getenv("HOME") orelse return error.HomeNotFound;
}

pub fn configPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getHomeDir();
    return std.fs.path.join(allocator, &.{ home, ".config", "nts", "config.json" });
}

pub fn cacheDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getHomeDir();
    return std.fs.path.join(allocator, &.{ home, ".cache", "nts" });
}

pub fn metaCachePath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getHomeDir();
    return std.fs.path.join(allocator, &.{ home, ".cache", "nts", "meta.json" });
}

const JsonConfig = struct {
    notes_dir: ?[]const u8 = null,
    editor: ?[]const u8 = null,
};

fn defaultNotesDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getHomeDir();
    return std.fs.path.join(allocator, &.{ home, "nts" });
}

pub fn load(allocator: std.mem.Allocator) !Config {
    const path = try configPath(allocator);
    defer allocator.free(path);

    const data = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) return Config{
            .notes_dir = try defaultNotesDir(allocator),
            .allocator = allocator,
        };
        return err;
    };
    defer allocator.free(data);

    const parsed = try std.json.parseFromSlice(JsonConfig, allocator, data, .{});
    defer parsed.deinit();

    const notes_dir = if (parsed.value.notes_dir) |d|
        try allocator.dupe(u8, d)
    else
        try defaultNotesDir(allocator);

    const editor = if (parsed.value.editor) |e|
        try allocator.dupe(u8, e)
    else
        null;

    return Config{
        .notes_dir = notes_dir,
        .editor = editor,
        .allocator = allocator,
    };
}

pub fn save(allocator: std.mem.Allocator, cfg: Config) !void {
    const path = try configPath(allocator);
    defer allocator.free(path);

    const dir = std.fs.path.dirname(path) orelse return error.InvalidPath;
    try std.fs.cwd().makePath(dir);

    const json_cfg = JsonConfig{
        .notes_dir = cfg.notes_dir,
        .editor = cfg.editor,
    };

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try std.json.stringify(json_cfg, .{ .whitespace = .indent_2 }, buf.writer());
    try buf.append('\n');

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = buf.items });
}
