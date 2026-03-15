-- lvim-lsp: highlight group definitions for installer and info popups.
-- Call M.setup(colors) once after the color palette is available.
-- Subsequent calls are no-ops unless M.reset() is called first.
--
---@module "lvim-lsp.highlights"

local M = {}

local _done = false

--- Derive a fallback color palette from Neovim's active highlight groups.
--- Used when the caller does not supply explicit colors.
---@return table<string, string>
function M.derive_colors()
    ---@param group string
    ---@param attr  "fg"|"bg"
    ---@return string|nil
    local function hl_color(group, attr)
        local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
        if ok and hl and hl[attr] then
            return string.format("#%06x", hl[attr])
        end
    end
    return {
        bg_float = hl_color("NormalFloat", "bg") or hl_color("Normal", "bg") or "#1e1e2e",
        red      = hl_color("DiagnosticError",  "fg") or "#f38ba8",
        orange   = hl_color("DiagnosticWarn",   "fg") or "#fab387",
        blue     = hl_color("Function",         "fg") or "#89b4fa",
        green    = hl_color("String",           "fg") or "#a6e3a1",
        fg       = hl_color("Normal",           "fg") or "#cdd6f4",
        cyan     = hl_color("Special",          "fg") or "#89dceb",
        purple   = hl_color("Keyword",          "fg") or "#cba6f7",
        yellow   = hl_color("DiagnosticHint",   "fg") or "#f9e2af",
    }
end

--- Define all highlight groups used by the installer popup and the LSP info
--- floating window.  Colors that are absent from `colors` fall back to
--- derived values so the plugin works without an explicit palette.
---@param colors table<string, string>  Color palette (may be partial or empty)
function M.setup(colors)
    if _done then
        return
    end
    _done = true

    local fallback = M.derive_colors()
    local c = vim.tbl_extend("keep", colors or {}, fallback)

    local api = vim.api

    -- Installer popup
    api.nvim_set_hl(0, "MasonPopupBG",      { bg = c.bg_float })
    api.nvim_set_hl(0, "MasonTitle",        { fg = c.red,    bg = "NONE", bold = true })
    api.nvim_set_hl(0, "MasonPkgName",      { fg = c.orange, bg = "NONE", bold = true })
    api.nvim_set_hl(0, "MasonIconProgress", { fg = c.blue,   bg = "NONE", bold = true })
    api.nvim_set_hl(0, "MasonIconOk",       { fg = c.green,  bg = "NONE", bold = true })
    api.nvim_set_hl(0, "MasonIconError",    { fg = c.red,    bg = "NONE", bold = true })
    api.nvim_set_hl(0, "MasonCurrentAction",{ fg = c.green,  bg = "NONE" })

    -- LSP info popup
    api.nvim_set_hl(0, "LspIcon",           { fg = c.blue,   bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoBG",         { bg = c.bg_float })
    api.nvim_set_hl(0, "LspInfoTitle",      { fg = c.red,    bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoServerName", { fg = c.orange, bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoSection",    { fg = c.blue,   bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoKey",        { fg = c.green,  bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoValue",      { fg = c.fg,     bg = "NONE" })
    api.nvim_set_hl(0, "LspInfoSeparator",  { fg = c.blue,   bg = "NONE" })
    api.nvim_set_hl(0, "LspInfoLinter",     { fg = c.purple, bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoFormatter",  { fg = c.purple, bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoToolName",   { fg = c.green,  bg = "NONE", bold = true })
    api.nvim_set_hl(0, "LspInfoBuffer",     { fg = c.cyan,   bg = "NONE", italic = true })
    api.nvim_set_hl(0, "LspInfoDate",       { fg = c.fg,     bg = "NONE", italic = true })
    api.nvim_set_hl(0, "LspInfoConfig",     { fg = c.fg,     bg = "NONE" })
    api.nvim_set_hl(0, "LspInfoConfigKey",  { fg = c.cyan,   bg = "NONE", italic = true })
    api.nvim_set_hl(0, "LspInfoFold",       { fg = c.yellow, bg = "NONE", bold = true })

    -- Diagnostics popup
    api.nvim_set_hl(0, "DiagnosticSourceInfo", { fg = c.cyan, bg = "NONE", italic = true })
end

--- Allow re-running setup (e.g. after a colorscheme change).
function M.reset()
    _done = false
end

return M
