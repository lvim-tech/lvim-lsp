-- lvim-lsp.ui.severity: the ONE severity → sign glyph used across every LSP UI (the info panel's
-- "Diagnostics (total)" and the diagnostics navigator). Resolution honours YOUR Neovim configuration first,
-- so a glyph set once in your config shows identically everywhere:
--   1. `vim.diagnostic.config().signs.text[severity]`  — the modern diagnostic-sign config (recommended),
--   2. the legacy `:sign_define`d `DiagnosticSign*` text — older configs that still define signs that way,
--   3. lvim-lsp's own `config.info.icons.{error,warn,info,hint}` — the plugin default, only when you set neither.
--
---@module "lvim-lsp.ui.severity"

local lsp_state = require("lvim-lsp.state")

local sev = vim.diagnostic.severity

local M = {}

--- severity → the `config.info.icons` key holding lvim-lsp's own fallback glyph.
---@type table<integer, string>
local CFG_KEY = { [sev.ERROR] = "error", [sev.WARN] = "warn", [sev.INFO] = "info", [sev.HINT] = "hint" }

--- severity → the legacy diagnostic sign name.
---@type table<integer, string>
local SIGN_NAME = {
    [sev.ERROR] = "DiagnosticSignError",
    [sev.WARN] = "DiagnosticSignWarn",
    [sev.INFO] = "DiagnosticSignInfo",
    [sev.HINT] = "DiagnosticSignHint",
}

--- Your `vim.diagnostic.config().signs.text` (severity → glyph), or `{}` when you have not set signs.
---@return table<integer, string>
local function user_signs()
    local cfg = vim.diagnostic.config() or {}
    local signs = type(cfg.signs) == "table" and cfg.signs or nil
    if signs and type(signs.text) == "table" then
        return signs.text
    end
    return {}
end

--- The legacy `:sign_define`d glyph for one severity (older configs), or nil when undefined / blank.
---@param severity integer
---@return string?
local function legacy_sign(severity)
    local defined = vim.fn.sign_getdefined(SIGN_NAME[severity])
    local d = defined and defined[1]
    if d and type(d.text) == "string" then
        local text = vim.trim(d.text)
        if text ~= "" then
            return text
        end
    end
    return nil
end

--- The unified severity → glyph table: YOUR Neovim signs (modern, then legacy) win, else lvim-lsp's
--- `config.info.icons`. Read live each call so a runtime `vim.diagnostic.config` change is reflected.
---@return table<integer, string>
function M.glyphs()
    local user = user_signs()
    local ic = (lsp_state.config.info and lsp_state.config.info.icons) or {}
    local out = {}
    for severity, key in pairs(CFG_KEY) do
        out[severity] = user[severity] or legacy_sign(severity) or ic[key]
    end
    return out
end

return M
