-- lvim-lsp: DAP adapter and configuration registration.
-- Called after a server's mason dependencies are confirmed installed.
-- nvim-dap is an optional dependency — silently skips when not available.
--
-- Expected dap field format in server configs:
--   dap = {
--       adapters       = { adapter_name = value, ... },
--       configurations = { ft = { config_table, ... }, ... },
--   }
--
---@module "lvim-lsp.core.dap"

local M = {}

--- Register DAP adapters and configurations from a server config's `dap` field.
--- Merges configurations (does not replace the whole table for a filetype).
---@param dap_config table  The `dap` field from the server config module
function M.setup(dap_config)
	if not dap_config then
		return
	end
	local ok, dap = pcall(require, "dap")
	if not ok then
		return
	end

	-- Register adapters
	if type(dap_config.adapters) == "table" then
		for name, adapter in pairs(dap_config.adapters) do
			dap.adapters[name] = adapter
		end
	end

	-- Merge configurations per filetype (append, don't overwrite)
	if type(dap_config.configurations) == "table" then
		for ft, configs in pairs(dap_config.configurations) do
			dap.configurations[ft] = dap.configurations[ft] or {}
			for _, cfg in ipairs(configs) do
				-- Avoid duplicates by checking the `name` field
				local exists = false
				for _, existing in ipairs(dap.configurations[ft]) do
					if existing.name == cfg.name then
						exists = true
						break
					end
				end
				if not exists then
					table.insert(dap.configurations[ft], cfg)
				end
			end
		end
	end
end

return M
