const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // var args = try std.process.argsWithAllocator(gpa.allocator());
    // defer args.deinit();
    // _ = args.next(); // Skip argv[0]
    //
    // const expression = args.next() orelse {
    //     return error.UsageError;
    // };

    const expression = "thing+(ab-cd)*ef";

    print("Expression: '{s}'\n", .{expression});
    var iter = TokenIterator.new(expression);
    while (iter.next()) |token| {
        print("iter.next() -> '{s}'\n", .{token.data});
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
    start: usize,
    end: usize,
    data: []const u8,
};

const TokenIterator = struct {
    data: []const u8,
    index: usize,

    const Self = @This();

    pub fn new(data: []const u8) Self {
        return TokenIterator{
            .data = data,
            .index = 0,
        };
    }

    pub fn next(self: *Self) ?Token {
        if (self.index >= self.data.len) return null;
        // Find start of next token
        const token_type = blk: {
            var t = TokenType.fromChar(self.data[self.index]);
            while (t == null) {
                self.index += 1;
                if (self.index >= self.data.len) return null;
                t = TokenType.fromChar(self.data[self.index]);
            }
            break :blk t;
        } orelse unreachable; // TODO: I think this is a little hacky

        // Find end of current token
        const token_start = self.index;
        var offset: u32 = 1;
        while (true) : (offset += 1) {
            const token_end = token_start + offset;
            if (token_end >= self.data.len) {
                self.index = token_end;
                return Token{
                    .t = token_type,
                    .start = token_start,
                    .end = token_end,
                    .data = self.data[token_start..token_end],
                };
            }
            // Operators are single-character
            if (token_type == .operator or token_type == .left_paren or token_type == .right_paren or TokenType.fromChar(self.data[token_end]) != token_type) {
                self.index = token_end;
                return Token{
                    .t = token_type,
                    .start = token_start,
                    .end = token_end,
                    .data = self.data[token_start..token_end],
                };
            }
        }
    }
};

test "Token.next" {
    const t = std.testing;
    const expression = "thing+(ab-cd)*ef";
    var iter = TokenIterator.new(expression);
    try t.expectEqual(iter.data.ptr, expression.ptr);
    try t.expectEqual(iter.index, 0);
    try t.expectEqualDeep(Token{
        .t = .identifier,
        .start = 0,
        .end = 5,
        .data = "thing",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .operator,
        .start = 5,
        .end = 6,
        .data = "+",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .left_paren,
        .start = 6,
        .end = 7,
        .data = "(",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .identifier,
        .start = 7,
        .end = 9,
        .data = "ab",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .operator,
        .start = 9,
        .end = 10,
        .data = "-",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .identifier,
        .start = 10,
        .end = 12,
        .data = "cd",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .right_paren,
        .start = 12,
        .end = 13,
        .data = ")",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .operator,
        .start = 13,
        .end = 14,
        .data = "*",
    }, iter.next());
    try t.expectEqualDeep(Token{
        .t = .identifier,
        .start = 14,
        .end = 16,
        .data = "ef",
    }, iter.next());
    try t.expectEqualDeep(null, iter.next());
}
