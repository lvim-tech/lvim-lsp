-- lvim-lsp: custom Mason-backed installer UI.
-- Tracks one or more Mason package installations in parallel, showing a
-- braille spinner, per-tool status (pending / ok / fail), and the latest
-- stdout/stderr action line.  Progress is rendered via lvim-utils.notify's
-- progress panel so it shares the same floating stack as LSP progress.
-- Exposes M.ensure_mason_tools(tools, cb) and M.status() debug helper.
--
---@module "lvim-lsp.installer"
---@diagnostic disable: undefined-doc-name, undefined-field

local state = require("lvim-lsp.state")
local notify = require("lvim-lsp.utils.notify")
local dbg = require("lvim-lsp.utils.debug")

-- ── Constants ─────────────────────────────────────────────────────────────────

-- Maps dep names to the actual Mason package name when they differ.
local MASON_PACKAGE_ALIASES = {
	["efm-langserver"] = "efm",
}

local function mason_pkg_name(dep)
	return MASON_PACKAGE_ALIASES[dep] or dep
end

local INSTALLER_ID = "lvim-lsp-installer"

---@type { PENDING: string, OK: string, FAIL: string }
local STATUS = { PENDING = "pending", OK = "ok", FAIL = "fail" }

---@type table<string, string>
local STATUS_TEXT = {
	[STATUS.PENDING] = "Installing",
	[STATUS.OK] = "Installed",
	[STATUS.FAIL] = "Error",
}

---@type uv.uv_timer_t|nil
local refresh_timer = nil

-- ── Notify helper ─────────────────────────────────────────────────────────────

local function notify_mod()
	local ok, m = pcall(require, "lvim-utils.notify")
	return ok and m or nil
end

--- Register the installer progress channel with its configured appearance.
--- Called once lazily on first install; safe to call multiple times.
local _channel_registered = false
local function ensure_channel()
	if _channel_registered then
		return
	end
	_channel_registered = true
	local nm = notify_mod()
	if not nm or not nm.progress_register then
		return
	end
	local panel_cfg = (state.config.installer or {}).panel or {}
	nm.progress_register(INSTALLER_ID, {
		name = panel_cfg.name,
		icon = panel_cfg.icon,
		header_hl = panel_cfg.header_hl,
	})
end

-- ── Installer state ───────────────────────────────────────────────────────────

---@class AllinOne
---@field tools                string[]
---@field states               table<string, table>
---@field callbacks            { tools: string[], callback: function }[]
---@field closed               boolean
---@field active_installations integer
---@field is_installing        boolean
local allin1 = {
	tools = {},
	states = {},
	callbacks = {},
	closed = false,
	active_installations = 0,
	is_installing = false,
}

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function render_to_notify()
	local nm = notify_mod()
	if not nm then
		return
	end

	if not allin1.tools or #allin1.tools == 0 then
		nm.progress_clear(INSTALLER_ID)
		return
	end

	-- Pick a spinner frame from the first still-pending tool.
	local spin_frame = 0
	for _, tool in ipairs(allin1.tools) do
		local s = allin1.states[tool]
		if s and s.status == STATUS.PENDING then
			spin_frame = s.spinner_frame or 0
			break
		end
	end
	local inst_cfg = state.config.installer
	local frames = inst_cfg.spinner
	local spin = frames[(spin_frame % #frames) + 1]
	local icon_ok = inst_cfg.icon_ok or ""
	local icon_err = inst_cfg.icon_error or ""

	-- Highlight groups from config.
	local hls = (state.config.installer or {}).highlights or {}
	local function icon_hl(status)
		if status == STATUS.OK then
			return hls.icon_ok or "Constant"
		end
		if status == STATUS.FAIL then
			return hls.icon_fail or "DiagnosticError"
		end
		return hls.icon_pending or "Question"
	end
	local function status_hl(status)
		if status == STATUS.OK then
			return hls.status_ok or "Constant"
		end
		if status == STATUS.FAIL then
			return hls.status_fail or "DiagnosticError"
		end
		return hls.status_pending or "WarningMsg"
	end
	local hl_tool = hls.tool or "Title"
	local hl_action = hls.action or "Comment"

	local lines = {}
	local marks = {}
	local row = 0

	for _, tool in ipairs(allin1.tools) do
		local s = allin1.states[tool]
		if not s then
			goto continue
		end

		local icon
		if s.status == STATUS.PENDING then
			icon = spin
		elseif s.status == STATUS.OK then
			icon = icon_ok
		else
			icon = icon_err
		end

		local status_text = STATUS_TEXT[s.status] or ""

		-- Track byte offsets: " <icon> <tool>  <status_text>"
		local icon_s = 1
		local icon_e = 1 + #icon
		local tool_s = icon_e + 1 -- after " "
		local tool_e = tool_s + #tool
		local stat_s = tool_e + 2 -- after "  "
		local stat_e = stat_s + #status_text

		table.insert(lines, " " .. icon .. " " .. tool .. "  " .. status_text)
		table.insert(marks, { row, icon_s, icon_e, icon_hl(s.status) })
		table.insert(marks, { row, tool_s, tool_e, hl_tool })
		table.insert(marks, { row, stat_s, stat_e, status_hl(s.status) })
		row = row + 1

		if s.current_action and s.current_action ~= "" and s.status == STATUS.PENDING then
			local action = s.current_action
			if vim.fn.strdisplaywidth(action) > 52 then
				action = action:sub(1, 51) .. "…"
			end
			local act_s = 3
			local act_e = act_s + #action
			table.insert(lines, "   " .. action)
			table.insert(marks, { row, act_s, act_e, hl_action })
			row = row + 1
		end

		::continue::
	end

	if #lines == 0 then
		nm.progress_clear(INSTALLER_ID)
	else
		nm.progress_update(INSTALLER_ID, lines, marks)
	end
end

-- ── Timer helpers ─────────────────────────────────────────────────────────────

local function close_popup(force)
	if not force and allin1.is_installing then
		return
	end

	if refresh_timer and not refresh_timer:is_closing() then
		refresh_timer:stop()
		refresh_timer:close()
		refresh_timer = nil
	end

	local nm = notify_mod()
	if nm then
		nm.progress_clear(INSTALLER_ID)
	end

	allin1.closed = true
	vim.defer_fn(function()
		allin1.tools = {}
		allin1.states = {}
		allin1.callbacks = {}
		allin1.closed = false
		allin1.active_installations = 0
		allin1.is_installing = false
	end, 200)
end

local function update_current_action(tool, line)
	if not allin1.states[tool] then
		return
	end
	line = vim.trim(line)
	if line == "" then
		return
	end
	if line:match("^ERROR: ") then
		line = line:gsub("^ERROR: ", "")
	end
	allin1.states[tool].current_action = line
	if #line < 30 then
		allin1.states[tool].message = line
	end
	render_to_notify()
end

local function start_ui_refresh_timer()
	if refresh_timer and not refresh_timer:is_closing() then
		refresh_timer:stop()
		refresh_timer:close()
	end
	local hide_delay = (state.config.installer.done_ttl or 5000) / 1000
	refresh_timer = vim.uv.new_timer()
	if not refresh_timer then
		return
	end
	refresh_timer:start(
		0,
		80,
		vim.schedule_wrap(function()
			if allin1.closed then
				if refresh_timer and not refresh_timer:is_closing() then
					refresh_timer:stop()
					refresh_timer:close()
					refresh_timer = nil
				end
				return
			end

			-- Advance spinner for pending tools.
			for _, tool in ipairs(allin1.tools) do
				local s = allin1.states[tool]
				if s and s.status == STATUS.PENDING then
					s.spinner_frame = (s.spinner_frame or 0) + 1
				end
			end

			-- Hide completed tools after done_ttl ms.
			local to_remove = {}
			for _, tool in ipairs(allin1.tools) do
				local s = allin1.states[tool]
				if s and s.status == STATUS.OK and not s.hide_timer_started then
					s.hide_timer_started = true
					s.hide_time = os.time() + hide_delay
				end
				if s and s.status == STATUS.OK and s.hide_time and os.time() >= s.hide_time then
					table.insert(to_remove, tool)
				end
			end

			for _, tool in ipairs(to_remove) do
				for i, t in ipairs(allin1.tools) do
					if t == tool then
						table.remove(allin1.tools, i)
						break
					end
				end
				allin1.states[tool] = nil
			end

			pcall(render_to_notify)
		end)
	)
end

-- ── Mason helpers ─────────────────────────────────────────────────────────────

local function add_tools(new_tools)
	local mason_registry_ok, mason_registry = pcall(require, "mason-registry")
	if not mason_registry_ok then
		notify("Error loading mason-registry", vim.log.levels.ERROR)
		return {}
	end
	local actually_added = {}
	for _, name in ipairs(new_tools) do
		local already = false
		for _, t in ipairs(allin1.tools) do
			if t == name then
				already = true
				break
			end
		end
		if not already then
			local ok, pkg = pcall(mason_registry.get_package, mason_pkg_name(name))
			if not ok or not pkg then
				state.not_in_registry[name] = true
				vim.schedule(function()
					notify(
						string.format(
							"[lvim-lsp] Mason package not found: '%s'. Check the package name — this tool will be skipped.",
							name
						),
						vim.log.levels.ERROR
					)
				end)
			end
			if ok and pkg then
				local bin = state.bin_aliases[name] or name
				local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/" .. bin
				local binary_ok = vim.fn.executable(bin) == 1 or vim.fn.executable(mason_bin) == 1
				local broken_symlink = false
				if not binary_ok then
					local lstat = vim.uv.fs_lstat(mason_bin) ---@diagnostic disable-line: param-type-mismatch
					if lstat then
						broken_symlink = true
						pcall(vim.uv.fs_unlink, mason_bin)
					end
				end
				local needs_install = not pkg:is_installed() or not binary_ok
				local force_reinstall = (pkg:is_installed() and not binary_ok) or broken_symlink
				if needs_install then
					table.insert(allin1.tools, name)
					allin1.states[name] = {
						status = STATUS.PENDING,
						current_action = "Preparing installation...",
						spinner_frame = 0,
						message = "Preparing...",
						force_reinstall = force_reinstall,
					}
					allin1.active_installations = allin1.active_installations + 1
					allin1.is_installing = true
					table.insert(actually_added, name)
				end
			end
		end
	end
	return actually_added
end

local function are_tools_completed(tools)
	for _, tool in ipairs(tools) do
		if allin1.states[tool] and allin1.states[tool].status == STATUS.PENDING then
			return false
		end
	end
	return true
end

local function check_callbacks()
	local to_remove = {}
	for i, cb_data in ipairs(allin1.callbacks) do
		if are_tools_completed(cb_data.tools) then
			if cb_data.callback then
				cb_data.callback()
			end
			table.insert(to_remove, i)
		end
	end
	for i = #to_remove, 1, -1 do
		table.remove(allin1.callbacks, to_remove[i])
	end

	if are_tools_completed(allin1.tools) and allin1.active_installations == 0 then
		local manager = require("lvim-lsp.core.manager")
		pcall(manager.set_installation_status, false)
		allin1.is_installing = false
		vim.defer_fn(function()
			close_popup(false)
		end, 10000)
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

local M = {}

--- Ensures that all `tools` are installed via Mason.
--- Already-installed tools are skipped.  When all finish (or were already
--- present) `cb` is invoked once.  Diagnostics are reset on all loaded
--- buffers before `cb` runs.
---@param tools string[]
---@param cb    function|nil
M.ensure_mason_tools = function(tools, cb)
	local mason_registry_ok, mason_registry = pcall(require, "mason-registry")
	if not mason_registry_ok then
		notify("Error loading mason-registry", vim.log.levels.ERROR)
		if cb then
			cb()
		end
		return
	end

	local manager = require("lvim-lsp.core.manager")

	tools = tools or {}
	if #tools == 0 then
		if cb then
			cb()
		end
		return
	end

	if cb then
		local original_callback = cb
		local wrapped_callback = function()
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
					vim.diagnostic.reset(nil, bufnr)
				end
			end
			original_callback()
		end
		table.insert(allin1.callbacks, {
			tools = vim.deepcopy(tools),
			callback = wrapped_callback,
		})
	end

	local new_tools = add_tools(tools)
	if #new_tools == 0 then
		allin1.is_installing = false
		check_callbacks()
		return
	end

	manager.set_installation_status(true)
	allin1.is_installing = true
	allin1.closed = false

	ensure_channel()
	start_ui_refresh_timer()
	render_to_notify()

	local function on_tool_closed(tool)
		local bin = state.bin_aliases[tool] or tool
		local bin_path = vim.fn.stdpath("data") .. "/mason/bin/" .. bin
		local installed = vim.fn.executable(bin) == 1 or vim.fn.executable(bin_path) == 1
		if not installed then
			pcall(function()
				local fresh_pkg = require("mason-registry").get_package(mason_pkg_name(tool))
				if fresh_pkg then
					installed = fresh_pkg:is_installed()
				end
			end)
		end

		if allin1.states and allin1.states[tool] then
			if installed then
				update_current_action(tool, "Installation completed successfully")
				allin1.states[tool].status = STATUS.OK
				allin1.states[tool].message = "Installation complete"
				allin1.states[tool].hide_timer_started = false
				allin1.states[tool].hide_time = nil
				dbg(string.format("[installer] %s installed successfully", tool), vim.log.levels.INFO)
			else
				local last_action = allin1.states[tool].current_action or ""
				update_current_action(tool, "Installation failed")
				allin1.states[tool].status = STATUS.FAIL
				allin1.states[tool].message = "Installation failed"
				local detail = (last_action ~= "" and last_action ~= "Installation failed") and ("\n" .. last_action)
					or ""
				dbg(string.format("[installer] %s FAILED: %s", tool, last_action), vim.log.levels.ERROR)
				vim.schedule(function()
					notify(
						string.format("[lvim-lsp] Failed to install '%s'.%s", tool, detail),
						vim.log.levels.ERROR
					)
				end)
			end
			allin1.active_installations = math.max(0, allin1.active_installations - 1)
			if allin1.active_installations == 0 then
				vim.defer_fn(function()
					if allin1.active_installations == 0 then
						allin1.is_installing = false
					end
				end, 1000)
			end
		end
		render_to_notify()
		pcall(check_callbacks)
	end

	local function fail_tool(tool, reason)
		allin1.states[tool].status = STATUS.FAIL
		allin1.states[tool].current_action = reason
		allin1.active_installations = math.max(0, allin1.active_installations - 1)
		render_to_notify()
		pcall(check_callbacks)
	end

	for _, tool in ipairs(new_tools) do
		if not (allin1.states[tool] and allin1.states[tool].status == STATUS.PENDING) then
			goto continue
		end

		local pkg = mason_registry.get_package(mason_pkg_name(tool))
		if not pkg then
			fail_tool(tool, "Package not found")
			goto continue
		end

		update_current_action(tool, "Starting installation...")

		local install_ok, install_result = pcall(function()
			local opts = allin1.states[tool].force_reinstall and { force = true } or {}
			return pkg:install(opts)
		end)
		if not install_ok then
			fail_tool(tool, "Failed to start: " .. tostring(install_result))
			goto continue
		end

		local handle = install_result
		if not handle then
			fail_tool(tool, "No installation handle returned")
			goto continue
		end

		handle:on(
			"stdout",
			vim.schedule_wrap(function(chunk)
				if allin1.closed or not allin1.states or not allin1.states[tool] then
					return
				end
				if chunk and #chunk > 0 then
					local best_line = ""
					for line in chunk:gmatch("[^\r\n]+") do
						if line and #line > 0 and not line:match("^%s*%*+%s*$") then
							best_line = line
						end
					end
					if best_line ~= "" then
						update_current_action(tool, best_line)
					end
				end
			end)
		)

		handle:on(
			"stderr",
			vim.schedule_wrap(function(chunk)
				if allin1.closed or not allin1.states or not allin1.states[tool] then
					return
				end
				if chunk and #chunk > 0 then
					for line in chunk:gmatch("[^\r\n]+") do
						if line and #line > 0 then
							update_current_action(tool, line)
						end
					end
				end
			end)
		)

		handle:on(
			"progress",
			vim.schedule_wrap(function(progress)
				if allin1.closed or not allin1.states or not allin1.states[tool] then
					return
				end
				if progress.message then
					update_current_action(tool, progress.message)
					allin1.states[tool].message = progress.message
				end
				render_to_notify()
			end)
		)

		handle:once(
			"closed",
			vim.schedule_wrap(function()
				vim.defer_fn(function()
					if not allin1 or not allin1.states or not allin1.states[tool] then
						return
					end
					on_tool_closed(tool)
				end, 500)
			end)
		)

		::continue::
	end
end

--- Returns the Mason registry package name for a dep (resolves MASON_PACKAGE_ALIASES).
---@type fun(dep: string): string
M.pkg_name = mason_pkg_name

--- Prints a debug summary of the current installer state.
M.status = function()
	local tools_list = table.concat(allin1.tools, ", ")
	notify(
		string.format(
			"Active = %d, Installing = %s, Tools: %s",
			allin1.active_installations,
			allin1.is_installing and "YES" or "NO",
			#allin1.tools > 0 and tools_list or "none"
		),
		vim.log.levels.INFO
	)
	for tool, s in pairs(allin1.states) do
		notify(
			string.format("%s: %s, Action: %s", tool, s.status or "unknown", s.current_action or ""),
			vim.log.levels.INFO
		)
	end
end

return M
