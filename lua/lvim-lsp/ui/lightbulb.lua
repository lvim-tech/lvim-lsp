-- lvim-lsp.ui.lightbulb: code-action availability indicator.
-- Shows a 󰌵 hint on the cursor line (EOL virtual text or a sign-column extmark) whenever an
-- attached client offers textDocument/codeAction there, so actions are discoverable without
-- probing. Timing discipline: updates are debounced through ONE persistent uv timer per buffer
-- (CursorHold / CursorMoved), the previous in-flight request is CANCELLED before the next is
-- issued (typing never queues a backlog), and a late response for an older cursor position is
-- dropped by a per-buffer GENERATION counter — never by comparing positions, which race.
-- Lifecycle: attach on LspAttach (capability-checked), detach with the LAST codeAction-capable
-- client (timer close + extmark clear). Pure extmark decoration — no windows, nothing panel-like.
--
---@module "lvim-lsp.ui.lightbulb"

local lsp_state = require("lvim-lsp.state")

local M = {}

--- Extmark namespace: one hint per buffer, cleared wholesale before every render.
---@type integer
local ns = vim.api.nvim_create_namespace("lvim-lsp-lightbulb")

--- Autocmd group; (re)created by setup().
---@type integer?
local group

---@class LvimLspLightbulbBufState
---@field timer uv.uv_timer_t Persistent debounce timer (closed on detach)
---@field generation integer  Bumped per scheduled probe AND per clear; stale responses compare against it
---@field cancel? fun()       Cancels the in-flight buf_request_all, if any
---@field autocmds integer[]  Buffer-local autocmd ids (removed on detach)
---@field count integer       Actions available at the last completed probe
---@field preferred boolean   Whether any of them is marked isPreferred
---@field row? integer        0-based row the hint is currently rendered on (nil = none); a cursor line-change clears it
---@field last_fire integer   `vim.uv.now()` of the last probe — drives the LEADING throttle in schedule_update

--- Per-buffer runtime state, keyed by bufnr. Presence = the buffer is attached.
---@type table<integer, LvimLspLightbulbBufState>
local buf_state = {}

--- Live view of the merged lightbulb config.
---@return LvimLspLightbulb
local function cfg()
    return lsp_state.config.lightbulb or {}
end

--- Cancel the in-flight request of a buffer, if any.
---@param st LvimLspLightbulbBufState
---@return nil
local function cancel_request(st)
    if st.cancel then
        pcall(st.cancel)
        st.cancel = nil
    end
end

--- Remove the rendered hint (extmark) from `bufnr` and forget the row it was on.
---@param bufnr integer
---@return nil
local function clear_hint(bufnr)
    local st = buf_state[bufnr]
    if st then
        st.row = nil
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
end

--- Clear the hint AND zero the availability snapshot (used when probing is not applicable).
---@param bufnr integer
---@return nil
local function reset(bufnr)
    local st = buf_state[bufnr]
    if st then
        st.count, st.preferred = 0, false
    end
    clear_hint(bufnr)
end

--- Render the hint on `row` (0-based). The `preferred` accent (orange) only applies when
--- `show_preferred` is on; otherwise the plain yellow accent is used.
---@param bufnr integer
---@param row integer
---@param preferred boolean
---@return nil
local function render(bufnr, row, preferred)
    local c = cfg()
    local icon = c.icon or "󰌵"
    local pref = preferred and c.show_preferred ~= false
    clear_hint(bufnr)
    if c.placement == "sign" then
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
            sign_text = icon,
            sign_hl_group = pref and "LvimLspLightbulbPreferred" or "LvimLspLightbulb",
        })
    else
        -- Padded so the chip's bg tint reads as a soft box, placed IMMEDIATELY AFTER the line's text
        -- (`eol`) — a leading space separates it from the last character — NOT flush to the window edge.
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
            virt_text = {
                {
                    " " .. icon .. " ",
                    pref and "LvimLspLightbulbVirtualTextPreferred" or "LvimLspLightbulbVirtualText",
                },
            },
            virt_text_pos = "eol",
            hl_mode = "combine",
        })
    end
    local st = buf_state[bufnr]
    if st then
        st.row = row -- track where the hint lives, so a line-change clear can fire immediately
    end
end

--- Probe codeAction availability at the cursor and render/clear the hint from the result.
--- Runs after the debounce; every early-out clears the hint so nothing stale lingers.
---@param bufnr integer
---@return nil
local function do_update(bufnr)
    local st = buf_state[bufnr]
    if not st then
        return
    end
    st.generation = st.generation + 1
    local gen = st.generation
    cancel_request(st)
    -- Only probe while the buffer is current, in normal mode, and not opted out per buffer.
    if
        vim.api.nvim_get_current_buf() ~= bufnr
        or vim.b[bufnr].lvim_lsp_lightbulb_disable
        or not vim.api.nvim_get_mode().mode:find("^n")
    then
        reset(bufnr)
        return
    end
    if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" }) == 0 then
        reset(bufnr)
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    local col = math.min(cursor[2], #line) -- byte col, clamped inside the line
    local diags = vim.diagnostic.get(bufnr, { lnum = row })
    -- Params per client. Range = the CURSOR POSITION (a zero-width range), NOT the whole line: some servers
    -- (lua_ls) offer position-specific actions — e.g. "Change to parameter N" on a call argument — ONLY for
    -- the exact cursor point and return NOTHING for a whole-line range, so a whole-line probe missed them.
    -- The line's diagnostics still ride in `context.diagnostics`, so diagnostic quickfixes keep working. This
    -- is exactly what `vim.lsp.buf.code_action` sends, so the bulb reflects what a manual invocation offers.
    ---@param client vim.lsp.Client
    ---@return table
    local params = function(client)
        local ok, cchar = pcall(vim.str_utfindex, line, client.offset_encoding or "utf-16", col)
        cchar = ok and cchar or col
        return {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
            range = {
                start = { line = row, character = cchar },
                ["end"] = { line = row, character = cchar },
            },
            context = {
                diagnostics = vim.lsp.diagnostic.from(diags),
                only = cfg().only,
                -- INVOKED (not Automatic): several servers (lua_ls) return FEWER actions for the Automatic
                -- trigger — a background hint that skips the refactor/rewrite kinds — so an action the user
                -- WOULD get on a manual `code_action` (e.g. "Change to parameter N") never lit the bulb.
                -- Invoked matches exactly what a manual invocation offers, so the bulb reflects reality.
                triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
            },
        }
    end
    st.cancel = vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", params, function(results)
        local cur = buf_state[bufnr]
        if not cur or cur.generation ~= gen then
            return -- stale: the cursor moved on (or the hint was cleared) after this was sent
        end
        cur.cancel = nil
        local count, preferred = 0, false
        for _, r in pairs(results or {}) do
            if not r.err then
                for _, action in ipairs(r.result or {}) do
                    count = count + 1
                    preferred = preferred or (type(action) == "table" and action.isPreferred == true)
                end
            end
        end
        cur.count, cur.preferred = count, preferred
        if count > 0 and vim.api.nvim_buf_is_valid(bufnr) and row < vim.api.nvim_buf_line_count(bufnr) then
            render(bufnr, row, preferred)
        else
            clear_hint(bufnr)
        end
    end)
end

--- (Re)start the debounce timer of `bufnr`; the probe fires `update_ms` after the last event.
---@param bufnr integer
---@return nil
local function schedule_update(bufnr)
    local st = buf_state[bufnr]
    if not st then
        return
    end
    -- LEADING throttle (NOT a trailing debounce): the FIRST cursor event after an idle gap probes
    -- IMMEDIATELY (wait 0), so the hint appears the instant the cursor LANDS — then re-probes at most once
    -- per `update_ms` while the cursor keeps moving, so it TRACKS during a held `l`/`h` instead of only
    -- firing once movement stops (the trailing tick still lands after the last move).
    local ms = math.max(0, cfg().update_ms or 100)
    local elapsed = vim.uv.now() - (st.last_fire or 0)
    st.timer:stop()
    st.timer:start(
        elapsed >= ms and 0 or (ms - elapsed),
        0,
        vim.schedule_wrap(function()
            st.last_fire = vim.uv.now()
            do_update(bufnr)
        end)
    )
end

--- Detach `bufnr`: close its timer, cancel any in-flight request, drop its autocmds + hint.
---@param bufnr integer
---@return nil
local function detach(bufnr)
    local st = buf_state[bufnr]
    if not st then
        return
    end
    buf_state[bufnr] = nil
    st.timer:stop()
    st.timer:close()
    cancel_request(st)
    for _, id in ipairs(st.autocmds) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    clear_hint(bufnr)
end

--- Attach `bufnr`: create its persistent timer + buffer-local trigger/clear autocmds.
---@param bufnr integer
---@return nil
local function attach(bufnr)
    if buf_state[bufnr] then
        return
    end
    local timer = vim.uv.new_timer()
    if not timer then
        return
    end
    local st = { timer = timer, generation = 0, autocmds = {}, count = 0, preferred = false, last_fire = 0 }
    buf_state[bufnr] = st
    st.autocmds[#st.autocmds + 1] = vim.api.nvim_create_autocmd({ "CursorHold", "CursorMoved" }, {
        group = group,
        buffer = bufnr,
        desc = "lvim-lsp lightbulb: debounced code-action probe",
        callback = function()
            -- If the hint is on a DIFFERENT line than the cursor now, drop it IMMEDIATELY so it never
            -- lingers a line behind while the next probe debounces (the "slow to update" feel). The fresh
            -- probe then re-renders on the current line if an action is available there.
            if st.row ~= nil and st.row ~= vim.api.nvim_win_get_cursor(0)[1] - 1 then
                clear_hint(bufnr)
            end
            schedule_update(bufnr)
        end,
    })
    st.autocmds[#st.autocmds + 1] = vim.api.nvim_create_autocmd({ "InsertEnter", "BufLeave" }, {
        group = group,
        buffer = bufnr,
        desc = "lvim-lsp lightbulb: clear on insert / leaving the buffer",
        callback = function()
            st.timer:stop()
            cancel_request(st)
            -- Bump the generation so an already-delivered response for the old spot is dropped.
            st.generation = st.generation + 1
            reset(bufnr)
        end,
    })
    schedule_update(bufnr)
end

--- Code-action availability at the last completed probe — for statusline / winbar consumers.
---@param bufnr? integer  defaults to the current buffer
---@return { count: integer, preferred: boolean }
function M.get(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local st = buf_state[bufnr]
    return { count = st and st.count or 0, preferred = st and st.preferred or false }
end

--- Install the LspAttach/LspDetach lifecycle. Called from lvim-lsp setup(); a re-run tears the
--- previous state down first, so flipping `lightbulb.enabled` and re-running setup() is clean.
---@return nil
function M.setup()
    for bufnr in pairs(buf_state) do
        detach(bufnr)
    end
    if cfg().enabled == false then
        if group then
            vim.api.nvim_del_augroup_by_id(group)
            group = nil
        end
        return
    end
    group = vim.api.nvim_create_augroup("LvimLspLightbulb", { clear = true })
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        desc = "lvim-lsp lightbulb: attach when a codeAction-capable client arrives",
        callback = function(ev)
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            if client and client:supports_method("textDocument/codeAction", ev.buf) then
                attach(ev.buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd("LspDetach", {
        group = group,
        desc = "lvim-lsp lightbulb: detach with the last codeAction-capable client",
        callback = function(ev)
            -- LspDetach fires BEFORE the client is detached, so it still shows up here:
            -- keep the buffer attached only if ANOTHER capable client remains.
            for _, client in ipairs(vim.lsp.get_clients({ bufnr = ev.buf, method = "textDocument/codeAction" })) do
                if client.id ~= ev.data.client_id then
                    return
                end
            end
            detach(ev.buf)
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        desc = "lvim-lsp lightbulb: free the timer/state of a dying buffer",
        callback = function(ev)
            detach(ev.buf)
        end,
    })
    -- Buffers whose capable clients attached before setup() ran (e.g. a live reconfigure).
    for _, client in ipairs(vim.lsp.get_clients({ method = "textDocument/codeAction" })) do
        for bufnr in pairs(client.attached_buffers or {}) do
            attach(bufnr)
        end
    end
end

return M
