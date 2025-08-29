const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    // var args = try std.process.argsWithAllocator(gpa.allocator());
    // defer args.deinit();
    // _ = args.next(); // Skip argv[0]
    //
    // const expression = args.next() orelse {
    //     return error.UsageError;
    // };

    const expression = "   thing+ (ab   -cd) *   ef    ";

    print("Expression: '{s}'\n", .{expression});
    const expr_reader = std.Io.Reader.fixed(expression);
    var iter = TokenIterator.init(gpa.allocator(), expr_reader);
    defer iter.deinit();

    while (iter.next()) |token| {
        print("iter.next() -> '{s}' ({t})\n", .{ token.data, token.t });
    }
}

const TokenType = enum {
    identifier,
    operator,
    left_paren,
    right_paren,
    number,

    pub fn fromChar(c: u8) ?TokenType {
        if (!std.ascii.isAscii(c) or !std.ascii.isPrint(c) or std.ascii.isWhitespace(c)) {
            // Non-ASCII, non-printable, or whitespace characters are not valid
            return null;
        } else if (std.ascii.isAlphabetic(c)) {
            return .identifier;
        } else if (std.ascii.isDigit(c)) {
            return .number;
        } else if (c == '(') {
            return .left_paren;
        } else if (c == ')') {
            return .right_paren;
        }
        return .operator;
    }
};

const Operator = enum {
    add, // Add
    sub, // Subtract
    mul, // Multiply
    div, // Divide
    exp, // Exponent

    const Assoc = enum { left, right };

    /// Get precedence of operator
    pub fn prec(self: Operator) u8 {
        return switch (self) {
            .add, .sub => 2,
            .mul, .div => 3,
            .exp => 4,
        };
    }
    // Get associativity of operator
    pub fn assoc(self: Operator) Assoc {
        return switch (self) {
            .exp => .right,
            _ => .left,
        };
    }
};

const Lexeme = union(TokenType) {
    identifier: []const u8,
    operator: Operator,
    left_paren,
    right_paren,
    number: u32,
};

const Token = struct {
    t: TokenType,
    data: []const u8,
};

const TokenIterator = struct {
    reader: std.Io.Reader,
    arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, r: std.Io.Reader) Self {
        return TokenIterator{
            .reader = r,
            .arena = std.heap.ArenaAllocator.init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn next(self: *Self) ?Token {
        // Find start of next token
        const token_type = blk: {
            var t = TokenType.fromChar(self.reader.peekByte() catch return null);
            while (t == null) {
                self.reader.toss(1);
                t = TokenType.fromChar(self.reader.peekByte() catch return null);
            }
            break :blk t orelse return null; // TODO: I think this is a little hacky (orelse return null)
        };

        // Find end of current token
        var token_len: u32 = 1;
        while (true) : (token_len += 1) {
            const token_plus = self.reader.peek(token_len + 1) catch {
                const token_data = self.arena.allocator().dupe(
                    u8,
                    self.reader.take(token_len) catch @panic("Should be safe after the previous iteration's Reader.peek()"),
                ) catch @panic("OOM");
                return Token{
                    .t = token_type,
                    .data = token_data,
                };
            };

            if (token_type == .operator or token_type == .left_paren or token_type == .right_paren or TokenType.fromChar(token_plus[token_plus.len - 1]) != token_type) {
                const token_data = self.arena.allocator().dupe(
                    u8,
                    self.reader.take(token_len) catch @panic("Should be safe after the previous iteration's Reader.peek()"),
                ) catch @panic("OOM");
                return Token{
                    .t = token_type,
                    .data = token_data,
                };
            }
        }
    }
};

test "Token.next" {
    const tst = std.testing;
    const gpa = tst.allocator;

    const expr_reader = std.Io.Reader.fixed(" thing  +(ab -   cd)*ef  ");
    var iter = TokenIterator.init(gpa, expr_reader);
    defer iter.deinit();
    try tst.expectEqualDeep(Token{
        .t = .identifier,
        .data = "thing",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .operator,
        .data = "+",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .left_paren,
        .data = "(",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .identifier,
        .data = "ab",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .operator,
        .data = "-",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .identifier,
        .data = "cd",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .right_paren,
        .data = ")",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .operator,
        .data = "*",
    }, iter.next());
    try tst.expectEqualDeep(Token{
        .t = .identifier,
        .data = "ef",
    }, iter.next());
    try tst.expectEqualDeep(null, iter.next());
}
