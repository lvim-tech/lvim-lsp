-- lvim-lsp.ui.calls: present LSP call hierarchy (incoming/outgoing) in the lvim-utils peek.
--
-- prepareCallHierarchy at the cursor, then request BOTH incoming and outgoing calls and tag each
-- result with its direction, so the peek's filter bar can toggle Incoming/Outgoing live (a predicate
-- filter — no re-request). Items are grouped by file with a live preview. Mirrors ui/locations.lua.
--
---@module "lvim-lsp.ui.calls"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local peek = require("lvim-lsp.ui.peek")

local M = {}

--- CallHierarchyItem → a peek item base (1-based loc from its selection range).
---@param item table
---@return table
local function item_to_loc(item)
    local r = item.selectionRange or item.range
    return {
        filename = vim.uri_to_fname(item.uri),
        lnum = (r and r.start.line or 0) + 1,
        col = (r and r.start.character or 0) + 1,
        end_lnum = r and (r["end"].line + 1) or nil,
        end_col = r and (r["end"].character + 1) or nil,
        text = item.name,
        icon = "󰊕",
        icon_hl = "LvimLspOutlineKindFunc",
    }
end

--- Open the call-hierarchy peek focused on `direction` ("incoming"|"outgoing"). `mode` = split|float.
---@param direction string
---@param mode string
function M.open(direction, mode)
    local bufnr = vim.api.nvim_get_current_buf()
    if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/prepareCallHierarchy" }) == 0 then
        notify("No LSP client supporting call hierarchy found.", vim.log.levels.WARN)
        return
    end
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    vim.lsp.buf_request_all(bufnr, "textDocument/prepareCallHierarchy", params, function(prep)
        local target
        for _, r in pairs(prep or {}) do
            if r.result and r.result[1] then
                target = r.result[1]
                break
            end
        end
        if not target then
            notify("No call hierarchy at the cursor.", vim.log.levels.INFO)
            return
        end

        local items, pending = {}, 2
        local function collect(results, kind)
            for _, r in pairs(results or {}) do
                for _, call in ipairs(r.result or {}) do
                    local it = item_to_loc(kind == "incoming" and call.from or call.to)
                    it.direction = kind
                    items[#items + 1] = it
                end
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
            local function dir(id, label, key)
                return {
                    id = id,
                    label = label,
                    key = key,
                    predicate = function(it)
                        return it.direction == id
                    end,
                }
            end
            peek.open({
                title = "Call Hierarchy",
                items = items,
                mode = mode,
                list_match = false, -- rows are symbol names, not source lines
                bar = {
                    groups = {
                        {
                            id = "direction",
                            active = direction,
                            primary = true,
                            buttons = { dir("incoming", "Incoming", "i"), dir("outgoing", "Outgoing", "o") },
                        },
                    },
                },
            }, { peek = (lsp_state.config.peek or {}).appearance })
        end
        vim.lsp.buf_request_all(bufnr, "callHierarchy/incomingCalls", { item = target }, function(res)
            collect(res, "incoming")
            done()
        end)
        vim.lsp.buf_request_all(bufnr, "callHierarchy/outgoingCalls", { item = target }, function(res)
            collect(res, "outgoing")
            done()
        end)
    end)
end

return M
