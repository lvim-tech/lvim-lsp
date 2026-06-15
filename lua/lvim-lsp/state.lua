-- lvim-lsp: UI configuration state (popup / menus / info / project + the highlight
-- factory). Held HERE, not in the engine — lvim-ls.state.config stays pure data,
-- mirroring lvim-pkg (engine, zero UI) vs lvim-installer (holds the UI config).
--
---@module "lvim-lsp.state"

local M = {}

local hl = require("lvim-lsp.config.highlights")

--- Merged UI config (defaults ⊕ user setup opts). Mutated in place by configure().
M.config = vim.deepcopy(require("lvim-lsp.config.ui"))
M.config.build = hl.build
M.config.force = hl.force

--- Merge user UI overrides over the defaults, in place (cached refs stay valid).
---@param ui_opts table|nil
function M.configure(ui_opts)
    require("lvim-utils.utils").merge(M.config, ui_opts)
    M.config.build = M.config.build or hl.build
    if M.config.force == nil then
        M.config.force = hl.force
    end
end

return M
