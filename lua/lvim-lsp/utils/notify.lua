-- lvim-lsp: notification utility.
-- Routes through lvim-utils.notify when available so notifications can be
-- globally controlled from a single place.  Falls back to vim.notify.
-- Respects config.notify.enabled and config.notify.min_level.

local levels = require("lvim-lsp.utils.levels")

---@param msg   string
---@param level string|integer|nil
return function(msg, level)
	local state = require("lvim-lsp.state")
	local cfg = state.config.notify or {}

	if cfg.enabled == false then
		return
	end

	if type(msg) ~= "string" or msg == "" then
		return
	end

	local min_level = cfg.min_level or levels.INFO
	if not levels.should_show(level, min_level) then
		return
	end

	local level_num = levels.to_level_number(level)
	local title = cfg.title or "Lvim LSP"

	vim.schedule(function()
		pcall(vim.notify, msg, level_num, { title = title })
	end)
end
