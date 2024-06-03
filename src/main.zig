const rl = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    const screen_width: i32 = 800;
    const screen_height: i32 = 450;

    rl.InitWindow(screen_width, screen_height, "Chip8-Emulator");
    defer rl.CloseWindow();

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.RAYWHITE);
    }
}
