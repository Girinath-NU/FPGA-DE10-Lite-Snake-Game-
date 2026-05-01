module games (
    input  logic        MAX10_CLK1_50,
    input  logic [4:0]  KEY,
    input  logic [3:0]  GPIO_IN,           // Player 1: GPIO_0[3:0] on JP1
                                            // [0]=Up [1]=Down [2]=Left [3]=Right
    input  logic [3:0]  GPIO_IN2,          // Player 2: GPIO_1[3:0] on JP2
                                            // [0]=Up [1]=Down [2]=Left [3]=Right
    output logic [3:0]  VGA_R,
    output logic [3:0]  VGA_G,
    output logic [3:0]  VGA_B,
    output logic        VGA_HS,
    output logic        VGA_VS
);

// ---------------------------------------------------------------------------
// 1.  25 MHz pixel clock
// ---------------------------------------------------------------------------
logic vga_clk;
initial vga_clk = 1'b0;
always_ff @(posedge MAX10_CLK1_50)
    vga_clk <= ~vga_clk;

// ---------------------------------------------------------------------------
// 2.  VGA timing  (800 x 525 total, 640 x 480 visible)
// ---------------------------------------------------------------------------
localparam H_VISIBLE = 10'd640;
localparam H_FRONT   = 10'd16;
localparam H_SYNC    = 10'd96;
localparam H_BACK    = 10'd48;
localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;

localparam V_VISIBLE = 10'd480;
localparam V_FRONT   = 10'd10;
localparam V_SYNC    = 10'd2;
localparam V_BACK    = 10'd33;
localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

logic [9:0] hcount, vcount;
initial hcount = 10'd0;
initial vcount = 10'd0;

always_ff @(posedge vga_clk) begin
    if (hcount == H_TOTAL - 1) begin
        hcount <= 10'd0;
        vcount <= (vcount == V_TOTAL - 1) ? 10'd0 : vcount + 10'd1;
    end else
        hcount <= hcount + 10'd1;
end

assign VGA_HS = ~(hcount >= H_VISIBLE + H_FRONT &&
                  hcount <  H_VISIBLE + H_FRONT + H_SYNC);
assign VGA_VS = ~(vcount >= V_VISIBLE + V_FRONT &&
                  vcount <  V_VISIBLE + V_FRONT + V_SYNC);

logic display_on;
assign display_on = (hcount < H_VISIBLE) && (vcount < V_VISIBLE);

// ---------------------------------------------------------------------------
// 3.  Grid constants
// ---------------------------------------------------------------------------
localparam [9:0] GRID_X0   = 10'd10;
localparam [9:0] GRID_X1   = 10'd630;
localparam [9:0] GRID_Y0   = 10'd20;
localparam [9:0] GRID_Y1   = 10'd470;
localparam [5:0] GRID_COLS = 6'd62;
localparam [5:0] GRID_ROWS = 6'd45;
localparam [6:0] MAX_SNAKE = 7'd64;

// ---------------------------------------------------------------------------
// 4.  LFSR
// ---------------------------------------------------------------------------
logic [15:0] lfsr;
initial lfsr = 16'hACE1;
always_ff @(posedge vga_clk)
    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

function automatic [9:0] rand_apple_x;
    input [15:0] r;
    logic [5:0] col;
    begin
        col = r[5:0] % GRID_COLS;
        rand_apple_x = GRID_X0 + ({4'b0, col} * 10);
    end
endfunction

function automatic [9:0] rand_apple_y;
    input [15:0] r;
    logic [5:0] row;
    begin
        row = r[11:6] % GRID_ROWS;
        rand_apple_y = GRID_Y0 + ({4'b0, row} * 10);
    end
endfunction

// ---------------------------------------------------------------------------
// 5.  KEY debounce  (~1 ms at 25 MHz, active-low)
// ---------------------------------------------------------------------------
localparam [16:0] DB_COUNT = 17'd25000;

logic [4:0] btn_sync0, btn_sync1, btn_db, btn_db_prev;
logic [16:0] db_cnt [0:4];

initial begin
    btn_db      = 5'b11111;
    btn_sync0   = 5'b11111;
    btn_sync1   = 5'b11111;
    btn_db_prev = 5'b11111;
    db_cnt[0]=0; db_cnt[1]=0; db_cnt[2]=0; db_cnt[3]=0; db_cnt[4]=0;
end

always_ff @(posedge vga_clk) begin
    btn_sync0 <= KEY;
    btn_sync1 <= btn_sync0;
end

genvar b;
generate
    for (b = 0; b < 5; b++) begin : debounce_key
        always_ff @(posedge vga_clk) begin
            if (btn_sync1[b] == btn_db[b])
                db_cnt[b] <= 17'd0;
            else begin
                db_cnt[b] <= db_cnt[b] + 17'd1;
                if (db_cnt[b] >= DB_COUNT - 1) begin
                    db_cnt[b] <= 17'd0;
                    btn_db[b] <= btn_sync1[b];
                end
            end
        end
    end
endgenerate

always_ff @(posedge vga_clk)
    btn_db_prev <= btn_db;

// KEY falling-edge detection (active-low: 1→0 = press)
logic rst_press;
assign rst_press = btn_db_prev[4] & ~btn_db[4];

// ---------------------------------------------------------------------------
// 5b. GPIO debounce — Player 1  (~1 ms at 25 MHz, active-high)
//     [0]=Up  [1]=Down  [2]=Left  [3]=Right
// ---------------------------------------------------------------------------
logic [3:0] gpio_sync0, gpio_sync1, gpio_db, gpio_db_prev;
logic [16:0] gpio_cnt [0:3];

initial begin
    gpio_db      = 4'b0000;
    gpio_sync0   = 4'b0000;
    gpio_sync1   = 4'b0000;
    gpio_db_prev = 4'b0000;
    gpio_cnt[0]=0; gpio_cnt[1]=0; gpio_cnt[2]=0; gpio_cnt[3]=0;
end

always_ff @(posedge vga_clk) begin
    gpio_sync0 <= GPIO_IN;
    gpio_sync1 <= gpio_sync0;
end

genvar g;
generate
    for (g = 0; g < 4; g++) begin : debounce_gpio
        always_ff @(posedge vga_clk) begin
            if (gpio_sync1[g] == gpio_db[g])
                gpio_cnt[g] <= 17'd0;
            else begin
                gpio_cnt[g] <= gpio_cnt[g] + 17'd1;
                if (gpio_cnt[g] >= DB_COUNT - 1) begin
                    gpio_cnt[g] <= 17'd0;
                    gpio_db[g]  <= gpio_sync1[g];
                end
            end
        end
    end
endgenerate

always_ff @(posedge vga_clk)
    gpio_db_prev <= gpio_db;

// GPIO1 rising-edge (P1)
logic up_press_p1, dn_press_p1, lt_press_p1, rt_press_p1;
assign up_press_p1 = ~gpio_db_prev[0] & gpio_db[0];
assign dn_press_p1 = ~gpio_db_prev[1] & gpio_db[1];
assign lt_press_p1 = ~gpio_db_prev[2] & gpio_db[2];
assign rt_press_p1 = ~gpio_db_prev[3] & gpio_db[3];

// ---------------------------------------------------------------------------
// 5c. GPIO debounce — Player 2  (~1 ms at 25 MHz, active-high)
//     [0]=Up  [1]=Down  [2]=Left  [3]=Right
// ---------------------------------------------------------------------------
logic [3:0] gpio2_sync0, gpio2_sync1, gpio2_db, gpio2_db_prev;
logic [16:0] gpio2_cnt [0:3];

initial begin
    gpio2_db      = 4'b0000;
    gpio2_sync0   = 4'b0000;
    gpio2_sync1   = 4'b0000;
    gpio2_db_prev = 4'b0000;
    gpio2_cnt[0]=0; gpio2_cnt[1]=0; gpio2_cnt[2]=0; gpio2_cnt[3]=0;
end

always_ff @(posedge vga_clk) begin
    gpio2_sync0 <= GPIO_IN2;
    gpio2_sync1 <= gpio2_sync0;
end

genvar g2;
generate
    for (g2 = 0; g2 < 4; g2++) begin : debounce_gpio2
        always_ff @(posedge vga_clk) begin
            if (gpio2_sync1[g2] == gpio2_db[g2])
                gpio2_cnt[g2] <= 17'd0;
            else begin
                gpio2_cnt[g2] <= gpio2_cnt[g2] + 17'd1;
                if (gpio2_cnt[g2] >= DB_COUNT - 1) begin
                    gpio2_cnt[g2] <= 17'd0;
                    gpio2_db[g2]  <= gpio2_sync1[g2];
                end
            end
        end
    end
endgenerate

always_ff @(posedge vga_clk)
    gpio2_db_prev <= gpio2_db;

// GPIO2 rising-edge (P2)
logic up_press_p2, dn_press_p2, lt_press_p2, rt_press_p2;
assign up_press_p2 = ~gpio2_db_prev[0] & gpio2_db[0];
assign dn_press_p2 = ~gpio2_db_prev[1] & gpio2_db[1];
assign lt_press_p2 = ~gpio2_db_prev[2] & gpio2_db[2];
assign rt_press_p2 = ~gpio2_db_prev[3] & gpio2_db[3];

// ---------------------------------------------------------------------------
// 6.  Power-on reset
// ---------------------------------------------------------------------------
logic [1:0] por_cnt;
logic       por_done;
initial begin
    por_cnt  = 2'd0;
    por_done = 1'b0;
end

always_ff @(posedge vga_clk) begin
    if (!por_done) begin
        if (por_cnt == 2'd3)
            por_done <= 1'b1;
        else
            por_cnt <= por_cnt + 2'd1;
    end
end

logic do_reset;
assign do_reset = ~por_done | rst_press;

// ---------------------------------------------------------------------------
// 7.  Game tick generator  (speed based on larger snake)
// ---------------------------------------------------------------------------
localparam [21:0] TICK_BASE = 22'd800_000;
localparam [21:0] TICK_STEP = 22'd5_000;
localparam [21:0] TICK_MIN  = 22'd100_000;

logic [6:0]  snake_size1, snake_size2;
logic [21:0] tick_limit;
logic [21:0] tick_cnt;
logic        update_tick;
logic        game_over;

initial begin
    tick_cnt    = 22'd0;
    update_tick = 1'b0;
    game_over   = 1'b0;
    snake_size1 = 7'd5;
    snake_size2 = 7'd5;
end

// Use the larger snake size to set speed
logic [6:0] max_snake_sz;
assign max_snake_sz = (snake_size1 >= snake_size2) ? snake_size1 : snake_size2;

always_comb begin
    automatic logic [21:0] red;
    red = TICK_STEP * {15'b0, max_snake_sz};
    tick_limit = (TICK_BASE > red + TICK_MIN) ? TICK_BASE - red : TICK_MIN;
end

always_ff @(posedge vga_clk) begin
    if (do_reset) begin
        tick_cnt    <= 22'd0;
        update_tick <= 1'b0;
    end else if (game_over) begin
        update_tick <= 1'b0;
    end else begin
        if (tick_cnt >= tick_limit - 1) begin
            tick_cnt    <= 22'd0;
            update_tick <= 1'b1;
        end else begin
            tick_cnt    <= tick_cnt + 22'd1;
            update_tick <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------------------
// 8.  Countdown timer — 2 minutes
// ---------------------------------------------------------------------------
localparam [26:0] SEC_CYCLES = 27'd25_000_000;
localparam [6:0]  GAME_SECS  = 7'd120;

logic [26:0] sec_cnt;
logic [6:0]  timer_secs;
logic        time_up;

initial begin
    sec_cnt    = 27'd0;
    timer_secs = GAME_SECS;
    time_up    = 1'b0;
end

always_ff @(posedge vga_clk) begin
    if (do_reset) begin
        sec_cnt    <= 27'd0;
        timer_secs <= GAME_SECS;
        time_up    <= 1'b0;
    end else if (!game_over && !time_up) begin
        if (sec_cnt >= SEC_CYCLES - 1) begin
            sec_cnt <= 27'd0;
            if (timer_secs > 7'd0)
                timer_secs <= timer_secs - 7'd1;
            else
                time_up <= 1'b1;
        end else begin
            sec_cnt <= sec_cnt + 27'd1;
        end
        if (timer_secs == 7'd0)
            time_up <= 1'b1;
    end
end

// ---------------------------------------------------------------------------
// 9.  Direction constants
// ---------------------------------------------------------------------------
localparam [1:0] DIR_UP    = 2'd0;
localparam [1:0] DIR_DOWN  = 2'd1;
localparam [1:0] DIR_LEFT  = 2'd2;
localparam [1:0] DIR_RIGHT = 2'd3;

// ---------------------------------------------------------------------------
// 10. Snake state + game logic
//     Player 1 starts center-right moving left
//     Player 2 starts center-left  moving right
// ---------------------------------------------------------------------------
logic [9:0]  snakeX1 [0:63],  snakeY1 [0:63];
logic [9:0]  snakeX2 [0:63],  snakeY2 [0:63];
logic [1:0]  dir1, next_dir1;
logic [1:0]  dir2, next_dir2;
logic [9:0]  appleX, appleY;
logic [15:0] score1, score2;

// Minimum snake size — never shrink below this
localparam [6:0] MIN_SNAKE = 7'd3;

integer i;

initial begin
    // P1 — starts at right half, heading left
    for (i = 0; i < 64; i++) begin
        snakeX1[i] = 10'd390 + (i * 10);   // head at 390, tail extends right
        snakeY1[i] = 10'd250;
    end
    // P2 — starts at left half, heading right
    for (i = 0; i < 64; i++) begin
        snakeX2[i] = 10'd250 - (i * 10);   // head at 250, tail extends left
        snakeY2[i] = 10'd250;
    end
    dir1       = DIR_LEFT;
    next_dir1  = DIR_LEFT;
    dir2       = DIR_RIGHT;
    next_dir2  = DIR_RIGHT;
    snake_size1 = 7'd5;
    snake_size2 = 7'd5;
    game_over  = 1'b0;
    score1     = 16'd0;
    score2     = 16'd0;
    appleX     = 10'd320;
    appleY     = 10'd110;
end

// ---------------------------------------------------------------------------
// 10a. Cross-collision helpers
//      p1_hits_p2 : head of P1 lands on any P2 body segment
//      p2_hits_p1 : head of P2 lands on any P1 body segment
//      Returns the segment index (1-based) that was hit, 0 = no hit
// ---------------------------------------------------------------------------
logic [6:0] p1_hit_seg;   // index in P2 array (0 = no hit)
logic [6:0] p2_hit_seg;   // index in P1 array (0 = no hit)

always_comb begin : cross_collision
    p1_hit_seg = 7'd0;
    p2_hit_seg = 7'd0;
    for (int j = 0; j < 64; j++) begin
        // P1 head vs P2 body
        if (j < snake_size2)
            if (snakeX1[0] == snakeX2[j] && snakeY1[0] == snakeY2[j])
                p1_hit_seg = j[6:0];
        // P2 head vs P1 body
        if (j < snake_size1)
            if (snakeX2[0] == snakeX1[j] && snakeY2[0] == snakeY1[j])
                p2_hit_seg = j[6:0];
    end
end

// ---------------------------------------------------------------------------
// 10b. Self-collision helpers
// ---------------------------------------------------------------------------
logic p1_self_hit, p2_self_hit;

always_comb begin : self_collision
    p1_self_hit = 1'b0;
    p2_self_hit = 1'b0;
    for (int j = 1; j < 64; j++) begin
        if (j < snake_size1)
            if (snakeX1[0] == snakeX1[j] && snakeY1[0] == snakeY1[j])
                p1_self_hit = 1'b1;
        if (j < snake_size2)
            if (snakeX2[0] == snakeX2[j] && snakeY2[0] == snakeY2[j])
                p2_self_hit = 1'b1;
    end
end

// ---------------------------------------------------------------------------
// 10c. Main game logic always block
// ---------------------------------------------------------------------------
always_ff @(posedge vga_clk) begin : game_logic

    if (do_reset) begin
        for (i = 0; i < 64; i++) begin
            snakeX1[i] <= 10'd390 + (i * 10);
            snakeY1[i] <= 10'd250;
            snakeX2[i] <= 10'd250 - (i * 10);
            snakeY2[i] <= 10'd250;
        end
        dir1        <= DIR_LEFT;
        next_dir1   <= DIR_LEFT;
        dir2        <= DIR_RIGHT;
        next_dir2   <= DIR_RIGHT;
        snake_size1 <= 7'd5;
        snake_size2 <= 7'd5;
        game_over   <= 1'b0;
        score1      <= 16'd0;
        score2      <= 16'd0;
        appleX      <= 10'd320;
        appleY      <= 10'd110;

    end else if (!game_over && !time_up) begin

        // ---- Direction input P1 ----
        if      (up_press_p1 && dir1 != DIR_DOWN)  next_dir1 <= DIR_UP;
        else if (dn_press_p1 && dir1 != DIR_UP)    next_dir1 <= DIR_DOWN;
        else if (lt_press_p1 && dir1 != DIR_RIGHT) next_dir1 <= DIR_LEFT;
        else if (rt_press_p1 && dir1 != DIR_LEFT)  next_dir1 <= DIR_RIGHT;

        // ---- Direction input P2 ----
        if      (up_press_p2 && dir2 != DIR_DOWN)  next_dir2 <= DIR_UP;
        else if (dn_press_p2 && dir2 != DIR_UP)    next_dir2 <= DIR_DOWN;
        else if (lt_press_p2 && dir2 != DIR_RIGHT) next_dir2 <= DIR_LEFT;
        else if (rt_press_p2 && dir2 != DIR_LEFT)  next_dir2 <= DIR_RIGHT;

        if (update_tick) begin
            dir1 <= next_dir1;
            dir2 <= next_dir2;

            // ---- Shift P1 body ----
            for (i = 63; i > 0; i--) begin
                if (i < snake_size1) begin
                    snakeX1[i] <= snakeX1[i-1];
                    snakeY1[i] <= snakeY1[i-1];
                end
            end

            // ---- Shift P2 body ----
            for (i = 63; i > 0; i--) begin
                if (i < snake_size2) begin
                    snakeX2[i] <= snakeX2[i-1];
                    snakeY2[i] <= snakeY2[i-1];
                end
            end

            // ---- Move P1 head (wrap) ----
            case (next_dir1)
                DIR_UP:    snakeY1[0] <= (snakeY1[0] <= GRID_Y0)      ? GRID_Y1 - 10 : snakeY1[0] - 10'd10;
                DIR_DOWN:  snakeY1[0] <= (snakeY1[0] >= GRID_Y1 - 10) ? GRID_Y0      : snakeY1[0] + 10'd10;
                DIR_LEFT:  snakeX1[0] <= (snakeX1[0] <= GRID_X0)      ? GRID_X1 - 10 : snakeX1[0] - 10'd10;
                DIR_RIGHT: snakeX1[0] <= (snakeX1[0] >= GRID_X1 - 10) ? GRID_X0      : snakeX1[0] + 10'd10;
            endcase

            // ---- Move P2 head (wrap) ----
            case (next_dir2)
                DIR_UP:    snakeY2[0] <= (snakeY2[0] <= GRID_Y0)      ? GRID_Y1 - 10 : snakeY2[0] - 10'd10;
                DIR_DOWN:  snakeY2[0] <= (snakeY2[0] >= GRID_Y1 - 10) ? GRID_Y0      : snakeY2[0] + 10'd10;
                DIR_LEFT:  snakeX2[0] <= (snakeX2[0] <= GRID_X0)      ? GRID_X1 - 10 : snakeX2[0] - 10'd10;
                DIR_RIGHT: snakeX2[0] <= (snakeX2[0] >= GRID_X1 - 10) ? GRID_X0      : snakeX2[0] + 10'd10;
            endcase

            // ---- Apple eaten by P1 ----
            if (snakeX1[0] == appleX && snakeY1[0] == appleY) begin
                if (snake_size1 < MAX_SNAKE)
                    snake_size1 <= snake_size1 + 7'd1;
                score1 <= score1 + 16'd10;
                appleX <= rand_apple_x(lfsr);
                appleY <= rand_apple_y(lfsr);
            end

            // ---- Apple eaten by P2 ----
            if (snakeX2[0] == appleX && snakeY2[0] == appleY) begin
                if (snake_size2 < MAX_SNAKE)
                    snake_size2 <= snake_size2 + 7'd1;
                score2 <= score2 + 16'd10;
                appleX <= rand_apple_x({lfsr[7:0], lfsr[15:8]});  // different seed offset
                appleY <= rand_apple_y({lfsr[7:0], lfsr[15:8]});
            end

            // ---- Cross-collision: P1 head hits P2 body ----
            // Shrink P2 from the hit point to the end; P1 gains a point
            if (p1_hit_seg != 7'd0) begin
                // Truncate P2 to (hit_segment) segments — keep [0 .. hit_seg-1]
                if (p1_hit_seg > MIN_SNAKE)
                    snake_size2 <= p1_hit_seg;
                else
                    snake_size2 <= MIN_SNAKE;
                score1 <= score1 + 16'd5;
            end

            // ---- Cross-collision: P2 head hits P1 body ----
            if (p2_hit_seg != 7'd0) begin
                if (p2_hit_seg > MIN_SNAKE)
                    snake_size1 <= p2_hit_seg;
                else
                    snake_size1 <= MIN_SNAKE;
                score2 <= score2 + 16'd5;
            end

            // ---- Head-on collision (both heads meet) — game over ----
            if (snakeX1[0] == snakeX2[0] && snakeY1[0] == snakeY2[0])
                game_over <= 1'b1;

            // ---- Self-collision → game over for that player ----
            if (p1_self_hit || p2_self_hit)
                game_over <= 1'b1;

        end // update_tick

    end else begin
        if (time_up)
            game_over <= 1'b1;
    end

end // game_logic

// ---------------------------------------------------------------------------
// 11. 3x5 bitmap digit renderer
// ---------------------------------------------------------------------------
function automatic pixel_in_digit;
    input [3:0] digit;
    input [2:0] row;
    input [1:0] col;
    reg [2:0] bm [0:9][0:4];
    begin
        bm[0][0]=3'b111; bm[0][1]=3'b101; bm[0][2]=3'b101; bm[0][3]=3'b101; bm[0][4]=3'b111;
        bm[1][0]=3'b010; bm[1][1]=3'b110; bm[1][2]=3'b010; bm[1][3]=3'b010; bm[1][4]=3'b111;
        bm[2][0]=3'b111; bm[2][1]=3'b001; bm[2][2]=3'b111; bm[2][3]=3'b100; bm[2][4]=3'b111;
        bm[3][0]=3'b111; bm[3][1]=3'b001; bm[3][2]=3'b111; bm[3][3]=3'b001; bm[3][4]=3'b111;
        bm[4][0]=3'b101; bm[4][1]=3'b101; bm[4][2]=3'b111; bm[4][3]=3'b001; bm[4][4]=3'b001;
        bm[5][0]=3'b111; bm[5][1]=3'b100; bm[5][2]=3'b111; bm[5][3]=3'b001; bm[5][4]=3'b111;
        bm[6][0]=3'b111; bm[6][1]=3'b100; bm[6][2]=3'b111; bm[6][3]=3'b101; bm[6][4]=3'b111;
        bm[7][0]=3'b111; bm[7][1]=3'b001; bm[7][2]=3'b001; bm[7][3]=3'b001; bm[7][4]=3'b001;
        bm[8][0]=3'b111; bm[8][1]=3'b101; bm[8][2]=3'b111; bm[8][3]=3'b101; bm[8][4]=3'b111;
        bm[9][0]=3'b111; bm[9][1]=3'b101; bm[9][2]=3'b111; bm[9][3]=3'b001; bm[9][4]=3'b111;
        pixel_in_digit = bm[digit][row][2 - col];
    end
endfunction

// ---------------------------------------------------------------------------
// 12. Digit cell renderers
// ---------------------------------------------------------------------------
function automatic pix_digit_small;
    input [3:0] digit;
    input [9:0] ox, oy, px, py;
    logic [9:0] lx, ly;
    begin
        pix_digit_small = 1'b0;
        if (px >= ox && px < ox + 10'd8 && py >= oy && py < oy + 10'd12) begin
            lx = px - ox;
            ly = py - oy;
            if (lx >= 1 && lx <= 6 && ly >= 1 && ly <= 10)
                pix_digit_small = pixel_in_digit(digit,
                                                 (ly - 1) / 2,
                                                 (lx - 1) / 2);
        end
    end
endfunction

function automatic pix_digit_large;
    input [3:0] digit;
    input [9:0] ox, oy, px, py;
    logic [9:0] lx, ly;
    begin
        pix_digit_large = 1'b0;
        if (px >= ox && px < ox + 10'd14 && py >= oy && py < oy + 10'd22) begin
            lx = px - ox;
            ly = py - oy;
            if (lx >= 1 && lx <= 12 && ly >= 1 && ly <= 20)
                pix_digit_large = pixel_in_digit(digit,
                                                 (ly - 1) / 4,
                                                 (lx - 1) / 4);
        end
    end
endfunction

// ---------------------------------------------------------------------------
// 13. BCD decomposition — both players + timer
// ---------------------------------------------------------------------------
logic [3:0] s1_4, s1_3, s1_2, s1_1, s1_0;  // P1 score digits
logic [3:0] s2_4, s2_3, s2_2, s2_1, s2_0;  // P2 score digits
logic [3:0] tm2, tm1, tm0;

always_comb begin
    automatic logic [15:0] s;
    s    = score1;
    s1_4 = s / 10000; s = s % 10000;
    s1_3 = s / 1000;  s = s % 1000;
    s1_2 = s / 100;   s = s % 100;
    s1_1 = s / 10;
    s1_0 = s % 10;
end

always_comb begin
    automatic logic [15:0] s;
    s    = score2;
    s2_4 = s / 10000; s = s % 10000;
    s2_3 = s / 1000;  s = s % 1000;
    s2_2 = s / 100;   s = s % 100;
    s2_1 = s / 10;
    s2_0 = s % 10;
end

always_comb begin
    automatic logic [6:0] t;
    t   = timer_secs;
    tm2 = t / 100; t = t % 100;
    tm1 = t / 10;
    tm0 = t % 10;
end

// ---------------------------------------------------------------------------
// 14. Pixel signals
// ---------------------------------------------------------------------------
logic pix_border;
logic pix_head1,  pix_body1;   // P1 — cyan / green
logic pix_head2,  pix_body2;   // P2 — yellow / orange
logic pix_apple;
logic pix_score1, pix_score2, pix_timer;
logic pix_go_score1, pix_go_score2;

assign pix_border = (hcount < GRID_X0)   ||
                    (hcount >= GRID_X1)   ||
                    (vcount == GRID_Y0)   ||
                    (vcount >= GRID_Y1);

// Player 1 head
assign pix_head1 = (hcount >= snakeX1[0] && hcount < snakeX1[0] + 10 &&
                    vcount >= snakeY1[0] && vcount < snakeY1[0] + 10);

// Player 2 head
assign pix_head2 = (hcount >= snakeX2[0] && hcount < snakeX2[0] + 10 &&
                    vcount >= snakeY2[0] && vcount < snakeY2[0] + 10);

// Apple
assign pix_apple = (hcount >= appleX && hcount < appleX + 10 &&
                    vcount >= appleY && vcount < appleY + 10);

// Player 1 body
always_comb begin
    pix_body1 = 1'b0;
    for (int j = 1; j < 64; j++)
        if (j < snake_size1)
            if (hcount >= snakeX1[j] && hcount < snakeX1[j] + 10 &&
                vcount >= snakeY1[j] && vcount < snakeY1[j] + 10)
                pix_body1 = 1'b1;
end

// Player 2 body
always_comb begin
    pix_body2 = 1'b0;
    for (int j = 1; j < 64; j++)
        if (j < snake_size2)
            if (hcount >= snakeX2[j] && hcount < snakeX2[j] + 10 &&
                vcount >= snakeY2[j] && vcount < snakeY2[j] + 10)
                pix_body2 = 1'b1;
end

// ---------------------------------------------------------------------------
// 14b. HUD — score P1 (top-left, cyan), score P2 (top-right, yellow), timer (center-top)
// ---------------------------------------------------------------------------
// P1 score at x=15..55, y=4
always_comb begin
    pix_score1 = 1'b0;
    if (pix_digit_small(s1_4, 10'd15, 10'd4, hcount, vcount)) pix_score1 = 1'b1;
    if (pix_digit_small(s1_3, 10'd23, 10'd4, hcount, vcount)) pix_score1 = 1'b1;
    if (pix_digit_small(s1_2, 10'd31, 10'd4, hcount, vcount)) pix_score1 = 1'b1;
    if (pix_digit_small(s1_1, 10'd39, 10'd4, hcount, vcount)) pix_score1 = 1'b1;
    if (pix_digit_small(s1_0, 10'd47, 10'd4, hcount, vcount)) pix_score1 = 1'b1;
end

// P2 score at x=575..615, y=4
always_comb begin
    pix_score2 = 1'b0;
    if (pix_digit_small(s2_4, 10'd575, 10'd4, hcount, vcount)) pix_score2 = 1'b1;
    if (pix_digit_small(s2_3, 10'd583, 10'd4, hcount, vcount)) pix_score2 = 1'b1;
    if (pix_digit_small(s2_2, 10'd591, 10'd4, hcount, vcount)) pix_score2 = 1'b1;
    if (pix_digit_small(s2_1, 10'd599, 10'd4, hcount, vcount)) pix_score2 = 1'b1;
    if (pix_digit_small(s2_0, 10'd607, 10'd4, hcount, vcount)) pix_score2 = 1'b1;
end

// Timer at center-top x=305..325, y=4
always_comb begin
    pix_timer = 1'b0;
    if (pix_digit_small(tm2, 10'd305, 10'd4, hcount, vcount)) pix_timer = 1'b1;
    if (pix_digit_small(tm1, 10'd313, 10'd4, hcount, vcount)) pix_timer = 1'b1;
    if (pix_digit_small(tm0, 10'd321, 10'd4, hcount, vcount)) pix_timer = 1'b1;
end

// Game-over large scores: P1 left, P2 right
always_comb begin
    pix_go_score1 = 1'b0;
    if (pix_digit_large(s1_4, 10'd185, 10'd229, hcount, vcount)) pix_go_score1 = 1'b1;
    if (pix_digit_large(s1_3, 10'd199, 10'd229, hcount, vcount)) pix_go_score1 = 1'b1;
    if (pix_digit_large(s1_2, 10'd213, 10'd229, hcount, vcount)) pix_go_score1 = 1'b1;
    if (pix_digit_large(s1_1, 10'd227, 10'd229, hcount, vcount)) pix_go_score1 = 1'b1;
    if (pix_digit_large(s1_0, 10'd241, 10'd229, hcount, vcount)) pix_go_score1 = 1'b1;
end

always_comb begin
    pix_go_score2 = 1'b0;
    if (pix_digit_large(s2_4, 10'd385, 10'd229, hcount, vcount)) pix_go_score2 = 1'b1;
    if (pix_digit_large(s2_3, 10'd399, 10'd229, hcount, vcount)) pix_go_score2 = 1'b1;
    if (pix_digit_large(s2_2, 10'd413, 10'd229, hcount, vcount)) pix_go_score2 = 1'b1;
    if (pix_digit_large(s2_1, 10'd427, 10'd229, hcount, vcount)) pix_go_score2 = 1'b1;
    if (pix_digit_large(s2_0, 10'd441, 10'd229, hcount, vcount)) pix_go_score2 = 1'b1;
end

// ---------------------------------------------------------------------------
// 15. Colour output
// ---------------------------------------------------------------------------
always_comb begin
    if (!display_on)
        {VGA_R, VGA_G, VGA_B} = 12'h000;

    else if (game_over) begin
        // Dark red background; P1 score cyan-left, P2 score yellow-right
        if (pix_go_score1)
            {VGA_R, VGA_G, VGA_B} = 12'h0FF;   // cyan  = P1
        else if (pix_go_score2)
            {VGA_R, VGA_G, VGA_B} = 12'hFF0;   // yellow = P2
        else
            {VGA_R, VGA_G, VGA_B} = 12'h600;
    end

    else begin
        // HUD layer
        if (pix_score1)
            {VGA_R, VGA_G, VGA_B} = 12'h0FF;   // P1 score — cyan
        else if (pix_score2)
            {VGA_R, VGA_G, VGA_B} = 12'hFF0;   // P2 score — yellow
        else if (pix_timer)
            {VGA_R, VGA_G, VGA_B} = 12'hFFF;   // timer — white

        // Game objects (head drawn on top of body)
        else if (pix_head1)
            {VGA_R, VGA_G, VGA_B} = 12'h0FF;   // P1 head — bright cyan
        else if (pix_head2)
            {VGA_R, VGA_G, VGA_B} = 12'hFF0;   // P2 head — bright yellow
        else if (pix_body1)
            {VGA_R, VGA_G, VGA_B} = 12'h0A0;   // P1 body — green
        else if (pix_body2)
            {VGA_R, VGA_G, VGA_B} = 12'hA50;   // P2 body — orange
        else if (pix_apple)
            {VGA_R, VGA_G, VGA_B} = 12'hF20;   // apple — red-orange
        else if (pix_border)
            {VGA_R, VGA_G, VGA_B} = 12'h33F;   // border — blue
        else
            {VGA_R, VGA_G, VGA_B} = 12'h111;   // background — dark grey
    end
end

endmodule
