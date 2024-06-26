const std = @import("std");
const hash = @import("hash.zig");

// Manual (-h)
const manual = @embedFile("manual.txt");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    _ = stdout;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("MEMORY LEAKED!");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var program = Program(){};

    try program.init(allocator, args);
    defer program.deinit();

    try program.exec();
}

fn catchError(err: anyerror) !void {
    const stdout = std.io.getStdOut().writer();

    std.log.info("{}", .{err});
    try stdout.print("{}\n", .{err});
}

fn Program() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator = undefined,
        flags: std.StringHashMap([]const u8) = undefined,

        pub fn init(self: *Self, allocator: std.mem.Allocator, args: []const []u8) !void {
            self.allocator = allocator;
            self.flags = std.StringHashMap([]const u8).init(self.allocator);
            try self.importArgs(args);
        }

        pub fn deinit(self: *Self) void {
            self.flags.deinit();
        }

        fn importArgs(self: *Self, args: []const []const u8) !void {
            const supporeted_flags = [_][]const u8{ "-h", "-hf", "-ec", "-f", "-d" };

            for (0.., args) |i, arg| {
                for (supporeted_flags) |flag| {
                    if (std.mem.eql(u8, arg, "-h")) {
                        try self.flags.put(arg, "");
                    }

                    if (std.mem.eql(u8, arg, flag) and i < args.len - 1) {
                        try self.flags.put(arg, args[i + 1]);
                    }
                }
            }
        }

        pub fn exec(self: *Self) !void {
            const stdout = std.io.getStdOut().writer();

            var readFile: bool = false;
            var filePath: []const u8 = undefined;
            var hashFunction: hash.HashHint = .sha256;
            var encoding: hash.EncodingHint = .hex;

            if (self.flags.contains("-h")) {
                try stdout.print("{s}", .{manual});
                return;
            }

            if (self.flags.contains("-f")) {
                filePath = self.flags.get("-f").?;
                readFile = true;
            }

            if (self.flags.contains("-hf")) {
                const hashFunctionString = self.flags.get("-hf").?;
                hashFunction = try hash.hashHintFromString(hashFunctionString);
            }

            if (self.flags.contains("-ec")) {
                const encodingString = self.flags.get("-ec").?;
                encoding = try hash.encodingHintFromString(encodingString);
            }

            if (readFile == true) {
                const digest = hash.fileHash(self.allocator, filePath, hashFunction, encoding) catch |err| {
                    try catchError(err);
                    return;
                };
                defer self.allocator.free(digest);

                switch (encoding) {
                    .raw => {
                        for (1.., digest) |i, byte| {
                            if (i < digest.len) {
                                try stdout.print("{d}, ", .{byte});
                            } else {
                                try stdout.print("{d}\n", .{byte});
                            }
                        }
                    },
                    .hex, .base64 => {
                        try stdout.print("{s}\n", .{digest});
                    },
                }
            }
        }
    };
}
