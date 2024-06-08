const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});

pub const CPU = struct {
    key: [16]u8,
    gfx: [64 * 32]u8,

    pc: u16,
    opcode: u16,
    I: u12,
    sp: u16,

    memory: [4096]u8,
    stack: [16]u16,
    V: [16]u8,

    delay_timer: u8,
    sound_timer: u8,

    sound: rl.Sound,

    pub fn init(self: *CPU) void {
        self.pc = 0x200;
        self.opcode = 0;
        self.I = 0;
        self.sp = 0;

        @memset(&self.key, 0);
        @memset(&self.gfx, 0);
        @memset(&self.memory, 0);
        @memset(&self.stack, 0);
        @memset(&self.V, 0);

        for (0..chip8_fontset.len) |i| {
            self.memory[i] = chip8_fontset[i];
        }

        self.delay_timer = 0;
        self.sound_timer = 0;

        self.sound = rl.LoadSound("audio/chip8_sound.wav");
    }

    pub fn loadProgram(self: *CPU, sub_path: []const u8) !void {
        var buffer: [4096 - 512]u8 = undefined;
        const file = try std.fs.cwd().openFile(sub_path, .{});
        defer file.close();

        _ = try file.read(&buffer);

        for (0..buffer.len) |i| {
            self.memory[i + 512] = buffer[i];
        }
    }

    pub fn emulateCycle(self: *CPU) void {
        // Fetch opcode
        self.opcode = @as(u16, self.memory[self.pc]) << 8 | self.memory[self.pc + 1];

        const x = (self.opcode & 0x0F00) >> 8;
        const y = (self.opcode & 0x00F0) >> 4;

        // Decode opcode
        switch (self.opcode & 0xF000) {
            0x0000 => { // 0x0NNN: Calls machine code routine at address NNN
                switch (self.opcode & 0x000F) {
                    0x0000 => { // 0x00E0: Clears the screen
                        @memset(&self.gfx, 0);
                    },
                    0x000E => { // 0x00EE: Returns from subroutine
                        self.sp -= 1;
                        self.pc = self.stack[self.sp];
                    },
                    else => std.debug.panic("Unknown opcode\n", .{}),
                }
                self.pc += 2;
            },
            0x1000 => { // 0x1NNN jumps to address NNN
                self.pc = self.opcode & 0x0FFF;
            },
            0x2000 => { // 0x2NNN: Calls the subroutine at address NNN
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = self.opcode & 0x0FFF;
            },
            0x3000 => { // 0x3XNN: Skips the next instruction if VX equals NN
                if (self.V[x] == self.opcode & 0x00FF) {
                    self.pc += 4;
                } else {
                    self.pc += 2;
                }
            },
            0x4000 => { // 0x4XNN: Skips the next instruction if VX does not equal NN
                if (self.V[x] != self.opcode & 0x00FF) {
                    self.pc += 4;
                } else {
                    self.pc += 2;
                }
            },
            0x5000 => { // 0x5XY0: Skips the next instruction if VX equals VY
                if (self.V[x] == self.V[y]) {
                    self.pc += 4;
                } else {
                    self.pc += 2;
                }
            },
            0x6000 => { // 0x6XNN: Sets VX to NN
                self.V[x] = @truncate(self.opcode & 0x00FF);
                self.pc += 2;
            },
            0x7000 => { // 0x7XNN: Adds NN to VX
                // self.V[x] += @truncate(self.opcode & 0x00FF);
                self.V[x], _ = @addWithOverflow(self.V[x], @as(u8, @truncate(self.opcode & 0x00FF)));
                self.pc += 2;
            },
            0x8000 => {
                switch (self.opcode & 0x000F) {
                    0x0000 => { // 0x8XY0: Sets VX to the value of VY
                        self.V[x] = self.V[y];
                    },
                    0x0001 => { // 0x8XY1: Sets VX to VX OR VY (bitwise)
                        self.V[x] |= self.V[y];
                    },
                    0x0002 => { // 0x8XY2: Sets VX to VX AND VY (bitwise)
                        self.V[x] &= self.V[y];
                    },
                    0x0003 => { // 0x8XY3: Sets VX to VX XOR VY
                        self.V[x] ^= self.V[y];
                    },
                    0x0004 => { // 0x8XY4: Adds VY to VX. VF is set to 1 when there is an overflow and to 0 when there is not.
                        self.V[x], self.V[0xF] = @addWithOverflow(self.V[x], self.V[y]);
                    },
                    0x0005 => { // 0x8XY5: VY is subtracted from VX. VF is set to 0 when there is an underflow and to 1 when there is not.
                        self.V[x], self.V[0xF] = @subWithOverflow(self.V[x], self.V[y]);
                        if (self.V[0xF] == 1) { // convert carry to borrow bit
                            self.V[0xF] = 0;
                        } else {
                            self.V[0xF] = 1;
                        }
                    },
                    0x0006 => { // 0x8XY6: Shifts VX to the right by one. VF is set to the value of the least significant bit of VX before the shift.
                        self.V[0xF] = self.V[x] & 0x1;
                        self.V[x] >>= 1;
                    },
                    0x0007 => { // 0x8XY7: Sets VX to VY - VX. VF is set to 0 when there is an underflow and to 1 when there is not.
                        self.V[x], self.V[0xF] = @subWithOverflow(self.V[y], self.V[x]);
                        if (self.V[0xF] == 1) { // convert carry to borrow bit
                            self.V[0xF] = 0;
                        } else {
                            self.V[0xF] = 1;
                        }
                    },
                    0x000E => { // Shifts VX to the left by 1. Sets VF to 1 if the most significant bit of VX prior to that shift was set, 0 otherwise.
                        self.V[x], self.V[0xF] = @shlWithOverflow(self.V[x], 1);
                    },
                    else => std.debug.panic("Unknown opcode\n", .{}),
                }
                self.pc += 2;
            },
            0x9000 => { // 0x9XY0: Skips the next instruction if VX != VY
                if (self.V[x] != self.V[y]) {
                    self.pc += 4;
                } else {
                    self.pc += 2;
                }
            },
            0xA000 => { // 0xANNN: Sets I to the address NNN
                self.I = @truncate(self.opcode & 0x0FFF);
                self.pc += 2;
            },
            0xB000 => { // 0xBNNN: Jumps to the address NNN plus V0
                self.pc = self.V[0] + self.opcode & 0x0FFF;
            },
            0xC000 => { // 0xCXNN: Sets VX to the result of a bitwise AND operation on a random number and NN
                var seed = std.Random.DefaultPrng.init(@truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
                const prng = std.Random.DefaultPrng.random(&seed);
                self.V[x] = @truncate(std.Random.uintAtMost(prng, u8, 255) & (self.opcode & 0x00FF));
                self.pc += 2;
            },
            0xD000 => { // DXYN: Draws a sprite at coordinate (VX, VY) 8 pixels wide and N pixels high.
                //               Each row of 8 pixels is bit-coded starting from the memory location in stored in I.
                //               I does not change its value after this instruction. VF is set to 1 if screen pixels
                //               are flipped from set to unset when drawing and to 0 otherwise.
                const height: u16 = self.opcode & 0x000F;
                const width: u4 = 8;
                const msb: u8 = 0b1000_0000; // = 0x80, most significant bit (used to scan through a pixel byte bit by bit)
                var pixel: u16 = undefined;

                self.V[0xF] = 0;
                for (0..height) |yy| {
                    pixel = self.memory[self.I + yy];
                    for (0..width) |xx| {
                        if (pixel & (msb >> @as(u3, @intCast(xx))) != 0) {
                            const x_coord = (self.V[x] + xx) % 64; // wrap pixels when going over screen border
                            const y_coord = (self.V[y] + yy) % 32;

                            const idx = x_coord + y_coord * 64;
                            self.gfx[idx] ^= 1;

                            if (self.gfx[idx] == 0) {
                                self.V[0xF] = 1;
                            }
                        }
                    }
                }
                self.pc += 2;
            },
            0xE000 => { // Handles input
                switch (self.opcode & 0x00FF) {
                    0x009E => { // EX9E: Skips the next instruction if key stored in VX is pressed
                        if (self.key[self.V[x]] != 0) {
                            self.pc += 4;
                        } else {
                            self.pc += 2;
                        }
                    },
                    0x00A1 => { // EXA1: Skips the next instruction if the key stored in VX is not pressed
                        if (self.key[self.V[x]] == 0) {
                            self.pc += 4;
                        } else {
                            self.pc += 2;
                        }
                    },
                    else => std.debug.panic("Unkown opcode\n", .{}),
                }
            },
            0xF000 => {
                switch (self.opcode & 0x00FF) {
                    0x0007 => { // FX07: Sets VX to the value of the delay timer
                        self.V[x] = self.delay_timer;
                        self.pc += 2;
                    },
                    0x000A => { // FX0A: Waits for key press and stores it in VX (blocking operation)
                        var key_pressed = false;
                        for (0..self.key.len) |i| {
                            if (self.key[i] != 0) {
                                self.V[x] = @intCast(i);
                                self.pc += 2;
                                key_pressed = true;
                                break;
                            }
                        }
                        if (!key_pressed) {
                            return;
                        }
                    },
                    0x0015 => { // FX15: Sets the delay timer to VX
                        self.delay_timer = self.V[x];
                        self.pc += 2;
                    },
                    0x0018 => { // FX18: Sets the sound timer to VX
                        self.sound_timer = self.V[x];
                        self.pc += 2;
                    },
                    0x001E => { // FX1E: Adds VX to I. Does not affect VF (carry).
                        self.I += self.V[x];
                        self.pc += 2;
                    },
                    0x0029 => { // FX29: Sets I to the location of the sprite for the character in VX.
                        //               Characters 0x0-0xF are represented by a 4x5 font.
                        self.I = self.V[x] * 0x5;
                        self.pc += 2;
                    },
                    0x0033 => { // FX33: Stores the binary coded decimal representation of VX at the
                        //               addresses I (hundreds digit), I+1 (tens digit) and I+2 (ones digit)
                        self.memory[self.I] = self.V[x] / 100;
                        self.memory[self.I + 1] = (self.V[x] / 10) % 10;
                        self.memory[self.I + 2] = (self.V[x] % 100) % 10;
                        self.pc += 2;
                    },
                    0x0055 => { // FX55: Stores from V0 to VX in memory (starting at I)
                        var i: usize = 0;
                        while (i <= x) : (i += 1) {
                            self.memory[self.I + i] = self.V[i];
                        }
                        self.pc += 2;
                    },
                    0x0065 => { // FX65: Fills V0 to VX with values from memory (starting at I)
                        var i: usize = 0;
                        while (i <= x) : (i += 1) {
                            self.V[i] = self.memory[self.I + i];
                        }
                        self.pc += 2;
                    },
                    else => std.debug.panic("Unkown opcode\n", .{}),
                }
            },
            else => std.debug.panic("Unknown opcode\n", .{}),
        }

        // Update timers
        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }
        if (self.sound_timer > 0) {
            if (self.sound_timer == 1) {
                if (!rl.IsSoundPlaying(self.sound)) {
                    rl.PlaySound(self.sound);
                }
            }
            self.sound_timer -= 1;
        }
    }
};

const chip8_fontset = [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, //0
    0x20, 0x60, 0x20, 0x20, 0x70, //1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, //2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, //3
    0x90, 0x90, 0xF0, 0x10, 0x10, //4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, //5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, //6
    0xF0, 0x10, 0x20, 0x40, 0x40, //7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, //8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, //9
    0xF0, 0x90, 0xF0, 0x90, 0x90, //A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, //B
    0xF0, 0x80, 0x80, 0x80, 0xF0, //C
    0xE0, 0x90, 0x90, 0x90, 0xE0, //D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, //E
    0xF0, 0x80, 0xF0, 0x80, 0x80, //F
};

// Keypad                   Keyboard
// +-+-+-+-+                +-+-+-+-+
// |1|2|3|C|                |1|2|3|4|
// +-+-+-+-+                +-+-+-+-+
// |4|5|6|D|                |Q|W|E|R|
// +-+-+-+-+       =>       +-+-+-+-+
// |7|8|9|E|                |A|S|D|F|
// +-+-+-+-+                +-+-+-+-+
// |A|0|B|F|                |Y|X|C|V|
// +-+-+-+-+                +-+-+-+-+
pub const keymap: [16]c_int = .{
    rl.KEY_X,
    rl.KEY_ONE,
    rl.KEY_TWO,
    rl.KEY_THREE,
    rl.KEY_Q,
    rl.KEY_W,
    rl.KEY_E,
    rl.KEY_A,
    rl.KEY_S,
    rl.KEY_D,
    rl.KEY_Y,
    rl.KEY_C,
    rl.KEY_FOUR,
    rl.KEY_R,
    rl.KEY_F,
    rl.KEY_V,
};
