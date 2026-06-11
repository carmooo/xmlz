//! XML tokenizer. Takes partial input buffer as the input; provides a
//! streaming, non-allocating API to pull tokens one at a time.
//! This tokenizer can emit partial tokens;
//! The input to this class is a sequence of input buffers that you must supply one at a time.
//! This was inspired by https://github.com/andrewrk/xml and by the std lib json module.
//! For now we can use ' and " interchangeably for values. It is the responsability of the user
//! to check for that. This might change in the future.
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

    comment_q,
    comment_start,
    comment_body,
    comment_end_maybe,
    comment_b,
};

pub const Token = struct {
    tag: Tag,
    bytes: []const u8,

    pub const Tag = enum {
        doctype,
        doctype_partial,
        attr_key,
        attr_key_partial,
        attr_value,
        attr_value_partial,
        tag_open,
        tag_open_partial,
        tag_close,
        tag_close_partial,
        tag_close_empty,
        content,
        content_partial,
    };
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
                        Token{ .tag = .doctype, .bytes = xml.buffer[tok_start..xml.index] },
                    );
                },
                '?' => {
                    return xml.emit(
                        State.doctype_end,
                        Token{ .tag = .doctype, .bytes = xml.buffer[tok_start..xml.index] },
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
                        Token{ .tag = .attr_key, .bytes = xml.buffer[tok_start..xml.index] },
                    );
                },
                '?', '<', '>' => return error.SyntaxError,
                else => {},
            },
            .doctype_attr_value_q => switch (byte) {
                '"', '\'' => {
                    tok_start = xml.index;
                    xml.state = .doctype_attr_value;
                },
                else => return error.SyntaxError,
            },
            .doctype_attr_value => switch (byte) {
                '"', '\'' => {
                    return xml.emit(
                        State.doctype,
                        Token{ .tag = .attr_value, .bytes = xml.buffer[tok_start .. xml.index + 1] },
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
                '!' => xml.state = .comment_start,
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
                        Token{ .tag = .tag_open, .bytes = xml.buffer[tok_start..xml.index] },
                    );
                },
                '>' => {
                    return xml.emit(
                        State.body,
                        Token{ .tag = .tag_open, .bytes = xml.buffer[tok_start..xml.index] },
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
                        Token{ .tag = .tag_open, .bytes = xml.buffer[tok_start..xml.index] },
                    );
                },
                '>' => {
                    return xml.emit(
                        State.body,
                        Token{ .tag = .tag_close, .bytes = xml.buffer[tok_start..xml.index] },
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
                    Token{ .tag = .tag_close_empty, .bytes = xml.buffer[tok_start..xml.index] },
                ),
                else => return error.SyntaxError,
            },
            .tag_attr_key => switch (byte) {
                '=' => {
                    return xml.emit(
                        State.tag_attr_value_q,
                        Token{ .tag = .attr_key, .bytes = xml.buffer[tok_start..xml.index] },
                    );
                },
                '<', '>' => return error.SyntaxError,
                else => {},
            },
            .tag_attr_value_q => switch (byte) {
                '"', '\'' => {
                    tok_start = xml.index;
                    xml.state = .tag_attr_value;
                },
                else => return error.SyntaxError,
            },
            .tag_attr_value => switch (byte) {
                '"', '\'' => {
                    return xml.emit(
                        State.tag,
                        Token{ .tag = .attr_value, .bytes = xml.buffer[tok_start .. xml.index + 1] },
                    );
                },
                '\n' => return error.SyntaxError,
                else => {},
            },
            .content => switch (byte) {
                '<' => return xml.emit(
                    State.tag_name_start,
                    Token{ .tag = .content, .bytes = xml.buffer[tok_start..xml.index] },
                ),
                else => {},
            },
            .comment_q => switch (byte) {
                '-' => xml.state = .comment_start,
                else => return error.SyntaxError,
            },
            .comment_start => switch (byte) {
                '-' => xml.state = .comment_body,
                else => return error.SyntaxError,
            },
            .comment_body => switch (byte) {
                '-' => xml.state = .comment_end_maybe,
                else => {},
            },
            .comment_end_maybe => switch (byte) {
                '-' => xml.state = .comment_b,
                else => xml.state = .comment_body,
            },
            .comment_b => switch (byte) {
                '>' => xml.state = .body,
                else => return error.SyntaxError,
            },
        }
    } else {
        switch (xml.state) {
            .doctype_name => return .{ .tag = .doctype_partial, .bytes = xml.buffer[tok_start..xml.buffer.len] },
            .doctype_attr_key, .tag_attr_key => return .{ .tag = .attr_key_partial, .bytes = xml.buffer[tok_start..xml.buffer.len] },
            .doctype_attr_value, .tag_attr_value => return .{ .tag = .attr_value_partial, .bytes = xml.buffer[tok_start..xml.buffer.len] },
            .tag_name => return .{ .tag = .tag_open_partial, .bytes = xml.buffer[tok_start..xml.buffer.len] },
            .tag_close_name => return .{ .tag = .tag_close_partial, .bytes = xml.buffer[tok_start..xml.buffer.len] },
            .content => return .{ .tag = .content_partial, .bytes = xml.buffer[tok_start..xml.buffer.len] },
            else => return error.BufferUnderrun,
        }
    }
}

fn emit(xml: *Xml, next_state: State, token: Token) Token {
    xml.state = next_state;
    xml.index += 1;
    return token;
}

pub fn nextContent(xml: *Xml) NextError!Token {
    var token: Token = undefined;
    while (true) {
        token = try xml.next();
        switch (token.tag) {
            .content, .content_partial => break,
            else => {},
        }
    }
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
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "version" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"1.0\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "encoding" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"UTF-8\"" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "doctype partial" {
    const bytes =
        \\<?xm
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype_partial, .bytes = "xm" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "doctype attr_key partial" {
    const bytes =
        \\<?xml versi
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key_partial, .bytes = "versi" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "doctype attr_value partial" {
    const bytes =
        \\<?xml version="1.0" encoding="U
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "version" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"1.0\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "encoding" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value_partial, .bytes = "\"U" }, try xml.next());
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
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "properties" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"gravity\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "type" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"float\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "value" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"12.34\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close_empty, .bytes = "/" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"never gonna give you up\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "type" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"bool\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "value" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"true\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close_empty, .bytes = "/" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"never gonna let you down\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "type" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"bool\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "value" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"true\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close_empty, .bytes = "/" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "properties" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "map" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "tag attr_key partial" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <prop
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open_partial, .bytes = "prop" }, try xml.next());
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
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "properties" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value_partial, .bytes = "\"" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "empty tag" {
    const bytes =
        \\<?xml?>
        \\<map />
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close_empty, .bytes = "/" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "tag open partial" {
    const bytes =
        \\<?xml?>
        \\<ma
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open_partial, .bytes = "ma" }, try xml.next());
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
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "map" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "properties" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_close_partial, .bytes = "propert" }, try xml.next());
    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "content with different tags" {
    const bytes =
        \\<?xml?>
        \\<h1>Title</h1>
        \\<text>Some text</text>
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "h1" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .content, .bytes = "Title" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "h1" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "text" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .content, .bytes = "Some text" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "text" }, try xml.next());

    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "content partial" {
    const bytes =
        \\<?xml?>
        \\<h1>Title</h1>
        \\<text>Some
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "h1" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .content, .bytes = "Title" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "h1" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "text" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .content_partial, .bytes = "Some" }, try xml.next());

    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "content and comment" {
    const bytes =
        \\<?xml?>
        \\<h1>Title</h1>
        \\ <!-- This is a multi-
        \\       line comment, Rick -->
        \\<text>Some text</text>
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "h1" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .content, .bytes = "Title" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "h1" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "text" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .content, .bytes = "Some text" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "text" }, try xml.next());

    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "support single and double quotes" {
    const bytes =
        \\<?xml version="1.0" encoding='UTF-8'?>
        \\  <property name="never gonna give you up" type='bool' value="true"/>
    ;
    var xml: Xml = .{ .buffer = bytes };

    try testing.expectEqualDeep(Token{ .tag = .doctype, .bytes = "xml" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "version" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"1.0\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "encoding" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\'UTF-8\'" }, try xml.next());

    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "property" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "name" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"never gonna give you up\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "type" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\'bool\'" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_key, .bytes = "value" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .attr_value, .bytes = "\"true\"" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_close_empty, .bytes = "/" }, try xml.next());

    try testing.expectError(NextError.BufferUnderrun, xml.next());
}

test "next content" {
    const bytes =
        \\<?xml?>
        \\<h1>Title</h1>
        \\<text>Some text</text>
        \\<text>Some
    ;
    var xml: Xml = .{ .buffer = bytes };
    try testing.expectEqualDeep(Token{ .tag = .content, .bytes = "Title" }, try xml.nextContent());

    try testing.expectEqualDeep(Token{ .tag = .tag_close, .bytes = "h1" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .tag_open, .bytes = "text" }, try xml.next());
    try testing.expectEqualDeep(Token{ .tag = .content, .bytes = "Some text" }, try xml.nextContent());

    try testing.expectEqualDeep(Token{ .tag = .content_partial, .bytes = "Some" }, try xml.nextContent());
}

pub fn main() !void {}
