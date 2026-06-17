-- lvim-lsp.ui.outline: a Document Symbols outline as a persistent side-split panel (neo-tree style).
--
-- Unlike the modal peek, this is a vertical split pinned to the far right (default) or left of the
-- tabpage (`nvim_open_win{ split=…, win=-1 }`). It tracks the current file's symbol tree, follows the
-- cursor, refreshes on edit, and jumps to a symbol on <CR>/click. The symbol tree is collapsible.
-- Pure UI over `textDocument/documentSymbol`; self-themed via the LvimLspOutline* groups.
--
---@module "lvim-lsp.ui.outline"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local frame = require("lvim-utils.ui.frame")
local uhl = require("lvim-utils.highlight")

local api = vim.api
local SymbolKind = vim.lsp.protocol.SymbolKind

local M = {}

local NS = api.nvim_create_namespace("LvimLspOutline") -- syntax (icon/name/detail) highlights
local NS_CURSOR = api.nvim_create_namespace("LvimLspOutlineCursor") -- the follow-cursor line, cleared on its own

-- SymbolKind name → its icon-colour group (defined in config/highlights.lua). Kinds are spread
-- across the palette so the column reads as a colourful legend rather than a few repeated hues.
local KIND_HL = {
    Function = "LvimLspOutlineKindFunc", -- blue
    Method = "LvimLspOutlineKindFunc",
    Constructor = "LvimLspOutlineKindFunc",
    Class = "LvimLspOutlineKindType", -- yellow
    Struct = "LvimLspOutlineKindType",
    Interface = "LvimLspOutlineKindIface", -- orange
    Enum = "LvimLspOutlineKindIface",
    EnumMember = "LvimLspOutlineKindIface",
    TypeParameter = "LvimLspOutlineKindIface",
    Variable = "LvimLspOutlineKindVar", -- cyan
    Field = "LvimLspOutlineKindField", -- teal
    Property = "LvimLspOutlineKindField",
    Constant = "LvimLspOutlineKindConst", -- red
    Module = "LvimLspOutlineKindModule", -- purple
    Namespace = "LvimLspOutlineKindModule",
    Package = "LvimLspOutlineKindModule",
    File = "LvimLspOutlineKindModule",
    String = "LvimLspOutlineKindValue", -- green
    Number = "LvimLspOutlineKindValue",
    Boolean = "LvimLspOutlineKindValue",
    Array = "LvimLspOutlineKindObject", -- magenta
    Object = "LvimLspOutlineKindObject",
    Key = "LvimLspOutlineKindObject",
    Null = "LvimLspOutlineKindObject",
}

---@class OutlineState
local state = {
    win = nil, ---@type integer|nil   the panel window
    buf = nil, ---@type integer|nil   the panel buffer
    src_buf = nil, ---@type integer|nil  the source buffer being outlined
    src_win = nil, ---@type integer|nil  the window holding the source
    tree = {}, ---@type table[]       normalized symbol nodes
    rows = {}, ---@type table<integer, table>  panel line → node
    collapsed = {}, ---@type table<string, boolean>  fold state by node path
    auto_fold = false, ---@type boolean  runtime accordion state (seeded from config, toggled at runtime)
    augroup = nil, ---@type integer|nil
    timer = nil, ---@type uv.uv_timer_t|nil
}

--- The effective outline config (live, merged in config/ui.lua).
local function cfg()
    return (lsp_state.config or {}).outline or {}
end

--- The glyph + highlight group for a SymbolKind number (shared with the workspace-symbols peek).
---@param kind integer
---@return string icon, string hl
function M.kind_icon(kind)
    local name = SymbolKind[kind] or "Variable"
    return (cfg().icons or {})[name] or "", KIND_HL[name] or "LvimLspOutlineKindMisc"
end

local function is_valid_win(w)
    return w and api.nvim_win_is_valid(w)
end

--- True when `group` (following links and the dotted-capture fallback, e.g.
--- `@keyword.conditional.lua` → `@keyword.conditional` → `@keyword`) resolves to a real foreground
--- colour. Used to skip underline/sign-only extmarks (diagnostics set `sp`/undercurl, no `fg`).
---@param group? string
---@param depth? integer
---@return boolean
local function has_fg(group, depth)
    depth = depth or 0
    if depth > 16 or not group then
        return false
    end
    local ok, h = pcall(api.nvim_get_hl, 0, { name = group })
    if not ok or type(h) ~= "table" then
        return false
    end
    if h.fg then
        return true
    end
    if h.link then
        return has_fg(h.link, depth + 1)
    end
    local cut = group:match("^(.*)%.[^.]+$")
    return cut ~= nil and has_fg(cut, depth + 1)
end

--- The highlight group colouring the symbol at (1-based lnum, col) in the source buffer, so the
--- outline mirrors the file 1:1. Returns the EXACT group the buffer paints there — the highest
--- render-priority layer that actually sets a foreground, across semantic tokens, treesitter, syntax
--- AND plugin extmarks. The extmark layer matters: rainbow-delimiters colours `if`/`for`/`end` by
--- nesting depth at priority 112 (above treesitter's 100), so a semantic/treesitter-only lookup would
--- show the wrong (uniform) keyword colour. When the position has no colour — lua_ls points some
--- statement symbols' selection range at whitespace / the wrong token — it recovers by colouring from
--- where the symbol's NAME sits on the line. nil = no buffer colour found → caller uses the kind colour.
---@param bufnr integer
---@param lnum integer
---@param col integer
---@param name? string   the symbol name, used to recover the colour when the position has none
---@return string|nil
local function source_hl(bufnr, lnum, col, name)
    if not (bufnr and api.nvim_buf_is_valid(bufnr)) then
        return nil
    end
    -- Gather every highlight layer at the position with its render priority, then pick the
    -- highest-priority group that sets a foreground — exactly what the buffer paints on screen.
    local function at(l, c)
        local ok, info = pcall(vim.inspect_pos, bufnr, l, c)
        if not ok or type(info) ~= "table" then
            return nil
        end
        -- Collect every layer at the position with its render priority, in application order. Within a
        -- layer a position can carry both a general and a more specific capture (e.g. `@variable` AND
        -- `@variable.parameter`); the LATER one is what the buffer shows, so ties must keep this order.
        local cands = {}
        local function push(g, p)
            if g then
                cands[#cands + 1] = { g = g, p = p, i = #cands }
            end
        end
        for _, e in ipairs(info.semantic_tokens or {}) do
            push(e.hl_group, e.priority or 125)
        end
        for _, e in ipairs(info.treesitter or {}) do
            push(e.hl_group, e.priority or 100)
        end
        for _, e in ipairs(info.syntax or {}) do
            push(e.hl_group, 50)
        end
        for _, e in ipairs(info.extmarks or {}) do
            local o = e.opts or {}
            push(o.hl_group, o.priority or 0)
        end
        -- Stable sort by (priority, insertion index) so equal-priority captures keep their order, then
        -- take the highest-priority / latest group that actually paints a foreground.
        table.sort(cands, function(a, b)
            if a.p ~= b.p then
                return a.p < b.p
            end
            return a.i < b.i
        end)
        for k = #cands, 1, -1 do
            if has_fg(cands[k].g) then
                return cands[k].g
            end
        end
        return nil
    end
    -- Colour from where the symbol NAME sits on its line — that is the text the outline shows, so its
    -- colour should match how the name looks in the file. lua_ls often points the selection range at a
    -- different token than the name (`return {…}` → the `{` → a constructor colour; `if` → whitespace),
    -- so name-first avoids those. Fall back to the selection-range position when the name isn't found.
    if name and name ~= "" then
        local line = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        local s = line and line:find(name, 1, true)
        if s then
            local g = at(lnum - 1, s - 1)
            if g then
                return g
            end
        end
    end
    return at(lnum - 1, math.max(0, col - 1))
end

-- Forward declaration: accordion fold — keep only the ancestors of the symbol under the source
-- cursor expanded (defined below, referenced by `request` which is defined earlier).
---@type fun()
local apply_auto_fold

-- ── symbol model ──────────────────────────────────────────────────────────────

--- Normalize a documentSymbol result (DocumentSymbol tree OR flat SymbolInformation) into a tree of
--- `{ name, kind, detail, lnum, col, range, children }` (1-based lnum/col).
---@param result table[]|nil
---@return table[]
local function normalize(result)
    local use_src = cfg().source_colors ~= false
    local nodes = {}
    for _, s in ipairs(result or {}) do
        if s.selectionRange or (s.range and s.children ~= nil) or (s.range and not s.location) then
            -- DocumentSymbol (nested)
            local sel = s.selectionRange or s.range
            local lnum, col = sel.start.line + 1, sel.start.character + 1
            nodes[#nodes + 1] = {
                name = s.name or "?",
                kind = s.kind,
                detail = s.detail,
                lnum = lnum,
                col = col,
                range = s.range,
                hl = use_src and source_hl(state.src_buf, lnum, col, s.name) or nil,
                children = normalize(s.children),
            }
        elseif s.location then
            -- SymbolInformation (flat)
            local r = s.location.range
            local lnum, col = r.start.line + 1, r.start.character + 1
            nodes[#nodes + 1] = {
                name = s.name or "?",
                kind = s.kind,
                detail = s.containerName,
                lnum = lnum,
                col = col,
                range = r,
                hl = use_src and source_hl(state.src_buf, lnum, col, s.name) or nil,
                children = {},
            }
        end
    end
    return nodes
end

--- A stable fold/identity key for a node within its parent path.
---@param parent_path string
---@param node table
---@return string
local function node_path(parent_path, node)
    return parent_path .. "/" .. (node.name or "?") .. ":" .. tostring(node.lnum)
end

-- ── rendering ───────────────────────────────────────────────────────────────

--- Render the tree into buffer lines, highlight spans, virtual-text (the dim `detail`) and the
--- line→node map. Each line is `<guides><marker><icon> <name>`: vertical guide lines (│) for the
--- ancestor levels, then a fixed 2-column MARKER — a fold arrow for a collapsible node, a ├ / └
--- branch connector for a leaf that has a parent, or two spaces for a top-level leaf — then the kind
--- icon and name. The marker is padded to exactly two display columns, so a child's icon always sits
--- under its parent's name regardless of glyph width. Every glyph comes from the config; the
--- `detail`/signature trails as dim virtual text.
---@return string[] lines, table[] hls, table[] virts, table<integer, table> rows
local function render_tree()
    local oc = cfg()
    local icons = oc.icons or {}
    local fold = oc.fold or {}
    local open, closed = fold.open or "▾", fold.closed or "▸"
    local guide_char, branch, branch_last = oc.guide or "│", oc.branch or "├", oc.branch_last or "└"

    -- Pad a 1-glyph marker to exactly two display columns (alignment is by display width, since the
    -- glyphs are multibyte and may render 1 or 2 cells wide).
    local function cell(glyph)
        return glyph .. string.rep(" ", math.max(0, 2 - vim.fn.strdisplaywidth(glyph)))
    end

    local lines, hls, virts, rows = {}, {}, {}, {}

    ---@param nodes table[]
    ---@param guide string       the accumulated ancestor guide columns ("│ " / "  " per level)
    ---@param parent_path string
    local function walk(nodes, guide, parent_path)
        local count = #nodes
        for i, n in ipairs(nodes) do
            local is_last = i == count
            local path = node_path(parent_path, n)
            local has_children = n.children and #n.children > 0
            local kind_name = SymbolKind[n.kind] or "Variable"
            local icon = icons[kind_name] or ""

            -- Marker: fold arrow for a foldable node; a ├/└ connector for a leaf that has a parent;
            -- two blanks for a top-level leaf (roots carry no connector).
            local arrow = has_children and (state.collapsed[path] and closed or open) or nil
            local connector = (not arrow and guide ~= "") and (is_last and branch_last or branch) or nil
            local marker = arrow or connector
            local fold_cell = marker and cell(marker) or "  "

            lines[#lines + 1] = guide .. fold_cell .. icon .. " " .. n.name
            local row = #lines

            hls[#hls + 1] = { row - 1, 0, #guide, "LvimLspOutlineGuide" }
            if marker then
                hls[#hls + 1] =
                    { row - 1, #guide, #guide + #marker, arrow and "LvimLspOutlineFold" or "LvimLspOutlineGuide" }
            end
            -- Icon + name share ONE colour. With `source_colors` it is the symbol's own colour from
            -- the buffer (semantic/treesitter), falling back to the per-kind colour when the buffer
            -- has none — so the icon and name never diverge (e.g. for keyword symbols if/else/return).
            -- With `source_colors = false`: kind colour for the icon, plain name colour for the text.
            local icon_hl, name_hl
            if oc.source_colors ~= false then
                icon_hl = n.hl or KIND_HL[kind_name] or "LvimLspOutlineKindMisc"
                name_hl = icon_hl
            else
                icon_hl = KIND_HL[kind_name] or "LvimLspOutlineKindMisc"
                name_hl = "LvimLspOutlineName"
            end
            local ioff = #guide + #fold_cell
            hls[#hls + 1] = { row - 1, ioff, ioff + #icon, icon_hl }
            local noff = ioff + #icon + 1
            hls[#hls + 1] = { row - 1, noff, noff + #n.name, name_hl }

            -- The symbol's detail / signature trails as dim virtual text (does not affect the buffer
            -- text, so clicks land on the name). Toggle off with `outline.detail = false`.
            if oc.detail ~= false and n.detail and n.detail ~= "" then
                virts[#virts + 1] = { row - 1, n.detail }
            end

            rows[row] = { lnum = n.lnum, col = n.col, path = path, has_children = has_children, range = n.range }
            if has_children and not state.collapsed[path] then
                walk(n.children, guide .. (is_last and "  " or guide_char .. " "), path)
            end
        end
    end

    walk(state.tree, "", "")
    if #lines == 0 then
        lines = { " No symbols" }
        hls = { { 0, 0, -1, "LvimLspOutlineDetail" } }
    end
    return lines, hls, virts, rows
end

--- Repaint the panel buffer from `state.tree` and refresh the follow highlight.
local function render()
    if not (is_valid_win(state.win) and state.buf and api.nvim_buf_is_valid(state.buf)) then
        return
    end
    local lines, hls, virts, rows = render_tree()
    state.rows = rows
    vim.bo[state.buf].modifiable = true
    api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
    for _, h in ipairs(hls) do
        pcall(
            api.nvim_buf_set_extmark,
            state.buf,
            NS,
            h[1],
            h[2],
            { end_col = h[3] < 0 and nil or h[3], end_row = h[3] < 0 and h[1] + 1 or nil, hl_group = h[4] }
        )
    end
    for _, v in ipairs(virts) do
        pcall(api.nvim_buf_set_extmark, state.buf, NS, v[1], 0, {
            virt_text = { { " " .. v[2], "LvimLspOutlineDetail" } },
            virt_text_pos = "eol",
            hl_mode = "combine",
        })
    end
    M.follow()
end

-- ── data + follow ─────────────────────────────────────────────────────────────

--- Request documentSymbol for `bufnr` and re-render. No-op without a supporting client.
---@param bufnr integer
local function request(bufnr)
    if not (bufnr and api.nvim_buf_is_valid(bufnr)) then
        return
    end
    if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentSymbol" }) == 0 then
        state.tree = {}
        render()
        return
    end
    local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", params, function(results)
        local merged = {}
        for _, r in pairs(results or {}) do
            for _, s in ipairs(r.result or {}) do
                merged[#merged + 1] = s
            end
        end
        state.tree = normalize(merged)
        if state.auto_fold then
            apply_auto_fold()
        end
        render()
    end)
end

--- The deepest panel row whose symbol range contains the source cursor (0-based line), or nil.
---@param line0 integer
---@return integer|nil
local function row_at_line(line0)
    local best
    for row, n in pairs(state.rows) do
        local r = n.range
        if r and r.start.line <= line0 and line0 <= r["end"].line then
            if
                not best
                or state.rows[best].range["end"].line - state.rows[best].range.start.line
                    >= r["end"].line - r.start.line
            then
                best = row -- prefer the tightest (smallest) enclosing range
            end
        end
    end
    return best
end

--- Highlight the symbol under the source cursor (follow mode).
function M.follow()
    if not (cfg().follow ~= false and is_valid_win(state.win) and state.buf and api.nvim_buf_is_valid(state.buf)) then
        return
    end
    api.nvim_buf_clear_namespace(state.buf, NS_CURSOR, 0, -1)
    if not is_valid_win(state.src_win) then
        return
    end
    local line0 = api.nvim_win_get_cursor(state.src_win)[1] - 1
    local row = row_at_line(line0)
    if row then
        pcall(api.nvim_buf_set_extmark, state.buf, NS_CURSOR, row - 1, 0, {
            line_hl_group = "LvimLspOutlineCursor",
            priority = 200,
        })
        -- Only reposition the PANEL cursor when following from the source (focus elsewhere). When the
        -- user is navigating/folding inside the panel, leave their cursor where it is.
        if is_valid_win(state.win) and api.nvim_get_current_win() ~= state.win then
            pcall(api.nvim_win_set_cursor, state.win, { row, 0 })
        end
    end
end

-- ── window lifecycle ───────────────────────────────────────────────────────────

--- The source buffer to outline: the current buffer when it is a real file, else the tracked one.
---@return integer|nil bufnr, integer|nil winnr
local function pick_source()
    local w = api.nvim_get_current_win()
    if w ~= state.win then
        local b = api.nvim_win_get_buf(w)
        if vim.bo[b].buftype == "" and api.nvim_buf_get_name(b) ~= "" then
            return b, w
        end
    end
    return state.src_buf, state.src_win
end

--- Jump to the symbol on panel line `row` (focuses the source). `close` forces the panel shut.
---@param row integer
---@param close? boolean
local function jump(row, close)
    local n = state.rows[row]
    if not (n and is_valid_win(state.src_win)) then
        return
    end
    api.nvim_set_current_win(state.src_win)
    pcall(api.nvim_win_set_cursor, state.src_win, { n.lnum, math.max(0, n.col - 1) })
    vim.cmd("normal! zz")
    if close then
        M.close()
    end
end

--- Move the SOURCE cursor to the symbol but keep focus in the panel (preview). Remembers where the
--- source cursor was so `restore_location` can return to it.
---@param row integer
local function peek(row)
    local n = state.rows[row]
    if not (n and is_valid_win(state.src_win)) then
        return
    end
    state.saved_cursor = state.saved_cursor or api.nvim_win_get_cursor(state.src_win)
    pcall(api.nvim_win_set_cursor, state.src_win, { n.lnum, math.max(0, n.col - 1) })
    api.nvim_win_call(state.src_win, function()
        vim.cmd("normal! zz")
    end)
end

--- Restore the source cursor to where it was before the first peek.
local function restore()
    if state.saved_cursor and is_valid_win(state.src_win) then
        pcall(api.nvim_win_set_cursor, state.src_win, state.saved_cursor)
        api.nvim_win_call(state.src_win, function()
            vim.cmd("normal! zz")
        end)
        state.saved_cursor = nil
    end
end

--- Focus the source at the symbol on `row`, then run an LSP buffer action (hover / code action /
--- rename) so it targets the right position.
---@param row integer
---@param fn fun()
local function at_symbol(row, fn)
    local n = state.rows[row]
    if n and is_valid_win(state.src_win) then
        api.nvim_set_current_win(state.src_win)
        pcall(api.nvim_win_set_cursor, state.src_win, { n.lnum, math.max(0, n.col - 1) })
        fn()
    end
end

--- Visit every node of the tree with its fold path.
---@param nodes table[]
---@param parent_path string
---@param fn fun(node: table, path: string)
local function walk_paths(nodes, parent_path, fn)
    for _, n in ipairs(nodes) do
        local path = node_path(parent_path, n)
        fn(n, path)
        if n.children then
            walk_paths(n.children, path, fn)
        end
    end
end

--- Set every collapsible node's fold state, then re-render. A manual fold-all suspends the accordion.
---@param collapsed boolean
local function set_all(collapsed)
    state.auto_fold = false
    state.collapsed = {}
    if collapsed then
        walk_paths(state.tree, "", function(n, path)
            if n.children and #n.children > 0 then
                state.collapsed[path] = true
            end
        end)
    end
    render()
end

--- Accordion: collapse every foldable node except the ancestor chain of the symbol under the source
--- cursor, so only the current symbol's parents stay open. No-op without a source window.
apply_auto_fold = function()
    if not is_valid_win(state.src_win) then
        return
    end
    local line0 = api.nvim_win_get_cursor(state.src_win)[1] - 1
    local open = {}
    -- Descend one TIGHTEST node per level (sibling ranges can overlap on shared boundary lines —
    -- e.g. lua_ls gives if/else adjacent ranges — so picking every match would open more than one
    -- branch). Only the single path to the most specific enclosing symbol is kept open.
    local function descend(nodes, parent_path)
        local best, best_path
        for _, n in ipairs(nodes) do
            local r = n.range
            if r and r.start.line <= line0 and line0 <= r["end"].line then
                local span = r["end"].line - r.start.line
                if not best or span < (best.range["end"].line - best.range.start.line) then
                    best, best_path = n, node_path(parent_path, n)
                end
            end
        end
        if best then
            open[best_path] = true
            if best.children then
                descend(best.children, best_path)
            end
        end
    end
    descend(state.tree, "")
    state.collapsed = {}
    walk_paths(state.tree, "", function(n, path)
        if n.children and #n.children > 0 and not open[path] then
            state.collapsed[path] = true
        end
    end)
end

--- Set / toggle the fold of the symbol on panel line `row`.
---@param row integer
---@param to boolean|nil   true=collapse, false=expand, nil=toggle
local function set_fold(row, to)
    local n = state.rows[row]
    if n and n.has_children then
        state.auto_fold = false -- manual fold suspends the accordion
        if to == nil then
            to = not state.collapsed[n.path]
        end
        state.collapsed[n.path] = to or nil
        render()
    end
end

-- Action name → label, in display order (for the `?` cheatsheet).
local HELP = {
    { "goto_location", "jump to the symbol" },
    { "goto_and_close", "jump and close" },
    { "peek_location", "preview (keep focus here)" },
    { "restore_location", "restore source cursor" },
    { "up_and_jump", "previous symbol + preview" },
    { "down_and_jump", "next symbol + preview" },
    { "fold", "collapse" },
    { "unfold", "expand" },
    { "fold_toggle", "toggle fold" },
    { "fold_all", "collapse all" },
    { "unfold_all", "expand all" },
    { "fold_toggle_all", "toggle all" },
    { "fold_reset", "reset folds" },
    { "fold_auto", "resume accordion auto-fold" },
    { "hover_symbol", "hover" },
    { "code_actions", "code actions" },
    { "rename_symbol", "rename" },
    { "help", "this help" },
    { "close", "close" },
}

--- Show the keymap cheatsheet — a read-only `frame` popup of full-width, column-aligned rows: a KEY box
--- + a DESCRIPTION box, striped blue (odd) / yellow (even), each box a tint of its accent (key 0.4,
--- description 0.2 — the tint canon).
local function show_help()
    local keys = cfg().keys or {}
    -- The tint highlight groups, recomputed from the live palette so they track the theme.
    local C = require("lvim-utils.colors")
    local function mtint(color, t)
        return uhl.blend(color, C.bg, t)
    end
    -- Key box = 0.4 (bold). Description box = 0.2, but on the ACTIVE row it rises to 0.4 so the whole row
    -- reads as one solid tint of its accent.
    api.nvim_set_hl(0, "LvimLspOutlineHelpKeyB", { fg = C.blue, bg = mtint(C.blue, 0.4), bold = true })
    api.nvim_set_hl(0, "LvimLspOutlineHelpDescB", { fg = C.blue, bg = mtint(C.blue, 0.2) })
    api.nvim_set_hl(0, "LvimLspOutlineHelpDescActiveB", { fg = C.blue, bg = mtint(C.blue, 0.4) })
    api.nvim_set_hl(0, "LvimLspOutlineHelpKeyY", { fg = C.yellow, bg = mtint(C.yellow, 0.4), bold = true })
    api.nvim_set_hl(0, "LvimLspOutlineHelpDescY", { fg = C.yellow, bg = mtint(C.yellow, 0.2) })
    api.nvim_set_hl(0, "LvimLspOutlineHelpDescActiveY", { fg = C.yellow, bg = mtint(C.yellow, 0.4) })

    local items = {}
    for _, e in ipairs(HELP) do
        local lhs = keys[e[1]]
        if lhs then
            lhs = type(lhs) == "table" and table.concat(lhs, " / ") or lhs
            items[#items + 1] = { lhs, e[2] }
        end
    end
    local kw, dw = 0, 0
    for _, r in ipairs(items) do
        kw = math.max(kw, vim.fn.strdisplaywidth(r[1]))
        dw = math.max(dw, vim.fn.strdisplaywidth(r[2]))
    end
    local keybox = kw + 4 -- 2 spaces left of the key + key + ≥2 right — the fixed, aligned KEY column

    local pan
    local provider = {
        hide_cursor = true, -- no hardware cursor; the active row is shown by the brighter (0.4) description
        size = function()
            return keybox + dw + 4, #items
        end,
        render = function(width)
            local cur = (pan and pan.win and api.nvim_win_is_valid(pan.win)) and api.nvim_win_get_cursor(pan.win)[1]
                or 1
            local lines, hls = {}, {}
            for i, r in ipairs(items) do
                local s = (i % 2 == 1) and "B" or "Y" -- odd = blue, even = yellow
                local kcell = "  " .. r[1]
                kcell = kcell .. string.rep(" ", math.max(0, keybox - #kcell))
                local dcell = "  " .. r[2]
                dcell = dcell .. string.rep(" ", math.max(0, width - keybox - #dcell)) -- fill to full width
                lines[i] = kcell .. dcell
                local desc = (i == cur) and ("LvimLspOutlineHelpDescActive" .. s) or ("LvimLspOutlineHelpDesc" .. s)
                hls[#hls + 1] = { i - 1, 0, #kcell, "LvimLspOutlineHelpKey" .. s }
                hls[#hls + 1] = { i - 1, #kcell, #lines[i], desc }
            end
            return lines, hls
        end,
        keys = function(_, p)
            pan = p
            -- Re-render so the brighter active-row tint follows the (hidden) cursor.
            api.nvim_create_autocmd("CursorMoved", {
                buffer = p.buf,
                callback = function()
                    if p.refresh then
                        p.refresh()
                    end
                end,
            })
        end,
    }
    -- Close on the panel's close keys + the help key itself (so `g?` toggles the cheatsheet).
    local close = vim.list_extend({ "<Esc>" }, type(keys.close) == "table" and keys.close or { keys.close })
    if keys.help then
        close[#close + 1] = keys.help
    end
    frame.open({
        mode = "float",
        border = { "", " ", "", " ", "", "", "", " " }, -- top " " for the brand + " " gutter left/right
        title = "Outline keymaps",
        panel_border = "none",
        size = { width = { auto = true, max = 0.7 }, height = { auto = true, max = 0.7 } },
        close_keys = close,
        content = { blocks = { { id = "help", provider = provider } } },
        footer = {
            bars = {
                {
                    items = {
                        {
                            key = "q",
                            name = "close",
                            run = function(st)
                                st.close()
                            end,
                        },
                    },
                },
            },
        },
    })
end

local function set_keys()
    local function map(lhs, fn)
        if lhs then
            vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
        end
    end
    local function cur_row()
        return api.nvim_win_get_cursor(state.win)[1]
    end
    local function move(delta)
        local target = math.max(1, math.min(cur_row() + delta, api.nvim_buf_line_count(state.buf)))
        api.nvim_win_set_cursor(state.win, { target, 0 })
        peek(target)
    end

    -- Action name → handler (receives the current row).
    local actions = {
        goto_location = function(r)
            jump(r, cfg().auto_close)
        end,
        goto_and_close = function(r)
            jump(r, true)
        end,
        peek_location = peek,
        restore_location = restore,
        up_and_jump = function()
            move(-1)
        end,
        down_and_jump = function()
            move(1)
        end,
        fold = function(r)
            set_fold(r, true)
        end,
        unfold = function(r)
            set_fold(r, false)
        end,
        fold_toggle = function(r)
            set_fold(r, nil)
        end,
        fold_all = function()
            set_all(true)
        end,
        unfold_all = function()
            set_all(false)
        end,
        fold_toggle_all = function()
            set_all(next(state.collapsed) == nil)
        end,
        fold_reset = function()
            set_all(cfg().fold_initial == "all")
        end,
        fold_auto = function()
            state.auto_fold = true
            apply_auto_fold()
            render()
        end,
        hover_symbol = function(r)
            at_symbol(r, vim.lsp.buf.hover)
        end,
        code_actions = function(r)
            at_symbol(r, vim.lsp.buf.code_action)
        end,
        rename_symbol = function(r)
            at_symbol(r, vim.lsp.buf.rename)
        end,
        help = show_help,
        close = M.close,
    }
    for action, lhs in pairs(cfg().keys or {}) do
        local fn = actions[action]
        if fn then
            for _, k in ipairs(type(lhs) == "table" and lhs or { lhs }) do
                map(k, function()
                    fn(cur_row())
                end)
            end
        end
    end

    map("<LeftMouse>", function()
        local m = vim.fn.getmousepos()
        if m.winid == state.win then
            jump(m.line, cfg().auto_close)
        end
    end)
    map("<2-LeftMouse>", function()
        local m = vim.fn.getmousepos()
        if m.winid == state.win then
            set_fold(m.line, nil)
        end
    end)
end

local function setup_autocmds()
    state.augroup = api.nvim_create_augroup("LvimLspOutline", { clear = true })
    local function schedule_refresh()
        if state.timer then
            state.timer:stop()
        end
        state.timer = vim.defer_fn(function()
            local b, w = pick_source()
            if b then
                state.src_buf, state.src_win = b, w
                request(b)
            end
        end, 250)
    end
    api.nvim_create_autocmd({ "BufEnter", "LspAttach", "InsertLeave", "TextChanged" }, {
        group = state.augroup,
        callback = function(ev)
            if is_valid_win(state.win) and ev.buf ~= state.buf then
                schedule_refresh()
            end
        end,
    })
    api.nvim_create_autocmd("CursorMoved", {
        group = state.augroup,
        callback = function(ev)
            -- Only react to the cursor moving in the REAL source buffer (not the panel, popups, or any
            -- other buffer) — that is what the outline tracks.
            if not (is_valid_win(state.win) and ev.buf == state.src_buf) then
                return
            end
            if state.auto_fold then
                apply_auto_fold()
                render() -- re-render with the new folds (render() re-applies the follow highlight)
            else
                M.follow()
            end
        end,
    })
    -- (Window-close teardown is the frame's job now — it fires the provider `on_close` on any frame
    -- window closing, so the outline no longer needs its own WinClosed watcher.)
end

--- Whether the panel is open.
---@return boolean
function M.is_open()
    return is_valid_win(state.win)
end

--- Open the outline panel (a far-side vertical split). Keeps focus in the source by default.
---@param enter? boolean  focus the panel
function M.open(enter)
    if M.is_open() then
        if enter then
            api.nvim_set_current_win(state.win)
        end
        return
    end
    local b, w = pick_source()
    if not b then
        notify("Outline: no file buffer to outline.", vim.log.levels.INFO)
        return
    end
    state.src_buf, state.src_win = b, w
    state.auto_fold = cfg().auto_fold ~= false -- seed the runtime accordion state from config

    local c = cfg()
    local width = c.width or 0.25
    local side = c.position == "left" and "left" or "right"
    local title = c.title
    if title == nil then
        title = "LVIM LSP OUTLINE"
    end

    -- A PERSISTENT docked frame: the tree IS the provider. Its `update` OWNS the panel buffer (the frame
    -- writes nothing for it), so the existing render() / follow() / fold / keymaps keep driving
    -- `state.buf` / `state.win` = the frame's panel buf/win, unchanged. The cursor is hidden via the
    -- user's `panel_ft = { "lvim-lsp-outline" }` registration (the ft set below). Leaving the panel works
    -- with `<C-w>w` (cycle) and, for the side dock, `<C-h>` (the frame's dock-aware directional escape).
    local provider = {
        cursorline = true,
        filetype = "lvim-lsp-outline", -- the frame stamps this on the panel buffer (cursor hiding + ft)
        size = function()
            local px = (width <= 1) and math.floor(vim.o.columns * width) or math.floor(width)
            return math.max(20, px), 1
        end,
        update = function(pan)
            if state.buf ~= pan.buf then
                state.buf, state.win = pan.buf, pan.win
                vim.bo[pan.buf].buftype = "nofile"
            end
            render()
        end,
        keys = function(_, pan)
            state.buf, state.win = pan.buf, pan.win
            set_keys()
        end,
        on_close = function()
            if state.timer then
                state.timer:stop()
                state.timer = nil
            end
            if state.augroup then
                pcall(api.nvim_del_augroup_by_id, state.augroup)
                state.augroup = nil
            end
            state.win, state.buf, state.rows, state.tree, state.frame = nil, nil, {}, {}, nil
        end,
    }

    state.frame = frame.open({
        mode = "split",
        native = true, -- a REAL split window (not a float over a container) → native `<C-w>` nav + redraw
        dock = side,
        enter = enter == true, -- focus the panel only when explicitly asked; else keep the cursor in code
        persistent = true,
        title = (title ~= false and title ~= "") and title or nil, -- centred winbar (blue-tinted)
        size = { width = { fixed = width } },
        content = { blocks = { { id = "tree", provider = provider } } },
        close_keys = {}, -- persistent: the outline's own `close` key (→ M.close) tears the frame down
    })
    setup_autocmds()
    request(b)
end

--- Close the outline panel. Delegates to the frame's teardown, which fires the provider `on_close`
--- (stops the timer, deletes the autocmds, clears state). Idempotent.
function M.close()
    if not state.frame then
        return
    end
    local f = state.frame
    state.frame = nil
    pcall(f.close)
end

--- Toggle the panel.
function M.toggle()
    if M.is_open() then
        M.close()
    else
        M.open(false)
    end
end

--- Focus the panel (opening it if needed).
function M.focus()
    M.open(true)
    if is_valid_win(state.win) then
        api.nvim_set_current_win(state.win)
    end
end

return M
