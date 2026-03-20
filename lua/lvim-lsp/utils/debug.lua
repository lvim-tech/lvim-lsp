-- lvim-lsp: file-based debug logging utility.
-- Writes timestamped log lines to stdpath("state")/lvim-lsp/debug.log.
-- File I/O is always scheduled so it is safe from fast-event and async contexts.
-- Enabled only when config.debug.enabled = true (default: false).

local levels = require("lvim-lsp.utils.levels")

---@param msg       string
---@param level_num integer
local function write_to_file(msg, level_num)
	vim.schedule(function()
		local path = vim.fn.stdpath("state") .. "/lvim-lsp/debug.log"
		local dir = vim.fn.fnamemodify(path, ":h")
		vim.fn.mkdir(dir, "p")

		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		local level_name = levels.get_level_name(level_num)
		local line = string.format("%s [%s] %s\n", timestamp, level_name, tostring(msg))

		local file = io.open(path, "a")
		if file then
			file:write(line)
			file:close()
		end
	end)
end

---@param msg   string
---@param level string|integer|nil
return function(msg, level)
	local state = require("lvim-lsp.state")
	local cfg = state.config.debug or {}

	if not cfg.enabled then
		return
	end

	local level_num = levels.to_level_number(level)
	local min_level = cfg.min_level or levels.DEBUG
	if not levels.should_show(level_num, min_level) then
		return
	end

	write_to_file(msg, level_num)
end
