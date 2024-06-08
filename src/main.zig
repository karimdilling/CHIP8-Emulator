const rl = @cImport({
    @cInclude("raylib.h");
});
const std = @import("std");
const chip8 = @import("chip8.zig");

pub fn main() !void {
    const scale = 10;
    const chip8_width = 64;
    const chip_height = 32;
    const screen_width = chip8_width * scale;
    const screen_height = chip_height * scale;

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();

    var cpu: chip8.CPU = undefined;
    chip8.CPU.init(&cpu);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const program = try progFromCmdLine(gpa.allocator());
    defer gpa.allocator().free(program);

    try cpu.loadProgram(program);

    rl.InitWindow(screen_width, screen_height, "Chip8-Emulator");
    defer rl.CloseWindow();

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        cpu.emulateCycle();

        check_input(&cpu);

        rl.BeginDrawing();
        defer rl.EndDrawing();

        for (0..cpu.gfx.len) |i| {
            if (cpu.gfx[i] == 1) {
                const row = i / chip8_width;
                const col = i % chip8_width;
                rl.DrawRectangle(@as(c_int, @intCast(col * scale)), @as(c_int, @intCast(row * scale)), scale, scale, rl.WHITE);
            }
        }
        rl.ClearBackground(rl.BLACK);
    }
    rl.UnloadSound(cpu.sound);
}

fn progFromCmdLine(allocator: std.mem.Allocator) ![]u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const program = args.next() orelse return error.NoProgramToLoad;
    return allocator.dupe(u8, program);
}

fn check_input(cpu: *chip8.CPU) void {
    for (chip8.keymap, 0..chip8.keymap.len) |key, i| {
        if (rl.IsKeyDown(key)) {
            cpu.key[i] = 1;
        }
        if (rl.IsKeyUp(key)) {
            cpu.key[i] = 0;
        }
    }
}
