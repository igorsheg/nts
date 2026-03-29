const std = @import("std");
const note_mod = @import("note.zig");

const ESC = "\x1b[";
const RESET = ESC ++ "0m";

pub fn writeBold(writer: anytype, s: []const u8) !void {
    try writer.writeAll(ESC ++ "1m");
    try writer.writeAll(s);
    try writer.writeAll(RESET);
}

pub fn writeFaint(writer: anytype, s: []const u8) !void {
    try writer.writeAll(ESC ++ "2m");
    try writer.writeAll(s);
    try writer.writeAll(RESET);
}

pub fn writeItalic(writer: anytype, s: []const u8) !void {
    try writer.writeAll(ESC ++ "3m");
    try writer.writeAll(s);
    try writer.writeAll(RESET);
}

pub fn writeColor(writer: anytype, color: u8, s: []const u8) !void {
    try writer.print(ESC ++ "38;5;{d}m", .{color});
    try writer.writeAll(s);
    try writer.writeAll(RESET);
}

pub fn isTTY() bool {
    return std.posix.isatty(std.posix.STDOUT_FILENO);
}

pub fn formatDate(timestamp: i64, buf: *[10]u8) []const u8 {
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(0, timestamp)) };
    const day = es.getEpochDay();
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();
    _ = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        yd.year,
        @intFromEnum(md.month),
        md.day_index + 1,
    }) catch unreachable;
    return buf;
}

pub fn formatNoteRow(writer: anytype, n: note_mod.Note) !void {
    const tty = isTTY();
    var date_buf: [10]u8 = undefined;
    const date = formatDate(n.date, &date_buf);

    if (!tty) {
        try writer.writeAll(date);
        try writer.writeAll("  ");
        try writer.writeAll(if (n.title.len > 0) n.title else "(untitled)");
        if (n.labels.len > 0) {
            try writer.writeAll(" [");
            try writeLabels(writer, n.labels);
            try writer.writeAll("]");
        }
        try writer.writeByte('\n');
        return;
    }

    try writeFaint(writer, date);
    try writer.writeAll("  ");
    try writeBold(writer, if (n.title.len > 0) n.title else "(untitled)");
    if (n.labels.len > 0) {
        try writer.writeAll(" ");
        try writer.print(ESC ++ "38;5;6m", .{});
        try writer.writeAll("[");
        try writeLabels(writer, n.labels);
        try writer.writeAll("]");
        try writer.writeAll(RESET);
    }
    if (n.context.project) |proj| {
        try writer.writeAll(" ");
        try writeColor(writer, 5, proj);
    }
    try writer.writeByte('\n');
}

pub fn formatSearchRow(writer: anytype, n: note_mod.Note, score: i32) !void {
    const tty = isTTY();
    if (!tty) {
        try writer.print("{d}\t", .{score});
        try formatNoteRow(writer, n);
        return;
    }
    try writeColor(writer, 3, "");
    try writer.print(ESC ++ "38;5;3m{d}" ++ RESET ++ "\t", .{score});
    try formatNoteRow(writer, n);
}

pub fn hint(writer: anytype, text: []const u8) !void {
    if (!isTTY()) return;
    try writer.writeAll(ESC ++ "2;3m");
    try writer.writeAll(text);
    try writer.writeAll(RESET);
}

fn writeLabels(writer: anytype, labels: []const []const u8) !void {
    for (labels, 0..) |label, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll(label);
    }
}
