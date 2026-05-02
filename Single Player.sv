module game (
    input  logic        MAX10_CLK1_50,
    input  logic [4:0]  KEY,
    input  logic [3:0]  GPIO_IN,          // GPIO_0[3:0] on JP1
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
logic up_press_key, dn_press_key, rt_press_key, lt_press_key, rst_press;
assign up_press_key = btn_db_prev[0] & ~btn_db[0];
assign dn_press_key = btn_db_prev[1] & ~btn_db[1];
assign rt_press_key = btn_db_prev[2] & ~btn_db[2];
assign lt_press_key = btn_db_prev[3] & ~btn_db[3];
assign rst_press    = btn_db_prev[4] & ~btn_db[4];

// ---------------------------------------------------------------------------
// 5b. GPIO debounce  (~1 ms at 25 MHz, active-high)
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

// GPIO rising-edge detection (active-high: 0→1 = press)
logic up_press_gpio, dn_press_gpio, lt_press_gpio, rt_press_gpio;
assign up_press_gpio = ~gpio_db_prev[0] & gpio_db[0];   // [0]=Up
assign dn_press_gpio = ~gpio_db_prev[1] & gpio_db[1];   // [1]=Down
assign lt_press_gpio = ~gpio_db_prev[2] & gpio_db[2];   // [2]=Left
assign rt_press_gpio = ~gpio_db_prev[3] & gpio_db[3];   // [3]=Right

// ---------------------------------------------------------------------------
// 5c. Merged directional press signals (KEY OR GPIO)
// ---------------------------------------------------------------------------
logic up_press, dn_press, lt_press, rt_press;
assign up_press = up_press_key | up_press_gpio;
assign dn_press = dn_press_key | dn_press_gpio;
assign lt_press = lt_press_key | lt_press_gpio;
assign rt_press = rt_press_key | rt_press_gpio;

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
// 7.  Game tick generator
// ---------------------------------------------------------------------------
localparam [21:0] TICK_BASE = 22'd800_000;
localparam [21:0] TICK_STEP = 22'd5_000;
localparam [21:0] TICK_MIN  = 22'd100_000;

logic [6:0]  snake_size;
logic [21:0] tick_limit;
logic [21:0] tick_cnt;
logic        update_tick;
logic        game_over;

initial begin
    tick_cnt    = 22'd0;
    update_tick = 1'b0;
    game_over   = 1'b0;
    snake_size  = 7'd5;
end

always_comb begin
    automatic logic [21:0] red;
    red = TICK_STEP * {15'b0, snake_size};
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
// ---------------------------------------------------------------------------
logic [9:0]  snakeX [0:63];
logic [9:0]  snakeY [0:63];
logic [1:0]  direction, next_dir;
logic [9:0]  appleX, appleY;
logic [15:0] score;

integer i;

initial begin
    for (i = 0; i < 64; i++) begin
        snakeX[i] = 10'd310 - (i * 10);
        snakeY[i] = 10'd250;
    end
    direction  = DIR_RIGHT;
    next_dir   = DIR_RIGHT;
    snake_size = 7'd5;
    game_over  = 1'b0;
    score      = 16'd0;
    appleX     = 10'd200;
    appleY     = 10'd110;
end

always_ff @(posedge vga_clk) begin : game_logic

    if (do_reset) begin
        for (i = 0; i < 64; i++) begin
            snakeX[i] <= 10'd310 - (i * 10);
            snakeY[i] <= 10'd250;
        end
        direction  <= DIR_RIGHT;
        next_dir   <= DIR_RIGHT;
        snake_size <= 7'd5;
        game_over  <= 1'b0;
        score      <= 16'd0;
        appleX     <= 10'd200;
        appleY     <= 10'd110;

    end else if (!game_over && !time_up) begin

        // Direction input — merged KEY + GPIO
        if      (up_press && direction != DIR_DOWN)  next_dir <= DIR_UP;
        else if (dn_press && direction != DIR_UP)    next_dir <= DIR_DOWN;
        else if (lt_press && direction != DIR_RIGHT) next_dir <= DIR_LEFT;
        else if (rt_press && direction != DIR_LEFT)  next_dir <= DIR_RIGHT;

        if (update_tick) begin
            direction <= next_dir;

            for (i = 63; i > 0; i--) begin
                if (i < snake_size) begin
                    snakeX[i] <= snakeX[i-1];
                    snakeY[i] <= snakeY[i-1];
                end
            end

            case (next_dir)
                DIR_UP:    snakeY[0] <= (snakeY[0] <= GRID_Y0)      ? GRID_Y1 - 10 : snakeY[0] - 10'd10;
                DIR_DOWN:  snakeY[0] <= (snakeY[0] >= GRID_Y1 - 10) ? GRID_Y0      : snakeY[0] + 10'd10;
                DIR_LEFT:  snakeX[0] <= (snakeX[0] <= GRID_X0)      ? GRID_X1 - 10 : snakeX[0] - 10'd10;
                DIR_RIGHT: snakeX[0] <= (snakeX[0] >= GRID_X1 - 10) ? GRID_X0      : snakeX[0] + 10'd10;
            endcase

            if (snakeX[0] == appleX && snakeY[0] == appleY) begin
                if (snake_size < MAX_SNAKE)
                    snake_size <= snake_size + 7'd1;
                score  <= score + 16'd10;
                appleX <= rand_apple_x(lfsr);
                appleY <= rand_apple_y(lfsr);
            end

            for (i = 1; i < 64; i++) begin
                if (i < snake_size)
                    if (snakeX[0] == snakeX[i] && snakeY[0] == snakeY[i])
                        game_over <= 1'b1;
            end
        end

    end else begin
        if (time_up)
            game_over <= 1'b1;
    end

end

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
// 13. BCD decomposition
// ---------------------------------------------------------------------------
logic [3:0] sc4, sc3, sc2, sc1, sc0;
logic [3:0] tm2, tm1, tm0;

always_comb begin
    automatic logic [15:0] s;
    s   = score;
    sc4 = s / 10000; s = s % 10000;
    sc3 = s / 1000;  s = s % 1000;
    sc2 = s / 100;   s = s % 100;
    sc1 = s / 10;
    sc0 = s % 10;
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
logic pix_border, pix_head, pix_body, pix_apple;
logic pix_score, pix_timer, pix_go_score;

assign pix_border = (hcount < GRID_X0)   ||
                    (hcount >= GRID_X1)   ||
                    (vcount < GRID_Y0 && (hcount < GRID_X0 || hcount >= GRID_X1)) ||
                    (vcount == GRID_Y0)   ||
                    (vcount >= GRID_Y1);

assign pix_head  = (hcount >= snakeX[0] && hcount < snakeX[0] + 10 &&
                    vcount >= snakeY[0] && vcount < snakeY[0] + 10);

assign pix_apple = (hcount >= appleX && hcount < appleX + 10 &&
                    vcount >= appleY && vcount < appleY + 10);

always_comb begin
    pix_body = 1'b0;
    for (int j = 1; j < 64; j++)
        if (j < snake_size)
            if (hcount >= snakeX[j] && hcount < snakeX[j] + 10 &&
                vcount >= snakeY[j] && vcount < snakeY[j] + 10)
                pix_body = 1'b1;
end

always_comb begin
    pix_score = 1'b0;
    if (pix_digit_small(sc4, 10'd15, 10'd4, hcount, vcount)) pix_score = 1'b1;
    if (pix_digit_small(sc3, 10'd23, 10'd4, hcount, vcount)) pix_score = 1'b1;
    if (pix_digit_small(sc2, 10'd31, 10'd4, hcount, vcount)) pix_score = 1'b1;
    if (pix_digit_small(sc1, 10'd39, 10'd4, hcount, vcount)) pix_score = 1'b1;
    if (pix_digit_small(sc0, 10'd47, 10'd4, hcount, vcount)) pix_score = 1'b1;
end

always_comb begin
    pix_timer = 1'b0;
    if (pix_digit_small(tm2, 10'd601, 10'd4, hcount, vcount)) pix_timer = 1'b1;
    if (pix_digit_small(tm1, 10'd609, 10'd4, hcount, vcount)) pix_timer = 1'b1;
    if (pix_digit_small(tm0, 10'd617, 10'd4, hcount, vcount)) pix_timer = 1'b1;
end

always_comb begin
    pix_go_score = 1'b0;
    if (pix_digit_large(sc4, 10'd285, 10'd229, hcount, vcount)) pix_go_score = 1'b1;
    if (pix_digit_large(sc3, 10'd299, 10'd229, hcount, vcount)) pix_go_score = 1'b1;
    if (pix_digit_large(sc2, 10'd313, 10'd229, hcount, vcount)) pix_go_score = 1'b1;
    if (pix_digit_large(sc1, 10'd327, 10'd229, hcount, vcount)) pix_go_score = 1'b1;
    if (pix_digit_large(sc0, 10'd341, 10'd229, hcount, vcount)) pix_go_score = 1'b1;
end

// ---------------------------------------------------------------------------
// 15. Colour output
// ---------------------------------------------------------------------------
always_comb begin
    if (!display_on)
        {VGA_R, VGA_G, VGA_B} = 12'h000;
    else if (game_over) begin
        if (pix_go_score)
            {VGA_R, VGA_G, VGA_B} = 12'hFFF;
        else
            {VGA_R, VGA_G, VGA_B} = 12'hA00;
    end
    else if (pix_score || pix_timer)
        {VGA_R, VGA_G, VGA_B} = 12'hFF0;
    else if (pix_head)
        {VGA_R, VGA_G, VGA_B} = 12'h0FF;
    else if (pix_body)
        {VGA_R, VGA_G, VGA_B} = 12'h0A0;
    else if (pix_apple)
        {VGA_R, VGA_G, VGA_B} = 12'hF20;
    else if (pix_border)
        {VGA_R, VGA_G, VGA_B} = 12'h33F;
    else
        {VGA_R, VGA_G, VGA_B} = 12'h111;
end

endmodule
