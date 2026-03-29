const std = @import("std");
const gitctx = @import("gitctx.zig");

pub const Note = struct {
    title: []const u8,
    labels: []const []const u8,
    date: i64,
    body: []const u8,
    dir: []const u8,
    path: []const u8,
    context: gitctx.Context,

    pub fn deinit(self: *Note, allocator: std.mem.Allocator) void {
        if (self.title.len > 0) allocator.free(self.title);
        for (self.labels) |l| allocator.free(l);
        if (self.labels.len > 0) allocator.free(self.labels);
        if (self.body.len > 0) allocator.free(self.body);
        if (self.dir.len > 0) allocator.free(self.dir);
        if (self.path.len > 0) allocator.free(self.path);
        self.context.deinit(allocator);
        self.* = .{
            .title = "",
            .labels = &.{},
            .date = 0,
            .body = "",
            .dir = "",
            .path = "",
            .context = .{},
        };
    }
};

// --- helpers ---

pub fn slugify(s: []const u8, buf: []u8) []const u8 {
    var len: usize = 0;
    var prev_hyphen = true; // treat start as hyphen to skip leading
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (len >= buf.len) break;
            buf[len] = std.ascii.toLower(c);
            len += 1;
            prev_hyphen = false;
        } else if (!prev_hyphen) {
            if (len >= buf.len) break;
            buf[len] = '-';
            len += 1;
            prev_hyphen = true;
        }
    }
    // trim trailing hyphen
    if (len > 0 and buf[len - 1] == '-') len -= 1;
    return buf[0..len];
}

pub fn filename(title: []const u8, date: i64, buf: []u8) []const u8 {
    if (title.len > 0) {
        const slug = slugify(title, buf);
        const end = slug.len;
        if (end + 3 <= buf.len) {
            @memcpy(buf[end .. end + 3], ".md");
            return buf[0 .. end + 3];
        }
        return buf[0..end];
    }
    // fallback: nts-YYYY-MM-DD.md
    var date_buf: [10]u8 = undefined;
    const ds = formatDateOnly(date, &date_buf);
    const out = std.fmt.bufPrint(buf, "nts-{s}.md", .{ds}) catch return buf[0..0];
    return out;
}

fn formatDateOnly(timestamp: i64, buf: *[10]u8) []const u8 {
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

pub fn formatRfc3339(timestamp: i64, buf: *[20]u8) []const u8 {
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(0, timestamp)) };
    const day = es.getEpochDay();
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    _ = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year,
        @intFromEnum(md.month),
        md.day_index + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    }) catch unreachable;
    return buf;
}

pub fn parseRfc3339(s: []const u8) !i64 {
    // YYYY-MM-DDTHH:MM:SS followed by Z or +HH:MM or -HH:MM
    if (s.len < 19) return error.InvalidFormat;
    const year = try std.fmt.parseInt(i32, s[0..4], 10);
    const month = try std.fmt.parseInt(u8, s[5..7], 10);
    const day = try std.fmt.parseInt(u8, s[8..10], 10);
    const hour = try std.fmt.parseInt(u8, s[11..13], 10);
    const min = try std.fmt.parseInt(u8, s[14..16], 10);
    const sec = try std.fmt.parseInt(u8, s[17..19], 10);
    var epoch = try dateToEpoch(year, month, day, hour, min, sec);

    // parse timezone offset
    if (s.len > 19) {
        const tz = s[19..];
        if (tz[0] == 'Z' or tz[0] == 'z') {
            // UTC, no adjustment
        } else if ((tz[0] == '+' or tz[0] == '-') and tz.len >= 6) {
            const tz_h = std.fmt.parseInt(i64, tz[1..3], 10) catch 0;
            const tz_m = std.fmt.parseInt(i64, tz[4..6], 10) catch 0;
            const offset_secs = tz_h * 3600 + tz_m * 60;
            if (tz[0] == '+') {
                epoch -= offset_secs;
            } else {
                epoch += offset_secs;
            }
        }
    }

    return epoch;
}

fn dateToEpoch(year: i32, month: u8, day: u8, hour: u8, min: u8, sec: u8) !i64 {
    // Hinnant civil_from_days algorithm
    var y: i64 = @intCast(year);
    var m: i64 = @intCast(month);
    if (m <= 2) {
        y -= 1;
        m += 9;
    } else {
        m -= 3;
    }
    const era_approx = @divFloor(y, 400);
    const yoe = y - era_approx * 400;
    const doy = @divFloor(153 * m + 2, 5) + @as(i64, @intCast(day)) - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const days = era_approx * 146097 + doe - 719468;
    return days * 86400 + @as(i64, @intCast(hour)) * 3600 + @as(i64, @intCast(min)) * 60 + @as(i64, @intCast(sec));
}

const FrontmatterSplit = struct {
    yaml: []const u8,
    body: []const u8,
};

fn extractFrontmatter(content: []const u8) ?FrontmatterSplit {
    const delim = "---";
    // must start with ---
    if (!std.mem.startsWith(u8, content, delim)) return null;
    var pos: usize = delim.len;
    // skip rest of first --- line
    if (pos < content.len and content[pos] == '\n') {
        pos += 1;
    } else if (pos < content.len and content[pos] == '\r') {
        pos += 1;
        if (pos < content.len and content[pos] == '\n') pos += 1;
    } else return null;

    const yaml_start = pos;
    // find second ---
    while (pos < content.len) {
        if (std.mem.startsWith(u8, content[pos..], delim)) {
            const after = pos + delim.len;
            // must be at line start and followed by newline or EOF
            if (after >= content.len or content[after] == '\n' or content[after] == '\r') {
                const yaml = content[yaml_start..pos];
                var body_start = after;
                if (body_start < content.len and content[body_start] == '\r') body_start += 1;
                if (body_start < content.len and content[body_start] == '\n') body_start += 1;
                return .{
                    .yaml = yaml,
                    .body = content[body_start..],
                };
            }
        }
        // advance to next line
        while (pos < content.len and content[pos] != '\n') : (pos += 1) {}
        if (pos < content.len) pos += 1; // skip \n
    }
    return null;
}

fn parseYamlValue(line: []const u8) struct { key: []const u8, value: []const u8 } {
    if (std.mem.indexOfScalar(u8, line, ':')) |colon| {
        const key = std.mem.trim(u8, line[0..colon], &std.ascii.whitespace);
        const raw = if (colon + 1 < line.len) line[colon + 1 ..] else "";
        const value = std.mem.trim(u8, raw, &std.ascii.whitespace);
        return .{ .key = key, .value = value };
    }
    return .{ .key = std.mem.trim(u8, line, &std.ascii.whitespace), .value = "" };
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2) {
        if ((s[0] == '"' and s[s.len - 1] == '"') or
            (s[0] == '\'' and s[s.len - 1] == '\''))
        {
            return s[1 .. s.len - 1];
        }
    }
    return s;
}

// --- public API ---

pub fn frontmatter(allocator: std.mem.Allocator, n: Note) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const w = buf.writer();

    try w.writeAll("---\n");

    // title
    try w.print("title: \"{s}\"\n", .{n.title});

    // date
    var rfc_buf: [20]u8 = undefined;
    const ds = formatRfc3339(n.date, &rfc_buf);
    try w.print("date: \"{s}\"\n", .{ds});

    // tags
    if (n.labels.len > 0) {
        try w.writeAll("tags:\n");
        for (n.labels) |label| {
            try w.print("  - {s}\n", .{label});
        }
    }

    // context
    if (!n.context.isEmpty()) {
        try w.writeAll("context:\n");
        inline for (.{ "project", "branch", "issue", "repo_dir", "commit" }) |f| {
            if (@field(n.context, f)) |v| {
                try w.print("  {s}: {s}\n", .{ f, v });
            }
        }
        if (n.context.dirty) |d| {
            try w.print("  dirty: {}\n", .{d});
        }
        if (n.context.files) |files| {
            try w.writeAll("  files:\n");
            for (files) |file| {
                try w.print("    - {s}\n", .{file});
            }
        }
    }

    try w.writeAll("---\n");

    return buf.toOwnedSlice();
}

pub fn create(allocator: std.mem.Allocator, n: *Note) ![]const u8 {
    // ensure dir exists
    std.fs.cwd().makePath(n.dir) catch {};

    var fname_buf: [256]u8 = undefined;
    const base = filename(n.title, n.date, &fname_buf);

    // build path, dedup if needed
    var path = try std.fs.path.join(allocator, &.{ n.dir, base });

    var suffix: usize = 1;
    while (fileExists(path)) {
        allocator.free(path);
        // strip .md, add -N.md
        const stem = stripMd(base);
        var dedup_buf: [300]u8 = undefined;
        const dedup_name = std.fmt.bufPrint(&dedup_buf, "{s}-{d}.md", .{ stem, suffix }) catch break;
        path = try std.fs.path.join(allocator, &.{ n.dir, dedup_name });
        suffix += 1;
        if (suffix > 999) break;
    }

    // build content
    const fm = try frontmatter(allocator, n.*);
    defer allocator.free(fm);

    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    try content.appendSlice(fm);
    try content.append('\n');
    try content.appendSlice(n.body);
    if (n.body.len > 0 and n.body[n.body.len - 1] != '\n') {
        try content.append('\n');
    }

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = content.items });

    return path;
}

fn stripMd(name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, name, ".md")) return name[0 .. name.len - 3];
    return name;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn parse(allocator: std.mem.Allocator, path: []const u8) !Note {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(content);

    const split = extractFrontmatter(content) orelse return error.InvalidFrontmatter;

    var title: []const u8 = "";
    var date: i64 = 0;
    var labels = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (labels.items) |l| allocator.free(l);
        labels.deinit();
    }
    var ctx = gitctx.Context{};
    errdefer ctx.deinit(allocator);

    var ctx_files = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (ctx_files.items) |f| allocator.free(f);
        ctx_files.deinit();
    }

    const Section = enum { root, tags, context, context_files };
    var section: Section = .root;

    var lines_iter = std.mem.splitScalar(u8, split.yaml, '\n');
    while (lines_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        // check indentation level
        const indent = countIndent(line);

        // list items
        if (std.mem.startsWith(u8, trimmed, "- ")) {
            const item_val = std.mem.trim(u8, trimmed[2..], &std.ascii.whitespace);
            switch (section) {
                .tags => {
                    try labels.append(try allocator.dupe(u8, unquote(item_val)));
                },
                .context_files => {
                    try ctx_files.append(try allocator.dupe(u8, unquote(item_val)));
                },
                else => {},
            }
            continue;
        }

        const kv = parseYamlValue(trimmed);

        if (indent == 0) {
            // top-level key
            section = .root;
            if (std.mem.eql(u8, kv.key, "title")) {
                title = try allocator.dupe(u8, unquote(kv.value));
            } else if (std.mem.eql(u8, kv.key, "date")) {
                date = parseRfc3339(unquote(kv.value)) catch 0;
            } else if (std.mem.eql(u8, kv.key, "tags")) {
                section = .tags;
            } else if (std.mem.eql(u8, kv.key, "context")) {
                section = .context;
            }
        } else if (section == .context or section == .context_files) {
            if (std.mem.eql(u8, kv.key, "project")) {
                ctx.project = try allocator.dupe(u8, unquote(kv.value));
            } else if (std.mem.eql(u8, kv.key, "branch")) {
                ctx.branch = try allocator.dupe(u8, unquote(kv.value));
            } else if (std.mem.eql(u8, kv.key, "issue")) {
                ctx.issue = try allocator.dupe(u8, unquote(kv.value));
            } else if (std.mem.eql(u8, kv.key, "repo_dir")) {
                ctx.repo_dir = try allocator.dupe(u8, unquote(kv.value));
            } else if (std.mem.eql(u8, kv.key, "commit")) {
                ctx.commit = try allocator.dupe(u8, unquote(kv.value));
            } else if (std.mem.eql(u8, kv.key, "dirty")) {
                ctx.dirty = std.mem.eql(u8, kv.value, "true");
            } else if (std.mem.eql(u8, kv.key, "files")) {
                section = .context_files;
            }
        }
    }

    if (ctx_files.items.len > 0) {
        ctx.files = try ctx_files.toOwnedSlice();
    } else {
        ctx_files.deinit();
    }

    const body_trimmed = std.mem.trim(u8, split.body, &std.ascii.whitespace);
    const body = if (body_trimmed.len > 0) try allocator.dupe(u8, body_trimmed) else "";

    const dir = if (std.fs.path.dirname(path)) |d| try allocator.dupe(u8, d) else "";

    return Note{
        .title = title,
        .labels = try labels.toOwnedSlice(),
        .date = date,
        .body = body,
        .dir = dir,
        .path = try allocator.dupe(u8, path),
        .context = ctx,
    };
}

fn countIndent(line: []const u8) usize {
    var n: usize = 0;
    for (line) |c| {
        if (c == ' ') {
            n += 1;
        } else break;
    }
    return n;
}

pub fn parseAll(allocator: std.mem.Allocator, dir: []const u8) ![]Note {
    var notes = std.ArrayList(Note).init(allocator);
    errdefer {
        for (notes.items) |*n| n.deinit(allocator);
        notes.deinit();
    }

    var d = std.fs.cwd().openDir(dir, .{ .iterate = true }) catch return notes.toOwnedSlice();
    defer d.close();

    var iter = d.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
        const full_path = try std.fs.path.join(allocator, &.{ dir, entry.name });
        defer allocator.free(full_path);
        const n = parse(allocator, full_path) catch continue;
        try notes.append(n);
    }

    return notes.toOwnedSlice();
}

pub fn parseAllCached(allocator: std.mem.Allocator, dir: []const u8, cache_path: []const u8) ![]Note {
    // load existing cache
    var cache = loadCache(allocator, cache_path);
    defer cache.deinit();

    var notes = std.ArrayList(Note).init(allocator);
    errdefer {
        for (notes.items) |*n| n.deinit(allocator);
        notes.deinit();
    }

    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var key_iter = seen.keyIterator();
        while (key_iter.next()) |k| allocator.free(k.*);
        seen.deinit();
    }

    var d = std.fs.cwd().openDir(dir, .{ .iterate = true }) catch return notes.toOwnedSlice();
    defer d.close();

    var iter = d.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
        const full_path = try std.fs.path.join(allocator, &.{ dir, entry.name });

        try seen.put(try allocator.dupe(u8, full_path), {});

        const stat = std.fs.cwd().statFile(full_path) catch {
            allocator.free(full_path);
            continue;
        };
        const mtime: i128 = @intCast(stat.mtime);

        // check cache
        if (cache.entries.get(full_path)) |cached| {
            if (cached.mod_time == mtime) {
                // use cached metadata, body = ""
                var n = Note{
                    .title = if (cached.title.len > 0) try allocator.dupe(u8, cached.title) else "",
                    .labels = try dupeLabels(allocator, cached.labels),
                    .date = cached.date,
                    .body = "",
                    .dir = try allocator.dupe(u8, dir),
                    .path = full_path,
                    .context = try dupeContext(allocator, cached.context),
                };
                _ = &n;
                try notes.append(n);
                continue;
            }
        }

        // parse fresh
        const n = parse(allocator, full_path) catch {
            allocator.free(full_path);
            continue;
        };
        allocator.free(full_path); // parse dupes path

        // update cache
        const cache_entry = CacheEntry{
            .title = try allocator.dupe(u8, n.title),
            .labels = try dupeLabels(allocator, n.labels),
            .date = n.date,
            .mod_time = mtime,
            .context = try dupeContext(allocator, n.context),
        };
        const path_key = try allocator.dupe(u8, n.path);
        if (try cache.entries.fetchPut(path_key, cache_entry)) |old| {
            freeCacheEntry(allocator, old.value);
            allocator.free(old.key);
        }

        try notes.append(n);
    }

    // remove deleted entries
    var to_remove = std.ArrayList([]const u8).init(allocator);
    defer to_remove.deinit();
    var cache_iter = cache.entries.keyIterator();
    while (cache_iter.next()) |k| {
        if (!seen.contains(k.*)) {
            try to_remove.append(k.*);
        }
    }
    for (to_remove.items) |k| {
        if (cache.entries.fetchRemove(k)) |old| {
            freeCacheEntry(allocator, old.value);
            allocator.free(old.key);
        }
    }

    // save cache
    saveCache(allocator, cache_path, cache) catch {};

    // sort by path
    std.mem.sort(Note, notes.items, {}, struct {
        fn lessThan(_: void, a: Note, b: Note) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    return notes.toOwnedSlice();
}

pub fn parseBodyOnly(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(content);

    if (extractFrontmatter(content)) |split| {
        const trimmed = std.mem.trim(u8, split.body, &std.ascii.whitespace);
        if (trimmed.len > 0) return allocator.dupe(u8, trimmed);
        return allocator.dupe(u8, "");
    }
    // no frontmatter, return whole thing
    const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);
    return allocator.dupe(u8, trimmed);
}

// --- cache internals ---

const CacheEntry = struct {
    title: []const u8,
    labels: []const []const u8,
    date: i64,
    mod_time: i128,
    context: gitctx.Context,
};

const Cache = struct {
    entries: std.StringHashMap(CacheEntry),
    allocator: std.mem.Allocator,

    fn deinit(self: *Cache) void {
        var it = self.entries.iterator();
        while (it.next()) |e| {
            freeCacheEntry(self.allocator, e.value_ptr.*);
            self.allocator.free(e.key_ptr.*);
        }
        self.entries.deinit();
    }
};

fn freeCacheEntry(allocator: std.mem.Allocator, e: CacheEntry) void {
    if (e.title.len > 0) allocator.free(e.title);
    for (e.labels) |l| allocator.free(l);
    if (e.labels.len > 0) allocator.free(e.labels);
    var ctx = e.context;
    ctx.deinit(allocator);
}

fn dupeLabels(allocator: std.mem.Allocator, labels: []const []const u8) ![]const []const u8 {
    if (labels.len == 0) return &.{};
    var result = try allocator.alloc([]const u8, labels.len);
    for (labels, 0..) |l, i| {
        result[i] = try allocator.dupe(u8, l);
    }
    return result;
}

fn dupeContext(allocator: std.mem.Allocator, ctx: gitctx.Context) !gitctx.Context {
    var new_ctx = gitctx.Context{};
    inline for (.{ "project", "branch", "issue", "repo_dir", "commit" }) |f| {
        if (@field(ctx, f)) |v| {
            @field(new_ctx, f) = try allocator.dupe(u8, v);
        }
    }
    new_ctx.dirty = ctx.dirty;
    if (ctx.files) |files| {
        new_ctx.files = try dupeLabels(allocator, files);
    }
    return new_ctx;
}

fn loadCache(allocator: std.mem.Allocator, cache_path: []const u8) Cache {
    var cache = Cache{
        .entries = std.StringHashMap(CacheEntry).init(allocator),
        .allocator = allocator,
    };

    const data = std.fs.cwd().readFileAlloc(allocator, cache_path, 50 * 1024 * 1024) catch return cache;
    defer allocator.free(data);

    // manual JSON parse using std.json.Scanner
    var scanner = std.json.Scanner.initCompleteInput(allocator, data);
    defer scanner.deinit();

    // expect top-level object
    parseJsonCache(allocator, &scanner, &cache) catch return cache;

    return cache;
}

fn parseJsonCache(allocator: std.mem.Allocator, scanner: *std.json.Scanner, cache: *Cache) !void {
    // { "entries": { ... } }
    try expectToken(scanner, .object_begin);
    while (true) {
        const tok = try scanner.next();
        switch (tok) {
            .object_end => return,
            .string => |s| {
                if (std.mem.eql(u8, s, "entries")) {
                    try parseEntries(allocator, scanner, cache);
                } else {
                    try skipValue(scanner);
                }
            },
            else => return error.UnexpectedToken,
        }
    }
}

fn parseEntries(allocator: std.mem.Allocator, scanner: *std.json.Scanner, cache: *Cache) !void {
    try expectToken(scanner, .object_begin);
    while (true) {
        const tok = try scanner.next();
        switch (tok) {
            .object_end => return,
            .string => |path_str| {
                const path_key = try allocator.dupe(u8, path_str);
                const entry = parseOneEntry(allocator, scanner) catch {
                    allocator.free(path_key);
                    continue;
                };
                cache.entries.put(path_key, entry) catch {
                    allocator.free(path_key);
                    continue;
                };
            },
            else => return error.UnexpectedToken,
        }
    }
}

fn parseOneEntry(allocator: std.mem.Allocator, scanner: *std.json.Scanner) !CacheEntry {
    var title: []const u8 = "";
    var labels = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (labels.items) |l| allocator.free(l);
        labels.deinit();
    }
    var date: i64 = 0;
    var mod_time: i128 = 0;
    var ctx = gitctx.Context{};
    errdefer ctx.deinit(allocator);

    try expectToken(scanner, .object_begin);
    while (true) {
        const tok = try scanner.next();
        switch (tok) {
            .object_end => break,
            .string => |key| {
                if (std.mem.eql(u8, key, "title")) {
                    const val = try scanner.next();
                    if (val == .string) {
                        title = try allocator.dupe(u8, val.string);
                    }
                } else if (std.mem.eql(u8, key, "labels")) {
                    try expectToken(scanner, .array_begin);
                    while (true) {
                        const item = try scanner.next();
                        switch (item) {
                            .array_end => break,
                            .string => |s| try labels.append(try allocator.dupe(u8, s)),
                            else => {},
                        }
                    }
                } else if (std.mem.eql(u8, key, "date")) {
                    const val = try scanner.next();
                    if (val == .number) {
                        date = std.fmt.parseInt(i64, val.number, 10) catch 0;
                    }
                } else if (std.mem.eql(u8, key, "mod_time")) {
                    const val = try scanner.next();
                    if (val == .number) {
                        mod_time = std.fmt.parseInt(i128, val.number, 10) catch 0;
                    }
                } else if (std.mem.eql(u8, key, "context")) {
                    ctx = try parseContextJson(allocator, scanner);
                } else {
                    try skipValue(scanner);
                }
            },
            else => return error.UnexpectedToken,
        }
    }

    return CacheEntry{
        .title = title,
        .labels = try labels.toOwnedSlice(),
        .date = date,
        .mod_time = mod_time,
        .context = ctx,
    };
}

fn parseContextJson(allocator: std.mem.Allocator, scanner: *std.json.Scanner) !gitctx.Context {
    var ctx = gitctx.Context{};
    errdefer ctx.deinit(allocator);
    var ctx_files = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (ctx_files.items) |f| allocator.free(f);
        ctx_files.deinit();
    }

    try expectToken(scanner, .object_begin);
    while (true) {
        const tok = try scanner.next();
        switch (tok) {
            .object_end => break,
            .string => |key| {
                if (std.mem.eql(u8, key, "project") or
                    std.mem.eql(u8, key, "branch") or
                    std.mem.eql(u8, key, "issue") or
                    std.mem.eql(u8, key, "repo_dir") or
                    std.mem.eql(u8, key, "commit"))
                {
                    const val = try scanner.next();
                    if (val == .string) {
                        const duped = try allocator.dupe(u8, val.string);
                        if (std.mem.eql(u8, key, "project")) ctx.project = duped
                        else if (std.mem.eql(u8, key, "branch")) ctx.branch = duped
                        else if (std.mem.eql(u8, key, "issue")) ctx.issue = duped
                        else if (std.mem.eql(u8, key, "repo_dir")) ctx.repo_dir = duped
                        else if (std.mem.eql(u8, key, "commit")) ctx.commit = duped;
                    }
                } else if (std.mem.eql(u8, key, "dirty")) {
                    const val = try scanner.next();
                    if (val == .true) ctx.dirty = true
                    else if (val == .false) ctx.dirty = false;
                } else if (std.mem.eql(u8, key, "files")) {
                    try expectToken(scanner, .array_begin);
                    while (true) {
                        const item = try scanner.next();
                        switch (item) {
                            .array_end => break,
                            .string => |s| try ctx_files.append(try allocator.dupe(u8, s)),
                            else => {},
                        }
                    }
                } else {
                    try skipValue(scanner);
                }
            },
            else => return error.UnexpectedToken,
        }
    }

    if (ctx_files.items.len > 0) {
        ctx.files = try ctx_files.toOwnedSlice();
    } else {
        ctx_files.deinit();
    }

    return ctx;
}

fn expectToken(scanner: *std.json.Scanner, expected: std.json.Token) !void {
    const tok = try scanner.next();
    if (std.meta.activeTag(tok) != std.meta.activeTag(expected)) return error.UnexpectedToken;
}

fn skipValue(scanner: *std.json.Scanner) !void {
    const tok = try scanner.next();
    switch (tok) {
        .object_begin => {
            var depth: usize = 1;
            while (depth > 0) {
                const t = try scanner.next();
                switch (t) {
                    .object_begin => depth += 1,
                    .object_end => depth -= 1,
                    else => {},
                }
            }
        },
        .array_begin => {
            var depth: usize = 1;
            while (depth > 0) {
                const t = try scanner.next();
                switch (t) {
                    .array_begin => depth += 1,
                    .array_end => depth -= 1,
                    else => {},
                }
            }
        },
        else => {}, // scalar, already consumed
    }
}

fn saveCache(allocator: std.mem.Allocator, cache_path: []const u8, cache: Cache) !void {
    if (std.fs.path.dirname(cache_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    const w = buf.writer();

    try w.writeAll("{\"entries\":{");

    var first = true;
    var it = cache.entries.iterator();
    while (it.next()) |e| {
        if (!first) try w.writeByte(',');
        first = false;

        try w.writeByte('\n');
        try writeJsonString(w, e.key_ptr.*);
        try w.writeAll(":{");

        try w.writeAll("\"title\":");
        try writeJsonString(w, e.value_ptr.title);

        try w.writeAll(",\"labels\":[");
        for (e.value_ptr.labels, 0..) |l, i| {
            if (i > 0) try w.writeByte(',');
            try writeJsonString(w, l);
        }
        try w.writeAll("]");

        try w.print(",\"date\":{d}", .{e.value_ptr.date});
        try w.print(",\"mod_time\":{d}", .{e.value_ptr.mod_time});

        try w.writeAll(",\"context\":{");
        var ctx_first = true;
        inline for (.{ "project", "branch", "issue", "repo_dir", "commit" }) |f| {
            if (@field(e.value_ptr.context, f)) |v| {
                if (!ctx_first) try w.writeByte(',');
                ctx_first = false;
                try writeJsonString(w, f);
                try w.writeByte(':');
                try writeJsonString(w, v);
            }
        }
        if (e.value_ptr.context.dirty) |d| {
            if (!ctx_first) try w.writeByte(',');
            ctx_first = false;
            if (d) try w.writeAll("\"dirty\":true") else try w.writeAll("\"dirty\":false");
        }
        if (e.value_ptr.context.files) |files| {
            if (!ctx_first) try w.writeByte(',');
            //ctx_first = false;
            try w.writeAll("\"files\":[");
            for (files, 0..) |file, i| {
                if (i > 0) try w.writeByte(',');
                try writeJsonString(w, file);
            }
            try w.writeAll("]");
        }
        try w.writeByte('}');

        try w.writeByte('}');
    }

    try w.writeAll("}}\n");

    try std.fs.cwd().writeFile(.{ .sub_path = cache_path, .data = buf.items });
}

fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}
