const std = @import("std");
const zf = @import("zf");
const note_mod = @import("note.zig");

const max_visible = 10;
const slug_width = 24;

pub const PickerResult = struct {
    path: ?[]const u8 = null,
    canceled: bool = false,
};

const RankedItem = struct {
    index: usize,
    score: f64,
};

pub fn runPicker(allocator: std.mem.Allocator, notes: []const note_mod.Note) !PickerResult {
    const tty_fd = std.posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0) catch
        return .{ .canceled = true };
    defer std.posix.close(tty_fd);

    const orig = try std.posix.tcgetattr(tty_fd);
    var raw = orig;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(tty_fd, .FLUSH, raw);

    const tty_file = std.fs.File{ .handle = tty_fd };
    const reader = tty_file.reader();
    var bw = std.io.bufferedWriter(tty_file.writer());
    const w = bw.writer();

    // get terminal width for line truncation
    const term_width: usize = blk: {
        var wsz: std.posix.winsize = undefined;
        const rc = std.posix.system.ioctl(tty_fd, std.posix.T.IOCGWINSZ, @intFromPtr(&wsz));
        break :blk if (rc == 0 and wsz.col > 0) @as(usize, wsz.col) else 80;
    };

    var query_buf: [256]u8 = undefined;
    var query_len: usize = 0;
    var cursor: usize = 0;
    var offset: usize = 0;
    var rendered_height: usize = 0;

    var ranked = std.ArrayList(RankedItem).init(allocator);
    defer ranked.deinit();

    // reserve space by scrolling down, then move back up
    const initial_height = @min(notes.len, max_visible) + 2; // prompt + items + count
    for (0..initial_height) |_| try w.writeByte('\n');
    try w.print("\x1b[{d}A", .{initial_height});
    try bw.flush();

    while (true) {
        ranked.clearRetainingCapacity();
        try filterNotes(notes, query_buf[0..query_len], &ranked);

        if (cursor >= ranked.items.len) {
            cursor = if (ranked.items.len > 0) ranked.items.len - 1 else 0;
        }
        if (cursor < offset) offset = cursor;
        if (cursor >= offset + max_visible) offset = cursor - max_visible + 1;

        // render: move to start of our region, draw top-down
        try w.writeAll("\r");
        if (rendered_height > 0) {
            // we're at cursor position (prompt line) — already at top
        }

        // hide cursor during render
        try w.writeAll("\x1b[?25l");

        // line 0: prompt
        try w.writeAll("\x1b[2K\x1b[36m> \x1b[0m");
        try w.writeAll(query_buf[0..query_len]);
        try w.writeAll("\n");

        // lines 1..n: items
        const end = @min(offset + max_visible, ranked.items.len);
        var line: usize = 0;
        while (line < max_visible) : (line += 1) {
            try w.writeAll("\x1b[2K"); // clear line
            if (offset + line < end) {
                const item = ranked.items[offset + line];
                const n = notes[item.index];
                const is_selected = (offset + line == cursor);
                try writeItemRow(w, n, is_selected, query_buf[0..query_len], term_width);
            }
            try w.writeAll("\n");
        }

        // count line
        try w.writeAll("\x1b[2K");
        try w.print("  \x1b[38;5;8m{d}/{d}\x1b[0m", .{ ranked.items.len, notes.len });

        // total rendered: 1 (prompt) + max_visible (items) + 1 (count) = max_visible + 2
        rendered_height = max_visible + 2;

        // move cursor back to prompt line, position after query text
        try w.print("\x1b[{d}A", .{max_visible + 1});
        try w.print("\r\x1b[{d}C", .{2 + query_len});

        // show cursor
        try w.writeAll("\x1b[?25h");
        try bw.flush();

        // read input
        const b = reader.readByte() catch break;
        switch (b) {
            3 => { // ctrl-c
                try cleanup(w, &bw, rendered_height);
                std.posix.tcsetattr(tty_fd, .FLUSH, orig) catch {};
                return .{ .canceled = true };
            },
            27 => { // esc or arrow sequence
                const seq = readEscSeq(reader);
                switch (seq) {
                    .up => {
                        if (cursor > 0) cursor -= 1;
                    },
                    .down => {
                        if (ranked.items.len > 0 and cursor + 1 < ranked.items.len) cursor += 1;
                    },
                    .esc => {
                        try cleanup(w, &bw, rendered_height);
                        std.posix.tcsetattr(tty_fd, .FLUSH, orig) catch {};
                        return .{ .canceled = true };
                    },
                    .other => {},
                }
            },
            10, 13 => { // enter
                try cleanup(w, &bw, rendered_height);
                std.posix.tcsetattr(tty_fd, .FLUSH, orig) catch {};
                if (ranked.items.len > 0 and cursor < ranked.items.len) {
                    return .{ .path = notes[ranked.items[cursor].index].path };
                }
                return .{ .canceled = true };
            },
            127 => { // backspace
                if (query_len > 0) {
                    query_len -= 1;
                    cursor = 0;
                    offset = 0;
                }
            },
            16 => { // ctrl-p
                if (cursor > 0) cursor -= 1;
            },
            14 => { // ctrl-n
                if (ranked.items.len > 0 and cursor + 1 < ranked.items.len) cursor += 1;
            },
            else => {
                if (b >= 0x20 and b < 0x7f and query_len < query_buf.len) {
                    query_buf[query_len] = b;
                    query_len += 1;
                    cursor = 0;
                    offset = 0;
                }
            },
        }
    }

    std.posix.tcsetattr(tty_fd, .FLUSH, orig) catch {};
    return .{ .canceled = true };
}

fn cleanup(w: anytype, bw: anytype, height: usize) !void {
    // clear all rendered lines
    try w.writeAll("\r");
    for (0..height) |i| {
        try w.writeAll("\x1b[2K");
        if (i + 1 < height) try w.writeAll("\n");
    }
    // move back to top
    if (height > 1) {
        try w.print("\x1b[{d}A", .{height - 1});
    }
    try w.writeAll("\r\x1b[2K");
    try bw.flush();
}

const EscSeq = enum { up, down, esc, other };

fn readEscSeq(reader: anytype) EscSeq {
    const b1 = reader.readByte() catch return .esc;
    if (b1 != '[') return .esc;
    const b2 = reader.readByte() catch return .other;
    return switch (b2) {
        'A' => .up,
        'B' => .down,
        else => .other,
    };
}

fn filterNotes(
    notes: []const note_mod.Note,
    query: []const u8,
    ranked: *std.ArrayList(RankedItem),
) !void {
    if (query.len == 0) {
        for (0..notes.len) |i| {
            try ranked.append(.{ .index = i, .score = 0 });
        }
        return;
    }
    var tokens_buf: [16][]const u8 = undefined;
    var lower_buf: [1024]u8 = undefined;
    var token_count: usize = 0;
    var lower_pos: usize = 0;
    var iter = std.mem.tokenizeScalar(u8, query, ' ');
    while (iter.next()) |tok| {
        if (token_count >= 16) break;
        const start = lower_pos;
        for (tok) |c| {
            if (lower_pos >= lower_buf.len) break;
            lower_buf[lower_pos] = std.ascii.toLower(c);
            lower_pos += 1;
        }
        tokens_buf[token_count] = lower_buf[start..lower_pos];
        token_count += 1;
    }
    const tokens = tokens_buf[0..token_count];

    for (notes, 0..) |n, i| {
        if (zf.rank(n.title, tokens, false, true)) |score| {
            try ranked.append(.{ .index = i, .score = score });
        }
    }
    std.mem.sort(RankedItem, ranked.items, {}, struct {
        fn lessThan(_: void, a: RankedItem, b_item: RankedItem) bool {
            return a.score > b_item.score;
        }
    }.lessThan);
}

fn writeItemRow(
    writer: anytype,
    n: note_mod.Note,
    is_selected: bool,
    query: []const u8,
    max_width: usize,
) !void {
    var col: usize = 0;

    // cursor indicator: 2 visible chars
    if (is_selected) {
        try writer.writeAll("\x1b[36;1m\xe2\x96\xb8 \x1b[0m"); // ▸ + space
    } else {
        try writer.writeAll("  ");
    }
    col += 2;

    // slug: fixed width
    const slug = slugFromPath(n.path);
    const slug_len = @min(slug.len, slug_width);
    if (col + slug_width + 2 > max_width) {
        // not enough room, just write what fits
        const avail = if (max_width > col) max_width - col else 0;
        try writeN(writer, slug, avail);
        return;
    }
    try writeN(writer, slug, slug_len);
    // pad to slug_width
    var pad = slug_width - slug_len;
    while (pad > 0) : (pad -= 1) try writer.writeByte(' ');
    try writer.writeAll("  ");
    col += slug_width + 2;

    // title
    const title_budget = if (max_width > col + 2) max_width - col - 2 else 0; // leave room for labels hint
    if (title_budget == 0) return;

    // compute highlight set
    var match_set = [_]bool{false} ** 256;
    if (query.len > 0) {
        var tokens_buf: [16][]const u8 = undefined;
        var lower_buf: [1024]u8 = undefined;
        var token_count: usize = 0;
        var lower_pos: usize = 0;
        var iter = std.mem.tokenizeScalar(u8, query, ' ');
        while (iter.next()) |tok| {
            if (token_count >= 16) break;
            const start = lower_pos;
            for (tok) |c| {
                if (lower_pos >= lower_buf.len) break;
                lower_buf[lower_pos] = std.ascii.toLower(c);
                lower_pos += 1;
            }
            tokens_buf[token_count] = lower_buf[start..lower_pos];
            token_count += 1;
        }
        const tokens = tokens_buf[0..token_count];
        var matches_buf: [128]usize = undefined;
        const matches = zf.highlight(n.title, tokens, false, true, &matches_buf);
        for (matches) |m| {
            if (m < 256) match_set[m] = true;
        }
    }

    // write title chars up to budget
    var title_written: usize = 0;
    for (n.title, 0..) |c, i| {
        if (title_written >= title_budget) break;
        if (query.len > 0 and i < 256 and match_set[i]) {
            try writer.writeAll("\x1b[4;33m");
            try writer.writeByte(c);
            try writer.writeAll("\x1b[0m");
        } else {
            try writer.writeByte(c);
        }
        title_written += 1;
    }
    col += title_written;

    // labels if room
    if (n.labels.len > 0 and col + 4 < max_width) {
        try writer.writeAll("  \x1b[38;5;8m[");
        col += 3;
        for (n.labels, 0..) |label, li| {
            const extra: usize = if (li > 0) 2 else 0; // ", "
            if (col + extra + label.len + 1 > max_width) break;
            if (li > 0) {
                try writer.writeAll(", ");
                col += 2;
            }
            try writer.writeAll(label);
            col += label.len;
        }
        try writer.writeAll("]\x1b[0m");
    }
}

fn writeN(writer: anytype, s: []const u8, n: usize) !void {
    const len = @min(s.len, n);
    try writer.writeAll(s[0..len]);
}

fn slugFromPath(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, base, ".md")) return base[0 .. base.len - 3];
    return base;
}
