const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    // var args = try std.process.argsWithAllocator(gpa.allocator());
    // defer args.deinit();
    // _ = args.next(); // Skip argv[0]
    //
    // const expression = args.next() orelse {
    //     return error.UsageError;
    // };

    // const expression = "   thing+ (123+ab   -cd) *   2ef    ";
    const expression = "3 + four * two / ( 1 − five ) ^ 2 ^ three";

    print("Expression: '{s}'\n", .{expression});
    const expr_reader = std.Io.Reader.fixed(expression);
    var tokens = TokenIterator.init(gpa.allocator(), expr_reader);
    defer tokens.deinit();

    var iter = ShuntingYardIterator.init(gpa.allocator(), tokens);
    defer iter.deinit();

    var lexemes: std.ArrayList(Lexeme) = .empty;
    defer lexemes.deinit(gpa.allocator());

    print("\niter.next()\n", .{});
    while (iter.next()) |lexeme| {
        try lexemes.append(gpa.allocator(), lexeme);
        print("-> '{f}' ({t})\n", .{ lexeme, lexeme });
        print("\niter.next()\n", .{});
    }
    print("\n[", .{});
    for (lexemes.items) |lexeme| {
        print(" {{{t} '{f}'}}", .{ lexeme, lexeme });
    }
    print(" ]\n", .{});

    for (0.., iter.operator_stack.items) |i, op| {
        print("ops[{d}] -> '{f}' ({t})\n", .{ i, op, op });
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
        } else if (Operator.fromChar(c)) |_| {
            return .operator;
        }
        return null;
    }
};

const Operator = enum {
    add, // Add
    sub, // Subtract
    mul, // Multiply
    div, // Divide
    exp, // Exponent

    // Operator associativity
    const Assoc = enum { left, right };

    pub fn fromChar(c: u8) ?Operator {
        switch (c) {
            '+' => return .add,
            '-' => return .sub,
            '*' => return .mul,
            '/' => return .div,
            '^' => return .exp,
            else => return null,
        }
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

const Lexeme = union(TokenType) {
    identifier: []const u8,
    operator: Operator,
    left_paren,
    right_paren,
    number: u32,

    pub fn format(self: Lexeme, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .identifier => |s| try w.print("{s}", .{s}),
            .operator => |o| switch (o) {
                .add => try w.printAsciiChar('+', .{}),
                .sub => try w.printAsciiChar('-', .{}),
                .mul => try w.printAsciiChar('*', .{}),
                .div => try w.printAsciiChar('/', .{}),
                .exp => try w.printAsciiChar('^', .{}),
            },
            .left_paren => try w.print("(", .{}),
            .right_paren => try w.print(")", .{}),
            .number => |n| try w.printInt(n, 10, .lower, .{}),
        }
    }
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

test "TokenIterator.next" {
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

const ShuntingYardIterator = struct {
    tokens: TokenIterator,
    operator_stack: std.ArrayList(Lexeme),
    arena: std.heap.ArenaAllocator,
    _cached_next_token: ?Token = null,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, tokens: TokenIterator) Self {
        return Self{
            .tokens = tokens,
            .operator_stack = .empty,
            .arena = std.heap.ArenaAllocator.init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        // NOTE: Do I need to deinit the operator stack before deiniting the arena it is made with?
        self.operator_stack.deinit(self.arena.allocator());
        self.arena.deinit();
    }

    fn nextToken(self: *Self, clear_cache: bool) ?Token {
        if (clear_cache) self._cached_next_token = null;

        if (self._cached_next_token) |t| {
            print("  Got cached token\n", .{});
            return t;
        } else if (self.tokens.next()) |t| {
            print("  Got next token\n", .{});
            return t;
        }
        print("  No next token\n", .{});
        return null;
    }

    pub fn next(self: *Self) ?Lexeme {
        var token = self.nextToken(false) orelse {
            print("  Draining operator stack\n", .{});
            if (self.operator_stack.pop()) |t| {
                print("  {{{t} '{f}'}}\n", .{ t, t });
                return t;
            } else {
                print("  No operators left\n", .{});
                return null;
            }
        };
        print("  Next token: {{{t} \"{s}\"}}\n", .{ token.t, token.data });

        token_type: switch (token.t) {
            .number => {
                print("  Add number to output\n", .{});
                self._cached_next_token = null;
                return .{
                    .number = std.fmt.parseInt(u32, token.data, 10) catch @panic("Invalid digit in number token"),
                };
            },
            .identifier => {
                print("  Add identifier to output\n", .{});
                self._cached_next_token = null;
                return .{
                    .identifier = token.data, // FIXME:? This will become invalid when self.tokens is deinit'd
                };
            },
            .operator => {
                const op1 = Operator.fromChar(token.data[0]) orelse @panic("Invalid operator char in operator token");
                if (self.operator_stack.getLastOrNull()) |lexeme| blk: {
                    switch (lexeme) {
                        .left_paren => break :blk,
                        .operator => |op2| {
                            if (op2.prec() > op1.prec() or (op2.prec() == op1.prec() and op1.assoc() == .left)) {
                                self._cached_next_token = token;
                                _ = self.operator_stack.pop();
                                return .{ .operator = op2 };
                            }
                        },
                        else => @panic("There should only be operators and left_paren's on the operator stack"),
                    }
                }
                print("  Push operator to stack\n", .{});
                self.operator_stack.append(self.arena.allocator(), .{ .operator = op1 }) catch @panic("OOM");
                token = self.nextToken(true) orelse {
                    print("  Draining operator stack\n", .{});
                    return self.operator_stack.pop();
                };
                print("  Next token: {{{t} \"{s}\"}} (continue)\n", .{ token.t, token.data });
                continue :token_type token.t;
            },
            .left_paren => {
                self.operator_stack.append(self.arena.allocator(), .left_paren) catch @panic("OOM");
                token = self.nextToken(true) orelse {
                    print("  Draining operator stack\n", .{});
                    return self.operator_stack.pop();
                };
                print("  Next token: {{{t} \"{s}\"}} (continue)\n", .{ token.t, token.data });
                continue :token_type token.t;
            },
            .right_paren => {
                // const op = self.operator_stack.getLastOrNull() orelse @panic("Expected stack to not be empty");
                const op = self.operator_stack.pop() orelse @panic("Expected stack to not be empty");
                if (op == .left_paren) { // FIXME: Some weird logic here
                    // TODO:

                    // _ = self.operator_stack.pop();
                    token = self.nextToken(true) orelse {
                        print("  Draining operator stack\n", .{});
                        return self.operator_stack.pop();
                    };
                    print("  Next token: {{{t} \"{s}\"}} (continue)\n", .{ token.t, token.data });
                    continue :token_type token.t;
                }
                return op;
            },
        }
    }
};
