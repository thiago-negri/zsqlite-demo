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
    try createTables(db);

    // Insert some.
    try insert(db);

    // Select all types.
    try select(db);

    // Select some.
    const names = try selectNames(db, arena.allocator());

    // Print results.
    print("All your codebases ", .{});
    for (names.items) |name| {
        print("{s}", .{name});
    }
    print(" belong to us!\n", .{});
}

fn createTables(db: Sqlite3) !void {
    const ddl_codebases =
        \\CREATE TABLE codebases (
        \\  id INT PRIMARY KEY,
        \\  name CHAR NOT NULL,
        \\  belong_to CHAR(2) NOT NULL
        \\);
    ;
    const ddl_alltypes =
        \\CREATE TABLE alltypes (
        \\ c_integer INTEGER,
        \\ c_real    REAL,
        \\ c_numeric NUMERIC,
        \\ c_blob    BLOB,
        \\ c_text    TEXT,
        \\ c_null    INTEGER
        \\);
    ;
    errdefer db.printError("Failed to create table");
    try db.exec(ddl_codebases);
    try db.exec(ddl_alltypes);
}

fn insert(db: Sqlite3) !void {
    errdefer db.printError("Failed to insert rows");

    const names: [3][]const u8 = .{ "a", "r", "e" };
    const sql_insert_codebases = "INSERT INTO codebases (name, belong_to) VALUES (?, ?);";
    const stmt = try db.prepare(sql_insert_codebases);
    try stmt.bindText(2, "us");
    for (names) |name| {
        try stmt.bindText(1, name);
        try stmt.exec();
        try stmt.reset();
    }

    const sql_insert_alltypes = try db.prepare(
        \\INSERT INTO alltypes (c_integer, c_real, c_numeric, c_blob, c_text, c_null)
        \\     VALUES          (        ?,      ?,         ?,      ?,      ?,      ?);
    );
    defer sql_insert_alltypes.deinit();

    try sql_insert_alltypes.bind(1, i32, 42);
    try sql_insert_alltypes.bind(2, f32, 3.14);
    try sql_insert_alltypes.bind(3, i17, 0xCAFE);
    try sql_insert_alltypes.bindBlob(4, &[_]u8{ 0xBA, 0xBE });
    try sql_insert_alltypes.bindText(5, "The name");
    try sql_insert_alltypes.bindNull(6);
    try sql_insert_alltypes.exec();
}

fn select(db: Sqlite3) !void {
    errdefer db.printError("Failed to select alltypes");

    const assert = std.debug.assert;

    const sql = try db.prepare(
        \\SELECT c_integer,
        \\       c_real,
        \\       c_numeric,
        \\       c_blob,
        \\       c_text,
        \\       c_null
        \\ FROM alltypes
        \\ WHERE rowid = ?;
    );
    defer sql.deinit();

    try sql.bind(1, i32, 1);

    var row = try sql.step();
    assert(null != row);

    const c_integer = row.?.column(0, i32);
    assert(42 == c_integer);

    const c_real = row.?.column(1, f32);
    assert(3.14 == c_real);

    const c_numeric = row.?.column(2, i17);
    assert(0xCAFE == c_numeric);

    const c_blob = row.?.columnBlobPtr(3);
    assert(std.mem.eql(u8, &[_]u8{ 0xBA, 0xBE }, c_blob));

    const c_text = row.?.columnTextPtr(4);
    assert(std.mem.eql(u8, "The name", c_text));

    const c_null_type = try row.?.columnType(5);
    assert(.null == c_null_type);

    row = try sql.step();
    assert(null == row);
}

fn selectNames(db: Sqlite3, alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
    const sql =
        \\SELECT name
        \\ FROM codebases
        \\ WHERE belong_to = ?;
    ;

    const stmt = stmt: {
        errdefer db.printError("Failed to prepare select statement");
        break :stmt try db.prepare(sql);
    };
    defer stmt.deinit();

    try stmt.bindText(1, "us");

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
