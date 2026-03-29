const std = @import("std");

const max_files = 5;

pub const Context = struct {
    project: ?[]const u8 = null,
    branch: ?[]const u8 = null,
    issue: ?[]const u8 = null,
    repo_dir: ?[]const u8 = null,
    commit: ?[]const u8 = null,
    dirty: ?bool = null,
    files: ?[]const []const u8 = null,

    pub fn isEmpty(self: Context) bool {
        return self.project == null and self.branch == null and self.commit == null;
    }

    pub fn deinit(self: *Context, allocator: std.mem.Allocator) void {
        const fields = .{ "project", "branch", "issue", "repo_dir", "commit" };
        inline for (fields) |f| {
            if (@field(self, f)) |v| allocator.free(v);
        }
        if (self.files) |files| {
            for (files) |f| allocator.free(f);
            allocator.free(files);
        }
        self.* = .{};
    }
};

pub fn detect(allocator: std.mem.Allocator) Context {
    var ctx = Context{};

    const root = gitCmd(allocator, &.{ "rev-parse", "--show-toplevel" }) orelse return ctx;
    defer allocator.free(root);
    ctx.project = allocator.dupe(u8, std.fs.path.basename(root)) catch return ctx;

    if (gitCmd(allocator, &.{ "symbolic-ref", "--short", "HEAD" })) |branch| {
        ctx.issue = parseIssue(allocator, branch);
        ctx.branch = branch;
    } else {
        ctx.branch = gitCmd(allocator, &.{ "rev-parse", "--short", "HEAD" });
    }

    ctx.commit = gitCmd(allocator, &.{ "rev-parse", "--short", "HEAD" });

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (std.process.getCwd(&cwd_buf)) |cwd| {
        if (!std.mem.eql(u8, cwd, root)) {
            ctx.repo_dir = std.fs.path.relative(allocator, root, cwd) catch null;
        }
    } else |_| {}

    const dirty_raw = gitCmd(allocator, &.{ "diff", "--name-only" });
    defer if (dirty_raw) |d| allocator.free(d);
    const staged_raw = gitCmd(allocator, &.{ "diff", "--name-only", "--cached" });
    defer if (staged_raw) |s| allocator.free(s);

    const all = mergeFileLines(allocator, dirty_raw, staged_raw) catch null;
    if (all) |files| {
        ctx.dirty = files.len > 0;
        if (files.len > 0 and files.len <= max_files) {
            ctx.files = files;
        } else {
            for (files) |f| allocator.free(f);
            allocator.free(files);
        }
    } else {
        ctx.dirty = false;
    }

    return ctx;
}

fn gitCmd(allocator: std.mem.Allocator, args: []const []const u8) ?[]const u8 {
    var argv_buf: [16][]const u8 = undefined;
    argv_buf[0] = "git";
    for (args, 0..) |a, i| argv_buf[i + 1] = a;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv_buf[0 .. args.len + 1],
    }) catch return null;
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        return null;
    }

    const trimmed = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        allocator.free(result.stdout);
        return null;
    }
    if (trimmed.len == result.stdout.len) return result.stdout;

    const duped = allocator.dupe(u8, trimmed) catch {
        allocator.free(result.stdout);
        return null;
    };
    allocator.free(result.stdout);
    return duped;
}

fn parseIssue(allocator: std.mem.Allocator, branch: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < branch.len) : (i += 1) {
        const c = branch[i];
        if (!std.ascii.isUpper(c)) continue;
        const start = i;
        i += 1;
        while (i < branch.len and (std.ascii.isUpper(branch[i]) or std.ascii.isDigit(branch[i]))) : (i += 1) {}
        if (i >= branch.len or branch[i] != '-') continue;
        i += 1;
        const num_start = i;
        while (i < branch.len and std.ascii.isDigit(branch[i])) : (i += 1) {}
        if (i == num_start) continue;
        const match = branch[start..i];
        return allocator.dupe(u8, match) catch null;
    }
    return null;
}

fn mergeFileLines(allocator: std.mem.Allocator, a: ?[]const u8, b: ?[]const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit();
    }

    const sources = [_]?[]const u8{ a, b };
    for (&sources) |maybe| {
        const src = maybe orelse continue;
        var iter = std.mem.splitScalar(u8, src, '\n');
        while (iter.next()) |raw| {
            const line = std.mem.trim(u8, raw, &std.ascii.whitespace);
            if (line.len == 0) continue;
            var dup = false;
            for (list.items) |existing| {
                if (std.mem.eql(u8, existing, line)) {
                    dup = true;
                    break;
                }
            }
            if (!dup) try list.append(try allocator.dupe(u8, line));
        }
    }

    return list.toOwnedSlice();
}
