-- lvim-lsp.ui.calls: present LSP call hierarchy (incoming/outgoing) in the lvim-utils PICKER.
--
-- prepareCallHierarchy at the cursor, then request BOTH incoming and outgoing calls and tag each
-- result with its direction, so the picker's filter bar toggles Incoming/Outgoing live (a predicate
-- filter — no re-request). A file preview + jump, mirroring ui/locations.lua.
--
---@module "lvim-lsp.ui.calls"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local picker = require("lvim-picker")

local M = {}

--- CallHierarchyItem → a picker item base (1-based loc from its selection range).
---@param item table
---@return table
local function item_to_loc(item)
    local r = item.selectionRange or item.range
    return {
        path = vim.uri_to_fname(item.uri),
        lnum = (r and r.start.line or 0) + 1,
        col = (r and r.start.character or 0) + 1,
        end_lnum = r and (r["end"].line + 1) or nil,
        end_col = r and (r["end"].character + 1) or nil,
        text = item.name,
        icon = "󰊕", -- function glyph (folded into the row format)
    }
end

--- Jump to a location with `cmd` (edit/split/vsplit) and centre it.
---@param it table
---@param cmd? string
local function jump(it, cmd)
    cmd = cmd or "edit"
    if cmd == "edit" then
        -- `:edit` refuses with E37 on an unsaved buffer; swap the file in without that.
        local buf = vim.fn.bufadd(it.path)
        vim.fn.bufload(buf)
        vim.api.nvim_win_set_buf(0, buf)
    else
        vim.cmd(cmd .. " " .. vim.fn.fnameescape(it.path))
    end
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- Open the call-hierarchy picker focused on `direction` ("incoming"|"outgoing"). `layout` = area|float|bottom.
---@param direction string
---@param layout string
function M.open(direction, layout)
    local bufnr = vim.api.nvim_get_current_buf()
    if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/prepareCallHierarchy" }) == 0 then
        notify("No LSP client supporting call hierarchy found.", vim.log.levels.WARN)
        return
    end
    local params = function(client)
        return vim.lsp.util.make_position_params(0, client.offset_encoding or "utf-16")
    end
    vim.lsp.buf_request_all(bufnr, "textDocument/prepareCallHierarchy", params, function(prep)
        -- Remember WHICH client produced the item: a CallHierarchyItem carries client-private `data`, so the
        -- follow-up incoming/outgoing requests are valid ONLY against that same client — fanning it to every
        -- client (buf_request_all) is invalid per LSP and duplicates every row when two clients answer.
        local target, target_id
        for cid, r in pairs(prep or {}) do
            if r.result and r.result[1] then
                target, target_id = r.result[1], cid
                break
            end
        end
        if not target then
            notify("No call hierarchy at the cursor.", vim.log.levels.INFO)
            return
        end
        local client = target_id and vim.lsp.get_client_by_id(target_id)
        if not client then
            notify("The call-hierarchy client is gone.", vim.log.levels.INFO)
            return
        end

        local items, pending = {}, 2
        local function collect(result, kind)
            for _, call in ipairs(result or {}) do
                local it = item_to_loc(kind == "incoming" and call.from or call.to)
                it.direction = kind
                items[#items + 1] = it
            end
        end
        local function done()
            pending = pending - 1
            if pending > 0 then
                return
            end
            if #items == 0 then
                notify("No calls found.", vim.log.levels.INFO)
                return
            end
            -- Filter bar buttons (labels/keys) come from config.filters.calls.direction; the direction
            -- predicate is attached here (SEMANTICS), and `active` follows the direction opened with.
            local dir_cfg = lsp_state.config.filters.calls.direction
            local dir_buttons = {}
            for _, b in ipairs(dir_cfg.buttons) do
                local btn = vim.tbl_extend("force", {}, b)
                btn.predicate = function(it)
                    return it.direction == b.id
                end
                dir_buttons[#dir_buttons + 1] = btn
            end
            picker.open({
                title = "Call Hierarchy",
                layout = layout,
                list_wrap = ((lsp_state.config.peek or {}).appearance or {}).list_wrap ~= false,
                items = items,
                -- a flat row: `󰊕 name  tail:lnum` (the preview winbar carries the full path)
                format = function(it)
                    local tail = vim.fn.fnamemodify(it.path, ":t")
                    return ("%s %s  %s:%d"):format(it.icon or "", it.text or "", tail, it.lnum)
                end,
                preview_file = true, -- the REAL file buffer in the preview — jump-to on confirm
                subtitle = function(it)
                    return vim.fn.fnamemodify(it.path, ":t")
                end,
                on_confirm = function(it)
                    jump(it, "edit")
                end,
                -- header filter bar: Incoming / Outgoing (predicate toggle, no re-request)
                filters = {
                    { id = dir_cfg.id, active = direction, buttons = dir_buttons },
                },
                keys = {
                    {
                        key = "<C-x>",
                        name = "split",
                        run = function(it, close)
                            close()
                            jump(it, "split")
                        end,
                    },
                    {
                        key = "<C-v>",
                        name = "vsplit",
                        run = function(it, close)
                            close()
                            jump(it, "vsplit")
                        end,
                    },
                },
            })
        end
        -- Route each direction ONLY to the client that produced the item (its `data` is client-private).
        client:request("callHierarchy/incomingCalls", { item = target }, function(_, result)
            collect(result, "incoming")
            done()
        end, bufnr)
        client:request("callHierarchy/outgoingCalls", { item = target }, function(_, result)
            collect(result, "outgoing")
            done()
        end, bufnr)
    end)
end

return M
