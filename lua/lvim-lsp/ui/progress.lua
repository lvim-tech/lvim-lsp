-- lvim-lsp: LSP progress panel renderer.
-- Subscribes to the lvim-ls progress engine (data) and draws the live panel —
-- spinner animation, colours, layout — via lvim-hud.notify. All appearance comes
-- from the UI config (lvim-lsp.state.config.progress); the engine stays UI-agnostic.
--
---@module "lvim-lsp.ui.progress"

local lsp_state = require("lvim-lsp.state")
local ls_state = require("lvim-ls.state")
local ls_progress = require("lvim-ls.core.progress")

local M = {}

local _spin_frame = 0
local _spin_timer = nil ---@type uv.uv_timer_t?

local PANEL_ID = "lvim-ls-progress"

---@return table  UI progress config (spinner / done_icon / render_limit / panel / highlights)
local function ui_cfg()
    return lsp_state.config.progress or {}
end

---@return table|nil
local function notify_mod()
    local ok, m = pcall(require, "lvim-hud.notify")
    return ok and m or nil
end

---@return string
local function spinner_char()
    local frames = ui_cfg().spinner or { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    return frames[(_spin_frame % #frames) + 1]
end

local function render_panel()
    local nm = notify_mod()
    if not nm then
        return
    end

    local c = ui_cfg()
    local limit = c.render_limit or 4
    local lines = {}
    local marks = {}

    local hls = c.highlights or {}
    local hl_icon = hls.icon or "Question"
    local hl_srv = hls.server or "Title"
    local hl_ttl = hls.title or "WarningMsg"
    local hl_done = hls.done or "Constant"
    local hl_msg = hls.message or "Comment"
    local hl_pct = hls.percentage or "Special"

    -- Group entries by server_name, preserving insertion order, capped at `limit`.
    local groups, group_of, total = {}, {}, 0
    for _, data in ipairs(ls_progress.items()) do
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

    local TARGET_W = 58
    local row = 0
    for _, grp in ipairs(groups) do
        local srv = grp.server_name
        local n = #grp.entries
        for gi, data in ipairs(grp.entries) do
            local is_last = (gi == n)
            local icon = data.done and (c.done_icon or "✓") or spinner_char()
            local icon_hl = data.done and hl_done or hl_icon

            local left = " " .. icon .. " "
            local pos = 1 + #icon + 1
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
                -- Truncate by DISPLAY CELLS, char-safe: the row starts with a multibyte spinner/done glyph
                -- and titles/messages may be multibyte, so a byte slice could (a) cut inside a UTF-8 sequence
                -- and (b) no-op when byte length < TARGET_W despite the display width exceeding it.
                if vim.fn.strdisplaywidth(left) > TARGET_W then
                    local acc, cells = "", 0
                    for i = 0, vim.fn.strchars(left) - 1 do
                        local ch = vim.fn.strcharpart(left, i, 1)
                        local w = vim.fn.strdisplaywidth(ch)
                        if cells + w > TARGET_W - 1 then
                            break
                        end
                        acc, cells = acc .. ch, cells + w
                    end
                    left = acc .. "…"
                end
                line = left
            end

            table.insert(lines, line)
            -- The msg/pct byte offsets were computed against the UNtruncated `left`; clamp every mark to the
            -- final line length so a truncated row never hands an out-of-range extmark to the notify painter.
            local function push_mark(s, e, hl)
                if s and s < #line then
                    table.insert(marks, { row, s, math.min(e, #line), hl })
                end
            end
            push_mark(icon_s, icon_e, icon_hl)
            push_mark(ttl_s, ttl_e, ttl_hl)
            push_mark(msg_s, msg_e, hl_msg)
            push_mark(pct_s, pct_e, hl_pct)
            push_mark(srv_s, srv_e, hl_srv)
            row = row + 1
        end
    end

    if #lines == 0 then
        nm.progress_clear(PANEL_ID)
    else
        nm.progress_update(PANEL_ID, lines, marks)
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

--- Compact status string for statusline integration. Empty when nothing is active.
---@return string
function M.get_status()
    local parts = {}
    for _, data in ipairs(ls_progress.items()) do
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
    return table.concat(parts, "  ")
end

--- Register the progress panel + subscribe to the engine. Called from lvim-lsp setup.
---@return nil
function M.setup()
    local engine = ls_progress
    -- Honour the engine's enable flag (data config) for the renderer too.
    if (ls_state.config.progress or {}).enabled == false then
        return
    end
    local nm = notify_mod()
    local panel = ui_cfg().panel or {}
    if nm and nm.progress_register then
        nm.progress_register(PANEL_ID, {
            name = panel.name,
            icon = panel.icon,
            header_hl = panel.header_hl,
        })
    end
    engine.on_change(function()
        render_panel()
        if engine.active() > 0 then
            start_spinner()
        else
            stop_spinner()
        end
    end)
end

return M
