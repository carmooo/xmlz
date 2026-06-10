//! XML tokenizer. Takes partial input buffer as the input; provides a
//! streaming, non-allocating API to pull tokens one at a time.
//! This tokenizer can emit partial tokens;
//! The input to this class is a sequence of input buffers that you must supply one at a time.
//! This was inspired by https://github.com/andrewrk/xml
const Xml = @This();

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

buffer: []const u8 = "",
index: usize = 0,
state: State = .start,

pub const NextError = error{BufferUnderrun} || error{SyntaxError};

const State = enum {
    start,
    doctype_q,
    doctype_name_start,
    doctype_name,
    doctype,
    doctype_attr_key,
    doctype_attr_value_q,
    doctype_attr_value,
    doctype_end,
};

pub const Token = union(enum) {
    doctype: []const u8,
    doctype_partial: []const u8,
    attr_key: []const u8,
    attr_key_partial: []const u8,
    attr_value: []const u8,
    attr_value_partial: []const u8,
    content: []const u8,
    end_of_document,
};

pub fn next(xml: *Xml) NextError!Token {
    var tok_start: usize = undefined;
    while (xml.index < xml.buffer.len) : (xml.index += 1) {
        const byte = xml.buffer[xml.index];
        switch (xml.state) {
            .start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => xml.state = .doctype_q,
                else => return error.SyntaxError,
            },
            .doctype_q => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '?' => xml.state = .doctype_name_start,
                else => return error.SyntaxError,
            },
            .doctype_name_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<', '>' => return error.SyntaxError,
                else => {
                    tok_start = xml.index;
                    xml.state = .doctype_name;
                },
            },
            .doctype_name => switch (byte) {
                ' ', '\t', '\r', '\n' => {
                    return xml.emit(
                        State.doctype,
                        Token{ .doctype = xml.buffer[tok_start..xml.index] },
                    );
                },
                '?' => {
                    return xml.emit(
                        State.doctype_end,
                        Token{ .doctype = xml.buffer[tok_start..xml.index] },
                    );
                },
                '<', '>' => return error.SyntaxError,
                else => {},
            },
            .doctype => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '?' => xml.state = .doctype_end,
                '<', '>' => return error.SyntaxError,
                else => {
                    tok_start = xml.index;
                    xml.state = .doctype_attr_key;
                },
            },
            .doctype_attr_key => switch (byte) {
                '=' => {
                    return xml.emit(
                        State.doctype_attr_value_q,
                        Token{ .attr_key = xml.buffer[tok_start..xml.index] },
                    );
                },
                '?', '<', '>' => return error.SyntaxError,
                else => {},
            },
            .doctype_attr_value_q => switch (byte) {
                '"' => {
                    tok_start = xml.index;
                    xml.state = .doctype_attr_value;
                },
                else => return error.SyntaxError,
            },
            .doctype_attr_value => switch (byte) {
                '"' => {
                    return xml.emit(State.doctype, Token{
                        .attr_value = xml.buffer[tok_start .. xml.index + 1],
                    });
                },
                '\n' => return error.SyntaxError,
                else => {},
            },
            .doctype_end => switch (byte) {
                // TODO body
                '>' => {},
                else => return error.SyntaxError,
            },
        }
    } else {
        switch (xml.state) {
            .doctype_name => return xml.emit(
                State.doctype_name,
                Token{ .doctype_partial = xml.buffer[tok_start..xml.buffer.len] },
            ),
            .doctype_attr_key => return xml.emit(
                State.doctype_attr_key,
                Token{ .attr_key_partial = xml.buffer[tok_start..xml.buffer.len] },
            ),
            .doctype_attr_value => return xml.emit(
                State.doctype_attr_value,
                Token{ .attr_value_partial = xml.buffer[tok_start..xml.buffer.len] },
            ),
            else => return error.BufferUnderrun,
        }
    }
}

fn emit(xml: *Xml, next_state: State, token: Token) Token {
    xml.state = next_state;
    xml.index += 1;
    return token;
}

pub fn feedInput(xml: *Xml, _: []const u8) void {
    assert(xml.index == xml.buffer.len);
    @compileError("TODO implement me");
}

test "doctype xml" {
    const bytes =
        \\<?xml version="1.0" encoding="UTF-8"?>
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(try xml.next(), Token{ .doctype = "xml" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_key = "version" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_value = "\"1.0\"" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_key = "encoding" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_value = "\"UTF-8\"" });
}

test "doctype partial" {
    const bytes =
        \\<?xm
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(try xml.next(), Token{ .doctype_partial = "xm" });
}

test "attr_key partial" {
    const bytes =
        \\<?xml versi
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(try xml.next(), Token{ .doctype = "xml" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_key_partial = "versi" });
}

test "attr_value partial" {
    const bytes =
        \\<?xml version="1.0" encoding="U
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(try xml.next(), Token{ .doctype = "xml" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_key = "version" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_value = "\"1.0\"" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_key = "encoding" });
    try testing.expectEqualDeep(try xml.next(), Token{ .attr_value_partial = "\"U" });
}

pub fn main() !void {}
