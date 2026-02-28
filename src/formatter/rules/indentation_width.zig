const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

/// Normalizes leading indentation to two spaces for common Ruby block keywords.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var indent_level: usize = 0;
    var line_index: usize = 0;

    while (lines.next()) |line| : (line_index += 1) {
        const trimmed = std.mem.trim(u8, line, " \t");
        const is_blank = trimmed.len == 0;

        if (line_index != 0) try builder.append(allocator, '\n');

        if (is_blank) continue;

        const is_mid = isMiddleKeyword(trimmed);
        const is_closing = isClosingKeyword(trimmed);
        const current_indent = if ((is_mid or is_closing) and indent_level > 0) indent_level - 1 else indent_level;

        try appendIndent(allocator, &builder, current_indent);
        try builder.appendSlice(allocator, trimmed);

        if (opensBlock(trimmed)) {
            indent_level = current_indent + 1;
        } else if (is_mid) {
            indent_level = current_indent + 1;
        } else {
            indent_level = current_indent;
        }
    }

    if (builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    return Result{ .changed = true, .buffer = try builder.toOwnedSlice(allocator) };
}

fn appendIndent(allocator: std.mem.Allocator, builder: *std.ArrayListUnmanaged(u8), level: usize) !void {
    var count = level * 2;
    while (count > 0) : (count -= 1) {
        try builder.append(allocator, ' ');
    }
}

fn opensBlock(trimmed: []const u8) bool {
    if (startsWithWord(trimmed, "def")) return true;
    if (startsWithWord(trimmed, "class")) return true;
    if (startsWithWord(trimmed, "module")) return true;
    if (startsWithWord(trimmed, "begin")) return true;
    if (startsWithWord(trimmed, "case")) return true;
    if (startsWithWord(trimmed, "for")) return true;
    if (startsWithWord(trimmed, "if")) return true;
    if (startsWithWord(trimmed, "unless")) return true;
    if (startsWithWord(trimmed, "while")) return true;
    if (startsWithWord(trimmed, "until")) return true;
    if (std.mem.endsWith(u8, trimmed, " do") or std.mem.indexOf(u8, trimmed, " do |") != null) return true;
    return false;
}

fn isClosingKeyword(trimmed: []const u8) bool {
    return startsWithWord(trimmed, "end");
}

fn isMiddleKeyword(trimmed: []const u8) bool {
    return startsWithWord(trimmed, "else") or
        startsWithWord(trimmed, "elsif") or
        startsWithWord(trimmed, "when") or
        startsWithWord(trimmed, "rescue") or
        startsWithWord(trimmed, "ensure");
}

fn startsWithWord(line: []const u8, keyword: []const u8) bool {
    if (!std.mem.startsWith(u8, line, keyword)) return false;
    if (line.len == keyword.len) return true;
    const next = line[keyword.len];
    return std.ascii.isWhitespace(next);
}

test "indentation width normalizes nested blocks to two spaces" {
    const allocator = std.testing.allocator;
    const input =
        \\def run
        \\ if ready?
        \\   work
        \\ end
        \\end
        \\
    ;
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings(
        \\def run
        \\  if ready?
        \\    work
        \\  end
        \\end
        \\
    , result.buffer);
}

test "indentation width aligns else with its if block" {
    const allocator = std.testing.allocator;
    const input =
        \\if ready?
        \\    work
        \\   else
        \\  fallback
        \\ end
        \\
    ;
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings(
        \\if ready?
        \\  work
        \\else
        \\  fallback
        \\end
        \\
    , result.buffer);
}

test "indentation width leaves well formatted input unchanged" {
    const allocator = std.testing.allocator;
    const input =
        \\def run
        \\  work
        \\end
        \\
    ;
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
