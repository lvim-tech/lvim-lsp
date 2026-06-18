-- lvim-lsp.ui.float: the shared house chrome for a NATIVE floating preview — used by the hover and the
-- diagnostic floats (current / next / prev). Given a float already opened by `vim.lsp.util.open_floating_
-- preview` or `vim.diagnostic.open_float` (unfocused, cursor-anchored, auto-closing — the native behaviour),
-- `dress()` applies the palette (border bg, tinted title) + a 1-row air gap under the title + a DYNAMIC
-- footer that reads `K select` while the float is unfocused (press the trigger key to enter & scroll) and
-- `q close` once it is the current window. Idempotent per window: a 2nd invocation re-focuses the SAME
-- float (native `focus_id`) and is left untouched (else it would stack another air row each time).
--
---@module "lvim-lsp.ui.float"

local cursor = require("lvim-utils.cursor")

local api = vim.api

local M = {}

-- House border: a full " " ring (subtle palette padding, no hard lines). The native float helpers validate
-- the border strictly (every edge needs its corners), so this must be a complete ring; " " keeps it
-- visually borderless. Pass it as the `border` opt when OPENING the float.
M.border = { " ", " ", " ", " ", " ", " ", " ", " " }

--- Footer chunks for a row of `{ key, name }` buttons (`key` blue badge + `name` yellow label).
---@param buttons table[]
---@return table[]
local function footer_chunks(buttons)
    local out = {}
    for _, b in ipairs(buttons) do
        out[#out + 1] = { " " .. b.key .. " ", "LvimUiFooterKey" }
        out[#out + 1] = { (b.name or "") .. " ", "LvimUiFooterLabel" }
    end
    return out
end

--- Resolve a max dimension: a fraction ≤ 1 of `total`, or an absolute count.
---@param v number|nil
---@param total integer
---@return integer|nil
function M.dim(v, total)
    if not v then
        return nil
    end
    return v <= 1 and math.floor(total * v) or math.floor(v)
end

--- Apply the house chrome to a native float. Idempotent per window.
---@param winid integer|nil  the float window (from open_floating_preview / open_float)
---@param bufnr integer|nil  the float buffer
---@param opts? { title?: string|false, conceal?: boolean, air_bottom?: boolean, select?: table|false, actions?: table[], focus?: table }
---       title text (false = none); conceal = keep markdown markers hidden even on select (cursor-line);
---       air_bottom = also add a blank row ABOVE the footer; select = the unfocused `{ key, name }` hint
---       (false = none); actions = the focused footer buttons `{ { key, name, run }, … }` (run = "close" or a
---       function), also bound as keymaps on the float buffer; focus = `{ key, buf }` to bind `key` on the
---       SOURCE buffer for focusing the (unfocused) float from the editor
function M.dress(winid, bufnr, opts)
    opts = opts or {}
    if not (winid and api.nvim_win_is_valid(winid)) then
        return
    end
    if vim.w[winid].lvim_dressed then -- a re-focused float (2nd invocation) — already themed + air-rowed
        return
    end
    vim.w[winid].lvim_dressed = true

    -- 1 blank "air" row under the title (the native helpers strip a leading blank from the input, so add it
    -- after) — and optionally one above the footer — then grow the window to keep the whole content visible.
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        vim.bo[bufnr].modifiable = true
        api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
        local grow = 1
        if opts.air_bottom then
            api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
            grow = 2
        end
        vim.bo[bufnr].modifiable = false
        pcall(api.nvim_win_set_height, winid, api.nvim_win_get_height(winid) + grow)
        pcall(api.nvim_win_set_cursor, winid, { 1, 0 }) -- park the view at the top so the air row shows
    end

    -- Palette bg + border. Do NOT touch `conceallevel` — a markdown renderer (markview) owns it.
    vim.wo[winid].winhighlight = "Normal:LvimUiPeekNormal,FloatBorder:LvimUiPeekBorder"

    -- Footer: a `select` hint while the float is UNFOCUSED (press the trigger key to enter & scroll), the
    -- ACTION buttons while it is the current window (also bound as keymaps on the float buffer). Both
    -- configurable: `opts.select = { key, name }` (or false), `opts.actions = { { key, name, run }, … }`
    -- where `run` is "close" or a function.
    local select_btn = opts.select ~= false
            and vim.tbl_extend("force", { key = "K", name = "select" }, opts.select or {})
        or nil
    local actions = opts.actions or { { key = "q", name = "close", run = "close" } }
    local footer_actions = footer_chunks(actions)
    -- The UNFOCUSED footer is the `select` hint; with no hint (select = false) it is EMPTY — the action
    -- keys only work once focused, so showing them while the cursor is still in the code would mislead.
    -- An empty footer must be "" (an empty LIST makes nvim_win_set_config error — which would also drop the
    -- title set in the same call).
    local footer_select = select_btn and footer_chunks({ select_btn }) or ""

    -- Centred border-title (top) + the unfocused footer (bottom). Trim the title so padding is symmetric.
    local wcfg = { footer = footer_select, footer_pos = "center" }
    if opts.title ~= false then
        wcfg.title = { { " " .. vim.trim(opts.title or "Info") .. " ", "LvimUiPeekTitle" } }
        wcfg.title_pos = "center"
    end
    pcall(api.nvim_win_set_config, winid, wcfg)

    -- The title + footer live on the border, so the window must be at least as wide as the WIDEST of them,
    -- else they are truncated (a short message would hide `n next  p prev  q close`). Grow if needed.
    local function chunks_width(cs)
        if type(cs) ~= "table" then -- "" (no footer)
            return 0
        end
        local w = 0
        for _, c in ipairs(cs) do
            w = w + vim.fn.strdisplaywidth(c[1])
        end
        return w
    end
    local need = math.max(chunks_width(footer_actions), chunks_width(footer_select))
    if wcfg.title then
        need = math.max(need, chunks_width(wcfg.title))
    end
    need = math.min(need, vim.o.columns - 4)
    if api.nvim_win_get_width(winid) < need then
        pcall(api.nvim_win_set_width, winid, need)
    end

    -- Bind each action's key on the float buffer (active once the float is entered).
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        for _, b in ipairs(actions) do
            local rhs = b.run == "close" and "<cmd>close<CR>" or b.run
            if rhs then
                pcall(vim.keymap.set, "n", b.key, rhs, { buffer = bufnr, nowait = true, silent = true })
            end
        end
    end

    -- `opts.focus = { key, buf }`: bind `key` on the SOURCE buffer so the user can FOCUS the (unfocused)
    -- float from the editor; removed when the float closes.
    if opts.focus and opts.focus.buf and api.nvim_buf_is_valid(opts.focus.buf) then
        local fbuf, fkey = opts.focus.buf, opts.focus.key
        pcall(vim.keymap.set, "n", fkey, function()
            if api.nvim_win_is_valid(winid) then
                api.nvim_set_current_win(winid)
            end
        end, { buffer = fbuf, nowait = true, silent = true })
        api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(winid),
            once = true,
            callback = function()
                pcall(vim.keymap.del, "n", fkey, { buffer = fbuf })
            end,
        })
    end

    -- Dynamic footer: the `select` hint while unfocused, the action buttons while focused.
    local group = api.nvim_create_augroup("LvimLspFloatFooter_" .. winid, { clear = true })
    local function set_footer(f)
        if api.nvim_win_is_valid(winid) then
            pcall(api.nvim_win_set_config, winid, { footer = f, footer_pos = "center" })
        end
    end
    api.nvim_create_autocmd("WinEnter", {
        group = group,
        callback = function()
            if api.nvim_get_current_win() == winid then
                set_footer(footer_actions)
            end
        end,
    })
    api.nvim_create_autocmd("WinLeave", {
        group = group,
        callback = function()
            if api.nvim_get_current_win() == winid then
                set_footer(footer_select)
            end
        end,
    })
    api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(winid),
        once = true,
        callback = function()
            pcall(api.nvim_del_augroup_by_id, group)
        end,
    })

    -- Hide the hardware cursor while the float is the current window (delegated to the ONE cursor system,
    -- by buffer handle since the filetype is shared) — the content (a ➤ marker / cursorline) shows position.
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        cursor.mark_hide_buffer(bufnr, true)
        cursor.update()
        api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(winid),
            once = true,
            callback = function()
                cursor.mark_hide_buffer(bufnr, false)
            end,
        })
    end

    -- Markdown floats (hover): keep the ``` fences / backticks hidden even when ENTERED (no cursor-line
    -- reveal). Scheduled so it lands AFTER the markdown renderer (markview) has set the window up.
    if opts.conceal then
        vim.schedule(function()
            if api.nvim_win_is_valid(winid) then
                vim.wo[winid].concealcursor = "nvic"
            end
        end)
    end
end

return M
