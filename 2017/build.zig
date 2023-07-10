const std = @import("std");
const builtin = @import("builtin");
//const compat = @import("src/compat.zig");
//const tests = @import("test/tests.zig");

const Build = std.Build;
const CompileStep = Build.CompileStep;
const Step = Build.Step;
const Child = std.process.Child;

const assert = std.debug.assert;
const join = std.fs.path.join;
const print = std.debug.print;

const Kind = enum {
    /// Run the artifact as a normal executable.
    exe,
    /// Run the artifact as a test.
    @"test",
};

pub const Day = struct {
    /// main_file must have the format key_name.zig.
    /// The key will be used as a shorthand to build just one example.
    main_file: []const u8,

    /// This is the desired output of the program.
    /// A program passes if its output, excluding trailing whitespace, is equal
    /// to this string.
    //output: []const u8,

    /// This is an optional hint to give if the program does not succeed.
    hint: ?[]const u8 = null,

    /// By default, we verify output against stderr.
    /// Set this to true to check stdout instead.
    check_stdout: bool = false,

    /// This exercise makes use of C functions.
    /// We need to keep track of this, so we compile with libc.
    link_libc: bool = false,

    /// This exercise kind.
    kind: Kind = .exe,

    /// This exercise is not supported by the current Zig compiler.
    skip: bool = false,

    /// Returns the name of the main file with .zig stripped.
    pub fn name(self: Day) []const u8 {
        return std.fs.path.stem(self.main_file);
    }

    /// Returns the key of the main file, the string before the '_' with
    /// "zero padding" removed.
    /// For example, "001_hello.zig" has the key "1".
    pub fn key(self: Day) []const u8 {
        // Main file must be key_description.zig.
        const end_index = std.mem.indexOfScalar(u8, self.main_file, '.') orelse
            unreachable;

        // Remove zero padding by advancing index past '0's.
        var start_index: usize = std.mem.indexOfScalar(u8, self.main_file, 'y') orelse unreachable;
        while (self.main_file[start_index] == '0') start_index += 1;
        return self.main_file[start_index..end_index];
    }

    /// Returns the exercise key as an integer.
    pub fn number(self: Day) usize {
        return std.fmt.parseInt(usize, self.key(), 10) catch unreachable;
    }
};

/// Build mode.
const Mode = enum {
    /// Normal build mode: `zig build`
    normal,
    /// Named build mode: `zig build -Day=n`
    named,
};

pub const logo =
    \\         __           ___       _____
    \\        /  \         / _ \     / ___/ 
    \\       / /\ \       / / \ \   / /     
    \\      / /__\ \     / /   \ \ / /     
    \\     / ______ \    \ \   / / \ \    
    \\    / /      \ \  _ \ \_/ /_  \ \____ _
    \\   /_/        \_\(_) \___/(_)  \____/(_)
    \\
    \\
;

pub fn build(b: *Build) !void {
    //if (!compat.is_compatible) compat.die();
    // if (!validate_exercises()) std.os.exit(2);

    use_color_escapes = false;
    if (std.io.getStdErr().supportsAnsiEscapeCodes()) {
        use_color_escapes = true;
    } else if (builtin.os.tag == .windows) {
        const w32 = struct {
            const WINAPI = std.os.windows.WINAPI;
            const DWORD = std.os.windows.DWORD;
            const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
            const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));
            extern "kernel32" fn GetStdHandle(id: DWORD) callconv(WINAPI) ?*anyopaque;
            extern "kernel32" fn GetConsoleMode(console: ?*anyopaque, out_mode: *DWORD) callconv(WINAPI) u32;
            extern "kernel32" fn SetConsoleMode(console: ?*anyopaque, mode: DWORD) callconv(WINAPI) u32;
        };
        const handle = w32.GetStdHandle(w32.STD_ERROR_HANDLE);
        var mode: w32.DWORD = 0;
        if (w32.GetConsoleMode(handle, &mode) != 0) {
            mode |= w32.ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            use_color_escapes = w32.SetConsoleMode(handle, mode) != 0;
        }
    }

    if (use_color_escapes) {
        red_text = "\x1b[31m";
        red_bold_text = "\x1b[31;1m";
        red_dim_text = "\x1b[31;2m";
        green_text = "\x1b[32m";
        bold_text = "\x1b[1m";
        reset_text = "\x1b[0m";
    }

    // Remove the standard install and uninstall steps.
    b.top_level_steps = .{};

    //const healed = b.option(bool, "healed", "Run exercises from patches/healed") orelse
    //    false;
    //const override_healed_path = b.option([]const u8, "healed-path", "Override healed path");
    const dayn: ?usize = b.option(usize, "ay", "Select the Day");

    //const sep = std.fs.path.sep_str;
    //const healed_path = if (override_healed_path) |path|
    //    path
    //else
    //    "patches" ++ sep ++ "healed";
    const work_path = "src";

    const header_step = PrintStep.create(b, logo);

    if (dayn) |n| {
        // Named build mode: verifies a single exercise.
        if (n == 0 or n > days.len - 1) {
            print("unknown day number: {}\n", .{n});
            std.os.exit(2);
        }
        const ex = days[n - 1];

        const aoc_day_step = b.step(
            "day",
            b.fmt("Check the solution of {s}", .{ex.main_file}),
        );
        b.default_step = aoc_day_step;
        aoc_day_step.dependOn(&header_step.step);

        const verify_step = AocStep.create(b, ex, work_path, .named);
        verify_step.step.dependOn(&header_step.step);

        aoc_day_step.dependOn(&verify_step.step);

        return;
    }

    // Normal build mode: verifies all exercises according to the recommended
    // order.
    const aoc_step = b.step("aoc", "Check all days");
    b.default_step = aoc_step;

    var prev_step = &header_step.step;
    for (days) |ex| {
        const verify_stepn = AocStep.create(b, ex, work_path, .normal);
        verify_stepn.step.dependOn(prev_step);

        prev_step = &verify_stepn.step;
    }
    aoc_step.dependOn(prev_step);

    //const test_step = b.step("test", "Run all the tests");
    //test_step.dependOn(tests.addCliTests(b, &days));
}

var use_color_escapes = false;
var red_text: []const u8 = "";
var red_bold_text: []const u8 = "";
var red_dim_text: []const u8 = "";
var green_text: []const u8 = "";
var bold_text: []const u8 = "";
var reset_text: []const u8 = "";

const AocStep = struct {
    step: Step,
    day: Day,
    work_path: []const u8,
    mode: Mode,

    pub fn create(
        b: *Build,
        day: Day,
        work_path: []const u8,
        mode: Mode,
    ) *AocStep {
        const self = b.allocator.create(AocStep) catch @panic("OOM");
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = day.main_file,
                .owner = b,
                .makeFn = make,
            }),
            .day = day,
            .work_path = work_path,
            .mode = mode,
        };
        return self;
    }

    fn make(step: *Step, prog_node: *std.Progress.Node) !void {
        // NOTE: Using exit code 2 will prevent the Zig compiler to print the message:
        // "error: the following build command failed with exit code 1:..."
        const self = @fieldParentPtr(AocStep, "step", step);

        if (self.day.skip) {
            print("Skipping {s}\n\n", .{self.day.main_file});

            return;
        }

        const exe_path = self.compile(prog_node) catch {
            self.printErrors();

            if (self.day.hint) |hint|
                print("\n{s}Ziglings hint: {s}{s}", .{ bold_text, hint, reset_text });

            self.help();
            std.os.exit(2);
        };

        self.run(exe_path, prog_node) catch {
            self.printErrors();

            if (self.day.hint) |hint|
                print("\n{s}Ziglings hint: {s}{s}", .{ bold_text, hint, reset_text });

            self.help();
            std.os.exit(2);
        };

        // Print possible warning/debug messages.
        self.printErrors();
    }

    fn run(self: *AocStep, exe_path: []const u8, _: *std.Progress.Node) !void {
        resetLine();
        print("Checking {s}...\n", .{self.day.main_file});

        const b = self.step.owner;

        // Allow up to 1 MB of stdout capture.
        const max_output_bytes = 1 * 1024 * 1024;

        var result = Child.exec(.{
            .allocator = b.allocator,
            .argv = &.{exe_path},
            .cwd = b.build_root.path.?,
            .cwd_dir = b.build_root.handle,
            .max_output_bytes = max_output_bytes,
        }) catch |err| {
            return self.step.fail("unable to spawn {s}: {s}", .{
                exe_path, @errorName(err),
            });
        };

        switch (self.day.kind) {
            .exe => return self.check_output(result),
            .@"test" => return self.check_test(result),
        }
    }

    fn check_output(self: *AocStep, result: Child.ExecResult) !void {
        const b = self.step.owner;

        // Make sure it exited cleanly.
        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    return self.step.fail("{s} exited with error code {d} (expected {})", .{
                        self.day.main_file, code, 0,
                    });
                }
            },
            else => {
                return self.step.fail("{s} terminated unexpectedly", .{
                    self.day.main_file,
                });
            },
        }

        const raw_output = if (self.day.check_stdout)
            result.stdout
        else
            result.stderr;

        // Validate the output.
        // NOTE: exercise.output can never contain a CR character.
        // See https://ziglang.org/documentation/master/#Source-Encoding.
        const output = trimLines(b.allocator, raw_output) catch @panic("OOM");
        //const exercise_output = self.day.output;
        //if (!std.mem.eql(u8, output, self.day.output)) {
        //    const red = red_bold_text;
        //    const reset = reset_text;

        // Override the coloring applied by the printError method.
        // NOTE: the first red and the last reset are not necessary, they
        // are here only for alignment.
        //    return self.step.fail(
        //        \\
        //        \\{s}========= expected this output: =========={s}
        //        \\{s}
        //        \\{s}========= but found: ====================={s}
        //       \\{s}
        //        \\{s}=========================================={s}
        //    , .{ red, reset, exercise_output, red, reset, output, red, reset });
        //}

        print("\n{s}{s}\n\n", .{ output, reset_text });
    }

    fn check_test(self: *AocStep, result: Child.ExecResult) !void {
        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    // The test failed.
                    const stderr = std.mem.trimRight(u8, result.stderr, " \r\n");

                    return self.step.fail("\n{s}", .{stderr});
                }
            },
            else => {
                return self.step.fail("{s} terminated unexpectedly", .{
                    self.day.main_file,
                });
            },
        }

        print("{s}PASSED{s}\n\n", .{ green_text, reset_text });
    }

    fn compile(self: *AocStep, prog_node: *std.Progress.Node) ![]const u8 {
        print("Compiling {s}...\n", .{self.day.main_file});

        const b = self.step.owner;
        const day_path = self.day.main_file;
        const path = join(b.allocator, &.{ self.work_path, day_path }) catch
            @panic("OOM");

        var zig_args = std.ArrayList([]const u8).init(b.allocator);
        defer zig_args.deinit();

        zig_args.append(b.zig_exe) catch @panic("OOM");

        const cmd = switch (self.day.kind) {
            .exe => "build-exe",
            .@"test" => "test",
        };
        zig_args.append(cmd) catch @panic("OOM");

        // Enable C support for exercises that use C functions.
        if (self.day.link_libc) {
            zig_args.append("-lc") catch @panic("OOM");
        }

        zig_args.append(b.pathFromRoot(path)) catch @panic("OOM");

        zig_args.append("--cache-dir") catch @panic("OOM");
        zig_args.append(b.pathFromRoot(b.cache_root.path.?)) catch @panic("OOM");

        zig_args.append("--listen=-") catch @panic("OOM");

        return try self.step.evalZigProcess(zig_args.items, prog_node);
    }

    fn help(self: *AocStep) void {
        const b = self.step.owner;
        const key = self.day.key();
        const path = self.day.main_file;

        const cmd = switch (self.mode) {
            .normal => "zig build",
            .named => b.fmt("zig build -Dn={s}", .{key}),
        };

        print("\n{s}Edit exercises/{s} and run '{s}' again.{s}\n", .{
            red_bold_text, path, cmd, reset_text,
        });
    }

    fn printErrors(self: *AocStep) void {
        resetLine();

        // Display error/warning messages.
        if (self.step.result_error_msgs.items.len > 0) {
            for (self.step.result_error_msgs.items) |msg| {
                print("{s}error: {s}{s}{s}{s}\n", .{
                    red_bold_text, reset_text, red_dim_text, msg, reset_text,
                });
            }
        }

        // Render compile errors at the bottom of the terminal.
        // TODO: use the same ttyconf from the builder.
        const ttyconf: std.io.tty.Config = if (use_color_escapes)
            .escape_codes
        else
            .no_color;
        if (self.step.result_error_bundle.errorMessageCount() > 0) {
            self.step.result_error_bundle.renderToStdErr(.{ .ttyconf = ttyconf });
        }
    }
};

/// Clears the entire line and move the cursor to column zero.
/// Used for clearing the compiler and build_runner progress messages.
fn resetLine() void {
    if (use_color_escapes) print("{s}", .{"\x1b[2K\r"});
}

/// Removes trailing whitespace for each line in buf, also ensuring that there
/// are no trailing LF characters at the end.
pub fn trimLines(allocator: std.mem.Allocator, buf: []const u8) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, buf.len);

    var iter = std.mem.split(u8, buf, " \n");
    while (iter.next()) |line| {
        // TODO: trimming CR characters is probably not necessary.
        const data = std.mem.trimRight(u8, line, " \r");
        try list.appendSlice(data);
        try list.append('\n');
    }

    const result = try list.toOwnedSlice(); // TODO: probably not necessary

    // Remove the trailing LF character, that is always present in the exercise
    // output.
    return std.mem.trimRight(u8, result, "\n");
}

/// Prints a message to stderr.
const PrintStep = struct {
    step: Step,
    message: []const u8,

    pub fn create(owner: *Build, message: []const u8) *PrintStep {
        const self = owner.allocator.create(PrintStep) catch @panic("OOM");
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = "print",
                .owner = owner,
                .makeFn = make,
            }),
            .message = message,
        };

        return self;
    }

    fn make(step: *Step, _: *std.Progress.Node) !void {
        const self = @fieldParentPtr(PrintStep, "step", step);

        print("{s}", .{self.message});
    }
};

/// Checks that each exercise number, excluding the last, forms the sequence
/// `[1, exercise.len)`.
///
/// Additionally check that the output field lines doesn't have trailing whitespace.
fn validate_exercises() bool {
    // Don't use the "multi-object for loop" syntax, in order to avoid a syntax
    // error with old Zig compilers.
    var i: usize = 0;
    for (days[0..]) |ex| {
        const exno = ex.number();
        const last = 25;
        i += 1;

        if (exno != i and exno != last) {
            print("exercise {s} has an incorrect number: expected {}, got {s}\n", .{
                ex.main_file, i, ex.key(),
            });

            return false;
        }

        var iter = std.mem.split(u8, ex.output, "\n");
        while (iter.next()) |line| {
            const output = std.mem.trimRight(u8, line, " \r");
            if (output.len != line.len) {
                print("exercise {s} output field lines have trailing whitespace\n", .{
                    ex.main_file,
                });

                return false;
            }
        }

        if (!std.mem.endsWith(u8, ex.main_file, ".zig")) {
            print("exercise {s} is not a zig source file\n", .{ex.main_file});

            return false;
        }
    }

    return true;
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
//pub fn build(b: *std.Build) void {
// Standard target options allows the person running `zig build` to choose
// what target to build for. Here we do not override the defaults, which
// means any target is allowed, and the default is native. Other options
// for restricting supported target set are available.
//const target = b.standardTargetOptions(.{});

// Standard optimization options allow the person running `zig build` to select
// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
// set a preferred release mode, allowing the user to decide how to optimize.
//const optimize = b.standardOptimizeOption(.{});
//for (1..26) |i| {
//    const dayString = b.fmt("Day{:0>2}", .{i});
//    const zigFile = b.fmt("src/{s}.zig", .{dayString});
//    const exe = b.addExecutable(.{
//        .name = dayString,
//        .root_source_file = .{ .path = zigFile },
//        .target = target,
//        .optimize = optimize,
//    });
//    b.installArtifact(exe);

//    const run_cmd = b.addRunArtifact(exe);
//    run_cmd.step.dependOn(b.getInstallStep());
//    if (b.args) |args| {
//        run_cmd.addArgs(args);
//    }
//    const run_desc = b.fmt("Run {s}", .{dayString});
//    const run_step = b.step(dayString, run_desc);
//    run_step.dependOn(&run_cmd.step);
//}

// Creates a step for unit testing. This only builds the test executable
// but does not run it.
//const unit_tests = b.addTest(.{
//    .root_source_file = .{ .path = "src/main.zig" },
//    .target = target,
//    .optimize = optimize,
//});

//const run_unit_tests = b.addRunArtifact(unit_tests);

// Similar to creating the run step earlier, this exposes a `test` step to
// the `zig build --help` menu, providing a way for the user to request
// running the unit tests.
// const test_step = b.step("test", "Run unit tests");
//test_step.dependOn(&run_unit_tests.step);
//}
//
const days = [_]Day{
    .{
        .main_file = "Day01.zig",
    },
    .{
        .main_file = "Day02.zig",
    },
    .{
        .main_file = "Day03.zig",
    },
    .{
        .main_file = "Day04.zig",
    },
    .{
        .main_file = "Day05.zig",
    },
    .{
        .main_file = "Day06.zig",
    },
    .{
        .main_file = "Day07.zig",
    },
    .{
        .main_file = "Day08.zig",
    },
    .{
        .main_file = "Day09.zig",
    },
    .{
        .main_file = "Day10.zig",
    },
    .{
        .main_file = "Day11.zig",
    },
    .{
        .main_file = "Day12.zig",
    },
    .{
        .main_file = "Day13.zig",
    },
    .{
        .main_file = "Day14.zig",
    },
    .{
        .main_file = "Day15.zig",
    },
    .{
        .main_file = "Day16.zig",
    },
    .{
        .main_file = "Day17.zig",
    },
    .{
        .main_file = "Day18.zig",
    },
    .{
        .main_file = "Day19.zig",
    },
    .{
        .main_file = "Day20.zig",
    },
    .{
        .main_file = "Day21.zig",
    },
    .{
        .main_file = "Day22.zig",
    },
    .{
        .main_file = "Day23.zig",
    },
    .{
        .main_file = "Day24.zig",
    },
    .{
        .main_file = "Day25.zig",
    },
};
