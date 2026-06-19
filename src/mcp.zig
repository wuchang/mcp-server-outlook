/// Minimal MCP Protocol implementation (JSON-RPC 2.0 over stdio)
/// Uses Zig 0.16 std.json.fmt for serialization

const std = @import("std");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;
const c = if (is_windows) @cImport({
    @cInclude("stdio.h");
    @cInclude("io.h");
}) else @cImport({
    @cInclude("stdio.h");
    @cInclude("unistd.h");
});

pub const ToolHandler = *const fn (args: ?std.json.Value, allocator: std.mem.Allocator) ToolError!ToolResult;

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: std.json.Value,
    handler: ToolHandler,
};

pub const ToolResult = struct {
    text: []const u8,
    is_error: bool = false,
};

pub const ToolError = error{
    InvalidArguments,
    ExecutionFailed,
    PermissionDenied,
    ResourceNotFound,
    Timeout,
    OutOfMemory,
    Unknown,
};

// Write JSON value to stdout as a JSON-RPC response
fn writeJsonToStdout(value: std.json.Value) void {
    var buf: [16384]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{f}\n", .{std.json.fmt(value, .{})}) catch "";
    if (is_windows) {
        _ = c._write(1, s.ptr, @as(c_uint, @intCast(s.len)));
    } else {
        _ = c.write(1, s.ptr, @as(c_uint, @intCast(s.len)));
    }
}

// Convert a JSON value to a string representation (for embedding)
fn jsonValToString(buf: []u8, val: std.json.Value) []u8 {
    return std.fmt.bufPrint(buf, "{f}", .{std.json.fmt(val, .{})}) catch "null";
}

pub const Server = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    tools: std.StringHashMap(Tool),
    running: bool,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) Server {
        return .{
            .allocator = allocator,
            .name = name,
            .version = version,
            .tools = std.StringHashMap(Tool).init(allocator),
            .running = false,
        };
    }

    pub fn deinit(self: *Server) void {
        self.tools.deinit();
    }

    pub fn addTool(self: *Server, tool: Tool) !void {
        try self.tools.put(tool.name, tool);
    }

    pub fn run(self: *Server) !void {
        self.running = true;
        defer self.running = false;

        var read_buf: [65536]u8 = undefined;
        var msg_len: usize = 0;

        while (self.running) {
            // Try to find and process all complete messages in the buffer
            while (true) {
                // Look for newline in current buffer
                var newline_pos: ?usize = null;
                for (read_buf[0..msg_len], 0..) |byte, i| {
                    if (byte == '\n') {
                        newline_pos = i;
                        break;
                    }
                }

                if (newline_pos) |nl| {
                    // Found a complete message at position nl
                    if (nl > 0) {
                        const result = std.json.parseFromSlice(std.json.Value, self.allocator, read_buf[0..nl], .{});
                        if (result) |parsed| {
                            defer parsed.deinit();
                            self.handleMessage(parsed.value) catch sendErrorResponse(null, -32700, "Parse error");
                        } else |_| {
                            sendErrorResponse(null, -32700, "Parse error: invalid JSON");
                        }
                    }
                    // Remove processed message from buffer
                    const remaining = msg_len - nl - 1;
                    if (remaining > 0) {
                        @memmove(read_buf[0..remaining], read_buf[nl + 1 .. msg_len]);
                    }
                    msg_len = remaining;
                } else {
                    // No complete message — need to read more
                    const n = if (is_windows)
                        @as(usize, @intCast(c._read(0, &read_buf[msg_len], @as(c_uint, @intCast(read_buf.len - msg_len)))))
                    else
                        @as(usize, @intCast(c.read(0, &read_buf[msg_len], @as(c_uint, @intCast(read_buf.len - msg_len)))));
                    if (n == 0) {
                        // EOF — process any remaining partial message
                        if (msg_len > 0) {
                            const result = std.json.parseFromSlice(std.json.Value, self.allocator, read_buf[0..msg_len], .{});
                            if (result) |parsed| {
                                defer parsed.deinit();
                                self.handleMessage(parsed.value) catch {};
                            } else |_| {}
                        }
                        self.running = false;
                        return;
                    }
                    msg_len += n;
                    // Continue loop to look for newlines in new data
                }
                if (newline_pos == null) break;
            }
            // If we processed at least one message and have remaining data, keep going
        }
    }

    fn handleMessage(self: *Server, msg: std.json.Value) !void {
        const obj = msg.object;
        const id = obj.get("id");
        const method = if (obj.get("method")) |m| if (m == .string) m.string else null else null;

        if (method) |m| {
            const params = obj.get("params");

            if (std.mem.eql(u8, m, "initialize")) {
                try self.handleInitialize(id.?);
            } else if (std.mem.eql(u8, m, "ping")) {
                try self.handlePing(id.?);
            } else if (std.mem.eql(u8, m, "tools/list")) {
                try self.handleToolsList(id.?);
            } else if (std.mem.eql(u8, m, "tools/call")) {
                try self.handleToolsCall(id.?, params);
            } else if (std.mem.eql(u8, m, "notifications/initialized")) {
                // No response
            } else {
                try self.sendError(id, -32601, "Method not found");
            }
        }
    }

    fn handleInitialize(self: *Server, id: std.json.Value) !void {
        // Build capability JSON manually to avoid complex JSON construction
        var caps_obj = std.json.ObjectMap.empty;
        try caps_obj.put(self.allocator, "protocolVersion", .{ .string = "2025-11-25" });

        var info = std.json.ObjectMap.empty;
        try info.put(self.allocator, "name", .{ .string = self.name });
        try info.put(self.allocator, "version", .{ .string = self.version });
        try caps_obj.put(self.allocator, "serverInfo", .{ .object = info });

        var tools_cap = std.json.ObjectMap.empty;
        try tools_cap.put(self.allocator, "listChanged", .{ .bool = false });
        var caps = std.json.ObjectMap.empty;
        try caps.put(self.allocator, "tools", .{ .object = tools_cap });
        try caps_obj.put(self.allocator, "capabilities", .{ .object = caps });

        try self.sendResponse(id, .{ .object = caps_obj });
    }

    fn handlePing(self: *Server, id: std.json.Value) !void {
        try self.sendResponse(id, .{ .object = std.json.ObjectMap.empty });
    }

    fn handleToolsList(self: *Server, id: std.json.Value) !void {
        var tools_arr = std.json.Array.init(self.allocator);
        var iter = self.tools.iterator();
        while (iter.next()) |entry| {
            const tool = entry.value_ptr;
            var tool_obj = std.json.ObjectMap.empty;
            try tool_obj.put(self.allocator, "name", .{ .string = tool.name });
            try tool_obj.put(self.allocator, "description", .{ .string = tool.description });
            try tool_obj.put(self.allocator, "inputSchema", .{ .object = blk: {
                var schema = std.json.ObjectMap.empty;
                try schema.put(self.allocator, "type", .{ .string = "object" });
                break :blk schema;
            } });
            try tools_arr.append(.{ .object = tool_obj });
        }

        var result = std.json.ObjectMap.empty;
        try result.put(self.allocator, "tools", .{ .array = tools_arr });
        try self.sendResponse(id, .{ .object = result });
    }

    fn handleToolsCall(self: *Server, id: std.json.Value, params: ?std.json.Value) !void {
        const tool_name = if (params) |p| blk: {
            if (p == .object) {
                if (p.object.get("name")) |n| {
                    if (n == .string) break :blk n.string;
                }
            }
            break :blk "";
        } else "";

        const args = if (params) |p|
            if (p == .object) p.object.get("arguments") else null
        else null;

        if (self.tools.get(tool_name)) |tool| {
            const result = tool.handler(args, self.allocator) catch |err| {
                const msg = switch (err) {
                    error.InvalidArguments => "Invalid arguments",
                    error.ExecutionFailed => "Execution failed",
                    error.PermissionDenied => "Permission denied",
                    error.ResourceNotFound => "Resource not found",
                    error.Timeout => "Timeout",
                    error.OutOfMemory => "Out of memory",
                    error.Unknown => "Unknown error",
                };
                try self.sendError(id, -32603, msg);
                return;
            };

            if (result.is_error) {
                try self.sendError(id, -32603, result.text);
            } else {
                var content_arr = std.json.Array.init(self.allocator);
                var text_obj = std.json.ObjectMap.empty;
                try text_obj.put(self.allocator, "type", .{ .string = "text" });
                try text_obj.put(self.allocator, "text", .{ .string = result.text });
                try content_arr.append(.{ .object = text_obj });

                var resp_obj = std.json.ObjectMap.empty;
                try resp_obj.put(self.allocator, "content", .{ .array = content_arr });
                try self.sendResponse(id, .{ .object = resp_obj });
            }
        } else {
            try self.sendError(id, -32602, "Tool not found");
        }
    }

    fn sendResponse(self: *Server, id: std.json.Value, result: std.json.Value) !void {
        var obj = std.json.ObjectMap.empty;
        try obj.put(self.allocator, "jsonrpc", .{ .string = "2.0" });
        try obj.put(self.allocator, "id", id);
        try obj.put(self.allocator, "result", result);
        writeJsonToStdout(.{ .object = obj });
    }

    fn sendError(_: *Server, id: ?std.json.Value, code: i64, message: []const u8) !void {
        sendErrorResponse(id, code, message);
    }
};

fn sendErrorResponse(id: ?std.json.Value, code: i64, message: []const u8) void {
    var obj = std.json.ObjectMap.empty;
    var err_obj = std.json.ObjectMap.empty;
    err_obj.put(std.heap.page_allocator, "code", .{ .integer = code }) catch {};
    err_obj.put(std.heap.page_allocator, "message", .{ .string = message }) catch {};
    obj.put(std.heap.page_allocator, "jsonrpc", .{ .string = "2.0" }) catch {};
    obj.put(std.heap.page_allocator, "id", if (id) |i| i else .{ .null = {} }) catch {};
    obj.put(std.heap.page_allocator, "error", .{ .object = err_obj }) catch {};
    writeJsonToStdout(.{ .object = obj });
}
