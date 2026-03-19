-- lvim-lsp: shared lvim-utils UI instance.
-- Lazily created on first access so that lvim-utils is not required at load time.
--
---@module "lvim-lsp.ui"

local _instance = nil

--- Returns the shared lvim-utils UI instance (created once via .new()).
--- Passes state.config.popup_global so per-plugin overrides take effect.
--- Returns nil if lvim-utils is not available.
local function get()
	if _instance then
		return _instance
	end
	local ok, mod = pcall(require, "lvim-utils.ui")
	if not ok then
		return nil
	end
	local cfg = require("lvim-lsp.state").config.popup_global
	_instance = mod.new(cfg)
	return _instance
end

--- Invalidate the cached instance so the next get() rebuilds it with
--- the current popup_global config (called from state.configure()).
local function reset()
	_instance = nil
end

--- Resolves a popup width value: fraction (0–1) → columns, integer → as-is.
---@param pw number
---@param fallback integer
---@return integer
local function resolve_width(pw, fallback)
	if type(pw) == "number" and pw <= 1 then
		return math.floor(vim.o.columns * pw)
	end
	return type(pw) == "number" and pw or fallback
end

return { get = get, reset = reset, resolve_width = resolve_width }
