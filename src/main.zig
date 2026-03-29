const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    cli.run(arena.allocator()) catch |err| {
        if (err != error.NoteNotFound and err != error.AmbiguousMatch) {
            const stderr = std.io.getStdErr().writer();
            stderr.print("error: {s}\n", .{@errorName(err)}) catch {};
        }
        std.process.exit(1);
    };
}
