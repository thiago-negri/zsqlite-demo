const std = @import("std");
const zsqlite = @import("zsqlite");
const migrate = @import("zsqlite-migrate").migrate;
const embedMinifiedSql = @import("zsqlite-minify").embedMinifiedSql;

const Sqlite3 = zsqlite.Sqlite3;
const Row = zsqlite.Row;
const StatementIterator = zsqlite.StatementIterator;

const print = std.debug.print;
const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn main() !void {
    var gpa = GPA{};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var db = Sqlite3.init(":memory:", .{
        // Allocator is only required if track_open_statements is set to true
        .alloc = gpa.allocator(),
    }) catch |err| {
        print("Failed to connect to SQLite", .{});
        return err;
    };
    defer db.deinit();
    errdefer db.printError("oops");

    // Apply migrations.
    try migrate(db.sqlite3, .{ .emit_debug = true });

    // Create a table.
    try createTables(&db);

    // Insert some.
    try insert(&db);

    // Select all types.
    try select(&db);

    // Select some.
    const names = try selectNames(&db, arena.allocator());

    // Print results.
    print("All your codebases ", .{});
    for (names.items) |name| {
        print("{s}", .{name});
    }
    print(" belong to us!\n", .{});

    // Show case iterators, and embedded minified SQLs.
    try iterators(&db);
}

fn createTables(db: *Sqlite3) !void {
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
    try db.exec(ddl_alltypes);
}

fn insert(db: *Sqlite3) !void {
    errdefer db.printError("Failed to insert rows");

    const names: [3][]const u8 = .{ "a", "r", "e" };
    const sql_insert_codebases = "INSERT INTO codebases (name, belong_to) VALUES (?, ?);";
    const stmt = try db.prepare(sql_insert_codebases);
    defer stmt.deinit();
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

    const answer: i32 = 42;
    const pi: f32 = 3.14;
    const drink: i17 = 0xCAFE;

    try sql_insert_alltypes.bind(1, answer);
    try sql_insert_alltypes.bind(2, pi);
    try sql_insert_alltypes.bind(3, drink);
    try sql_insert_alltypes.bindBlob(4, &[_]u8{ 0xBA, 0xBE });
    try sql_insert_alltypes.bindText(5, "The name");
    try sql_insert_alltypes.bindNull(6);
    try sql_insert_alltypes.exec();
}

fn select(db: *Sqlite3) !void {
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

    try sql.bind(1, 1);

    var opt_row = try sql.step();
    assert(null != opt_row);

    const row = opt_row.?;

    const c_integer = row.column(0, i32);
    assert(42 == c_integer);

    const c_real = row.column(1, f32);
    assert(3.14 == c_real);

    const c_numeric = row.column(2, i17);
    assert(0xCAFE == c_numeric);

    const c_blob = row.columnBlobPtr(3);
    assert(std.mem.eql(u8, &[_]u8{ 0xBA, 0xBE }, c_blob));

    const c_text = row.columnTextPtr(4);
    assert(std.mem.eql(u8, "The name", c_text));

    const c_null_type = try row.columnType(5);
    assert(.null == c_null_type);

    opt_row = try sql.step();
    assert(null == opt_row);
}

fn selectNames(db: *Sqlite3, alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
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

const IterRow = struct {
    id: i64,
    name: []const u8,

    pub fn init(row: Row) IterRow {
        const id = row.column(0, i64);
        const name = row.columnTextPtr(1);
        return IterRow{
            .id = id,
            .name = name,
        };
    }
};

const IterStmt = StatementIterator(IterRow, IterRow.init, embedMinifiedSql("sqls/iter/select.sql"));

fn iterators(db: *Sqlite3) !void {
    const create_sql = comptime embedMinifiedSql("sqls/iter/create.sql");
    std.debug.print("The embedded SQL: ", .{});
    std.debug.print(create_sql, .{}); // notice it's comptime!
    std.debug.print("\n", .{});

    try db.exec(create_sql);
    try db.exec(embedMinifiedSql("sqls/iter/seed.sql"));

    const iter = try IterStmt.prepare(db);
    defer iter.deinit();
    while (try iter.next()) |typed_row| {
        std.debug.print("Typed Row: {d} - {s}\n", .{ typed_row.id, typed_row.name });
    }
}
