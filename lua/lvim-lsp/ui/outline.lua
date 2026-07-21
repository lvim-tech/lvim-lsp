-- lvim-lsp.ui.outline: a Document Symbols outline as a persistent side-split panel (neo-tree style).
--
-- Unlike the modal peek, this is a vertical split pinned to the far right (default) or left of the
-- tabpage (`nvim_open_win{ split=…, win=-1 }`). It tracks the current file's symbol tree, follows the
-- cursor, refreshes on edit, and jumps to a symbol on <CR>/click. The symbol tree is collapsible.
-- Pure UI over `textDocument/documentSymbol`. The tree itself renders through the SHARED
-- `lvim-ui.tree` primitive (guides/markers/fold state/mark/scrollbar/canonical keys + mouse); this
-- module owns only the LSP data (request/normalize), the source-colour lookup, the accordion
-- auto-fold, the follow logic and the outline actions. Self-themed via the LvimLspOutline* groups.
--
---@module "lvim-lsp.ui.outline"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local surface = require("lvim-ui.surface")
local lvim_ui = require("lvim-ui")
local uhl = require("lvim-utils.highlight")

local api = vim.api
local uv = vim.uv
local SymbolKind = vim.lsp.protocol.SymbolKind

local M = {}

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
    panel = nil, ---@type table|nil   the lvim-ui.tree handle (the shared tree content layer)
    auto_fold = false, ---@type boolean  runtime accordion state (seeded from config, toggled at runtime)
    augroup = nil, ---@type integer|nil
    timer = nil, ---@type uv.uv_timer_t|nil
    saved_cursor = nil, ---@type integer[]|nil  peek restore point (source cursor before a jump)
    surface = nil, ---@type table|nil  the lvim-utils.ui.frame handle for the panel
    src_source = nil, ---@type table|nil     the push source attached for the current source buffer (if any)
    src_source_buf = nil, ---@type integer|nil  the buffer that push source is attached to
}

-- Alternative outline SOURCES, keyed by filetype. A plugin whose server exposes a richer tree
-- than textDocument/documentSymbol (e.g. dartls' Flutter Outline) registers a push source here;
-- for a buffer of that filetype the panel renders the pushed nodes instead of requesting symbols.
---@type table<string, { attach: fun(bufnr: integer, push: fun(nodes: table[])), detach: fun(bufnr: integer) }>
local sources = {}

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

-- Memoized `has_fg` result per highlight group. The same handful of groups are resolved for EVERY node
-- on EVERY refresh (a 500-symbol file = thousands of nvim_get_hl calls, each walking a link/capture
-- chain), so the boolean is cached and only cleared when the palette changes (ColorScheme).
---@type table<string, boolean>
local fg_cache = {}
api.nvim_create_autocmd("ColorScheme", {
    group = api.nvim_create_augroup("LvimLspOutlineFgCache", { clear = true }),
    callback = function()
        fg_cache = {}
    end,
})

--- True when `group` (following links and the dotted-capture fallback, e.g.
--- `@keyword.conditional.lua` → `@keyword.conditional` → `@keyword`) resolves to a real foreground
--- colour. Used to skip underline/sign-only extmarks (diagnostics set `sp`/undercurl, no `fg`).
--- Memoized per group (see `fg_cache`) — invalidated on ColorScheme.
---@param group? string
---@param depth? integer
---@return boolean
local function has_fg(group, depth)
    depth = depth or 0
    if depth > 16 or not group then
        return false
    end
    local cached = fg_cache[group]
    if cached ~= nil then
        return cached
    end
    local result
    local ok, h = pcall(api.nvim_get_hl, 0, { name = group })
    if not ok or type(h) ~= "table" then
        result = false
    elseif h.fg then
        result = true
    elseif h.link then
        result = has_fg(h.link, depth + 1)
    else
        local cut = group:match("^(.*)%.[^.]+$")
        result = cut ~= nil and has_fg(cut, depth + 1)
    end
    fg_cache[group] = result
    return result
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
-- cursor expanded (defined below, referenced by `request` which is defined earlier). Returns whether
-- the fold set actually changed, so the CursorMoved handler can skip a full re-render when it did not.
---@type fun(): boolean
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

-- ── tree-node mapping + rendering ────────────────────────────────────────────

--- Map the normalized symbol tree into `lvim-ui.tree` nodes. Icon + name share ONE colour with
--- `source_colors`: the symbol's own colour from the buffer (semantic/treesitter/extmarks), falling
--- back to the per-kind colour — so the icon and name never diverge (e.g. keyword symbols if/return).
--- With `source_colors = false`: kind colour for the icon, plain name colour for the text. The
--- normalized node rides along as `data` (jump target + range for follow/auto-fold).
---@param nodes table[]
---@param parent_path string
---@return LvimUiTreeNode[]
local function to_ui_nodes(nodes, parent_path)
    local oc = cfg()
    local icons = oc.icons or {}
    local use_src = oc.source_colors ~= false
    local out = {}
    for _, n in ipairs(nodes) do
        local path = node_path(parent_path, n)
        local kind_name = SymbolKind[n.kind] or "Variable"
        local ui = {
            id = path,
            label = n.name,
            icon = icons[kind_name] or "",
            kind = kind_name,
            -- The symbol's detail / signature trails as dim virtual text (does not affect the buffer
            -- text, so clicks land on the name). Toggle off with `outline.detail = false`.
            detail = (oc.detail ~= false and n.detail ~= nil and n.detail ~= "") and n.detail or nil,
            children = to_ui_nodes(n.children or {}, path),
            data = n,
        }
        if use_src then
            ui.hl = n.hl or KIND_HL[kind_name] or "LvimLspOutlineKindMisc"
        else
            ui.icon_hl = KIND_HL[kind_name] or "LvimLspOutlineKindMisc"
            ui.label_hl = "LvimLspOutlineName"
        end
        out[#out + 1] = ui
    end
    return out
end

--- Repaint the panel (synchronous) and refresh the follow highlight.
local function repaint()
    if state.panel then
        state.panel.render()
        M.follow()
    end
end

--- Push the (re)normalized symbol tree into the panel and repaint.
local function sync_tree()
    if state.panel then
        state.panel.set_root(to_ui_nodes(state.tree, ""))
        repaint()
    end
end

-- ── alternative push source (Flutter Outline etc.) ───────────────────────────

--- Detach the currently-attached push source, if any.
local function detach_source()
    if state.src_source and state.src_source_buf then
        pcall(state.src_source.detach, state.src_source_buf)
    end
    state.src_source, state.src_source_buf = nil, nil
end

--- Attach `source` for `bufnr`: it drives the tree via a push callback (the panel renders the
--- pushed nodes instead of requesting documentSymbol). Idempotent for the same buffer+source.
---@param bufnr integer
---@param source table
local function attach_source(bufnr, source)
    if state.src_source == source and state.src_source_buf == bufnr then
        return
    end
    detach_source()
    state.src_source, state.src_source_buf = source, bufnr
    source.attach(bufnr, function(nodes)
        if bufnr ~= state.src_buf then
            return
        end
        state.tree = nodes or {}
        if state.auto_fold then
            apply_auto_fold()
        end
        sync_tree()
    end)
end

-- ── data + follow ─────────────────────────────────────────────────────────────

--- How long the outline keeps re-asking for symbols before accepting that a buffer simply has none.
--- Opening the panel almost always races the language server: it may not be ATTACHED yet, or it is attached but
--- still indexing, so the first `documentSymbol` answers with nothing. Without a retry the panel just sat EMPTY
--- until some unrelated event (a cursor move, a buffer switch) happened to trigger a refresh — which is exactly
--- why it "showed up after a few seconds, or only once you moved the cursor".
local RETRY_MS = 150
local RETRY_MAX = 20 -- ≈3s of grace; a file with genuinely no symbols settles as empty after that

--- Request documentSymbol for `bufnr` and re-render. Retries while the server is not ready yet.
---@param bufnr integer
---@param attempt? integer  1-based retry counter (internal)
local function request(bufnr, attempt)
    if not (bufnr and api.nvim_buf_is_valid(bufnr)) then
        return
    end
    -- A registered push source for this filetype replaces the documentSymbol path entirely.
    local source = sources[vim.bo[bufnr].filetype]
    if source then
        attach_source(bufnr, source)
        return
    end
    detach_source()
    attempt = attempt or 1

    --- Re-arm unless the panel closed / the source changed under us.
    ---@return boolean  true when a retry was scheduled
    local function retry()
        if attempt >= RETRY_MAX then
            return false
        end
        vim.defer_fn(function()
            if is_valid_win(state.win) and bufnr == state.src_buf then
                request(bufnr, attempt + 1)
            end
        end, RETRY_MS)
        return true
    end

    if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentSymbol" }) == 0 then
        if retry() then -- not attached YET — keep whatever is on screen and wait for the client
            return
        end
        state.tree = {}
        sync_tree()
        return
    end

    local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", params, function(results)
        if bufnr ~= state.src_buf or not api.nvim_buf_is_valid(bufnr) then
            return
        end
        local merged = {}
        for _, r in pairs(results or {}) do
            for _, s in ipairs(r.result or {}) do
                merged[#merged + 1] = s
            end
        end
        -- An empty answer from an attached server usually means "still indexing", not "no symbols" — so keep
        -- asking for a while instead of rendering an empty panel.
        if #merged == 0 and retry() then
            return
        end
        state.tree = normalize(merged)
        if state.auto_fold then
            apply_auto_fold()
        end
        sync_tree()
    end)
end

--- The deepest VISIBLE tree node whose symbol range contains the source cursor POSITION, or nil.
---@param line0 integer  0-based line
---@param col0 integer   0-based column
---@return LvimUiTreeNode|nil
local function visible_node_at(line0, col0)
    if not state.panel then
        return nil
    end
    --- Is (l1,c1) at or before (l2,c2)?
    ---@param l1 integer
    ---@param c1 integer
    ---@param l2 integer
    ---@param c2 integer
    ---@return boolean
    local function le(l1, c1, l2, c2)
        return l1 < l2 or (l1 == l2 and c1 <= c2)
    end

    local best
    for _, ui in ipairs(state.panel.visible()) do
        local r = ui.data and ui.data.range
        -- Match on the full POSITION (line AND column), not the line alone. A `for _, edit in …` declares its
        -- loop variables on the loop's own header line, so the loop and every variable it declares START on the
        -- same row — by line alone they are indistinguishable, and whichever tie-break you pick is wrong half
        -- the time (it marked `edit` while the cursor sat on `for`, or `for` while the cursor sat on `edit`).
        -- The column separates them cleanly: the variable's range covers only its name.
        if
            r
            and le(r.start.line, r.start.character, line0, col0)
            and le(line0, col0, r["end"].line, r["end"].character)
        then
            if not best then
                best = ui
            else
                local br = best.data.range
                local rlines = r["end"].line - r.start.line
                local blines = br["end"].line - br.start.line
                if rlines < blines then
                    best = ui -- tighter by lines
                elseif
                    rlines == blines
                    and (r["end"].character - r.start.character) < (br["end"].character - br.start.character)
                then
                    best = ui -- same height, tighter by columns
                end
            end
        end
    end
    return best
end

--- Highlight the symbol under the source cursor (follow mode) — the shared tree's `mark` row, which
--- also parks the panel cursor on it while the user is NOT inside the panel.
function M.follow()
    if not (cfg().follow ~= false and state.panel and state.panel.valid()) then
        return
    end
    if not is_valid_win(state.src_win) then
        state.panel.mark(nil)
        return
    end
    local cur = api.nvim_win_get_cursor(state.src_win)
    local line0, col0 = cur[1] - 1, cur[2]
    -- Clamp the column INTO the code. A cursor parked in a line's INDENT sits BEFORE the range of the statement
    -- that starts there, so a strict position match would skip it and resolve to the enclosing parent (the whole
    -- function). Visually the cursor is on that statement, so treat the indent as its first code column.
    local src = state.src_buf and api.nvim_buf_is_valid(state.src_buf) and state.src_buf or nil
    if src then
        local text = api.nvim_buf_get_lines(src, line0, line0 + 1, false)[1]
        if text then
            local first = (text:find("%S") or 1) - 1 -- 0-based column of the first non-blank
            if col0 < first then
                col0 = first
            end
        end
    end
    local ui = visible_node_at(line0, col0)
    state.panel.mark(ui and ui.id or nil, { move_cursor = true })
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

--- The normalized symbol under the panel cursor (nil on the placeholder row).
---@return table|nil
local function selected_symbol()
    local ui = state.panel and state.panel.selected()
    return ui and ui.data or nil
end

--- Jump to the symbol `n` (focuses the source). `close` forces the panel shut.
---@param n table|nil   a normalized symbol node
---@param close? boolean
local function jump(n, close)
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
---@param n table|nil   a normalized symbol node
local function peek(n)
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

--- Focus the source at the symbol `n`, then run an LSP buffer action (hover / code action /
--- rename) so it targets the right position.
---@param n table|nil   a normalized symbol node
---@param fn fun()
local function at_symbol(n, fn)
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
    if not state.panel then
        return
    end
    if collapsed then
        state.panel.collapse_all()
    else
        state.panel.expand_all()
    end
    repaint()
end

--- Accordion: collapse every foldable node except the ancestor chain of the symbol under the source
--- cursor, so only the current symbol's parents stay open. No-op without a source window.
apply_auto_fold = function()
    if not (is_valid_win(state.src_win) and state.panel) then
        return false
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
    -- The shared tree's fold-override map: nodes default EXPANDED here, so only the folded ones carry
    -- an explicit `false`. Bulk-replaced in one step (no per-node hooks, no render — the caller paints).
    local override = {}
    walk_paths(state.tree, "", function(n, path)
        if n.children and #n.children > 0 and not open[path] then
            override[path] = false
        end
    end)
    return state.panel.set_expanded(override)
end

--- Set / toggle the fold of the symbol under the panel cursor.
---@param to boolean|nil   true=collapse, false=expand, nil=toggle
local function set_fold(to)
    local ui = state.panel and state.panel.selected()
    if not (ui and type(ui.children) == "table" and #ui.children > 0) then
        return
    end
    state.auto_fold = false -- manual fold suspends the accordion
    if to == nil then
        state.panel.toggle(ui.id)
    elseif to then
        state.panel.collapse(ui.id)
    else
        state.panel.expand(ui.id)
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
--- The first key of a `string|string[]` key spec (for display in bars/help).
---@param lhs string|string[]|nil
---@return string
local function key_label(lhs)
    if type(lhs) == "table" then
        return lhs[1] or "?"
    end
    return lhs or "?"
end

local function show_help()
    local keys = cfg().keys or {}
    local items = {}
    for _, e in ipairs(HELP) do
        local lhs = keys[e[1]]
        if lhs then
            lhs = type(lhs) == "table" and table.concat(lhs, " / ") or lhs
            items[#items + 1] = { lhs, e[2] }
        end
    end
    local close = { "q", "<Esc>" }
    if keys.help then
        close[#close + 1] = type(keys.help) == "table" and keys.help[1] or keys.help
    end
    -- The rows / striping / colours / window are the shared component's; only the ACTION BAR is ours (it is
    -- config-driven: `config.footers.outline_help` through the shared `surface.bar`).
    lvim_ui.help({
        title = "Outline keymaps",
        items = items,
        close_keys = close,
        footer = {
            bars = {
                surface.bar(lsp_state.config.footers.outline_help, {
                    close = {
                        key = "q",
                        name = "close",
                        run = function(st)
                            st.close()
                        end,
                    },
                }, { separator = lsp_state.config.footer_separator }),
            },
        },
    })
end

--- Bind the outline's config keymaps on the panel buffer (the tree's `on_keys` hook — bound AFTER
--- the tree's canonical `l`/`<CR>`/`h`, so a config key on the same lhs overrides the default).
---@param map fun(lhs: string|string[], fn: fun())
local function set_keys(map)
    local function move(delta)
        if not (state.panel and state.panel.valid()) then
            return
        end
        local win, buf = state.panel.win(), state.panel.buf()
        ---@cast win integer
        ---@cast buf integer
        local target = math.max(1, math.min(api.nvim_win_get_cursor(win)[1] + delta, api.nvim_buf_line_count(buf)))
        api.nvim_win_set_cursor(win, { target, 0 })
        peek(selected_symbol())
    end

    -- Action name → handler (operates on the symbol under the panel cursor).
    local actions = {
        goto_location = function()
            jump(selected_symbol(), cfg().auto_close)
        end,
        goto_and_close = function()
            jump(selected_symbol(), true)
        end,
        peek_location = function()
            peek(selected_symbol())
        end,
        restore_location = restore,
        up_and_jump = function()
            move(-1)
        end,
        down_and_jump = function()
            move(1)
        end,
        fold = function()
            set_fold(true)
        end,
        unfold = function()
            set_fold(false)
        end,
        fold_toggle = function()
            set_fold(nil)
        end,
        fold_all = function()
            set_all(true)
        end,
        unfold_all = function()
            set_all(false)
        end,
        fold_toggle_all = function()
            set_all(state.panel ~= nil and state.panel.all_expanded())
        end,
        fold_reset = function()
            set_all(cfg().fold_initial == "all")
        end,
        fold_auto = function()
            state.auto_fold = true
            apply_auto_fold()
            repaint()
        end,
        hover_symbol = function()
            at_symbol(selected_symbol(), vim.lsp.buf.hover)
        end,
        code_actions = function()
            at_symbol(selected_symbol(), vim.lsp.buf.code_action)
        end,
        rename_symbol = function()
            at_symbol(selected_symbol(), vim.lsp.buf.rename)
        end,
        help = show_help,
        close = M.close,
    }
    for action, lhs in pairs(cfg().keys or {}) do
        local fn = actions[action]
        if fn then
            map(lhs, fn)
        end
    end
    -- Mouse is the shared tree canon: a click selects + activates the row (→ `on_activate` = jump,
    -- honouring `auto_close`), a click on the fold chevron / a double-click toggles the fold.
end

local function setup_autocmds()
    state.augroup = api.nvim_create_augroup("LvimLspOutline", { clear = true })
    -- ONE persistent uv timer (created in M.open), restarted on each burst — `vim.defer_fn` would spawn and
    -- leak a fresh handle every time a pending timer is `:stop()`ped before firing.
    local function schedule_refresh()
        if not state.timer then
            return
        end
        state.timer:stop()
        state.timer:start(
            250,
            0,
            vim.schedule_wrap(function()
                local b, w = pick_source()
                if b then
                    state.src_buf, state.src_win = b, w
                    request(b)
                end
            end)
        )
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
                if apply_auto_fold() then
                    repaint() -- re-render with the new folds (repaint re-applies the follow highlight)
                else
                    M.follow()
                end
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
    local fold = c.fold or {}

    -- A PERSISTENT docked frame whose content is the SHARED lvim-ui.tree: the tree handle owns the
    -- fold state, the guides/markers, the follow mark, the scrollbar, the canonical keys + mouse; this
    -- module feeds it symbol nodes and binds the outline actions on top. The cursor is hidden via the
    -- user's `panel_ft = { "lvim-lsp-outline" }` registration (the ft passed below). Leaving the panel
    -- works with `<C-w>w` (cycle) and, for the side dock, `<C-h>` (the frame's dock-aware escape).
    state.panel = lvim_ui.tree({
        default_expanded = true, -- symbols start unfolded (the accordion / manual folds collapse them)
        connectors = true, -- ├/└ connectors on leaf symbols (the outline look)
        elide_guides = true, -- guide columns stop below a last child
        -- Content padding + scrollbar from the LIVE config; unset, they fall back to `lvim-ui.config.tree`.
        padding = c.padding,
        scrollbar = c.scrollbar == true,
        icons = {
            fold_open = fold.open or "▾",
            fold_closed = fold.closed or "▸",
            guide = c.guide or "│",
            branch = c.branch or "├",
            branch_last = c.branch_last or "└",
        },
        hl = {
            guide = "LvimLspOutlineGuide",
            fold = "LvimLspOutlineFold",
            detail = "LvimLspOutlineDetail",
            mark = "LvimLspOutlineCursor",
            empty = "LvimLspOutlineDetail",
        },
        empty = " No symbols",
        filetype = "lvim-lsp-outline", -- the frame stamps this on the panel buffer (cursor hiding + ft)
        cursorline = true,
        size = function()
            local px = (width <= 1) and math.floor(vim.o.columns * width) or math.floor(width)
            return math.max(20, px), 1
        end,
        -- Activation (canonical <CR>/l fallback + the mouse click): jump, honouring `auto_close`. The
        -- outline's own config keys (goto/fold/peek/…) are bound in `on_keys` and override on clashes.
        on_activate = function(ui)
            jump(ui.data, cfg().auto_close)
        end,
        -- Any hook-firing fold (a key, the chevron, a double-click) is a MANUAL fold → suspend the
        -- accordion (the accordion itself recomputes via the hook-less bulk `set_expanded`).
        on_expand = function()
            state.auto_fold = false
        end,
        on_collapse = function()
            state.auto_fold = false
        end,
        on_keys = function(map, pan)
            state.buf, state.win = pan.buf, pan.win
            set_keys(map)
        end,
        on_close = function()
            if state.timer then
                state.timer:stop()
                if not state.timer:is_closing() then
                    state.timer:close()
                end
                state.timer = nil
            end
            if state.augroup then
                pcall(api.nvim_del_augroup_by_id, state.augroup)
                state.augroup = nil
            end
            state.win, state.buf, state.tree, state.panel, state.surface = nil, nil, {}, nil, nil
        end,
    })

    state.surface = surface.open({
        mode = "split",
        native = true, -- a REAL split window (not a float over a container) → native `<C-w>` nav + redraw
        dock = side,
        enter = enter == true, -- focus the panel only when explicitly asked; else keep the cursor in code
        persistent = true,
        -- The outline is a PERSISTENT docked SIDEBAR (like neo-tree), not a transient float — so wear the opaque
        -- sidebar background (`NormalSB`) rather than the float/peek bg that follows `transparent`.
        normal_hl = "NormalSB",
        title = (title ~= false and title ~= "") and title or nil, -- centred winbar (blue-tinted)
        size = { width = { fixed = width } },
        content = { blocks = { { id = "tree", provider = state.panel.provider } } },
        close_keys = {}, -- persistent: the outline's own `close` key (→ M.close) tears the frame down
        -- A key-hint bar pinned to the panel's bottom row: the outline had NONE, so its keys — and the
        -- cheatsheet itself — were undiscoverable. Real `surface.button`s (the shape this bar renders), no ●
        -- separators: the panel is narrow and they cost the chips their place.
        footer = {
            bars = {
                {
                    align = "center",
                    items = {
                        surface.button(
                            { name = "help", key = key_label(cfg().keys.help), style = "action", run = show_help },
                            "action"
                        ),
                        surface.button({
                            name = "close",
                            key = key_label(cfg().keys.close),
                            style = "action",
                            run = function()
                                M.close()
                            end,
                        }, "action"),
                    },
                },
            },
        },
    })
    if not state.timer then
        state.timer = uv.new_timer() -- the ONE refresh-debounce timer; stopped + closed in on_close
    end
    setup_autocmds()
    request(b)
end

--- Close the outline panel. Delegates to the frame's teardown, which fires the provider `on_close`
--- (stops the timer, deletes the autocmds, clears state). Idempotent.
function M.close()
    detach_source()
    local f = state.surface
    if not f then
        return
    end
    state.surface = nil
    pcall(f.close)
end

--- Register an alternative outline SOURCE for a filetype: a push source that feeds the panel a
--- richer tree than documentSymbol (e.g. dartls' Flutter Outline). `source.attach(bufnr, push)`
--- is called when a buffer of `ft` becomes the outline source; the source calls `push(nodes)`
--- (nodes in the normalized `{ name, kind, lnum, col, range, children }` shape) whenever it has
--- data. `source.detach(bufnr)` is called when the panel leaves that buffer / closes.
---@param ft string
---@param source { attach: fun(bufnr: integer, push: fun(nodes: table[])), detach: fun(bufnr: integer) }
function M.register_source(ft, source)
    sources[ft] = source
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
