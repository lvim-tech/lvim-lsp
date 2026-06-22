-- lvim-lsp.ui.diagnostic: show the current / next / previous diagnostic in the house float (lvim-lsp.ui.
-- float) — same chrome as the hover. Each diagnostic on the line is `message  (source)` (source dim, message
-- in the severity colour), sorted by severity (errors first), the count in the title. The float is an
-- interactive picker: a `➤` marks the selected diagnostic; entered (focus) the hardware cursor is hidden and
-- j/k move the `➤` and the editor cursor. next / prev (dn / dp) and the in-float n / p both walk EVERY
-- individual diagnostic in document order (line → severity → column, so arriving at a line lands on its error,
-- and several at one position are each visited), telling apart same-position diagnostics by their message.
-- Navigation REUSES the one float window in place (re-render + reposition, never close/reopen) so there is no
-- flicker; it dismisses only on a genuine manual cursor move.
--
---@module "lvim-lsp.ui.diagnostic"

local float = require("lvim-lsp.ui.float")
local hlmod = require("lvim-utils.highlight")
local colors = require("lvim-utils.colors")

local api = vim.api
local sev = vim.diagnostic.severity

local M = {}

-- The currently-open diagnostic float. next / prev CLOSE it before jumping so a NEW float opens at the new
-- position — else `open_floating_preview`'s `focus_id` would just re-focus the stale one (wrong diagnostic).
---@type integer?
local diag_win = nil

-- The diagnostic last SELECTED — by dn/dp/dc OR by moving inside the float. dn/dp step from HERE (while the
-- cursor is still on it), so repeated presses walk every INDIVIDUAL diagnostic in document order, including a
-- hint that shares a position with a higher-severity one (which a position-only jump would skip over).
---@type { lnum: integer, col: integer, severity: integer, message: string }?
local selected = nil

local ARROW = "➤" -- the canonical pointer (U+27A4): marks the selected diagnostic
local arrow_ns = api.nvim_create_namespace("LvimLspDiagnosticArrow")
local hl_ns = api.nvim_create_namespace("LvimLspDiagnosticFloat")

local lsp_state = require("lvim-lsp.state")

-- Severity → the message highlight group.
---@type table<integer, string>
local SEV_HL = {
    [sev.ERROR] = "DiagnosticError",
    [sev.WARN] = "DiagnosticWarn",
    [sev.INFO] = "DiagnosticInfo",
    [sev.HINT] = "DiagnosticHint",
}

--- The selection-marker config (configurable via `config.diagnostics.marker`):
---   enabled (true/false), icon (default ➤), pad = { front, back } spaces (default { 1, 1 } → " ➤ "),
---   hl      — nil → DERIVE per row (fg = the severity colour, bg = a `bg_tint` tint of it);
---             a string → a fixed group; a function(base_hl) → a group (fully programmable),
---   bg_tint — the derived bg tint of the fg (default 0.3; 0 = no bg).
---@return { enabled: boolean, text: string, width: integer, hl: string|function|nil, bg_tint: number }
local function marker_cfg()
    local m = (lsp_state.config.diagnostics or {}).marker or {}
    local icon = m.icon or ARROW
    local pad = m.pad or { 1, 1 }
    local text = string.rep(" ", pad[1] or 1) .. icon .. string.rep(" ", pad[2] or 1)
    return {
        enabled = m.enabled ~= false,
        text = text,
        width = vim.fn.strdisplaywidth(text),
        hl = m.hl,
        bg_tint = m.bg_tint or 0.3,
    }
end

--- The marker highlight for a row whose base (severity) group is `base` — per `mk.hl` (string | function |
--- nil). nil derives `{ fg = base's fg, bg = a tint of that fg }`; nothing is hardcoded — the tint and the
--- whole resolution are config-driven.
---@param mk table
---@param base string
---@return string
local function marker_group(mk, base)
    if type(mk.hl) == "string" then
        return mk.hl
    elseif type(mk.hl) == "function" then
        return mk.hl(base)
    end
    local g = vim.api.nvim_get_hl(0, { name = base, link = false })
    if not g.fg then
        return base
    end
    local name = "LvimLspDiagMarker" .. base
    local def = { fg = g.fg }
    if (mk.bg_tint or 0) > 0 then
        def.bg = hlmod.blend(string.format("#%06x", g.fg), colors.bg, mk.bg_tint)
    end
    vim.api.nvim_set_hl(0, name, def)
    return name
end

--- All of the buffer's diagnostics in DOCUMENT order: line, then SEVERITY (errors first), then column — so a
--- step visits EVERY individual diagnostic, and ARRIVING at a line lands on its most-severe one (the error,
--- not a lower-severity hint that happens to sit at a smaller column). It also matches the float's display
--- order (severity-sorted), so n / p move the arrow straight down the list.
---@param buf integer
---@return table[]
local function all_sorted(buf)
    local diags = vim.diagnostic.get(buf)
    table.sort(diags, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        local sa, sb = a.severity or 9, b.severity or 9
        if sa ~= sb then
            return sa < sb
        end
        return a.col < b.col
    end)
    return diags
end

--- Index of the diagnostic matching `sel` (lnum / col / severity / message) in `diags`, or nil. The message
--- is part of the match so SEVERAL diagnostics sharing one (lnum, col, severity) — e.g. "Unused local vim" and
--- "Redefined local vim" from two linters — are told apart, else the walk would stick on the first of them.
---@param diags table[]
---@param sel { lnum: integer, col: integer, severity: integer, message: string }?
---@return integer?
local function index_of(diags, sel)
    if not sel then
        return nil
    end
    for i, d in ipairs(diags) do
        if
            d.lnum == sel.lnum
            and d.col == sel.col
            and (d.severity or 9) == sel.severity
            and d.message == sel.message
        then
            return i
        end
    end
    return nil
end

--- Build the float lines + highlight spans + per-diagnostic entries. Every row is indented 2 cols (so the
--- `➤` overlay aligns); entries map a diagnostic to its content rows + editor position.
---@param diags table[]
---@param mk table
---@return string[] lines, table[] spans, table[] entries
local function build(diags, mk)
    -- DISPLAY order: by severity (errors first).
    table.sort(diags, function(a, b)
        return (a.severity or 9) < (b.severity or 9)
    end)
    local indent = mk.enabled and string.rep(" ", mk.width) or "" -- leading space the ➤ overlay sits on
    -- Text padding (independent of the marker, so it survives disabling the ➤) — `diagnostics.text_pad`.
    local tp = (lsp_state.config.diagnostics or {}).text_pad or { 1, 1 }
    local front = string.rep(" ", tp[1] or 1)
    local back = string.rep(" ", tp[2] or 1)
    local lines, spans, entries = {}, {}, {}
    for _, d in ipairs(diags) do
        local hl = SEV_HL[d.severity] or "DiagnosticError"
        local source = d.source and ("  (" .. d.source:gsub("%s+$", "") .. ")") or ""
        local msg = vim.split(d.message, "\n", { trimempty = true })
        local first_row = #lines + 1
        for j = 1, #msg do
            local last = j == #msg
            local body, tail = msg[j], (last and source or "")
            local line = indent .. front .. body .. tail .. back
            lines[#lines + 1] = line
            local row = #lines
            local mc0 = #indent + #front
            spans[#spans + 1] = { row = row, c0 = mc0, c1 = mc0 + #body, hl = hl } -- message
            if last and #source > 0 then
                spans[#spans + 1] =
                    { row = row, c0 = mc0 + #body, c1 = mc0 + #body + #source, hl = "DiagnosticSourceInfo" }
            end
        end
        entries[#entries + 1] = {
            first_row = first_row, -- 1-based content row of the diagnostic's first line
            last_row = #lines,
            lnum = d.lnum or 0,
            col = d.col or 0,
            end_col = d.end_col,
            severity = d.severity or 9,
            message = d.message, -- part of the identity: distinguishes several diagnostics at one (lnum,col,sev)
            hl = hl,
        }
    end
    return lines, spans, entries
end

local nav_step -- forward declaration (the in-float n / p call it, same as the editor dn / dp)

-- Live state of the OPEN float, kept at MODULE scope (not captured in a closure) so an IN-PLACE re-render
-- (reuse the same window — no close/reopen, hence no flicker) and the CursorMoved handler always read FRESH
-- entries, never a stale set from the first open.
---@type { winid: integer, bufnr: integer, origin: integer, entries: table[], min_line: integer, max_line: integer, mk: table }?
local view = nil

-- The editor-cursor position WE last set programmatically (dn/dp or the in-float j/k sync), as the actual
-- (clamped) { row, col }. The close-on-manual-move autocmd compares against it: a CursorMoved landing on this
-- exact spot is OUR move (don't close) — `eventignore` alone is not enough, since nvim_win_set_cursor fires a
-- DEFERRED CursorMoved that lands after eventignore is restored.
---@type integer[]?
local nav_pos = nil

--- Move the ➤ overlay to entry `i` of the open float and remember the selection (so editor dn/dp continue).
---@param i integer
local function set_arrow(i)
    if not view then
        return
    end
    local e = view.entries[i]
    if not e then
        return
    end
    vim.w[view.winid].lvim_diag_sel = i
    selected = { lnum = e.lnum, col = e.col, severity = e.severity, message = e.message }
    api.nvim_buf_clear_namespace(view.bufnr, arrow_ns, 0, -1)
    if not view.mk.enabled then
        return
    end
    pcall(api.nvim_buf_set_extmark, view.bufnr, arrow_ns, e.first_row, 0, {
        virt_text = { { view.mk.text, marker_group(view.mk, e.hl) } }, -- padded marker, severity fg + tinted bg
        virt_text_pos = "overlay",
    })
end

--- (Re-)render the open float for `view.origin`'s current cursor line — IN PLACE, reusing the window (no
--- close/reopen → no flicker). Rebuilds the content, repositions/resizes the window anchored to the SELECTED
--- diagnostic's buffer position (relative="win" + bufpos is stable regardless of which window is current),
--- and moves the ➤ + cursorline. `target` selects the matching diagnostic; nil → the most severe.
---@param target { lnum: integer, col: integer, severity: integer, message: string }?
local function populate(target)
    if not (view and api.nvim_win_is_valid(view.winid) and api.nvim_buf_is_valid(view.bufnr)) then
        return
    end
    local origin = view.origin
    if not api.nvim_win_is_valid(origin) then
        return
    end
    local obuf = api.nvim_win_get_buf(origin)
    local crow = api.nvim_win_get_cursor(origin)[1] - 1
    local diags = vim.diagnostic.get(obuf, { lnum = crow })
    if vim.tbl_isempty(diags) then
        return
    end
    local mk = marker_cfg()
    local lines, spans, entries = build(diags, mk)
    view.entries, view.mk = entries, mk
    local win, buf = view.winid, view.bufnr

    -- Content = 1 air row top + body + 1 air row bottom (matches float.dress), so content row r (1-based) lands
    -- on the 0-based buffer row r.
    local body = { "" }
    for _, l in ipairs(lines) do
        body[#body + 1] = l
    end
    body[#body + 1] = ""
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, body)
    vim.bo[buf].modifiable = false

    api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
    for _, s in ipairs(spans) do
        pcall(api.nvim_buf_set_extmark, buf, hl_ns, s.row, s.c0, { end_col = s.c1, hl_group = s.hl })
    end

    -- Selection: a `target` (dn/dp walk) selects the entry matching that exact diagnostic's (col, severity);
    -- otherwise (dc) the MOST SEVERE — entries are display-sorted by severity, so that's #1.
    local active = 1
    if target then
        for i, e in ipairs(entries) do
            if e.col == target.col and e.severity == target.severity and e.message == target.message then
                active = i
                break
            end
        end
    end
    view.min_line = entries[1].first_row + 1
    view.max_line = entries[#entries].last_row + 1

    -- Size: HUG the content. Width = the widest diagnostic row, shrunk to it whenever it is under the cap — NO
    -- footer / title floor (that padded a short message out to ~2× its text). The cap is `diagnostics.max_width`
    -- (a fraction of the screen when ≤ 1, else absolute columns; default 0.8), clamped to the screen.
    local title = #diags > 1 and ("Diagnostics (" .. #diags .. ")") or "Diagnostic"
    local mw = (lsp_state.config.diagnostics or {}).max_width or 0.8
    local cap = mw <= 1 and (float.dim(mw, vim.o.columns) or math.floor(vim.o.columns * mw)) or mw
    cap = math.min(cap, vim.o.columns - 4)
    -- Measure each row with nvim_strwidth — the string's INTRINSIC display width — NOT vim.fn.strdisplaywidth:
    -- the latter is evaluated against the CURRENT window's options and was returning a wrong (inflated) width
    -- when populate ran mid re-focus during in-float n / p navigation, so the float was left padded far wider
    -- than its content. nvim_strwidth is window-independent, so the width is stable.
    local width = 1
    for _, l in ipairs(lines) do
        width = math.max(width, api.nvim_strwidth(l))
    end
    width = math.max(1, math.min(width, cap))
    local height = math.max(1, math.min(#body, float.dim(0.5, vim.o.lines) or #body))

    -- Anchor to the SELECTED diagnostic's position in the editor window, above or below by screen space.
    local anchor = entries[active]
    local sp = vim.fn.screenpos(origin, anchor.lnum + 1, anchor.col + 1)
    local below = sp.row == 0 or (sp.row + height + 3) <= vim.o.lines
    local cfg = api.nvim_win_get_config(win)
    cfg.relative = "win"
    cfg.win = origin
    cfg.bufpos = { anchor.lnum, anchor.col }
    cfg.anchor = below and "NW" or "SW"
    cfg.row = below and 1 or 0
    cfg.col = 0
    cfg.width = width
    cfg.height = height
    cfg.title = { { " " .. vim.trim(title) .. " ", "LvimUiPeekTitle" } }
    cfg.title_pos = "center"
    pcall(api.nvim_win_set_config, win, cfg)

    set_arrow(active)
    -- Move the float cursor to the selection without retriggering the float's own CursorMoved (j/k) handler.
    local ei = vim.o.eventignore
    vim.o.eventignore = "CursorMoved,CursorMovedI"
    pcall(api.nvim_win_set_cursor, win, { entries[active].first_row + 1, 0 })
    vim.o.eventignore = ei
end

--- Open the float for `origin`'s cursor line, or REUSE the already-open one in place (no flicker). The window,
--- buffer, chrome and handlers are created ONCE; every later call just repopulates. `target` selects a
--- specific diagnostic (nil → most severe).
---@param origin integer
---@param target { lnum: integer, col: integer, severity: integer, message: string }?
local function open_for(origin, target)
    if not api.nvim_win_is_valid(origin) then
        return
    end
    local obuf = api.nvim_win_get_buf(origin)
    local crow = api.nvim_win_get_cursor(origin)[1] - 1
    local diags = vim.diagnostic.get(obuf, { lnum = crow })
    if vim.tbl_isempty(diags) then
        return
    end

    -- Reuse the open float — repopulate it in place.
    if view and diag_win and api.nvim_win_is_valid(diag_win) then
        view.origin = origin
        populate(target)
        return
    end

    -- First open with the REAL content (open_floating_preview bails on empty input → no window). dress + the
    -- handlers are wired once; populate() then re-renders + repositions the window every call.
    local lines = build(diags, marker_cfg())
    local ok, bufnr, winid = pcall(vim.lsp.util.open_floating_preview, lines, "plaintext", {
        border = float.border,
        focusable = true,
        focus = true,
        focus_id = "lvim-lsp-diagnostic",
        close_events = {}, -- we manage dismissal ourselves; the built-in auto-close fires on our own reposition
    })
    if not (ok and winid and api.nvim_win_is_valid(winid) and bufnr and api.nvim_buf_is_valid(bufnr)) then
        return
    end
    diag_win = winid
    view = {
        winid = winid,
        bufnr = bufnr,
        origin = origin,
        entries = {},
        min_line = 1,
        max_line = 1,
        mk = marker_cfg(),
    }

    float.dress(winid, bufnr, {
        title = "Diagnostic",
        air_bottom = true,
        select = { key = "↵", name = "focus" }, -- unfocused hint: <CR> enters the float
        focus = { key = "<CR>", buf = obuf }, -- bound on the code buffer → focus the float
        actions = {
            {
                key = "n",
                name = "next",
                run = function()
                    nav_step(1, view and view.origin or origin, true)
                end,
            },
            {
                key = "p",
                name = "prev",
                run = function()
                    nav_step(-1, view and view.origin or origin, true)
                end,
            },
            { key = "q", name = "close", run = "close" },
        },
    })

    vim.wo[winid].cursorline = true
    vim.wo[winid].winhighlight = vim.wo[winid].winhighlight .. ",CursorLine:LvimUiCursorLine"

    -- j/k inside the float pick a diagnostic: clamp off the air rows, move the ➤, sync the EDITOR cursor to it
    -- (eventignore so the float's auto-close, armed on the editor buffer, does not fire and close us).
    api.nvim_create_autocmd("CursorMoved", {
        buffer = bufnr,
        callback = function()
            if not (view and api.nvim_win_is_valid(view.winid)) then
                return
            end
            local cl = api.nvim_win_get_cursor(view.winid)[1]
            if cl < view.min_line then
                pcall(api.nvim_win_set_cursor, view.winid, { view.min_line, 0 })
            elseif cl > view.max_line then
                pcall(api.nvim_win_set_cursor, view.winid, { view.max_line, 0 })
            end
            local content_row = api.nvim_win_get_cursor(view.winid)[1] - 1 -- undo the air-row offset
            for i, e in ipairs(view.entries) do
                if content_row >= e.first_row and content_row <= e.last_row then
                    if vim.w[view.winid].lvim_diag_sel ~= i then
                        set_arrow(i)
                    end
                    if api.nvim_win_is_valid(view.origin) then
                        pcall(api.nvim_win_set_cursor, view.origin, { e.lnum + 1, e.col })
                        nav_pos = api.nvim_win_get_cursor(view.origin)
                    end
                    return
                end
            end
        end,
    })

    -- We manage dismissal ourselves (the built-in auto-close is off): close the float when the user moves the
    -- cursor in the EDITOR BY HAND, or starts insert. Our dn/dp + j/k moves are wrapped in `eventignore`, so
    -- they do NOT trigger this — only a genuine manual move dismisses the float.
    local close_grp = api.nvim_create_augroup("LvimLspDiagClose_" .. winid, { clear = true })
    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter" }, {
        group = close_grp,
        buffer = obuf,
        callback = function(ev)
            -- A CursorMoved that lands exactly where WE put the cursor (dn/dp/j-k) is our own move → keep open.
            if ev.event ~= "InsertEnter" and nav_pos then
                local ok2, p = pcall(api.nvim_win_get_cursor, 0)
                if ok2 and p[1] == nav_pos[1] and p[2] == nav_pos[2] then
                    return
                end
            end
            if diag_win and api.nvim_win_is_valid(diag_win) then
                pcall(api.nvim_win_close, diag_win, true)
            end
        end,
    })

    -- Drop the live state + the close autocmds when the float closes (manual move, or `q`).
    api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(winid),
        once = true,
        callback = function()
            pcall(api.nvim_del_augroup_by_id, close_grp)
            if view and view.winid == winid then
                view = nil
            end
            if diag_win == winid then
                diag_win = nil
            end
        end,
    })

    populate(target)
end

--- Open the float for the diagnostics on the CURRENT line (dc). `target` selects a specific one (nil = most
--- severe).
---@param target { lnum: integer, col: integer, severity: integer, message: string }?
local function show(target)
    open_for(api.nvim_get_current_win(), target)
end

--- Walk to the `dir`-th individual diagnostic in `origin`'s buffer, in document order (wrapping at the ends),
--- and show it by REUSING the open float in place (no close/reopen → no flicker). Steps from the last SELECTED
--- diagnostic while the cursor is still on its line — so repeated presses traverse EVERY diagnostic at a shared
--- position (the hint after the error) before moving to the next line; otherwise relative to the cursor.
--- Matched by LINE only, NOT exact column: a diagnostic can sit past the line's end (e.g. "expected …" at
--- EOL) where nvim_win_set_cursor clamps the cursor short of `selected.col`, so an exact-column guard would
--- never hold and the walk would re-snap to that same diagnostic forever. `keep_focus` keeps the focus in the
--- float (the in-float n / p) rather than the editor (dn / dp).
---@param dir integer  1 = next, -1 = prev
---@param origin integer  the EDITOR window (NOT the float — n / p run while the float is current)
---@param keep_focus boolean
nav_step = function(dir, origin, keep_focus)
    if not (origin and api.nvim_win_is_valid(origin)) then
        return
    end
    local buf = api.nvim_win_get_buf(origin)
    local diags = all_sorted(buf)
    if vim.tbl_isempty(diags) then
        return
    end
    local cur = api.nvim_win_get_cursor(origin)
    local cl, cc = cur[1] - 1, cur[2]
    local from = selected and selected.lnum == cl and index_of(diags, selected) or nil
    local target
    if from then
        target = diags[(from - 1 + dir) % #diags + 1] -- continue the walk from the selected diagnostic
    elseif dir > 0 then
        for _, d in ipairs(diags) do
            if d.lnum > cl or (d.lnum == cl and d.col > cc) then
                target = d
                break
            end
        end
        target = target or diags[1] -- wrap
    else
        for i = #diags, 1, -1 do
            local d = diags[i]
            if d.lnum < cl or (d.lnum == cl and d.col < cc) then
                target = d
                break
            end
        end
        target = target or diags[#diags] -- wrap
    end
    -- Move the EDITOR cursor to the target; record the landed (clamped) spot so the close autocmd recognises
    -- it as OUR move and keeps the float open.
    pcall(api.nvim_win_set_cursor, origin, { target.lnum + 1, target.col })
    nav_pos = api.nvim_win_get_cursor(origin)
    selected = { lnum = target.lnum, col = target.col, severity = target.severity or 9, message = target.message }
    open_for(origin, selected)
    if keep_focus and diag_win and api.nvim_win_is_valid(diag_win) then
        api.nvim_set_current_win(diag_win)
    end
end

--- Diagnostics on the current line.
function M.current()
    show()
end

--- Walk to the next individual diagnostic, then show its float.
function M.next()
    nav_step(1, api.nvim_get_current_win(), false)
end

--- Walk to the previous individual diagnostic, then show its float.
function M.prev()
    nav_step(-1, api.nvim_get_current_win(), false)
end

return M
