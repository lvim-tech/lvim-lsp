-- lvim-lsp: diagnostics — interactive floating diagnostic window.
-- Renders diagnostics for the current cursor line with per-severity highlights.
-- Stays focused; n/p navigate to next/prev diagnostic line.
-- Depends on lvim-utils for the floating window.
--
---@module "lvim-lsp.diagnostics"

local state          = require("lvim-lsp.state")
local protocol       = vim.lsp.protocol
local DiagnosticSeverity = protocol.DiagnosticSeverity

local M = {}

-- ── Severity → highlight group ────────────────────────────────────────────────

---@type table<integer, string>
local severity_hl = {
    [DiagnosticSeverity.Error]       = "DiagnosticError",
    [DiagnosticSeverity.Warning]     = "DiagnosticWarn",
    [DiagnosticSeverity.Information] = "DiagnosticInfo",
    [DiagnosticSeverity.Hint]        = "DiagnosticHint",
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function build_content(diags)
    local lines      = {}
    local hl_entries = {}

    for i, d in ipairs(diags) do
        local prefix    = string.format("%d. (%s) ", i, d.source or "unknown")
        local hiname    = severity_hl[d.severity] or "DiagnosticInfo"
        local msg_lines = vim.split(d.message, "\n", { trimempty = true })

        table.insert(lines, prefix .. msg_lines[1])
        local row = #lines - 1
        table.insert(hl_entries, { line = row, col_start = 0,       col_end = #prefix, group = "DiagnosticSourceInfo" })
        table.insert(hl_entries, { line = row, col_start = #prefix, col_end = -1,      group = hiname })

        for j = 2, #msg_lines do
            table.insert(lines, msg_lines[j])
            row = #lines - 1
            table.insert(hl_entries, { line = row, col_start = 0, col_end = -1, group = hiname })
        end
    end

    return lines, hl_entries
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Show diagnostics for the current cursor line in a floating window.
--- Focus stays in the window; n/p navigate, q/<Esc> close.
---@return integer|nil buf
---@return integer|nil win
function M.show_line_diagnostics()
    local ui = require("lvim-lsp.ui").get()
    if not ui then return end

    local src_win = vim.api.nvim_get_current_win()
    local line_nr = vim.api.nvim_win_get_cursor(src_win)[1] - 1
    local diags   = vim.diagnostic.get(vim.api.nvim_win_get_buf(src_win), { lnum = line_nr })
    if vim.tbl_isempty(diags) then return end

    local lines, hl_entries = build_content(diags)
    local title = string.format("%s (%d)", state.config.diagnostics.popup_title, #diags)

    local buf, win = ui.info(lines, {
        title        = title,
        position     = "cursor",
        highlights   = hl_entries,
        footer_hints = {
            { key = "n", label = "next" },
            { key = "p", label = "prev" },
        },
        on_open = function(b, w)
            local ok_cur, cursor_mod = pcall(require, "lvim-utils.cursor")
            if ok_cur then cursor_mod.mark_input_buffer(b, true) end

            local ko = { buffer = b, noremap = true, silent = true, nowait = true }
            local close_info = require("lvim-utils.ui").close_info
            vim.keymap.set("n", "n", function()
                close_info(w)
                vim.api.nvim_set_current_win(src_win)
                vim.diagnostic.jump({ count = 1, float = false })
                vim.schedule(M.show_line_diagnostics)
            end, ko)
            vim.keymap.set("n", "p", function()
                close_info(w)
                vim.api.nvim_set_current_win(src_win)
                vim.diagnostic.jump({ count = -1, float = false })
                vim.schedule(M.show_line_diagnostics)
            end, ko)
        end,
    })

    return buf, win
end

--- Jump to next diagnostic and show the popup.
function M.goto_next()
    vim.diagnostic.jump({ count = 1, float = false })
    M.show_line_diagnostics()
end

--- Jump to previous diagnostic and show the popup.
function M.goto_prev()
    vim.diagnostic.jump({ count = -1, float = false })
    M.show_line_diagnostics()
end

return M
