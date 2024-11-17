const std = @import("std");
const Sqlite3 = @import("zsqlite").Sqlite3;

const print = std.debug.print;
const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn main() !void {
    var gpa = GPA{};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const db = Sqlite3.init(":memory:") catch |err| {
        print("Failed to connect to SQLite", .{});
        return err;
    };
    defer db.deinit();

    // Create a table.
    try createTable(db);

    // Insert some.
    try insert(db);

    // Select some.
    const names = try select(db, arena.allocator());

    // Print results.
    print("All your codebases ", .{});
    for (names.items) |name| {
        print("{s}", .{name});
    }
    print(" belong to us!\n", .{});
}

fn createTable(db: Sqlite3) !void {
    const sql =
        \\CREATE TABLE codebases (
        \\  id INT PRIMARY KEY,
        \\  name CHAR NOT NULL,
        \\  belong_to CHAR(2) NOT NULL
        \\);
    ;
    errdefer db.printError("Failed to create table");
    try db.exec(sql);
}

fn insert(db: Sqlite3) !void {
    errdefer db.printError("Failed to insert rows");

    const names: [3][]const u8 = .{ "a", "r", "e" };
    const sql = "INSERT INTO codebases (name, belong_to) VALUES (?, ?);";
    const stmt = try db.prepare(sql);
    try stmt.bindText(2, "us");
    for (names) |name| {
        try stmt.bindText(1, name);
        try stmt.exec();
        try stmt.reset();
    }
}

fn select(db: Sqlite3, alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
    const sql =
        \\SELECT name
        \\ FROM codebases
        \\ WHERE belong_to = 'us';
    ;

    const stmt = stmt: {
        errdefer db.printError("Failed to prepare select statement");
        break :stmt try db.prepare(sql);
    };
    defer stmt.deinit();

    var names = std.ArrayList([]const u8).init(alloc);
    errdefer {
        for (names.items) |name| {
            alloc.free(name);
        }
        names.deinit();
    }

    while (try stmt.step()) |row| {
        const name = try row.columnText(0, alloc);
        errdefer alloc.free(name);
        try names.append(name);
    }

    return names;
}
