const std = @import("std");
const note = @import("note.zig");
const search = @import("search.zig");

pub fn exact(notes_dir: []const u8, query: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    const direct = std.fs.path.join(allocator, &.{ notes_dir, query }) catch return null;
    if (fileExists(direct)) return direct;
    allocator.free(direct);

    const with_ext = std.fmt.allocPrint(allocator, "{s}/{s}.md", .{ notes_dir, query }) catch return null;
    if (fileExists(with_ext)) return with_ext;
    allocator.free(with_ext);

    return null;
}

pub fn strict(
    allocator: std.mem.Allocator,
    notes_dir: []const u8,
    query: []const u8,
    cache_path: []const u8,
) ![]const u8 {
    if (exact(notes_dir, query, allocator)) |path| return path;

    const notes = try note.parseAllCached(allocator, notes_dir, cache_path);

    var results_buf: [256]search.Result = undefined;
    const results = search.fuzzySearch(query, notes, &results_buf);

    if (results.len == 0) {
        const stderr = std.io.getStdErr().writer();
        stderr.print("error: note not found: {s}\n", .{query}) catch {};
        return error.NoteNotFound;
    }

    if (results.len == 1) {
        return allocator.dupe(u8, notes[results[0].note_index].path);
    }

    const stderr = std.io.getStdErr().writer();
    stderr.print("ambiguous match for \"{s}\", found {d} notes:\n", .{ query, results.len }) catch {};
    const limit = @min(results.len, 5);
    for (results[0..limit]) |r| {
        const n = notes[r.note_index];
        const slug = slugFromPath(n.path);
        const title = if (n.title.len > 0) n.title else "(untitled)";
        stderr.print("  {s}\t{s}\n", .{ slug, title }) catch {};
    }
    if (results.len > 5) {
        stderr.print("  ... and {d} more\n", .{results.len - 5}) catch {};
    }
    stderr.print("use the full slug to be specific\n", .{}) catch {};

    return error.AmbiguousMatch;
}

fn slugFromPath(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    return if (std.mem.endsWith(u8, base, ".md")) base[0 .. base.len - 3] else base;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
