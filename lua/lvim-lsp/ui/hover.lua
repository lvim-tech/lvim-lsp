-- lvim-lsp.ui.hover: render LSP hover documentation in a themed lvim-utils info float instead
-- of the built-in popup, so it shares the house chrome (tinted title, palette border) with the
-- rest of lvim-lsp's UI. Pure UI: requests textDocument/hover, converts the contents to markdown
-- lines, and hands them to the shared lvim-utils instance.
--
---@module "lvim-lsp.ui.hover"

local lsp_state = require("lvim-lsp.state")
local lsp_ui = require("lvim-lsp.ui")
local notify = require("lvim-ls.utils.notify")

local M = {}

--- Request hover for the cursor and show it in the themed info float.
function M.open()
    local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/hover" })
    if #clients == 0 then
        notify("No hover provider for this buffer.", vim.log.levels.INFO)
        return
    end
    local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding or "utf-16")
    vim.lsp.buf_request_all(0, "textDocument/hover", params, function(results)
        local lines = {}
        for _, r in pairs(results) do
            local contents = r.result and r.result.contents
            if contents then
                lines = vim.lsp.util.convert_input_to_markdown_lines(contents, lines)
            end
        end
        while lines[1] == "" do
            table.remove(lines, 1)
        end
        while #lines > 0 and lines[#lines] == "" do
            table.remove(lines, #lines)
        end
        if #lines == 0 then
            notify("No hover information.", vim.log.levels.INFO)
            return
        end
        local ui = lsp_ui.get()
        if not ui then
            return
        end
        local cfg = lsp_state.config.hover or {}
        ui.info(lines, {
            title = cfg.title or " Hover",
            wrap = cfg.wrap ~= false,
            markview = cfg.markview == true,
        })
    end)
end

return M
