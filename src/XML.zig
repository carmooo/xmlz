//! XML tokenizer. Takes partial input buffer as the input; provides a
//! streaming, non-allocating API to pull tokens one at a time.
//! This tokenizer can emit partial tokens;
//! The input to this class is a sequence of input buffers that you must supply one at a time.
//! This was inspired by https://github.com/andrewrk/xml and by the std lib json module.
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

    body,
    tag_name_start,
    tag_name,
    tag_close_start,
    tag_close_name,
    tag_close_b,
    tag,
    tag_and_empty,
    content,
    tag_attr_key,
    tag_attr_value_q,
    tag_attr_value,
};

pub const Token = union(enum) {
    doctype: []const u8,
    doctype_partial: []const u8,
    attr_key: []const u8,
    attr_key_partial: []const u8,
    attr_value: []const u8,
    attr_value_partial: []const u8,
    tag_open: []const u8,
    tag_open_partial: []const u8,
    tag_close: []const u8,
    tag_close_partial: []const u8,
    tag_close_empty: []const u8,
    content: []const u8,
};

pub fn next(xml: *Xml) NextError!Token {
    if (xml.index == xml.buffer.len) return NextError.BufferUnderrun;

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
                    return xml.emit(
                        State.doctype,
                        Token{ .attr_value = xml.buffer[tok_start .. xml.index + 1] },
                    );
                },
                '\n' => return error.SyntaxError,
                else => {},
            },
            .doctype_end => switch (byte) {
                '>' => xml.state = .body,
                else => return error.SyntaxError,
            },
            .body => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => xml.state = .tag_name_start,
                else => {
                    tok_start = xml.index;
                    xml.state = .content;
                },
            },
            .tag_name_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<', '>' => return error.SyntaxError,
                '/' => xml.state = .tag_close_start,
                //TODO add comment
                else => {
                    tok_start = xml.index;
                    xml.state = .tag_name;
                },
            },
            .tag_name => switch (byte) {
                '<' => return error.SyntaxError,
                ' ', '\t', '\r', '\n' => {
                    return xml.emit(
                        State.tag,
                        Token{ .tag_open = xml.buffer[tok_start..xml.index] },
                    );
                },
                '>' => {
                    return xml.emit(
                        State.body,
                        Token{ .tag_open = xml.buffer[tok_start..xml.index] },
                    );
                },
                else => {},
            },
            .tag_close_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<', '>' => return error.SyntaxError,
                else => {
                    tok_start = xml.index;
                    xml.state = .tag_close_name;
                },
            },
            .tag_close_name => switch (byte) {
                '<' => return error.SyntaxError,
                ' ', '\t', '\r', '\n' => {
                    return xml.emit(
                        State.tag_close_b,
                        Token{ .tag_open = xml.buffer[tok_start..xml.index] },
                    );
                },
                '>' => {
                    return xml.emit(
                        State.body,
                        Token{ .tag_close = xml.buffer[tok_start..xml.index] },
                    );
                },
                else => {},
            },
            .tag_close_b => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>' => xml.state = .content,
                else => return error.SyntaxError,
            },
            .tag => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>' => xml.state = .body,
                '<' => return error.SyntaxError,
                '/' => {
                    tok_start = xml.index;
                    xml.state = .tag_and_empty;
                },
                else => {
                    tok_start = xml.index;
                    xml.state = .tag_attr_key;
                },
            },
            .tag_and_empty => switch (byte) {
                '>' => return xml.emit(
                    State.body,
                    Token{ .tag_close_empty = xml.buffer[tok_start..xml.index] },
                ),
                else => return error.SyntaxError,
            },
            .tag_attr_key => switch (byte) {
                '=' => {
                    return xml.emit(
                        State.tag_attr_value_q,
                        Token{ .attr_key = xml.buffer[tok_start..xml.index] },
                    );
                },
                '<', '>' => return error.SyntaxError,
                else => {},
            },
            .tag_attr_value_q => switch (byte) {
                '"' => {
                    tok_start = xml.index;
                    xml.state = .tag_attr_value;
                },
                else => return error.SyntaxError,
            },
            .tag_attr_value => switch (byte) {
                '"' => {
                    return xml.emit(
                        State.tag,
                        Token{ .attr_value = xml.buffer[tok_start .. xml.index + 1] },
                    );
                },
                '\n' => return error.SyntaxError,
                else => {},
            },
            .content => switch (byte) {
                '<' => return xml.emit(
                    State.tag_name_start,
                    Token{ .content = xml.buffer[tok_start..xml.index] },
                ),
                else => {},
            },
        }
    } else {
        switch (xml.state) {
            .doctype_name => return .{ .doctype_partial = xml.buffer[tok_start..xml.buffer.len] },
            .doctype_attr_key, .tag_attr_key => return .{ .attr_key_partial = xml.buffer[tok_start..xml.buffer.len] },
            .doctype_attr_value, .tag_attr_value => return .{ .attr_value_partial = xml.buffer[tok_start..xml.buffer.len] },
            .tag_name => return .{ .tag_open_partial = xml.buffer[tok_start..xml.buffer.len] },
            .tag_close_name => return .{ .tag_close_partial = xml.buffer[tok_start..xml.buffer.len] },
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
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "version" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"1.0\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "encoding" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"UTF-8\"" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "doctype partial" {
    const bytes =
        \\<?xm
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype_partial = "xm" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "doctype attr_key partial" {
    const bytes =
        \\<?xml versi
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key_partial = "versi" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "doctype attr_value partial" {
    const bytes =
        \\<?xml version="1.0" encoding="U
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "version" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"1.0\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "encoding" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value_partial = "\"U" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "some props" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <properties>
        \\  <property name="gravity" type="float" value="12.34"/>
        \\  <property name="never gonna give you up" type="bool" value="true"/>
        \\  <property name="never gonna let you down" type="bool" value="true"/>
        \\ </properties>
        \\</map>
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "properties" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag_open = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"gravity\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "type" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"float\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "value" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"12.34\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_close_empty = "/" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag_open = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"never gonna give you up\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "type" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"bool\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "value" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"true\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_close_empty = "/" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag_open = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"never gonna let you down\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "type" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"bool\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "value" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value = "\"true\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_close_empty = "/" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag_close = "properties" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_close = "map" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "tag attr_key partial" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <prop
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open_partial = "prop" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "tag attr_value partial" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <properties>
        \\  <property name="
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "properties" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag_open = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_key = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .attr_value_partial = "\"" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "empty tag" {
    const bytes =
        \\<?xml?>
        \\<map />
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_close_empty = "/" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "tag open partial" {
    const bytes =
        \\<?xml?>
        \\<ma
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open_partial = "ma" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "tag close partial" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <properties>
        \\ </propert
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .doctype = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag_open = "properties" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag_close_partial = "propert" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

pub fn main() !void {}
