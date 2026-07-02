-- lvim-lsp.ui.diagnostics_list: present diagnostics in the public lvim-utils PICKER.
--
-- Left pane = every diagnostic (one row each, with its severity sign); right pane = a live preview of the
-- file at that diagnostic. A header filter bar carries two button groups: a SCOPE toggle (Workspace /
-- Buffer = only the file that was focused when opened) and a SEVERITY filter (All / Error / Warn / Info /
-- Hint). The list re-reads `vim.diagnostic` live (errors fixed / appearing). Row actions: code action,
-- yank message, all → quickfix. Pure UI — reads vim.diagnostic, maps to picker items + filter predicates.
--
---@module "lvim-lsp.ui.diagnostics_list"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local picker = require("lvim-utils.picker")
local severity = require("lvim-lsp.ui.severity")

local M = {}

local sev = vim.diagnostic.severity

-- Severity → the foreground highlight for the row's sign icon (the editor's own groups, so it matches the
-- gutter + the theme).
---@type table<integer, string>
local SEVERITY_HL = {
    [sev.ERROR] = "DiagnosticError",
    [sev.WARN] = "DiagnosticWarn",
    [sev.INFO] = "DiagnosticInfo",
    [sev.HINT] = "DiagnosticHint",
}

-- Severity → the quickfix `type` (so a quickfix built from the marked subset carries E/W/I/H, like
-- vim.diagnostic.setqflist() does for the whole set).
---@type table<integer, string>
local SEVERITY_TYPE = {
    [sev.ERROR] = "E",
    [sev.WARN] = "W",
    [sev.INFO] = "I",
    [sev.HINT] = "H",
}

-- Filter button id → the severity it matches (the SEVERITY filter group). Used to attach each config
-- button's predicate by id; "all" has no entry (no predicate — it shows everything).
---@type table<string, integer>
local SEVERITY_OF = {
    error = sev.ERROR,
    warn = sev.WARN,
    info = sev.INFO,
    hint = sev.HINT,
}

--- Clone a config filter GROUP (display-only: id/label/key/colours) and attach each button's predicate
--- by id — the SEMANTICS the config never holds. The config buttons stay untouched (a fresh table per
--- button), so successive opens are not polluted.
---@param spec LvimLspFilterGroup
---@param preds table<string, fun(it: table): boolean>  button id → predicate (absent = matches everything)
---@return table  a picker filter group (LvimUiFilterGroup shape: display + attached predicates)
local function build_group(spec, preds)
    local buttons = {}
    for _, b in ipairs(spec.buttons) do
        local btn = vim.tbl_extend("force", {}, b)
        btn.predicate = preds[b.id]
        buttons[#buttons + 1] = btn
    end
    return { id = spec.id, active = spec.active, buttons = buttons }
end

--- Build the picker items from the current workspace diagnostics. Re-read live on every refresh so the
--- list tracks errors being fixed / appearing. Workspace-wide; the Buffer filter narrows it.
---@return table[]
local function build_items()
    local glyphs = severity.glyphs()
    local items = {}
    for _, d in ipairs(vim.diagnostic.get()) do
        -- vim.diagnostic.get() can still carry entries for a buffer that was wiped/unloaded — skip those.
        local fname = d.bufnr and vim.api.nvim_buf_is_valid(d.bufnr) and vim.api.nvim_buf_get_name(d.bufnr) or ""
        if fname ~= "" then
            local first = vim.split(d.message or "", "\n", { trimempty = true })[1]
            items[#items + 1] = {
                path = fname,
                lnum = (d.lnum or 0) + 1,
                col = (d.col or 0) + 1,
                text = first or d.message or "",
                severity = d.severity,
                icon = glyphs[d.severity],
                icon_hl = SEVERITY_HL[d.severity] or "DiagnosticInfo",
            }
        end
    end
    -- Group by SEVERITY first (Error → Warn → Info → Hint — the severity enum is 1→4), so the unfiltered
    -- "All" view reads E, W, I, H in blocks; then natural reading order (file, line, column) within each
    -- block. A single-severity filter shows only that block, so it stays in file/line order too.
    table.sort(items, function(a, b)
        if a.severity ~= b.severity then
            return (a.severity or 99) < (b.severity or 99)
        end
        if a.path ~= b.path then
            return a.path < b.path
        end
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        return (a.col or 0) < (b.col or 0)
    end)
    return items
end

--- Jump to a diagnostic and centre it.
---@param it table
local function jump(it)
    -- `:edit` refuses with E37 when the current buffer has unsaved changes (the editable preview may be
    -- modified); `nvim_win_set_buf` swaps the file in without that.
    local buf = vim.fn.bufadd(it.path)
    vim.fn.bufload(buf)
    vim.api.nvim_win_set_buf(0, buf)
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- Open the diagnostics picker. `layout` = "area" | "float" | "bottom".
---@param layout string
function M.open(layout)
    local origin_file = vim.api.nvim_buf_get_name(0)
    local items = build_items()
    if #items == 0 then
        notify("No diagnostics found.", vim.log.levels.INFO)
        return
    end

    picker.open({
        title = "Diagnostics",
        layout = layout,
        list_wrap = ((lsp_state.config.peek or {}).appearance or {}).list_wrap ~= false,
        items = items,
        format = function(it)
            return it.text
        end,
        preview_file = true, -- the REAL file buffer in the preview — fix the diagnostic inline
        subtitle = function(it) -- the focused file name, after "Diagnostics" in the statusline
            return vim.fn.fnamemodify(it.path, ":t")
        end,
        on_confirm = jump,
        -- header filter bar: SCOPE (workspace / current buffer) + SEVERITY (all / per level). Button lists
        -- (labels/keys/colours) come from config.filters.diagnostics; the predicates are attached here.
        filters = (function()
            local dcfg = lsp_state.config.filters.diagnostics
            -- SCOPE predicates by id: "workspace" shows all (no predicate), "buffer" narrows to origin_file.
            local scope_preds = {
                buffer = function(it)
                    return it.path == origin_file
                end,
            }
            -- SEVERITY predicates by id: one per level; "all" shows all (no predicate).
            local sev_preds = {}
            for id, s in pairs(SEVERITY_OF) do
                sev_preds[id] = function(it)
                    return it.severity == s
                end
            end
            return { build_group(dcfg.scope, scope_preds), build_group(dcfg.severity, sev_preds) }
        end)(),
        -- row actions on the focused diagnostic
        keys = {
            {
                key = "<C-a>",
                name = "code action",
                run = function(it, close)
                    close()
                    vim.schedule(function()
                        jump(it)
                        vim.lsp.buf.code_action()
                    end)
                end,
            },
            {
                key = "<C-y>",
                name = "yank",
                run = function(it)
                    vim.fn.setreg(vim.v.register ~= "" and vim.v.register or "+", it.text or "")
                    notify("Yanked diagnostic message.", vim.log.levels.INFO)
                end,
            },
            {
                key = "<C-q>",
                name = "quickfix",
                -- the MARKED diagnostics (multi-select) → a quickfix list carrying each one's severity type;
                -- nothing marked → the whole set (vim's own builder).
                run = function(_, close, marked)
                    close()
                    if marked and #marked > 0 then
                        local items = {}
                        for _, d in ipairs(marked) do
                            items[#items + 1] = {
                                filename = d.path,
                                lnum = d.lnum,
                                col = d.col,
                                text = d.text,
                                type = SEVERITY_TYPE[d.severity],
                            }
                        end
                        vim.fn.setqflist({}, " ", { title = "Diagnostics", items = items })
                        vim.cmd("botright copen")
                    else
                        vim.diagnostic.setqflist()
                    end
                end,
            },
        },
        -- live: re-read diagnostics as they change; dismiss once everything is resolved
        refresh = build_items,
        refresh_events = { "DiagnosticChanged" },
        close_on_empty = true,
    })
end

return M
