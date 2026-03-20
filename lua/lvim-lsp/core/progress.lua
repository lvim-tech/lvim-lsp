-- lvim-lsp: LSP progress tracker.
-- Subscribes to the LspProgress autocmd (Neovim ≥ 0.10), accumulates
-- per-token state, and renders a live progress panel via lvim-utils.notify.
--
-- One combined entry (id = "lvim-lsp-progress") is maintained in the notify
-- progress panel so the spinner animation stays smooth and the panel never
-- flickers from multiple rapid updates.
--
---@module "lvim-lsp.core.progress"

local state = require("lvim-lsp.state")
local M = {}

-- ── Private state ─────────────────────────────────────────────────────────────

-- Tracks active tokens: client_id → token → ProgressEntry
---@type table<integer, table<string|integer, table>>
local _tokens = {}

local _suppressed = false
local _spin_frame = 0
local _spin_timer = nil ---@type uv.uv_timer_t?

-- ── Helpers ───────────────────────────────────────────────────────────────────

---@return table|nil
local function notify_mod()
	local ok, m = pcall(require, "lvim-utils.notify")
	return ok and m or nil
end

---@return table
local function cfg()
	return state.config.progress or {}
end

---@return string
local function spinner_char()
	local frames = cfg().spinner or { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	return frames[(_spin_frame % #frames) + 1]
end

--- Count tokens that are still in progress (not done).
---@return integer
local function count_active()
	local n = 0
	for _, tokens in pairs(_tokens) do
		for _, t in pairs(tokens) do
			if not t.done then
				n = n + 1
			end
		end
	end
	return n
end

-- ── Spinner timer ─────────────────────────────────────────────────────────────

local function render_panel()
	local nm = notify_mod()
	if not nm then
		return
	end

	local c = cfg()
	local limit = c.render_limit or 4
	local lines = {}
	local marks = {}

	-- Highlight groups (configurable via config.progress.highlights).
	local hls = c.highlights or {}
	local hl_icon = hls.icon or "Question"
	local hl_srv = hls.server or "Title"
	local hl_ttl = hls.title or "WarningMsg"
	local hl_done = hls.done or "Constant"
	local hl_msg = hls.message or "Comment"
	local hl_pct = hls.percentage or "Special"

	-- Collect and group entries by server_name, preserving insertion order.
	local groups = {} -- { server_name, entries[] }
	local group_of = {} -- server_name → index in groups
	local total = 0

	for _, tokens in pairs(_tokens) do
		for _, data in pairs(tokens) do
			total = total + 1
			if total > limit then
				break
			end
			local srv = data.server_name or "?"
			if not group_of[srv] then
				group_of[srv] = #groups + 1
				groups[#groups + 1] = { server_name = srv, entries = {} }
			end
			local g = groups[group_of[srv]]
			g.entries[#g.entries + 1] = data
		end
		if total > limit then
			break
		end
	end

	-- Target display width for right-aligning the server name.
	local TARGET_W = 58

	local row = 0
	for _, grp in ipairs(groups) do
		local srv = grp.server_name
		local n = #grp.entries

		for gi, data in ipairs(grp.entries) do
			local is_last = (gi == n)
			local icon = data.done and (c.done_icon or "✓") or spinner_char()
			local icon_hl = data.done and hl_done or hl_icon

			-- Build left content and track byte offsets.
			local left = " " .. icon .. " "
			local pos = 1 + #icon + 1 -- byte pos after " <icon> "

			local icon_s = 1
			local icon_e = 1 + #icon

			local ttl_s, ttl_e, ttl_hl
			if data.title and data.title ~= "" then
				ttl_s = pos
				ttl_e = pos + #data.title
				ttl_hl = data.done and hl_done or hl_ttl
				left = left .. data.title
				pos = ttl_e
			end

			local msg_s, msg_e
			if data.message and data.message ~= "" then
				left = left .. "  "
				pos = pos + 2
				msg_s = pos
				msg_e = pos + #data.message
				left = left .. data.message
				pos = msg_e
			end

			local pct_s, pct_e
			if data.percentage then
				local pct_str = tostring(data.percentage) .. "%"
				left = left .. "  "
				pos = pos + 2
				pct_s = pos
				pct_e = pos + #pct_str
				left = left .. pct_str
				pos = pct_e
			end

			-- Build final line: right-align server name on the last entry of each group.
			local line
			local srv_s, srv_e
			if is_last then
				local left_dw = vim.fn.strdisplaywidth(left)
				local srv_dw = vim.fn.strdisplaywidth(srv)
				local gap = math.max(2, TARGET_W - left_dw - srv_dw)
				srv_s = pos + gap
				srv_e = srv_s + #srv
				line = left .. string.rep(" ", gap) .. srv
			else
				-- Soft-truncate non-last lines at TARGET_W columns.
				if vim.fn.strdisplaywidth(left) > TARGET_W then
					left = left:sub(1, TARGET_W - 1) .. "…"
				end
				line = left
			end

			table.insert(lines, line)

			-- Extmarks (byte-offset, row 0-based within lines[]).
			table.insert(marks, { row, icon_s, icon_e, icon_hl })
			if ttl_s then
				table.insert(marks, { row, ttl_s, ttl_e, ttl_hl })
			end
			if msg_s then
				table.insert(marks, { row, msg_s, msg_e, hl_msg })
			end
			if pct_s then
				table.insert(marks, { row, pct_s, pct_e, hl_pct })
			end
			if srv_s then
				table.insert(marks, { row, srv_s, srv_e, hl_srv })
			end

			row = row + 1
		end
	end

	if #lines == 0 then
		nm.progress_clear("lvim-lsp-progress")
	else
		nm.progress_update("lvim-lsp-progress", lines, marks)
	end
end

local function start_spinner()
	if _spin_timer then
		return
	end
	_spin_timer = vim.uv.new_timer()
	if not _spin_timer then
		return
	end
	_spin_timer:start(
		100,
		100,
		vim.schedule_wrap(function()
			_spin_frame = _spin_frame + 1
			render_panel()
		end)
	)
end

local function stop_spinner()
	if not _spin_timer then
		return
	end
	_spin_timer:stop()
	_spin_timer:close()
	_spin_timer = nil
end

-- ── LspProgress handler ───────────────────────────────────────────────────────

---@param ev table  Autocmd event (ev.data = { client_id, params })
local function handle_progress(ev)
	if _suppressed then
		return
	end

	local client_id = ev.data and ev.data.client_id
	local params = ev.data and ev.data.params
	if not client_id or not params then
		return
	end

	local client = vim.lsp.get_client_by_id(client_id)
	if not client then
		return
	end

	-- Honour ignore list.
	for _, name in ipairs(cfg().ignore or {}) do
		if client.name == name then
			return
		end
	end

	local token = params.token
	local value = params.value
	if not token or not value then
		return
	end

	_tokens[client_id] = _tokens[client_id] or {}

	if value.kind == "begin" then
		_tokens[client_id][token] = {
			server_name = client.name,
			title = value.title,
			message = value.message,
			percentage = value.percentage,
			done = false,
		}
		start_spinner()
	elseif value.kind == "report" then
		local t = _tokens[client_id][token]
		if t then
			t.message = value.message or t.message
			t.percentage = value.percentage or t.percentage
		end
	elseif value.kind == "end" then
		local t = _tokens[client_id][token]
		if not t then
			return
		end
		t.done = true
		t.message = value.message or "Completed"
		t.percentage = nil

		-- Show the "done" state once, then remove after done_ttl.
		render_panel()
		vim.defer_fn(function()
			if _tokens[client_id] then
				_tokens[client_id][token] = nil
				if vim.tbl_isempty(_tokens[client_id]) then
					_tokens[client_id] = nil
				end
			end
			render_panel()
			if count_active() == 0 then
				stop_spinner()
			end
		end, cfg().done_ttl or 2000)
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Initialise the progress subsystem.  Called once from lvim-lsp setup().
---@return nil
function M.setup()
	if cfg().enabled == false then
		return
	end

	-- LspProgress requires Neovim 0.10+.
	if vim.fn.exists("##LspProgress") == 0 then
		return
	end

	-- Register the LSP progress channel with its configured appearance.
	local panel_cfg = cfg().panel or {}
	local nm = notify_mod()
	if nm and nm.progress_register then
		nm.progress_register("lvim-lsp-progress", {
			name = panel_cfg.name,
			icon = panel_cfg.icon,
			header_hl = panel_cfg.header_hl,
		})
	end

	local aug = vim.api.nvim_create_augroup("LvimLspProgress", { clear = true })

	vim.api.nvim_create_autocmd("LspProgress", {
		group = aug,
		callback = handle_progress,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = aug,
		callback = function(ev)
			local cid = ev.data and ev.data.client_id
			if not cid then
				return
			end
			vim.schedule(function()
				local detach_nm = notify_mod()
				if _tokens[cid] then
					_tokens[cid] = nil
					if detach_nm then
						detach_nm.progress_clear("lvim-lsp-progress")
					end
				end
				render_panel()
				if count_active() == 0 then
					stop_spinner()
				end
			end)
		end,
	})
end

--- Toggle suppression of progress tracking.
--- When suppressed, LspProgress events are silently discarded.
---@param bool boolean
---@return nil
function M.suppress(bool)
	_suppressed = bool
end

--- Returns a compact status string for statusline integration.
--- Empty string when no active (non-done) progress tokens exist.
---@return string
function M.get_status()
	local parts = {}
	for _, tokens in pairs(_tokens) do
		for _, data in pairs(tokens) do
			if not data.done then
				local s = spinner_char() .. " " .. data.server_name
				if data.title and data.title ~= "" then
					s = s .. ": " .. data.title
				end
				if data.percentage then
					s = s .. " " .. data.percentage .. "%"
				end
				table.insert(parts, s)
			end
		end
	end
	return table.concat(parts, "  ")
end

--- Clear all tracked progress tokens and close the progress panel immediately.
---@return nil
function M.clear()
	_tokens = {}
	stop_spinner()
	local nm = notify_mod()
	if nm then
		nm.progress_clear("lvim-lsp-progress")
	end
end

return M
