const std = @import("std");
const note_mod = @import("note.zig");
const gitctx = @import("gitctx.zig");
const format = @import("format.zig");

pub fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn writeIndent(writer: anytype, depth: usize) !void {
    var i: usize = 0;
    while (i < depth) : (i += 1) try writer.writeAll("  ");
}

fn writeContext(writer: anytype, ctx: gitctx.Context, depth: usize) !void {
    try writeIndent(writer, depth);
    try writer.writeAll("\"context\": {\n");
    var first = true;
    inline for (.{
        .{ "project", ctx.project },
        .{ "branch", ctx.branch },
        .{ "issue", ctx.issue },
        .{ "repo_dir", ctx.repo_dir },
        .{ "commit", ctx.commit },
    }) |pair| {
        if (pair[1]) |v| {
            if (!first) try writer.writeAll(",\n");
            first = false;
            try writeIndent(writer, depth + 1);
            try writer.print("\"{s}\": ", .{pair[0]});
            try writeJsonString(writer, v);
        }
    }
    if (ctx.dirty) |d| {
        if (!first) try writer.writeAll(",\n");
        first = false;
        try writeIndent(writer, depth + 1);
        try writer.print("\"dirty\": {s}", .{if (d) "true" else "false"});
    }
    if (ctx.files) |files| {
        if (!first) try writer.writeAll(",\n");
        try writeIndent(writer, depth + 1);
        try writer.writeAll("\"files\": [");
        for (files, 0..) |f, i| {
            if (i > 0) try writer.writeAll(", ");
            try writeJsonString(writer, f);
        }
        try writer.writeAll("]");
    }
    try writer.writeByte('\n');
    try writeIndent(writer, depth);
    try writer.writeByte('}');
}

fn writeNote(writer: anytype, n: note_mod.Note, depth: usize, include_body: bool) !void {
    try writeIndent(writer, depth);
    try writer.writeAll("{\n");

    try writeIndent(writer, depth + 1);
    try writer.writeAll("\"title\": ");
    try writeJsonString(writer, n.title);
    try writer.writeAll(",\n");

    try writeIndent(writer, depth + 1);
    var date_buf: [10]u8 = undefined;
    const date = format.formatDate(n.date, &date_buf);
    try writer.writeAll("\"date\": ");
    try writeJsonString(writer, date);
    try writer.writeAll(",\n");

    try writeIndent(writer, depth + 1);
    try writer.writeAll("\"labels\": [");
    for (n.labels, 0..) |label, i| {
        if (i > 0) try writer.writeAll(", ");
        try writeJsonString(writer, label);
    }
    try writer.writeAll("],\n");

    try writeIndent(writer, depth + 1);
    try writer.writeAll("\"path\": ");
    try writeJsonString(writer, n.path);

    if (include_body) {
        try writer.writeAll(",\n");
        try writeIndent(writer, depth + 1);
        try writer.writeAll("\"body\": ");
        try writeJsonString(writer, n.body);
    }

    if (!n.context.isEmpty()) {
        try writer.writeAll(",\n");
        try writeContext(writer, n.context, depth + 1);
    }

    try writer.writeByte('\n');
    try writeIndent(writer, depth);
    try writer.writeByte('}');
}

fn writeActions(writer: anytype, actions: []const NextAction, depth: usize) !void {
    try writer.writeAll("[\n");
    for (actions, 0..) |a, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writeIndent(writer, depth + 1);
        try writer.writeAll("{\n");
        try writeIndent(writer, depth + 2);
        try writer.writeAll("\"command\": ");
        try writeJsonString(writer, a.command);
        try writer.writeAll(",\n");
        try writeIndent(writer, depth + 2);
        try writer.writeAll("\"description\": ");
        try writeJsonString(writer, a.description);
        try writer.writeByte('\n');
        try writeIndent(writer, depth + 1);
        try writer.writeByte('}');
    }
    try writer.writeByte('\n');
    try writeIndent(writer, depth);
    try writer.writeByte(']');
}

fn writeEnvelopeHead(writer: anytype, ok: bool, command: []const u8) !void {
    try writer.writeAll("{\n");
    try writer.print("  \"ok\": {s},\n", .{if (ok) "true" else "false"});
    try writer.writeAll("  \"command\": ");
    try writeJsonString(writer, command);
    try writer.writeAll(",\n");
    try writer.print("  \"timestamp\": {d},\n", .{std.time.timestamp()});
}

pub const NextAction = struct {
    command: []const u8,
    description: []const u8,
};

pub fn printNewEnvelope(writer: anytype, n: note_mod.Note, slug: []const u8) !void {
    try writeEnvelopeHead(writer, true, "new");
    try writer.writeAll("  \"result\": ");
    try writeNote(writer, n, 1, false);
    try writer.writeAll(",\n");
    try writer.writeAll("  \"next_actions\": ");
    try writeActions(writer, &noteActions(slug), 1);
    try writer.writeByte('\n');
    try writer.writeAll("}\n");
}

pub fn printListEnvelope(writer: anytype, notes: []const note_mod.Note) !void {
    try writeEnvelopeHead(writer, true, "list");
    try writer.writeAll("  \"result\": [\n");
    for (notes, 0..) |n, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writeNote(writer, n, 2, false);
    }
    try writer.writeAll("\n  ],\n");
    try writer.writeAll("  \"next_actions\": ");
    try writeActions(writer, &listActions(), 1);
    try writer.writeByte('\n');
    try writer.writeAll("}\n");
}

pub fn printShowEnvelope(writer: anytype, n: note_mod.Note, slug: []const u8) !void {
    try writeEnvelopeHead(writer, true, "show");
    try writer.writeAll("  \"result\": ");
    try writeNote(writer, n, 1, true);
    try writer.writeAll(",\n");
    try writer.writeAll("  \"next_actions\": ");
    try writeActions(writer, &noteActions(slug), 1);
    try writer.writeByte('\n');
    try writer.writeAll("}\n");
}

pub fn printSearchEnvelope(writer: anytype, query: []const u8, notes: []const note_mod.Note) !void {
    try writeEnvelopeHead(writer, true, "search");
    try writer.writeAll("  \"result\": [\n");
    for (notes, 0..) |n, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writeNote(writer, n, 2, false);
    }
    try writer.writeAll("\n  ],\n");
    try writer.writeAll("  \"next_actions\": ");
    try writeActions(writer, &searchActions(query), 1);
    try writer.writeByte('\n');
    try writer.writeAll("}\n");
}

pub fn printCommandTree(writer: anytype, version: []const u8) !void {
    try writeEnvelopeHead(writer, true, "nts");
    try writer.writeAll("  \"result\": {\n");
    try writer.writeAll("    \"description\": \"Note to self \\u2014 quick markdown notes from your terminal\",\n");
    try writer.writeAll("    \"version\": ");
    try writeJsonString(writer, version);
    try writer.writeAll("\n  },\n");
    try writer.writeAll("  \"next_actions\": ");
    try writeActions(writer, &.{
        .{ .command = "nts <title>", .description = "Create a new note" },
        .{ .command = "nts list", .description = "List all notes" },
        .{ .command = "nts search <query>", .description = "Search notes" },
    }, 1);
    try writer.writeByte('\n');
    try writer.writeAll("}\n");
}

pub fn printFailure(
    writer: anytype,
    command: []const u8,
    code: []const u8,
    message: []const u8,
    fix: ?[]const u8,
    retryable: bool,
) !void {
    try writeEnvelopeHead(writer, false, command);
    try writer.writeAll("  \"error\": {\n");
    try writer.writeAll("    \"message\": ");
    try writeJsonString(writer, message);
    try writer.writeAll(",\n");
    try writer.writeAll("    \"code\": ");
    try writeJsonString(writer, code);
    try writer.print(",\n    \"retryable\": {s}\n", .{if (retryable) "true" else "false"});
    try writer.writeAll("  }");
    if (fix) |f| {
        try writer.writeAll(",\n  \"fix\": ");
        try writeJsonString(writer, f);
    }
    try writer.writeAll(",\n  \"next_actions\": []\n}\n");
}

fn noteActions(slug: []const u8) [3]NextAction {
    _ = slug;
    return .{
        .{ .command = "nts show <slug>", .description = "Show this note" },
        .{ .command = "nts edit <slug>", .description = "Edit this note" },
        .{ .command = "nts append <slug> <text>", .description = "Append to this note" },
    };
}

fn listActions() [3]NextAction {
    return .{
        .{ .command = "nts show <slug>", .description = "Show a note" },
        .{ .command = "nts search <query>", .description = "Search notes" },
        .{ .command = "nts list [--labels <labels>] [--project <project>]", .description = "Filter notes" },
    };
}

fn searchActions(query: []const u8) [2]NextAction {
    _ = query;
    return .{
        .{ .command = "nts show <slug>", .description = "Show a result" },
        .{ .command = "nts search <query> [--labels <labels>]", .description = "Refine search" },
    };
}
