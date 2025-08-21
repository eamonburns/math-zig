const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const expression = "3+4*2/(1−5)^2^3";

    print("Expression: '{s}'\n", .{expression});
    var iter = ShuntingYardIterator.new(
        gpa.allocator(),
        TokenIterator.new(expression),
    );
    while (iter.next()) |lexeme| {
        print("\nget next\n", .{});
        print("got: {}\n", .{lexeme});
    }
}

const Lexeme = union(TokenType) {
    identifier: []const u8,
    operator: Operator,
    left_paren,
    right_paren,
    number: u32,

    pub fn format(self: Lexeme, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .identifier => |s| return writer.print("identifier({s})", .{s}),
            .operator => |op| return writer.print("operator({c})", .{@as(u8, switch (op) {
                .add => '+',
                .sub => '-',
                .mul => '*',
                .div => '/',
                .exp => '^',
            })}),
            .left_paren => return writer.print("left_paren", .{}),
            .right_paren => return writer.print("right_paren", .{}),
            .number => |num| return writer.print("number({d})", .{num}),
        }
    }
};

const ShuntingYardIterator = struct {
    tokens: TokenIterator,
    allocator: std.mem.Allocator,
    operator_stack: std.ArrayListUnmanaged(Lexeme),
    output_queue: std.ArrayListUnmanaged(Lexeme),

    const Self = @This();

    fn new(allocator: std.mem.Allocator, tokens: TokenIterator) Self {
        return Self{
            .tokens = tokens,
            .allocator = allocator,
            .operator_stack = std.ArrayListUnmanaged(Lexeme){},
            .output_queue = std.ArrayListUnmanaged(Lexeme){},
        };
    }

    // fn next(self: *Self) ?Lexeme {
    //     print("Shunt.next()\n", .{});
    //
    //     //const token = self.tokens.
    // }

    fn next(self: *Self) ?Lexeme {
        print("Shunt.next()\n", .{});
        // TODO: Return error union
        while (true) {
            const token = self.tokens.next() orelse {
                // Drain operator stack
                print("no operators left. draining op stack\n", .{});

                const op = self.operator_stack.pop() orelse return null;
                if (op == .left_paren) unreachable;
                return op;
            };

            return switch (token.t) {
                .identifier => Lexeme{ .identifier = token.data },
                // TODO: I could change the base to 0 to automatically handle different bases
                .number => Lexeme{ .number = std.fmt.parseInt(u32, token.data, 10) catch unreachable },
                .operator => {
                    const op1 = Operator.fromChar(token.data[0]) catch unreachable;
                    if (self.operator_stack.items.len <= 0) return Lexeme{ .operator = op1 };

                    switch (self.operator_stack.items[self.operator_stack.items.len - 1]) {
                        .left_paren => return Lexeme{ .operator = op1 },
                        .operator => |op2| {
                            // (o2 has greater precedence than o1) or (o1 and o2 have the same precedence and o1 is left-associative)
                            // - normalize ->
                            // (o2.prec > o1.prec) or (o1.prec == o2.prec and o1.assoc == left)
                            // - invert ->
                            // (o2.prec <= o1.prec) and (o1.prec != o2.prec or o1.assoc == right)
                            // if ((op2.prec() <= op1.prec()) and (op1.prec() != op2.prec() or op1.assoc() != .right)) {
                            //     return Lexeme{ .operator = op1 };
                            // }
                            if ((op2.prec() > op1.prec()) or (op1.prec() == op2.prec() and op1.assoc() == .right)) {
                                return Lexeme{ .operator = op1 };
                            }
                            _ = self.operator_stack.pop();
                            return Lexeme{ .operator = op2 };
                        },
                        else => unreachable,
                    }
                },
                .left_paren => Lexeme.left_paren,
                .right_paren => Lexeme.right_paren,
            };
        }
    }
};

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

    pub fn fromChar(c: u8) !Operator {
        return switch (c) {
            '+' => .add,
            '-' => .sub,
            '*' => .mul,
            '/' => .div,
            '^' => .exp,
            else => error.InvalidOperatorChar,
        };
    }

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
            else => .left,
        };
    }
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
