const std = @import("std");
const config = @import("config.zig");
const gitctx = @import("gitctx.zig");
const editor = @import("editor.zig");
const note_mod = @import("note.zig");
const search = @import("search.zig");
const resolve = @import("resolve.zig");
const format = @import("format.zig");
const envelope = @import("envelope.zig");
const picker = @import("picker.zig");

pub const version = "0.4.0";

pub fn run(allocator: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        showHelp();
        return;
    }

    const cmd = args[1];
    if (eql(cmd, "new")) return cmdNew(allocator, args[2..]);
    if (eql(cmd, "list") or eql(cmd, "ls")) return cmdList(allocator, args[2..]);
    if (eql(cmd, "show")) return cmdShow(allocator, args[2..]);
    if (eql(cmd, "search")) return cmdSearch(allocator, args[2..]);
    if (eql(cmd, "edit")) return cmdEdit(allocator, args[2..]);
    if (eql(cmd, "append")) return cmdAppend(allocator, args[2..]);
    if (eql(cmd, "config")) return cmdConfig(allocator, args[2..]);
    if (eql(cmd, "completion")) return cmdCompletion(args[2..]);
    if (eql(cmd, "version")) {
        showVersion();
        return;
    }
    if (eql(cmd, "--help") or eql(cmd, "-h")) {
        showHelp();
        return;
    }
    if (eql(cmd, "--version") or eql(cmd, "-v")) {
        showVersion();
        return;
    }
    if (eql(cmd, "--json")) return cmdRootJson();

    // bare arg → treat as title for new note
    return cmdNew(allocator, args[1..]);
}

// --- commands ---

fn cmdNew(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var title: ?[]const u8 = null;
    var labels_raw: ?[]const u8 = null;
    var body_flag: ?[]const u8 = null;
    var body_file: ?[]const u8 = null;
    var force_editor = false;
    var json_out = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "-t") or eql(a, "--title")) {
            title = nextArg(args, &i);
        } else if (eql(a, "-l") or eql(a, "--labels")) {
            labels_raw = nextArg(args, &i);
        } else if (eql(a, "-b") or eql(a, "--body")) {
            body_flag = nextArg(args, &i);
        } else if (eql(a, "-F") or eql(a, "--body-file")) {
            body_file = nextArg(args, &i);
        } else if (eql(a, "-e") or eql(a, "--editor")) {
            force_editor = true;
        } else if (eql(a, "--json")) {
            json_out = true;
        } else if (title == null) {
            title = a;
        }
    }

    var cfg = try config.load(allocator);
    defer cfg.deinit();

    const labels = try parseLabels(allocator, labels_raw);
    defer {
        for (labels) |l| allocator.free(l);
        if (labels.len > 0) allocator.free(labels);
    }

    const body = try resolveBody(allocator, body_flag, body_file);

    var n = note_mod.Note{
        .title = title orelse "",
        .labels = labels,
        .date = std.time.timestamp(),
        .body = body orelse "",
        .dir = cfg.notes_dir,
        .path = "",
        .context = gitctx.detect(allocator),
    };

    const path = try note_mod.create(allocator, &n);
    defer allocator.free(path);

    const needs_editor = (body == null and !json_out) or force_editor;
    if (needs_editor) {
        if (!format.isTTY()) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("error: no body provided — use -b or -F in non-interactive mode\n");
            return error.NoBody;
        }
        const before = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch "";
        defer if (before.len > 0) allocator.free(before);

        editor.open(cfg.resolveEditor(), path, allocator) catch {
            std.fs.cwd().deleteFile(path) catch {};
            return error.EditorFailed;
        };

        const after = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch "";
        defer if (after.len > 0) allocator.free(after);

        if (std.mem.eql(u8, before, after)) {
            std.fs.cwd().deleteFile(path) catch {};
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll("aborted — note discarded\n");
            return;
        }
    }

    if (json_out) {
        const parsed = try note_mod.parse(allocator, path);
        _ = parsed;
        const slug = slugFromPath(path);
        const stdout = std.io.getStdOut().writer();
        try envelope.printNewEnvelope(stdout, n, slug);
        return;
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("saved: {s}\n", .{path});
    const slug = slugFromPath(path);
    var hint_buf: [256]u8 = undefined;
    const h = std.fmt.bufPrint(&hint_buf, "  show: nts show {s}\n  edit: nts edit {s}", .{ slug, slug }) catch return;
    try format.hint(stdout, h);
    try stdout.writeByte('\n');
}

fn cmdList(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var labels_raw: ?[]const u8 = null;
    var limit: usize = 20;
    var search_text: ?[]const u8 = null;
    var project: ?[]const u8 = null;
    var json_out = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "-l") or eql(a, "--labels")) {
            labels_raw = nextArg(args, &i);
        } else if (eql(a, "-n") or eql(a, "--limit")) {
            if (nextArg(args, &i)) |v| {
                limit = std.fmt.parseInt(usize, v, 10) catch 20;
            }
        } else if (eql(a, "-S") or eql(a, "--search")) {
            search_text = nextArg(args, &i);
        } else if (eql(a, "-p") or eql(a, "--project")) {
            project = nextArg(args, &i);
        } else if (eql(a, "--json")) {
            json_out = true;
        }
    }

    var cfg = try config.load(allocator);
    defer cfg.deinit();

    const cache_path = try config.metaCachePath(allocator);
    defer allocator.free(cache_path);

    const all_notes = try note_mod.parseAllCached(allocator, cfg.notes_dir, cache_path);
    defer {
        for (all_notes) |*n| {
            var mn = n.*;
            mn.deinit(allocator);
        }
        allocator.free(all_notes);
    }

    // sort by date descending
    std.mem.sort(note_mod.Note, all_notes, {}, struct {
        fn lessThan(_: void, a: note_mod.Note, b: note_mod.Note) bool {
            return a.date > b.date;
        }
    }.lessThan);

    const labels = try parseLabels(allocator, labels_raw);
    defer {
        for (labels) |l| allocator.free(l);
        if (labels.len > 0) allocator.free(labels);
    }

    var filtered = std.ArrayList(note_mod.Note).init(allocator);
    defer filtered.deinit();

    for (all_notes) |n| {
        if (labels.len > 0 and !matchesLabels(n, labels)) continue;
        if (project) |p| {
            if (!matchesProject(n, p)) continue;
        }
        if (search_text) |q| {
            if (!matchesSearch(n, q)) continue;
        }
        try filtered.append(n);
        if (filtered.items.len >= limit) break;
    }

    if (json_out) {
        const stdout = std.io.getStdOut().writer();
        try envelope.printListEnvelope(stdout, filtered.items);
        return;
    }

    if (filtered.items.len == 0) {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("no notes yet — create one with: nts \"My first note\"\n");
        return;
    }

    const stdout = std.io.getStdOut().writer();
    for (filtered.items) |n| {
        try format.formatNoteRow(stdout, n);
    }
}

fn cmdShow(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var json_out = false;
    var raw = false;
    var query: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "--json")) {
            json_out = true;
        } else if (eql(a, "--raw")) {
            raw = true;
        } else if (query == null) {
            query = a;
        }
    }

    var cfg = try config.load(allocator);
    defer cfg.deinit();

    const cache_path = try config.metaCachePath(allocator);
    defer allocator.free(cache_path);

    var path: []const u8 = undefined;
    var path_owned = false;

    if (query) |q| {
        path = try resolve.strict(allocator, cfg.notes_dir, q, cache_path);
        path_owned = true;
    } else {
        if (!format.isTTY()) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("error: slug required in non-interactive mode: nts show <slug>\n");
            return error.MissingArgument;
        }
        const notes = try loadSortedNotes(allocator, cfg.notes_dir, cache_path);
        if (notes.len == 0) {
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll("no notes yet — create one with: nts \"My first note\"\n");
            return;
        }
        const result = try picker.runPicker(allocator, notes);
        if (result.canceled) return;
        path = result.path orelse return;
    }
    defer if (path_owned) allocator.free(path);

    if (json_out) {
        var n = try note_mod.parse(allocator, path);
        defer n.deinit(allocator);
        const slug = slugFromPath(path);
        const stdout = std.io.getStdOut().writer();
        try envelope.printShowEnvelope(stdout, n, slug);
        return;
    }

    if (raw or !format.isTTY()) {
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
        defer allocator.free(data);
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(data);
        return;
    }

    // TTY pretty print
    var n = try note_mod.parse(allocator, path);
    defer n.deinit(allocator);
    const stdout = std.io.getStdOut().writer();
    try renderPretty(stdout, n);
}

fn cmdSearch(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var labels_raw: ?[]const u8 = null;
    var limit: usize = 10;
    var project: ?[]const u8 = null;
    var json_out = false;
    var query: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "-l") or eql(a, "--labels")) {
            labels_raw = nextArg(args, &i);
        } else if (eql(a, "-n") or eql(a, "--limit")) {
            if (nextArg(args, &i)) |v| {
                limit = std.fmt.parseInt(usize, v, 10) catch 10;
            }
        } else if (eql(a, "-p") or eql(a, "--project")) {
            project = nextArg(args, &i);
        } else if (eql(a, "--json")) {
            json_out = true;
        } else if (query == null) {
            query = a;
        }
    }

    const q = query orelse {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("error: query required: nts search <query>\n");
        return error.MissingArgument;
    };

    var cfg = try config.load(allocator);
    defer cfg.deinit();

    const cache_path = try config.metaCachePath(allocator);
    defer allocator.free(cache_path);

    const all_notes = try note_mod.parseAllCached(allocator, cfg.notes_dir, cache_path);
    defer {
        for (all_notes) |*n| {
            var mn = n.*;
            mn.deinit(allocator);
        }
        allocator.free(all_notes);
    }

    const labels = try parseLabels(allocator, labels_raw);
    defer {
        for (labels) |l| allocator.free(l);
        if (labels.len > 0) allocator.free(labels);
    }

    // pre-filter
    var filtered = std.ArrayList(note_mod.Note).init(allocator);
    defer filtered.deinit();

    for (all_notes) |n| {
        if (labels.len > 0 and !matchesLabels(n, labels)) continue;
        if (project) |p| {
            if (!matchesProject(n, p)) continue;
        }
        try filtered.append(n);
    }

    var fuzzy_buf: [256]search.Result = undefined;
    const fuzzy_results = search.fuzzySearch(q, filtered.items, &fuzzy_buf);

    var body_buf: [256]search.Result = undefined;
    const body_results = search.bodySearch(allocator, q, filtered.items, &body_buf);

    var merged_buf: [512]search.Result = undefined;
    const results = search.mergeResults(fuzzy_results, body_results, &merged_buf, limit);

    if (json_out) {
        // collect result notes for envelope
        var result_notes = try allocator.alloc(note_mod.Note, results.len);
        defer allocator.free(result_notes);
        for (results, 0..) |r, ri| {
            result_notes[ri] = filtered.items[r.note_index];
        }
        const stdout = std.io.getStdOut().writer();
        try envelope.printSearchEnvelope(stdout, q, result_notes);
        return;
    }

    if (results.len == 0) {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("no results\n");
        var hint_buf: [256]u8 = undefined;
        const h = std.fmt.bufPrint(&hint_buf, "try broader terms, or create: nts \"{s}\"", .{q}) catch return;
        try format.hint(stdout, h);
        try stdout.writeByte('\n');
        return;
    }

    const stdout = std.io.getStdOut().writer();
    for (results) |r| {
        const n = filtered.items[r.note_index];
        const score: i32 = @intFromFloat(@min(@max(r.score, -2147483648.0), 2147483647.0));
        try format.formatSearchRow(stdout, n, score);
    }
}

fn cmdEdit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var query: ?[]const u8 = null;

    for (args) |a| {
        if (!std.mem.startsWith(u8, a, "-")) {
            query = a;
            break;
        }
    }

    var cfg = try config.load(allocator);
    defer cfg.deinit();

    const cache_path = try config.metaCachePath(allocator);
    defer allocator.free(cache_path);

    var path: []const u8 = undefined;
    var path_owned = false;

    if (query) |q| {
        path = try resolve.strict(allocator, cfg.notes_dir, q, cache_path);
        path_owned = true;
    } else {
        if (!format.isTTY()) {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("error: query required in non-interactive mode: nts edit <slug>\n");
            return error.MissingArgument;
        }
        const notes = try loadSortedNotes(allocator, cfg.notes_dir, cache_path);
        if (notes.len == 0) {
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll("no notes yet — create one with: nts \"My first note\"\n");
            return;
        }
        const result = try picker.runPicker(allocator, notes);
        if (result.canceled) return;
        path = result.path orelse return;
    }
    defer if (path_owned) allocator.free(path);

    if (!format.isTTY()) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("error: cannot open editor in non-interactive mode\n");
        return error.NotATTY;
    }

    const mtime_before = blk: {
        const stat = std.fs.cwd().statFile(path) catch break :blk @as(i128, 0);
        break :blk stat.mtime;
    };

    try editor.open(cfg.resolveEditor(), path, allocator);

    const mtime_after = blk: {
        const stat = std.fs.cwd().statFile(path) catch break :blk @as(i128, 0);
        break :blk stat.mtime;
    };

    const stdout = std.io.getStdOut().writer();
    if (mtime_before == mtime_after) {
        try stdout.writeAll("no changes\n");
    } else {
        try stdout.print("edited: {s}\n", .{path});
    }
}

fn cmdAppend(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var body_file: ?[]const u8 = null;
    var positionals = std.ArrayList([]const u8).init(allocator);
    defer positionals.deinit();

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "-F") or eql(a, "--body-file")) {
            body_file = nextArg(args, &i);
        } else {
            try positionals.append(a);
        }
    }

    if (positionals.items.len == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("error: query required: nts append <slug> <text>\n");
        return error.MissingArgument;
    }

    var cfg = try config.load(allocator);
    defer cfg.deinit();

    const cache_path = try config.metaCachePath(allocator);
    defer allocator.free(cache_path);

    const query_str = positionals.items[0];
    const path = try resolve.strict(allocator, cfg.notes_dir, query_str, cache_path);
    defer allocator.free(path);

    // resolve text to append
    var text: ?[]const u8 = null;
    var text_owned = false;

    if (positionals.items.len > 1) {
        // join remaining positionals
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        for (positionals.items[1..], 0..) |p, pi| {
            if (pi > 0) try buf.append(' ');
            try buf.appendSlice(p);
        }
        text = try buf.toOwnedSlice();
        text_owned = true;
    } else {
        text = try resolveBody(allocator, null, body_file);
        text_owned = text != null;
    }
    defer if (text_owned) if (text) |t| allocator.free(t);

    const append_text = text orelse {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("error: no text provided\n");
        return error.NoBody;
    };

    if (append_text.len == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("error: no text provided\n");
        return error.NoBody;
    }

    const existing = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(existing);

    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    try content.appendSlice(existing);
    if (existing.len > 0 and existing[existing.len - 1] != '\n') {
        try content.append('\n');
    }
    try content.append('\n');
    try content.appendSlice(append_text);
    if (append_text.len > 0 and append_text[append_text.len - 1] != '\n') {
        try content.append('\n');
    }

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = content.items });

    const stdout = std.io.getStdOut().writer();
    try stdout.print("appended: {s}\n", .{path});
}

fn cmdConfig(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var get_key: ?[]const u8 = null;
    var set_pair: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "--get")) {
            get_key = nextArg(args, &i);
        } else if (eql(a, "--set")) {
            set_pair = nextArg(args, &i);
        }
    }

    var cfg = try config.load(allocator);
    defer cfg.deinit();

    const stdout = std.io.getStdOut().writer();

    if (get_key) |key| {
        if (eql(key, "notes_dir")) {
            try stdout.print("{s}\n", .{cfg.notes_dir});
        } else if (eql(key, "editor")) {
            try stdout.print("{s}\n", .{cfg.resolveEditor()});
        } else {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("error: unknown config key: {s}\n", .{key});
            return error.UnknownConfigKey;
        }
        return;
    }

    if (set_pair) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const key = pair[0..eq_pos];
            const val = pair[eq_pos + 1 ..];

            if (eql(key, "notes_dir")) {
                const new_dir = try allocator.dupe(u8, val);
                allocator.free(cfg.notes_dir);
                cfg.notes_dir = new_dir;
            } else if (eql(key, "editor")) {
                if (cfg.editor) |e| allocator.free(e);
                cfg.editor = try allocator.dupe(u8, val);
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("error: unknown config key: {s}\n", .{key});
                return error.UnknownConfigKey;
            }

            try config.save(allocator, cfg);
            try stdout.print("{s}={s}\n", .{ key, val });
        } else {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("error: invalid format, use key=value\n");
            return error.InvalidFormat;
        }
        return;
    }

    // no flags: print config as JSON
    try stdout.print("{{\"notes_dir\": \"{s}\"", .{cfg.notes_dir});
    if (cfg.editor) |e| {
        try stdout.print(", \"editor\": \"{s}\"", .{e});
    }
    try stdout.writeAll("}\n");
}

fn cmdCompletion(args: []const []const u8) !void {
    if (args.len == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("error: shell required: nts completion <bash|zsh|fish>\n");
        return error.MissingArgument;
    }

    const shell = args[0];
    const stdout = std.io.getStdOut().writer();

    if (eql(shell, "bash")) {
        try stdout.writeAll(bash_completion);
    } else if (eql(shell, "zsh")) {
        try stdout.writeAll(zsh_completion);
    } else if (eql(shell, "fish")) {
        try stdout.writeAll(fish_completion);
    } else {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("error: unsupported shell: {s}\n", .{shell});
        return error.UnsupportedShell;
    }
}

fn cmdRootJson() !void {
    const stdout = std.io.getStdOut().writer();
    try envelope.printCommandTree(stdout, version);
}

fn showHelp() void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(help_text) catch {};
}

fn showVersion() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("nts {s}\n", .{version}) catch {};
}

// --- helpers ---

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn nextArg(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* + 1 < args.len) {
        i.* += 1;
        return args[i.*];
    }
    return null;
}

fn resolveBody(allocator: std.mem.Allocator, body_flag: ?[]const u8, body_file_flag: ?[]const u8) !?[]const u8 {
    if (body_flag) |b| return b;
    if (body_file_flag) |file| {
        if (eql(file, "-")) {
            return try std.io.getStdIn().reader().readAllAlloc(allocator, 1024 * 1024);
        }
        return try std.fs.cwd().readFileAlloc(allocator, file, 1024 * 1024);
    }
    if (!std.posix.isatty(std.posix.STDIN_FILENO)) {
        return try std.io.getStdIn().reader().readAllAlloc(allocator, 1024 * 1024);
    }
    return null;
}

fn parseLabels(allocator: std.mem.Allocator, raw: ?[]const u8) ![]const []const u8 {
    const s = raw orelse return &.{};
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (list.items) |l| allocator.free(l);
        list.deinit();
    }
    var iter = std.mem.splitScalar(u8, s, ',');
    while (iter.next()) |tok| {
        const trimmed = std.mem.trim(u8, tok, &std.ascii.whitespace);
        if (trimmed.len > 0) {
            try list.append(try allocator.dupe(u8, trimmed));
        }
    }
    return list.toOwnedSlice();
}

fn matchesLabels(n: note_mod.Note, filter_labels: []const []const u8) bool {
    for (n.labels) |nl| {
        for (filter_labels) |fl| {
            if (asciiEqlIgnoreCase(nl, fl)) return true;
        }
    }
    return false;
}

fn matchesProject(n: note_mod.Note, project: []const u8) bool {
    const p = n.context.project orelse return false;
    return asciiEqlIgnoreCase(p, project);
}

fn matchesSearch(n: note_mod.Note, query: []const u8) bool {
    if (containsIgnoreCase(n.title, query)) return true;
    if (containsIgnoreCase(n.body, query)) return true;
    return false;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var pos: usize = 0;
    while (pos + needle.len <= haystack.len) : (pos += 1) {
        if (asciiEqlIgnoreCase(haystack[pos..][0..needle.len], needle)) return true;
    }
    return false;
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

fn slugFromPath(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    return if (std.mem.endsWith(u8, base, ".md")) base[0 .. base.len - 3] else base;
}

fn loadSortedNotes(allocator: std.mem.Allocator, notes_dir: []const u8, cache_path: []const u8) ![]note_mod.Note {
    const notes = try note_mod.parseAllCached(allocator, notes_dir, cache_path);
    std.mem.sort(note_mod.Note, notes, {}, struct {
        fn lessThan(_: void, a: note_mod.Note, b: note_mod.Note) bool {
            return a.date > b.date;
        }
    }.lessThan);
    return notes;
}

fn renderPretty(writer: anytype, n: note_mod.Note) !void {
    try format.writeBold(writer, n.title);
    try writer.writeByte('\n');

    var date_buf: [10]u8 = undefined;
    const date = format.formatDate(n.date, &date_buf);
    try format.writeItalic(writer, date);

    if (n.labels.len > 0) {
        try writer.writeAll("  ");
        for (n.labels, 0..) |label, li| {
            if (li > 0) try writer.writeByte(' ');
            try format.writeColor(writer, 6, label);
        }
    }

    if (n.context.project) |proj| {
        try writer.writeAll("  ");
        try format.writeColor(writer, 5, proj);
        if (n.context.branch) |br| {
            try writer.writeByte('@');
            try format.writeColor(writer, 5, br);
        }
    }

    try writer.writeAll("\n\n");
    try format.writeFaint(writer, "────────────────────────────────────────");
    try writer.writeAll("\n\n");
    if (n.body.len > 0) {
        try writer.writeAll(n.body);
        try writer.writeByte('\n');
    }
}

// --- completion scripts ---

const bash_completion =
    \\# nts bash completion
    \\_nts() {
    \\    local cur prev commands
    \\    COMPREPLY=()
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    commands="new list ls show search edit append config completion"
    \\
    \\    if [[ ${COMP_CWORD} -eq 1 ]]; then
    \\        COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
    \\        return 0
    \\    fi
    \\}
    \\complete -F _nts nts
    \\
;

const zsh_completion =
    \\#compdef nts
    \\_nts() {
    \\    local -a commands
    \\    commands=(
    \\        'new:Create a new note'
    \\        'list:List notes'
    \\        'ls:List notes'
    \\        'show:Show a note'
    \\        'search:Search notes'
    \\        'edit:Edit a note'
    \\        'append:Append to a note'
    \\        'config:Show/modify config'
    \\        'completion:Shell completions'
    \\    )
    \\    _arguments '1: :->cmd' '*:: :->args'
    \\    case $state in
    \\        cmd) _describe 'command' commands ;;
    \\    esac
    \\}
    \\_nts
    \\
;

const fish_completion =
    \\# nts fish completion
    \\complete -c nts -f
    \\complete -c nts -n "__fish_use_subcommand" -a "new" -d "Create a new note"
    \\complete -c nts -n "__fish_use_subcommand" -a "list" -d "List notes"
    \\complete -c nts -n "__fish_use_subcommand" -a "ls" -d "List notes"
    \\complete -c nts -n "__fish_use_subcommand" -a "show" -d "Show a note"
    \\complete -c nts -n "__fish_use_subcommand" -a "search" -d "Search notes"
    \\complete -c nts -n "__fish_use_subcommand" -a "edit" -d "Edit a note"
    \\complete -c nts -n "__fish_use_subcommand" -a "append" -d "Append to a note"
    \\complete -c nts -n "__fish_use_subcommand" -a "config" -d "Show/modify config"
    \\complete -c nts -n "__fish_use_subcommand" -a "completion" -d "Shell completions"
    \\
;

const help_text =
    \\nts — note to self
    \\
    \\Usage:
    \\  nts [title]              create a note (shorthand for nts new)
    \\  nts new [title]          create a note
    \\  nts list                 list notes
    \\  nts show [slug]          show a note
    \\  nts search <query>       search notes
    \\  nts edit [slug]          edit a note
    \\  nts append <slug> <text> append to a note
    \\  nts config               show/modify config
    \\  nts completion <shell>   shell completions (bash, zsh, fish)
    \\  nts version              show version
    \\
    \\Flags:
    \\  -h, --help               show help
    \\  -v, --version            show version
    \\  --json                   JSON output with HATEOAS envelopes
    \\
    \\New:
    \\  nts new [title] [flags]
    \\  -t, --title <title>      note title
    \\  -l, --labels <a,b>       comma-separated labels
    \\  -b, --body <text>        note body (inline)
    \\  -F, --body-file <path>   read body from file (use - for stdin)
    \\  -e, --editor             force open $EDITOR even with -b
    \\  --json                   output as JSON
    \\
    \\List:
    \\  nts list [flags]         (alias: nts ls)
    \\  -l, --labels <a,b>       filter by labels
    \\  -n, --limit <n>          max notes to show (default: 20)
    \\  -S, --search <query>     filter by text match
    \\  -p, --project <name>     filter by git project context
    \\  --json                   output as JSON
    \\
    \\Show:
    \\  nts show [slug] [flags]  (interactive picker if no slug)
    \\  --raw                    print raw markdown (no formatting)
    \\  --json                   output as JSON
    \\
    \\Search:
    \\  nts search <query> [flags]
    \\  -l, --labels <a,b>       filter by labels
    \\  -n, --limit <n>          max results (default: 10)
    \\  -p, --project <name>     filter by git project context
    \\  --json                   output as JSON
    \\
    \\Edit:
    \\  nts edit [slug]          (interactive picker if no slug)
    \\
    \\Append:
    \\  nts append <slug> <text>
    \\  -F, --body-file <path>   read text from file (use - for stdin)
    \\
    \\Config:
    \\  nts config               show current config as JSON
    \\  --get <key>              get a config value (notes_dir, editor)
    \\  --set <key=value>        set a config value
    \\
    \\Examples:
    \\  nts "quick thought"                    create with title, open editor
    \\  nts new -t "Bug" -l work -b "details"  create inline, no editor
    \\  echo "piped" | nts new -t "From stdin"  pipe body from stdin
    \\  nts list -l work -n 5                  last 5 work notes
    \\  nts show redis                         fuzzy-match slug
    \\  nts search "oauth" -p auth-service     search within a project
    \\  nts append standup "shipped the fix"   append text to a note
    \\  nts config --set editor=nvim           change editor
    \\
;
