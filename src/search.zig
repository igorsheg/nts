const std = @import("std");
const zf = @import("zf");
const note = @import("note.zig");

pub const Result = struct {
    note_index: usize,
    score: f64,
};

const max_tokens = 16;

fn tokenize(query: []const u8, token_buf: *[max_tokens][]const u8, lower_buf: *[max_tokens * 64]u8) struct { tokens: [][]const u8, count: usize } {
    var count: usize = 0;
    var lower_pos: usize = 0;
    var it = std.mem.tokenizeScalar(u8, query, ' ');
    while (it.next()) |tok| {
        if (count >= max_tokens) break;
        const start = lower_pos;
        for (tok) |c| {
            if (lower_pos >= lower_buf.len) break;
            lower_buf[lower_pos] = std.ascii.toLower(c);
            lower_pos += 1;
        }
        token_buf[count] = lower_buf[start..lower_pos];
        count += 1;
    }
    return .{ .tokens = token_buf[0..count], .count = count };
}

fn slugFromPath(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    return if (std.mem.endsWith(u8, base, ".md")) base[0 .. base.len - 3] else base;
}

pub fn fuzzySearch(query: []const u8, notes: []const note.Note, results_buf: []Result) []Result {
    var token_buf: [max_tokens][]const u8 = undefined;
    var lower_buf: [max_tokens * 64]u8 = undefined;
    const tok = tokenize(query, &token_buf, &lower_buf);
    if (tok.count == 0) return results_buf[0..0];

    var count: usize = 0;
    for (notes, 0..) |n, i| {
        if (count >= results_buf.len) break;

        const title_score = zf.rank(n.title, tok.tokens, false, true);
        const slug = slugFromPath(n.path);
        const slug_score = zf.rank(slug, tok.tokens, false, true);

        const score = blk: {
            if (title_score) |ts| {
                if (slug_score) |ss| break :blk @max(ts, ss);
                break :blk ts;
            }
            if (slug_score) |ss| break :blk ss;
            break :blk @as(?f64, null);
        };

        if (score) |s| {
            results_buf[count] = .{ .note_index = i, .score = s };
            count += 1;
        }
    }

    sortResults(results_buf[0..count]);
    return results_buf[0..count];
}

pub fn bodySearch(allocator: std.mem.Allocator, query: []const u8, notes: []const note.Note, results_buf: []Result) []Result {
    if (query.len == 0) return results_buf[0..0];

    var lower_query_buf: [256]u8 = undefined;
    const qlen = @min(query.len, lower_query_buf.len);
    for (query[0..qlen], 0..) |c, j| lower_query_buf[j] = std.ascii.toLower(c);
    const lower_query = lower_query_buf[0..qlen];

    var count: usize = 0;
    for (notes, 0..) |n, i| {
        if (count >= results_buf.len) break;
        const body = std.fs.cwd().readFileAlloc(allocator, n.path, 1024 * 1024) catch continue;
        defer allocator.free(body);

        var occurrences: f64 = 0;
        var pos: usize = 0;
        while (pos + lower_query.len <= body.len) {
            if (asciiEqlIgnoreCase(body[pos..][0..qlen], lower_query)) {
                occurrences += 1;
                pos += qlen;
            } else {
                pos += 1;
            }
        }

        if (occurrences > 0) {
            results_buf[count] = .{ .note_index = i, .score = occurrences * 100 };
            count += 1;
        }
    }

    sortResults(results_buf[0..count]);
    return results_buf[0..count];
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != cb) return false;
    }
    return true;
}

pub fn mergeResults(fuzzy_results: []const Result, body_results: []const Result, merged_buf: []Result, limit: usize) []Result {
    var count: usize = 0;

    for (fuzzy_results) |r| {
        if (count >= merged_buf.len) break;
        merged_buf[count] = r;
        count += 1;
    }

    for (body_results) |br| {
        var found = false;
        for (merged_buf[0..count]) |*mr| {
            if (mr.note_index == br.note_index) {
                mr.score += br.score;
                found = true;
                break;
            }
        }
        if (!found and count < merged_buf.len) {
            merged_buf[count] = br;
            count += 1;
        }
    }

    sortResults(merged_buf[0..count]);
    const cap = @min(count, limit);
    return merged_buf[0..cap];
}

fn sortResults(results: []Result) void {
    var i: usize = 1;
    while (i < results.len) : (i += 1) {
        const key = results[i];
        var j: usize = i;
        while (j > 0 and results[j - 1].score < key.score) {
            results[j] = results[j - 1];
            j -= 1;
        }
        results[j] = key;
    }
}
