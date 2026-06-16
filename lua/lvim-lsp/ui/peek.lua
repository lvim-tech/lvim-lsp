-- lvim-lsp.ui.peek: the two-pane "peek" navigator for a list of source locations, built as a PRESET on
-- the lvim-utils `frame` chassis + the lvim-utils `preview` provider. The left center panel is the
-- locations grouped by file (a collapsible tree in "manual", a cursor-following list in "auto"); the
-- right panel is the live preview. A header filter bar (when `opts.bar` is given) re-filters live; the
-- footer carries open / split / close as a navigable sector. The domain logic (grouping, the source-line
-- render, the match highlight, the filter) lives here; the windowing / sectors / theming come from frame.
--
-- Consumers: ui/diagnostics_list.lua and ui/locations.lua call `peek.open(items, …)`.
--
---@module "lvim-lsp.ui.peek"

local frame = require("lvim-utils.ui.frame")
local preview = require("lvim-utils.ui.preview")
local util = require("lvim-utils.ui.util")

local api = vim.api
local NS = api.nvim_create_namespace("LvimLspPeekList")

local M = {}

-- ─── config / model ───────────────────────────────────────────────────────────

--- Effective peek config: lvim-utils ui.peek defaults ⊕ instance overrides ⊕ the per-call mode.
---@param instance_cfg table|nil
---@param opts table
---@return table
local function resolve_cfg(instance_cfg, opts)
    local p = vim.deepcopy(util.cfg().peek or {})
    if instance_cfg and instance_cfg.peek then
        p = vim.tbl_deep_extend("force", p, instance_cfg.peek)
    end
    if opts.mode then
        p.mode = opts.mode
    end
    return p
end

--- Group flat items by file (first-seen order) into a tree + flat index maps.
---@param items table[]
---@return table
local function build_model(items)
    local order, byfile = {}, {}
    for _, it in ipairs(items) do
        if not byfile[it.filename] then
            byfile[it.filename] = {}
            order[#order + 1] = it.filename
        end
        table.insert(byfile[it.filename], it)
    end
    local groups, items_flat, item_group = {}, {}, {}
    for gi, fname in ipairs(order) do
        local rel = vim.fn.fnamemodify(fname, ":~:.")
        local dir = vim.fn.fnamemodify(rel, ":h")
        local g = { tail = vim.fn.fnamemodify(fname, ":t"), dir = (dir == "." or dir == "") and "" or dir, items = {} }
        for _, it in ipairs(byfile[fname]) do
            items_flat[#items_flat + 1] = it
            item_group[#items_flat] = gi
            g.items[#g.items + 1] = { it = it, idx = #items_flat }
        end
        groups[gi] = g
    end
    return { groups = groups, items_flat = items_flat, item_group = item_group }
end

--- The button active in `group`.
local function active_button(group)
    for _, b in ipairs(group.buttons) do
        if b.id == group.active then
            return b
        end
    end
    return group.buttons[1]
end

--- True when `it` passes every group's active predicate except `except`.
local function passes_bar(bar, it, except)
    for _, g in ipairs(bar.groups) do
        if g ~= except then
            local b = active_button(g)
            if b and b.predicate and not b.predicate(it) then
                return false
            end
        end
    end
    return true
end

--- (Re)build the visible model from `state.all_items` through the bar filter; reset the selection.
local function apply_filter(state)
    local items = state.all_items
    if state.bar then
        local kept = {}
        for _, it in ipairs(items) do
            if passes_bar(state.bar, it, nil) then
                kept[#kept + 1] = it
            end
        end
        items = kept
    end
    local model = build_model(items)
    state.groups, state.items_flat, state.item_group = model.groups, model.items_flat, model.item_group
    state.cur = 1
    state.sel = (#state.groups > 0 and #state.groups[1].items > 0) and 2 or 1
    state.expanded = { [1] = true }
end

--- Which groups are open now: the focused group in "auto", the toggled set in "manual".
local function expanded_set(state)
    if state.mode == "manual" then
        return state.expanded
    end
    return { [state.item_group[state.cur] or 1] = true }
end

--- Compose one display line from segments, recording byte-range highlight spans.
local function compose(segments)
    local text, spans, off = "", {}, 0
    for _, seg in ipairs(segments) do
        local t = seg[1]
        if t ~= "" and seg[2] then
            spans[#spans + 1] = { off, off + #t, seg[2] }
        end
        text = text .. t
        off = off + #t
    end
    return text, spans
end

-- ─── theming (winbar type-tint) ───────────────────────────────────────────────

--- A tint of `accent`'s fg toward the panel bg by `t` (fg too when `fg_too`) — for the winbar chrome
--- cells coloured by the active filter type. Recomputed from the current theme.
local function tint_hl(accent, t, out, fg_too)
    local af = accent and api.nvim_get_hl(0, { name = accent, link = false })
    local fg = af and af.fg
    if not fg then
        return nil
    end
    local nb = api.nvim_get_hl(0, { name = "LvimUiPeekNormal", link = false })
    local bg = nb.bg or 0
    local function comp(c, sh)
        return math.floor(c / sh) % 256
    end
    local function mix(a, b)
        return math.floor(a * t + b * (1 - t) + 0.5)
    end
    local rgb = mix(comp(fg, 65536), comp(bg, 65536)) * 65536
        + mix(comp(fg, 256), comp(bg, 256)) * 256
        + mix(comp(fg, 1), comp(bg, 1))
    api.nvim_set_hl(0, out, { bg = rgb, fg = fg_too and fg or nil, bold = fg_too or nil })
    return out
end

-- ─── list render ──────────────────────────────────────────────────────────────

--- Pure render of the grouped list → (texts, frame hls {row0,c0,c1,hl}, cur→line map, row descriptors).
---@param state table
---@return string[], table[], table, table[]
local function render_list(state)
    local p = state.cfg
    local exp = expanded_set(state)
    local texts, rows, item_line, hls = {}, {}, {}, {}
    local function emit(descriptor, segments)
        local text, sp = compose(segments)
        texts[#texts + 1] = text
        rows[#texts] = descriptor
        for _, s in ipairs(sp) do
            hls[#hls + 1] = { #texts - 1, s[1], s[2], s[3] }
        end
        return #texts
    end
    for gi, g in ipairs(state.groups) do
        local icon = exp[gi] and (p.group_icon_open or "") or (p.group_icon_closed or "")
        emit({ kind = "header", gi = gi }, {
            { icon, "LvimUiPeekGroupIcon" },
            { " ", nil },
            { g.tail, "LvimUiPeekGroup" },
            { g.dir ~= "" and "  " or "", nil },
            { g.dir, "LvimUiPeekDir" },
            { "  ", nil },
            { tostring(#g.items), "LvimUiPeekCount" },
        })
        if exp[gi] then
            for _, entry in ipairs(g.items) do
                local it = entry.it
                local guide = p.guide_icon or "▏"
                local raw = it.text or ""
                local shown = raw:gsub("^%s+", "")
                local lead = #raw - #shown
                local iconseg = it.icon and (it.icon .. " ") or ""
                local prefix = #guide + 2 + #iconseg
                local ln = emit({ kind = "item", gi = gi, idx = entry.idx }, {
                    { guide, "LvimUiPeekGuide" },
                    { "  ", nil },
                    { iconseg, it.icon_hl or "LvimUiPeekText" },
                    { shown, "LvimUiPeekText" },
                })
                if state.list_match ~= false then
                    local c0 = math.max(0, (it.col or 1) - 1 - lead)
                    local same = not it.end_lnum or it.end_lnum == it.lnum
                    local c1
                    if it.end_col and same then
                        c1 = it.end_col - 1 - lead
                    elseif it.end_lnum and not same then
                        c1 = #shown
                    else
                        c1 = c0 + 1
                    end
                    c1 = math.max(c0 + 1, math.min(c1, #shown))
                    if c0 < #shown then
                        hls[#hls + 1] = { ln - 1, prefix + c0, prefix + c1, "LvimUiPeekMatch" }
                    end
                end
                item_line[entry.idx] = ln
            end
        end
    end
    return texts, hls, item_line, rows
end

--- The location currently in focus (auto = items_flat[cur]; manual = the item under the sel line).
---@param state table
---@return table|nil
local function focused(state)
    if state.mode == "manual" then
        local row = state.rows and state.rows[state.sel]
        return row and row.kind == "item" and state.items_flat[row.idx] or nil
    end
    return state.items_flat[state.cur]
end

--- The list winbar: kind + active PRIMARY filter label + filtered count, type-tinted.
---@param state table
local function winbar(state)
    local pan = state.list_pan
    if not (pan and pan.win and api.nvim_win_is_valid(pan.win)) then
        return
    end
    local label, accent
    for _, g in ipairs(state.bar and state.bar.groups or {}) do
        if g.primary then
            for _, b in ipairs(g.buttons) do
                if b.id == g.active then
                    label, accent = b.label, b.hl_active or "LvimUiPeekFilterActive"
                end
            end
        end
    end
    local kind_hl = (accent and tint_hl(accent, 0.4, "LvimLspPeekKindLabel", true)) or "LvimUiPeekKind"
    local count_hl = (accent and tint_hl(accent, 0.3, "LvimLspPeekKindType", true)) or "LvimUiPeekKindBar"
    vim.wo[pan.win].winbar = "%#"
        .. kind_hl
        .. "# "
        .. (state.kind or "Locations")
        .. " %#"
        .. count_hl
        .. "# "
        .. (label and (label .. " ") or "")
        .. "("
        .. #state.items_flat
        .. ")%="
end

-- ─── navigation / actions ─────────────────────────────────────────────────────

--- Reposition the list cursor to the focused row and refresh the preview + winbar.
---@param state table
local function sync(state)
    local pan = state.list_pan
    if not (pan and pan.win and api.nvim_win_is_valid(pan.win)) then
        return
    end
    local line = state.mode == "manual" and state.sel or (state.item_line and state.item_line[state.cur])
    if line then
        pcall(api.nvim_win_set_cursor, pan.win, { line, 0 })
    end
    winbar(state)
    if state.preview_pan and state.preview_pan.refresh then
        state.preview_pan.refresh()
    end
end

--- Move the selection by `delta`. Auto: through items (re-render so the focused group expands).
--- Manual: line by line over all rows.
---@param state table
---@param delta integer
local function move(state, delta)
    if state.mode == "manual" then
        local n = math.max(1, #state.rows)
        state.sel = math.max(1, math.min((state.sel or 1) + delta, n))
        sync(state)
    else
        if #state.items_flat == 0 then
            return
        end
        state.cur = math.max(1, math.min((state.cur or 1) + delta, #state.items_flat))
        state.list_pan.refresh() -- the focused group changed → re-expand
        sync(state)
    end
end

--- Open the focused location with `cmd` and close the peek.
---@param state table
---@param cmd string
local function jump(state, cmd)
    local it = focused(state)
    if not it then
        return
    end
    local origin, on_jump = state.origin, state.on_jump
    state.frame.close()
    if on_jump then
        on_jump(it, cmd)
        return
    end
    if origin and api.nvim_win_is_valid(origin) then
        api.nvim_set_current_win(origin)
    end
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(it.filename))
    pcall(api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- <CR> on the focused row: toggle a header (manual) / open an item.
---@param state table
local function activate(state)
    if state.mode == "manual" then
        local row = state.rows and state.rows[state.sel]
        if not row then
            return
        end
        if row.kind == "header" then
            state.expanded[row.gi] = not state.expanded[row.gi]
            state.list_pan.refresh()
            sync(state)
            return
        end
    end
    jump(state, "edit")
end

--- Apply filter group `gi` = button `id`: re-filter, re-render, refresh the header (active + counts).
---@param state table
---@param gi integer
---@param id string
local function set_filter(state, gi, id)
    state.bar.groups[gi].active = id
    apply_filter(state)
    if state.update_filter then
        state.update_filter()
    end
    state.list_pan.refresh()
    sync(state)
    state.frame.refresh_chrome()
end

-- ─── bars ─────────────────────────────────────────────────────────────────────

--- The filter header band (ui.bar buttons + `●` group separators) and an updater for active/counts.
---@param state table
---@return table band
local function filter_band(state)
    local specs = {}
    for gi, g in ipairs(state.bar.groups) do
        if gi > 1 then
            specs[#specs + 1] = { separator = "●", hl = "LvimUiPeekFilterSep", pad = "   " }
        end
        for _, b in ipairs(g.buttons) do
            local accent = b.hl_active or "LvimUiPeekFilterActive"
            local dim = b.hl or "LvimUiPeekFilterInactive"
            specs[#specs + 1] = {
                type = "label",
                label = b.label,
                key = b.key,
                _gi = gi,
                _id = b.id,
                count = function()
                    local n = 0
                    for _, it in ipairs(state.all_items) do
                        if passes_bar(state.bar, it, g) and (not b.predicate or b.predicate(it)) then
                            n = n + 1
                        end
                    end
                    return n
                end,
                active = b.id == g.active,
                run = function()
                    set_filter(state, gi, b.id)
                end,
                hl = {
                    normal = { key = accent, label = dim, count = dim },
                    active = { key = accent, label = accent, count = accent },
                    hover = { key = accent, label = dim, count = dim },
                },
            }
        end
    end
    -- Keep the active flags in sync when the filter changes.
    state.update_filter = function()
        for _, s in ipairs(specs) do
            if s._gi then
                s.active = state.bar.groups[s._gi].active == s._id
            end
        end
    end
    return { buttons = specs, align = "center" }
end

-- ─── open ─────────────────────────────────────────────────────────────────────

--- Open the peek over `opts.items`.
---@param opts { title?: string, items: table[], mode?: string, bar?: table, list_match?: boolean, actions?: table[], on_jump?: fun(item: table, cmd: string) }
---@param instance_cfg? table
---@return boolean opened
function M.open(opts, instance_cfg)
    opts = opts or {}
    if not opts.items or #opts.items == 0 then
        return false
    end
    local p = resolve_cfg(instance_cfg, opts)
    p.title = p.title or "LVIM LSP"

    local state = {
        cfg = p,
        on_jump = opts.on_jump,
        mode = nil, -- "manual" | "auto"
        all_items = opts.items,
        bar = opts.bar,
        list_match = opts.list_match ~= false,
        origin = api.nvim_get_current_win(),
        kind = opts.title or p.title,
    }
    state.mode = p.expand == "manual" and "manual" or "auto"
    apply_filter(state)

    local k = p.keys or {}
    local list_provider = {
        hide_cursor = true,
        cursorline = true,
        size = function()
            local w = 30
            for _, g in ipairs(state.groups) do
                w = math.max(w, util.dw(g.tail .. "  " .. g.dir) + 8)
            end
            return w, math.max(1, #state.items_flat + #state.groups)
        end,
        render = function()
            local texts, hls, item_line, rows = render_list(state)
            state.item_line, state.rows = item_line, rows
            return texts, hls
        end,
        keys = function(map, pan, st)
            state.list_pan, state.frame = pan, st
            vim.schedule(function()
                sync(state)
            end)
            map({ k.down or "j", "<Down>" }, function()
                move(state, 1)
            end)
            map({ k.up or "k", "<Up>" }, function()
                move(state, -1)
            end)
            map(k.jump or "<CR>", function()
                activate(state)
            end)
            map(k.split or "s", function()
                jump(state, "split")
            end)
            map(k.vsplit or "v", function()
                jump(state, "vsplit")
            end)
            map(k.focus_preview or "<C-l>", function()
                if state.preview_pan then
                    st.focus_panel(state.preview_idx)
                end
            end)
            -- caller's extra row actions (e.g. diagnostics: code action / yank / quickfix)
            for _, a in ipairs(opts.actions or {}) do
                map(a.key, function()
                    local it = focused(state)
                    if it then
                        a.run(it, function()
                            st.close()
                        end)
                    end
                end)
            end
        end,
    }

    local preview_provider = preview.new({
        item = function()
            return focused(state)
        end,
        number = p.preview_number,
        match_hl = "LvimUiPeekMatch",
    })

    -- Panel order honours list_position; the list carries the width weight, the preview takes the rest.
    local left = p.list_position ~= "right"
    local list_pan = { provider = list_provider, weight = p.list_width or 0.4, border = p.list_border }
    local prev_pan = { provider = preview_provider, border = p.preview_border }
    local panels = left and { list_pan, prev_pan } or { prev_pan, list_pan }
    state.preview_idx = left and 2 or 1
    preview_provider.back_panel = left and 1 or 2

    state.frame = frame.open({
        mode = p.mode == "split" and "split" or "float",
        dock = "below",
        title = p.title,
        border = p.border,
        panel_border = p.list_border,
        chevrons = p.chevrons,
        auto_width = false,
        auto_height = false,
        width = (p.float and p.float.width) or 0.85,
        height = p.mode == "split" and (p.preview_height or 16) or ((p.float and p.float.height) or 0.8),
        header = state.bar and { bands = { filter_band(state) } } or nil,
        panels = panels,
        footer = {
            actions = {
                {
                    key = k.jump or "<CR>",
                    name = "open",
                    run = function()
                        jump(state, "edit")
                    end,
                },
                {
                    key = k.split or "s",
                    name = "split",
                    run = function()
                        jump(state, "split")
                    end,
                },
                {
                    key = k.close or "q",
                    name = "close",
                    run = function(st)
                        st.close()
                    end,
                },
            },
        },
    })
    return true
end

return M
