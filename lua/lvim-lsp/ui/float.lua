-- lvim-lsp.ui.float: the shared house chrome for a NATIVE floating preview — used by the hover and the
-- diagnostic floats (current / next / prev). Given a float already opened by `vim.lsp.util.open_floating_
-- preview` or `vim.diagnostic.open_float` (unfocused, cursor-anchored, auto-closing — the native behaviour),
-- `dress()` applies the palette (border bg, tinted title) + a 1-row air gap under the title + a DYNAMIC
-- footer that reads `K select` while the float is unfocused (press the trigger key to enter & scroll) and,
-- once it is the current window, becomes a NAVIGABLE action bar — each button's own key fires it (q close,
-- n next, …) AND h/l (←/→) move the visible selection with <CR>/<Space> activating it (the chassis footer
-- key model). The bar rides the native border-footer because a native float's single window scrolls (a
-- content-row footer would scroll off with the body) — a documented native-float exception to the unified
-- "border-footer = counter only" rule; the count, when any, rides the title. Idempotent per window: a 2nd
-- invocation re-focuses the SAME float (native `focus_id`) and is left untouched (else it would stack
-- another air row each time).
--
---@module "lvim-lsp.ui.float"

local cursor = require("lvim-utils.cursor")

local api = vim.api

local M = {}

-- House border: `lvim-utils.ui.util.chrome_border()` — it follows the shared `config.ui.border`, but when that
-- is "none" (the chassis panels are borderless, with the title in a content row) it returns an INVISIBLE all-" "
-- padding ring. A NATIVE float carries its title + action footer ON the border, so a literal "none" would drop
-- BOTH — the padding ring keeps the borderless LOOK while the title / buttons still render. Exposed as a LIVE
-- field through the metatable, so `float.border` re-reads it on every access (a runtime change reflects on the
-- next peek). Pass it as the `border` opt when OPENING the float.
setmetatable(M, {
    __index = function(_, k)
        if k == "border" then
            return require("lvim-utils.ui.util").chrome_border()
        end
    end,
})

--- Footer chunks for a row of `{ key, name }` buttons (`key` blue badge + `name` yellow label). When `sel`
--- is given, that button renders in the brighter HOVER tint — the visible selection of the navigable action
--- bar (the same key/label hover groups the chassis footer sector uses, so the look matches).
---@param buttons table[]
---@param sel? integer  index of the selected (hovered) button, or nil for none
---@return table[]
local function footer_chunks(buttons, sel)
    -- The button COLOURS come from the shared `surface.STYLES.action` box (the `action` KIND — one style source
    -- for every action bar, panels AND these native floats), so the look tracks it. A native float renders its
    -- footer as extmark CHUNKS (not a `ui.bar` band), so we read the highlight-group NAMES off the kind rather
    -- than build a bar; the hardcoded LvimUiFooter* groups stay as the fallback.
    local a = (require("lvim-utils.ui.surface").STYLES.action or {}).hl or {}
    local key_n = (a.icon and a.icon.normal) or "LvimUiFooterKey"
    local key_h = (a.icon and a.icon.hover) or "LvimUiFooterKeyHover"
    local lbl_n = (a.text and a.text.normal) or "LvimUiFooterLabel"
    local lbl_h = (a.text and a.text.hover) or "LvimUiFooterLabelHover"
    -- a plain 1-space lead so the first badge is not flush against the edge; then each button is a key BADGE
    -- and a NAME label, BOTH symmetrically padded ` x ` (a space front AND back), so the labels read evenly.
    local out = { { " " } }
    for i, b in ipairs(buttons) do
        local on = i == sel
        out[#out + 1] = { " " .. b.key .. " ", on and key_h or key_n }
        out[#out + 1] = { " " .. (b.name or "") .. " ", on and lbl_h or lbl_n }
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
    -- The FOCUSED footer is a NAVIGABLE action bar: `nav.sel` is the selected button, moved with h/l (←/→)
    -- and activated with <CR>/<Space> while the float is focused (the direct per-key bindings n/p/q below
    -- still work too). The native border-footer is the only non-scrolling place for it on a NATIVE float
    -- (a content row would scroll off with the body), so the bar rides the border here — a documented
    -- native-float exception to the "border-footer = counter only" rule; the chassis-framed panels keep the
    -- bar in a content sector. The count, when any, rides the title (diagnostic peek), not this footer.
    local nav = { sel = 1 }
    local function footer_actions()
        return footer_chunks(actions, nav.sel)
    end
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
            w = w + api.nvim_strwidth(c[1]) -- intrinsic width (window-independent), not vim.fn.strdisplaywidth
        end
        return w
    end
    local need = math.max(chunks_width(footer_actions()), chunks_width(footer_select))
    if wcfg.title then
        need = math.max(need, chunks_width(wcfg.title))
    end
    need = math.min(need, vim.o.columns - 4)
    if api.nvim_win_get_width(winid) < need then
        pcall(api.nvim_win_set_width, winid, need)
    end

    --- Run a footer button's action (`run` = "close" | a function), shared by the direct key bindings and
    --- the navigable bar's <CR>/<Space> confirm.
    ---@param b table
    local function run_action(b)
        if b.run == "close" then
            if api.nvim_win_is_valid(winid) then
                pcall(api.nvim_win_close, winid, true)
            end
        elseif type(b.run) == "function" then
            b.run()
        end
    end

    -- Bind the footer as a NAVIGABLE button bar on the float buffer (active once the float is entered):
    -- each action's OWN key fires it directly (n / p / q), AND h/l (←/→) move the visible selection across
    -- the bar with <CR>/<Space> activating the selected button — the same key model as the chassis footer
    -- sector, so a focused float is operable without remembering the per-button keys.
    if bufnr and api.nvim_buf_is_valid(bufnr) then
        local function refresh_nav()
            if api.nvim_win_is_valid(winid) and api.nvim_get_current_win() == winid then
                pcall(api.nvim_win_set_config, winid, { footer = footer_actions(), footer_pos = "center" })
            end
        end
        local function move(d)
            nav.sel = math.max(1, math.min(#actions, nav.sel + d))
            refresh_nav()
        end
        local map = function(lhs, fn)
            pcall(vim.keymap.set, "n", lhs, fn, { buffer = bufnr, nowait = true, silent = true })
        end
        for _, b in ipairs(actions) do
            map(b.key, function()
                run_action(b)
            end)
        end
        for _, k in ipairs({ "h", "<Left>" }) do
            map(k, function()
                move(-1)
            end)
        end
        for _, k in ipairs({ "l", "<Right>" }) do
            map(k, function()
                move(1)
            end)
        end
        for _, k in ipairs({ "<CR>", "<Space>" }) do
            map(k, function()
                local b = actions[nav.sel]
                if b then
                    run_action(b)
                end
            end)
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
                nav.sel = 1 -- start the navigable bar on the first button each time the float is focused
                set_footer(footer_actions())
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
