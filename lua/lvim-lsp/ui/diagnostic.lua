-- lvim-lsp.ui.diagnostic: show the current / next / previous diagnostic in the house float (lvim-lsp.ui.
-- float) — same chrome as the hover. Each diagnostic on the line is `message  (source)` (source dim,
-- message in the severity colour), sorted by severity (errors first), the count in the title. The float is
-- an interactive picker, ordered by COLUMN (the buffer position) so n / p walk the line left→right: a `➤`
-- marks the entry the editor cursor is on; entered (focus) the hardware cursor is hidden and j/k move the
-- `➤` AND the editor cursor to the selected diagnostic. next / prev (dn / dp) walk EVERY individual
-- diagnostic in document order — including a hint sharing a position with an error — re-showing the float on
-- the one they land on (a position-only jump would skip the lower-severity one at a shared position).
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
---@type { lnum: integer, col: integer, severity: integer }?
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

--- Index of the diagnostic matching `sel` (lnum / col / severity) in `diags`, or nil.
---@param diags table[]
---@param sel { lnum: integer, col: integer, severity: integer }?
---@return integer?
local function index_of(diags, sel)
    if not sel then
        return nil
    end
    for i, d in ipairs(diags) do
        if d.lnum == sel.lnum and d.col == sel.col and (d.severity or 9) == sel.severity then
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
            hl = hl,
        }
    end
    return lines, spans, entries
end

local show -- forward declaration (show ⇄ nav_step)
local nav_step -- forward declaration (the in-float n / p call it, same as the editor dn / dp)

--- Open the themed, interactive float for the diagnostics on the current line. `target` (from dn/dp) selects
--- the entry matching that exact diagnostic; without it the MOST SEVERE entry is selected (for dc).
---@param target { lnum: integer, col: integer, severity: integer }?
show = function(target)
    local origin = api.nvim_get_current_win()
    local origin_buf = api.nvim_win_get_buf(origin)
    local cursor = api.nvim_win_get_cursor(origin)
    local diags = vim.diagnostic.get(0, { lnum = cursor[1] - 1 })
    if vim.tbl_isempty(diags) then
        return
    end
    local mk = marker_cfg()
    local lines, spans, entries = build(diags, mk)
    local ok, bufnr, winid = pcall(vim.lsp.util.open_floating_preview, lines, "plaintext", {
        border = float.border,
        max_width = float.dim(0.8, vim.o.columns),
        max_height = float.dim(0.5, vim.o.lines),
        focusable = true,
        focus = true,
        focus_id = "lvim-lsp-diagnostic",
    })
    if not (ok and winid and api.nvim_win_is_valid(winid)) then
        return
    end
    diag_win = winid
    local fresh = not vim.w[winid].lvim_dressed
    local title = #diags > 1 and ("Diagnostics (" .. #diags .. ")") or "Diagnostic"
    -- n / p (focused) walk EVERY diagnostic in document order — exactly like the editor dn / dp — but keep
    -- the focus in the float so the user can keep pressing n. Once at the last entry of a line they advance to
    -- the first diagnostic of the NEXT line (not wrap within the line); they wrap only at the buffer ends.
    local function step(dir)
        nav_step(dir, origin, true)
    end
    float.dress(winid, bufnr, {
        title = title,
        air_bottom = true,
        select = { key = "↵", name = "focus" }, -- unfocused hint: <CR> enters the float
        focus = { key = "<CR>", buf = origin_buf }, -- bound on the code buffer → focus the float
        actions = {
            {
                key = "n",
                name = "next",
                run = function()
                    step(1)
                end,
            },
            {
                key = "p",
                name = "prev",
                run = function()
                    step(-1)
                end,
            },
            { key = "q", name = "close", run = "close" },
        },
    })
    if not (bufnr and api.nvim_buf_is_valid(bufnr)) then
        return
    end

    -- dress() inserted 1 air row at the top, so content row `r` (1-based) lands on the 0-based buffer row `r`.
    if fresh then
        for _, s in ipairs(spans) do
            pcall(api.nvim_buf_set_extmark, bufnr, hl_ns, s.row, s.c0, { end_col = s.c1, hl_group = s.hl })
        end
    end

    --- Move the ➤ overlay to entry `i` (and remember it on the window).
    local function set_arrow(i)
        local e = entries[i]
        if not e then
            return
        end
        vim.w[winid].lvim_diag_sel = i
        selected = { lnum = e.lnum, col = e.col, severity = e.severity } -- so editor dn/dp continue from here
        api.nvim_buf_clear_namespace(bufnr, arrow_ns, 0, -1)
        if not mk.enabled then
            return
        end
        pcall(api.nvim_buf_set_extmark, bufnr, arrow_ns, e.first_row, 0, {
            virt_text = { { mk.text, marker_group(mk, e.hl) } }, -- padded marker, severity fg + tinted bg
            virt_text_pos = "overlay",
        })
    end

    -- Selection: a `target` (dn/dp walk) selects the entry matching that exact diagnostic's (col, severity);
    -- otherwise (dc) start on the MOST SEVERE — entries are display-sorted by severity, so that's #1 — not the
    -- one under the cursor, which can be a low-severity hint while an error sits elsewhere on the line.
    local active = 1
    if target then
        for i, e in ipairs(entries) do
            if e.col == target.col and e.severity == target.severity then
                active = i
                break
            end
        end
    end
    set_arrow(active)
    pcall(api.nvim_win_set_cursor, winid, { entries[active].first_row + 1, 0 }) -- +1 for the air row

    -- A cursorline marks the selected row; the content rows are buffer lines [min_line, max_line] (the air
    -- rows top + bottom are excluded — the cursor is clamped to the real diagnostics in CursorMoved).
    vim.wo[winid].cursorline = true
    vim.wo[winid].winhighlight = vim.wo[winid].winhighlight .. ",CursorLine:LvimUiCursorLine"
    local min_line = entries[1].first_row + 1
    local max_line = entries[#entries].last_row + 1

    -- While focused, j/k pick a diagnostic: move the ➤ and sync the EDITOR cursor to it (eventignore so the
    -- float's own CursorMoved auto-close, armed on the editor buffer, does not fire and close us).
    if fresh then
        api.nvim_create_autocmd("CursorMoved", {
            buffer = bufnr,
            callback = function()
                if not api.nvim_win_is_valid(winid) then
                    return
                end
                -- Keep the cursor (cursorline) off the air rows — clamp to the real content lines.
                local cl = api.nvim_win_get_cursor(winid)[1]
                if cl < min_line then
                    pcall(api.nvim_win_set_cursor, winid, { min_line, 0 })
                elseif cl > max_line then
                    pcall(api.nvim_win_set_cursor, winid, { max_line, 0 })
                end
                local content_row = api.nvim_win_get_cursor(winid)[1] - 1 -- undo the air-row offset
                for i, e in ipairs(entries) do
                    if content_row >= e.first_row and content_row <= e.last_row then
                        if vim.w[winid].lvim_diag_sel ~= i then
                            set_arrow(i)
                        end
                        if api.nvim_win_is_valid(origin) then
                            local ei = vim.o.eventignore
                            vim.o.eventignore = "CursorMoved,CursorMovedI"
                            pcall(api.nvim_win_set_cursor, origin, { e.lnum + 1, e.col })
                            vim.o.eventignore = ei
                        end
                        return
                    end
                end
            end,
        })
    end
end

--- Close the open diagnostic float (if any) so the next step shows a FRESH one at the new position.
local function close_open()
    if diag_win and api.nvim_win_is_valid(diag_win) then
        pcall(api.nvim_win_close, diag_win, true)
    end
    diag_win = nil
end

--- Walk to the `dir`-th individual diagnostic in `origin`'s buffer, in document order (wrapping at the ends),
--- and show its float. Steps from the last SELECTED diagnostic while the cursor is still on it — so repeated
--- presses traverse EVERY diagnostic at a shared position (the hint after the error) before moving to the next
--- line; otherwise it steps relative to the cursor. `keep_focus` re-focuses the new float (the in-float n / p).
---@param dir integer  1 = next, -1 = prev
---@param origin integer  the EDITOR window (NOT the float — n / p run while the float is current)
---@param keep_focus boolean  true → focus the new float (in-float n / p); false → stay in the editor (dn / dp)
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
    -- Continue the walk from the last SELECTED diagnostic while the cursor is still on its LINE. Match by LINE
    -- only, NOT by exact column: a diagnostic can sit past the line's end (e.g. "expected …" at EOL), where
    -- nvim_win_set_cursor clamps the cursor short of `selected.col` — an exact-column guard would then never
    -- match, so every press would re-snap to that same diagnostic instead of advancing to the next.
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
    close_open()
    if api.nvim_win_is_valid(origin) then
        api.nvim_set_current_win(origin) -- leave the float (if focused) before moving the editor cursor
        pcall(api.nvim_win_set_cursor, origin, { target.lnum + 1, target.col })
    end
    selected = { lnum = target.lnum, col = target.col, severity = target.severity or 9 }
    vim.schedule(function()
        show(selected)
        if keep_focus and diag_win and api.nvim_win_is_valid(diag_win) then
            api.nvim_set_current_win(diag_win)
        end
    end)
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
