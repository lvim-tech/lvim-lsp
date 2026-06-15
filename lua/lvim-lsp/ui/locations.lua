-- lvim-lsp.ui.locations: present LSP "go to / list locations" results in the lvim-utils peek.
--
-- The built-in handlers are reused via their `on_list` callback (so multi-client results are
-- already aggregated into quickfix-shaped items); we normalize those into peek items and open
-- the two-pane navigator. A single result jumps directly, matching the native feel. Pure UI —
-- the engine is untouched; which commands route here is decided by `config.peek` in commands.lua.
--
---@module "lvim-lsp.ui.locations"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local peek = require("lvim-utils.ui.peek")

local M = {}

-- method key → the built-in request, invoked with our `on_list` handler.
local REQUESTS = {
    references = function(on_list)
        vim.lsp.buf.references({ includeDeclaration = true }, { on_list = on_list })
    end,
    definition = function(on_list)
        vim.lsp.buf.definition({ on_list = on_list })
    end,
    type_definition = function(on_list)
        vim.lsp.buf.type_definition({ on_list = on_list })
    end,
    implementation = function(on_list)
        vim.lsp.buf.implementation({ on_list = on_list })
    end,
    declaration = function(on_list)
        vim.lsp.buf.declaration({ on_list = on_list })
    end,
}

local TITLES = {
    references = "References",
    definition = "Definitions",
    type_definition = "Type Definitions",
    implementation = "Implementations",
    declaration = "Declarations",
}

--- Jump to a single location in the current window.
---@param it table
local function jump(it)
    vim.cmd("edit " .. vim.fn.fnameescape(it.filename))
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- Open `method`'s locations in the peek (`mode` = "split" | "float").
---@param method string
---@param mode string
function M.open(method, mode)
    local request = REQUESTS[method]
    if not request then
        return
    end
    request(function(res)
        local qf = (res and res.items) or {}
        if #qf == 0 then
            notify("No " .. (TITLES[method] or method):lower() .. " found.", vim.log.levels.INFO)
            return
        end
        local items = {}
        for _, e in ipairs(qf) do
            items[#items + 1] = {
                filename = e.filename or (e.bufnr and vim.api.nvim_buf_get_name(e.bufnr)) or "",
                lnum = e.lnum or 1,
                col = e.col or 1,
                end_lnum = e.end_lnum,
                end_col = e.end_col,
                text = e.text,
            }
        end
        if #items == 1 then
            jump(items[1])
            return
        end
        peek.open({
            title = res.title or TITLES[method] or method, -- the KIND, shown in the list winbar
            items = items,
            mode = mode,
        }, { peek = (lsp_state.config.peek or {}).appearance })
    end)
end

return M
