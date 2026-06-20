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

-- Severity → the filter button's { inactive, active } highlight groups.
---@type table<integer, { [1]: string, [2]: string }>
local SEVERITY_BTN = {
    [sev.ERROR] = { "LvimLspPeekFilterError", "LvimLspPeekFilterErrorActive" },
    [sev.WARN] = { "LvimLspPeekFilterWarn", "LvimLspPeekFilterWarnActive" },
    [sev.INFO] = { "LvimLspPeekFilterInfo", "LvimLspPeekFilterInfoActive" },
    [sev.HINT] = { "LvimLspPeekFilterHint", "LvimLspPeekFilterHintActive" },
}

-- Fallback severity glyphs (Nerd Font) when no diagnostic signs are configured.
---@type table<integer, string>
local FALLBACK_ICON = {
    [sev.ERROR] = "󰅙",
    [sev.WARN] = "󰀨",
    [sev.INFO] = "",
    [sev.HINT] = "",
}

--- The configured diagnostic sign glyphs (severity → text), read live from `vim.diagnostic.config`.
---@return table<integer, string>
local function sign_text()
    local cfg = vim.diagnostic.config() or {}
    local signs = type(cfg.signs) == "table" and cfg.signs or nil
    if signs and type(signs.text) == "table" then
        return signs.text
    end
    return {}
end

--- A severity filter button (the predicate runs on the item source).
---@param id string
---@param label string
---@param severity integer
---@return table
local function severity_button(id, label, severity)
    local groups = SEVERITY_BTN[severity]
    return {
        id = id,
        label = label,
        key = label:sub(1, 1):lower(), -- a / e / w / i / h
        predicate = function(it)
            return it.severity == severity
        end,
        hl = groups[1],
        hl_active = groups[2],
    }
end

--- Build the picker items from the current workspace diagnostics. Re-read live on every refresh so the
--- list tracks errors being fixed / appearing. Workspace-wide; the Buffer filter narrows it.
---@return table[]
local function build_items()
    local signs = sign_text()
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
                icon = signs[d.severity] or FALLBACK_ICON[d.severity],
                icon_hl = SEVERITY_HL[d.severity] or "DiagnosticInfo",
            }
        end
    end
    -- Natural reading order within each file group: by line, then column.
    table.sort(items, function(a, b)
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
    vim.cmd("edit " .. vim.fn.fnameescape(it.path))
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- The picker preview for a diagnostic: the file's lines, focused on the diagnostic's line.
---@param it table
---@return string[] lines, string? filetype, integer? focus
local function preview(it)
    if not (it.path and it.path ~= "") then
        return { "" }
    end
    local ok, lines = pcall(vim.fn.readfile, it.path, "", 2000)
    if not ok or type(lines) ~= "table" then
        return { "" }
    end
    return lines, vim.filetype.match({ filename = it.path }) or "", it.lnum
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
        preview = preview,
        on_confirm = jump,
        -- header filter bar: SCOPE (workspace / current buffer) + SEVERITY (all / per level)
        filters = {
            {
                id = "scope",
                active = "workspace",
                buttons = {
                    {
                        id = "workspace",
                        label = "Workspace",
                        key = "o", -- W is the Warn hotkey, so bracket the `o`: W[o]rkspace
                        hl = "LvimLspPeekFilterScope",
                        hl_active = "LvimLspPeekFilterScopeActive",
                    },
                    {
                        id = "buffer",
                        label = "Buffer",
                        key = "b",
                        hl = "LvimLspPeekFilterScope",
                        hl_active = "LvimLspPeekFilterScopeActive",
                        predicate = function(it)
                            return it.path == origin_file
                        end,
                    },
                },
            },
            {
                id = "severity",
                active = "all",
                buttons = {
                    { id = "all", label = "All", key = "a" },
                    severity_button("error", "Error", sev.ERROR),
                    severity_button("warn", "Warn", sev.WARN),
                    severity_button("info", "Info", sev.INFO),
                    severity_button("hint", "Hint", sev.HINT),
                },
            },
        },
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
                run = function(_, close)
                    close()
                    vim.diagnostic.setqflist()
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
