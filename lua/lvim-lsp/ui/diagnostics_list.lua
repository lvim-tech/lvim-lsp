-- lvim-lsp.ui.diagnostics_list: present diagnostics in the lvim-utils two-pane peek.
--
-- Left pane = every diagnostic, grouped by file (one row each, with its severity sign); right pane =
-- a live preview of the file at that diagnostic. A subtitle filter bar carries two button groups:
-- a SCOPE toggle (Workspace / Buffer = only the file that was focused when opened) and a SEVERITY
-- filter (All / Error / Warn / Info / Hint). Clicking a button — or the `keys.filter` cycle key on
-- the severity group — re-filters live without reopening. Pure UI: it reads vim.diagnostic, maps to
-- peek items + filter predicates, and hands off to `lvim-utils.ui.peek` (sibling of ui/locations).
--
---@module "lvim-lsp.ui.diagnostics_list"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local peek = require("lvim-utils.ui.peek")

local M = {}

local sev = vim.diagnostic.severity

-- Severity → the foreground highlight used for the row's sign icon (the editor's own groups, so the
-- preview/list match the gutter and the theme).
---@type table<integer, string>
local SEVERITY_HL = {
    [sev.ERROR] = "DiagnosticError",
    [sev.WARN] = "DiagnosticWarn",
    [sev.INFO] = "DiagnosticInfo",
    [sev.HINT] = "DiagnosticHint",
}

-- Severity → the filter button's { inactive, active } highlight groups (defined in config/highlights).
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

--- Build a severity filter button.
---@param id string
---@param label string
---@param severity integer
---@return table
local function severity_button(id, label, severity)
    local groups = SEVERITY_BTN[severity]
    return {
        id = id,
        label = label,
        predicate = function(it)
            return it.severity == severity
        end,
        hl = groups[1],
        hl_active = groups[2],
    }
end

--- Open the diagnostics peek (`mode` = "split" | "float").
---@param mode string
function M.open(mode)
    local origin_buf = vim.api.nvim_get_current_buf()
    local origin_file = vim.api.nvim_buf_get_name(origin_buf)

    local diags = vim.diagnostic.get() -- workspace-wide; the Buffer button filters down to origin
    if #diags == 0 then
        notify("No diagnostics found.", vim.log.levels.INFO)
        return
    end

    local signs = sign_text()
    local items = {}
    for _, d in ipairs(diags) do
        local fname = vim.api.nvim_buf_get_name(d.bufnr)
        if fname ~= "" then
            local first = vim.split(d.message or "", "\n", { trimempty = true })[1]
            items[#items + 1] = {
                filename = fname,
                lnum = (d.lnum or 0) + 1,
                col = (d.col or 0) + 1,
                end_lnum = d.end_lnum and (d.end_lnum + 1) or nil,
                end_col = d.end_col and (d.end_col + 1) or nil,
                text = first or d.message or "",
                severity = d.severity,
                icon = signs[d.severity] or FALLBACK_ICON[d.severity],
                icon_hl = SEVERITY_HL[d.severity] or "DiagnosticInfo",
            }
        end
    end
    if #items == 0 then
        notify("No diagnostics found.", vim.log.levels.INFO)
        return
    end
    -- Natural reading order within each file group: by line, then column.
    table.sort(items, function(a, b)
        if a.filename ~= b.filename then
            return a.filename < b.filename
        end
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        return (a.col or 0) < (b.col or 0)
    end)

    local bar = {
        groups = {
            {
                id = "scope",
                active = "workspace",
                buttons = {
                    {
                        id = "workspace",
                        label = "Workspace",
                        key = "W", -- Shift+W; plain "w" is Warn's hotkey in the severity group
                        predicate = function()
                            return true
                        end,
                    },
                    {
                        id = "buffer",
                        label = "Buffer",
                        predicate = function(it)
                            return it.filename == origin_file
                        end,
                    },
                },
            },
            {
                id = "severity",
                active = "all",
                primary = true, -- the `f` cycle key advances the severity filter
                buttons = {
                    {
                        id = "all",
                        label = "All",
                        predicate = function()
                            return true
                        end,
                    },
                    severity_button("error", "Error", sev.ERROR),
                    severity_button("warn", "Warn", sev.WARN),
                    severity_button("info", "Info", sev.INFO),
                    severity_button("hint", "Hint", sev.HINT),
                },
            },
        },
    }

    peek.open({
        title = "Diagnostics",
        items = items,
        mode = mode,
        bar = bar,
        -- The list rows are diagnostic MESSAGES, not source lines, so the col/end_col match span
        -- (used for references) would highlight a meaningless slice of the message — suppress it.
        list_match = false,
    }, { peek = (lsp_state.config.peek or {}).appearance })
end

return M
