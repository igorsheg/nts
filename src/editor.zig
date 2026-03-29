const std = @import("std");

pub fn open(editor_bin: []const u8, path: []const u8, allocator: std.mem.Allocator) !void {
    var argv_buf = [_][]const u8{ editor_bin, path };
    var child = std.process.Child.init(&argv_buf, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    _ = try child.spawn();
    const term = try child.wait();
    if (term.Exited != 0) return error.EditorFailed;
}
