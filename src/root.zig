pub const Ini = struct {
    /// An allocator that will be used for methods that need to allocate and
    /// free owned memory.
    allocator: std.mem.Allocator,

    /// An internal buffer holding raw ini data.
    buffer: ?union(enum) {
        owned: []const u8,
        borrowed: []const u8,
    },

    /// Options for reading, writing, parsing, etc.
    options: IniOptions = .{},

    const IniOptions = struct {
        /// The max size (in bytes) to read (default: 10MiB)
        max_read_size: usize = 10 * 1024 * 1024,
    };

    pub fn init(allocator: std.mem.Allocator, options: IniOptions) Ini {
        return .{
            .allocator = allocator,
            .buffer = null,
            .options = options,
        };
    }

    pub fn deinit(self: *Ini) void {
        if (self.buffer) |buffer| {
            switch (buffer) {
                .owned => |owned_buffer| {
                    self.allocator.free(owned_buffer);
                },
                else => {},
            }
        }

        self.buffer = null;
    }

    const LoadBufferError = error{} || Allocator.Error;

    /// Load a buffer. Does not take ownership of the memory and does not copy
    /// it. Care must be taken to ensure `buffer` outlives `self` (the `Ini`
    /// instance).
    pub fn loadBuffer(self: *Ini, buffer: []const u8) void {
        self.buffer = .{ .borrowed = buffer };
    }

    /// Load a buffer. Does not take ownership of the memory. This method copies the
    /// buffer into the internal buffer.
    pub fn loadBufferOwned(self: *Ini, buffer: []const u8) LoadBufferError!void {
        const buffer_copy = try self.allocator.dupe(u8, buffer);
        self.buffer = .{ .owned = buffer_copy };
    }

    const LoadFileError = error{} || Allocator.Error || File.OpenError || anyerror;

    /// Load a file. This method reads the entire file (up to
    /// `IniOptions.max_read_size`) and copies it to the the internal buffer.
    pub fn loadFile(self: *Ini, path: []const u8) LoadFileError!void {
        const file = try if (std.fs.path.isAbsolute(path))
            std.fs.openFileAbsolute(path, .{})
        else
            std.fs.cwd().openFile(path, .{});
        defer file.close();

        const buffer_copy = try file.readToEndAlloc(self.allocator, self.options.max_read_size);
        self.buffer = .{ .owned = buffer_copy };
    }

    const LoadStreamError = error{} || Allocator.Error || anyerror;

    /// Load a stream. This method reads the entire stream (up to
    /// `IniOptions.max_read_size`) and copies it to the the internal buffer.
    pub fn loadStream(self: *Ini, stream: anytype) LoadStreamError!void {
        const buffer_copy = try stream.readAllAlloc(self.allocator, self.options.max_read_size);
        self.buffer = .{ .owned = buffer_copy };
    }

    const ParseError = error{} || Parser.ParseError;

    /// Parses the internal buffer and produces a `ParsedIni`.
    pub fn parse(self: *Ini) ParseError!ParsedIni {
        var parser = Parser.init(self);
        const entries = try parser.parse();

        return ParsedIni{
            .allocator = self.allocator,
            .entries = entries,
        };
    }
};

const ParsedIni = struct {
    allocator: std.mem.Allocator,
    entries: MultiArrayList(IniEntry) = .{},

    pub fn deinit(self: *ParsedIni) void {
        self.entries.deinit(self.allocator);
    }

    const GetValueError = error{NotFound};

    /// Get a value from the ini given a section and a key.
    pub fn get(self: ParsedIni, section: []const u8, key: []const u8) GetValueError![]const u8 {
        const sections = self.entries.slice().items(.section);
        const keys = self.entries.slice().items(.key);
        const values = self.entries.slice().items(.value);

        for (sections, 0..) |entry_section, i| {
            const trimmed_entry_section = std.mem.trim(u8, entry_section, " ");
            if (std.mem.eql(u8, section, trimmed_entry_section)) {
                const trimmed_entry_key = std.mem.trim(u8, keys[i], " ");
                if (std.mem.eql(u8, key, trimmed_entry_key)) {
                    const trimmed_value = std.mem.trim(u8, values[i], " ");
                    return trimmed_value;
                }
            }
        }

        return error.NotFound;
    }

    const PutValueError = error{ NotFound, KeyExists } || Allocator.Error;

    /// Put a new value into the ini. If the section:key already exists, this
    /// method returns an error.
    pub fn put(self: *ParsedIni, section: []const u8, key: []const u8, value: []const u8) PutValueError!void {
        if (self.get(section, key)) |_| {
            return PutValueError.KeyExists;
        } else |err| switch (err) {
            GetValueError.NotFound => try self.entries.append(self.allocator, .{
                .section = section,
                .key = key,
                .value = value,
            }),
        }
    }

    /// Put a new value or update an existing value into the ini. If the
    /// section:key already exists, this function updates the existing key;
    /// otherwise, a new key is added.
    pub fn putOrUpdate(self: *ParsedIni, section: []const u8, key: []const u8, value: []const u8) Allocator.Error!void {
        const sections = self.entries.slice().items(.section);
        const keys = self.entries.slice().items(.key);
        const values = self.entries.slice().items(.value);

        for (sections, 0..) |entry_section, i| {
            const trimmed_entry_section = std.mem.trim(u8, entry_section, " ");
            if (std.mem.eql(u8, section, trimmed_entry_section)) {
                const trimmed_entry_key = std.mem.trim(u8, keys[i], " ");
                if (std.mem.eql(u8, key, trimmed_entry_key)) {
                    values[i] = value;
                    return;
                }
            }
        }

        const result = self.put(section, key, value);

        std.debug.assert(@TypeOf(result) != PutValueError);
        std.debug.assert(@TypeOf(result) == Allocator.Error);

        return @errorCast(result);
    }
};

const Parser = struct {
    ini: *Ini,
    pub fn init(ini: *Ini) Parser {
        return .{ .ini = ini };
    }

    const ParseError = error{InvalidCharacter} || Allocator.Error;
    pub fn parse(self: *Parser) ParseError!MultiArrayList(IniEntry) {
        var entries = MultiArrayList(IniEntry){};
        const buffer = if (self.ini.buffer) |buffer| switch (buffer) {
            .owned, .borrowed => |b| b,
        } else {
            return .{};
        };
        var lines = std.mem.tokenizeScalar(u8, buffer, '\n');
        var i: usize = 0;

        var current_section: ?[]const u8 = null;
        while (lines.next()) |line| : (i += 1) {
            // comments
            if (line[0] == ';') {
                continue;
            }

            // sections
            if (line[0] == '[') {
                if (line[0] != '[' or line[line.len - 1] != ']') {
                    return ParseError.InvalidCharacter;
                }

                current_section = line[1 .. line.len - 1];
                continue;
            }

            // declarations
            if (current_section) |section| {
                var kv_tok = std.mem.tokenizeScalar(u8, line, '=');
                const maybe_key = kv_tok.next();
                const val = kv_tok.rest();

                if (maybe_key) |key| {
                    try entries.append(self.ini.allocator, .{
                        .section = section,
                        .key = key,
                        .value = val,
                    });
                } else {
                    return ParseError.InvalidCharacter;
                }
            } else {
                return ParseError.InvalidCharacter;
            }
        }

        return entries;
    }
};

const IniEntry = struct {
    section: []const u8,
    key: []const u8,
    value: []const u8,
};

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const MultiArrayList = std.MultiArrayList;

test "single section, single key" {
    const data =
        \\[main]
        \\hello=world
        \\
    ;

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        try ini.loadBufferOwned(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        ini.loadBuffer(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }
}

test "single section, multiple keys" {
    const data =
        \\[main]
        \\hello=world
        \\num=42
        \\
    ;

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        try ini.loadBufferOwned(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));
        try testing.expectEqualSlices(u8, "42", try parsed.get("main", "num"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        ini.loadBuffer(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));
        try testing.expectEqualSlices(u8, "42", try parsed.get("main", "num"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }
}

test "single section, duplicate key" {
    const data =
        \\[main]
        \\hello=world
        \\hello=world!!!
        \\
    ;
    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        try ini.loadBufferOwned(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        ini.loadBuffer(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }
}

test "multiple sections, one key per section" {
    const data =
        \\[main]
        \\hello=world
        \\[extra]
        \\num=42
        \\
    ;

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        try ini.loadBufferOwned(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));
        try testing.expectEqualSlices(u8, "42", try parsed.get("extra", "num"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        ini.loadBuffer(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));
        try testing.expectEqualSlices(u8, "42", try parsed.get("extra", "num"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }
}

test "multiple sections, duplicate key in different sections" {
    const data =
        \\[main]
        \\hello=world
        \\[extra]
        \\hello=world!!!
        \\
    ;

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        try ini.loadBufferOwned(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));
        try testing.expectEqualSlices(u8, "world!!!", try parsed.get("extra", "hello"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }

    {
        var ini = Ini.init(testing.allocator, .{});
        defer ini.deinit();

        ini.loadBuffer(data);
        var parsed = try ini.parse();
        defer parsed.deinit();

        // values are found
        try testing.expectEqualSlices(u8, "world", try parsed.get("main", "hello"));
        try testing.expectEqualSlices(u8, "world!!!", try parsed.get("extra", "hello"));

        // values are not found
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
        try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
    }
}

test "empty section" {
    const data =
        \\[main]
        \\[extra]
        \\hello=world
        \\
    ;

    var ini = Ini.init(testing.allocator, .{});
    defer ini.deinit();

    ini.loadBuffer(data);
    var parsed = try ini.parse();
    defer parsed.deinit();

    // values are found
    try testing.expectEqualSlices(u8, "world", try parsed.get("extra", "hello"));

    // values are not found
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "hello"));
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
}

test "chat-gippity file" {
    var ini = Ini.init(testing.allocator, .{});
    defer ini.deinit();

    try ini.loadFile("samples/chat-gippity.ini");
    var parsed = try ini.parse();
    defer parsed.deinit();

    // values are found
    try testing.expectEqualSlices(u8, "60", try parsed.get("Experimentation", "TestDuration"));
    try testing.expectEqualSlices(u8, "2GB", try parsed.get("Performance", "CacheSize"));

    // values are not found
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
}

test "chat-gippity stream" {
    var ini = Ini.init(testing.allocator, .{});
    defer ini.deinit();

    const file = try std.fs.cwd().openFile("samples/chat-gippity.ini", .{});
    defer file.close();

    try ini.loadStream(file.reader());
    var parsed = try ini.parse();
    defer parsed.deinit();

    // values are found
    try testing.expectEqualSlices(u8, "60", try parsed.get("Experimentation", "TestDuration"));
    try testing.expectEqualSlices(u8, "2GB", try parsed.get("Performance", "CacheSize"));

    // values are not found
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("main", "no_key"));
}

test "put" {
    var ini = Ini.init(testing.allocator, .{});
    defer ini.deinit();

    var parsed = try ini.parse();
    defer parsed.deinit();

    try parsed.put("new", "hello", "world");
    try testing.expectError(ParsedIni.PutValueError.KeyExists, parsed.put("new", "hello", "world"));

    // values are found
    try testing.expectEqualSlices(u8, "world", try parsed.get("new", "hello"));

    // values are not found
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
}

test "putOrUpdate" {
    var ini = Ini.init(testing.allocator, .{});
    defer ini.deinit();

    var parsed = try ini.parse();
    defer parsed.deinit();

    try parsed.put("new", "hello", "world");
    try parsed.putOrUpdate("new", "hello", "world!!!");

    // values are found
    try testing.expectEqualSlices(u8, "world!!!", try parsed.get("new", "hello"));
    try testing.expectError(ParsedIni.PutValueError.KeyExists, parsed.put("new", "hello", "world"));

    // values are not found
    try testing.expectError(ParsedIni.GetValueError.NotFound, parsed.get("no_section", "hello"));
}
