-- lvim-lsp.ui.hover: render LSP hover documentation with Neovim's NATIVE floating preview, dressed in the
-- house chrome (lvim-lsp.ui.float): palette border + bg, tinted "Hover" title, an air row, and a dynamic
-- `K select` / `q close` footer. The native preview owns rendering/sizing/placement, opens UNFOCUSED (the
-- cursor stays in the code), focuses on a 2nd invocation (to scroll) and auto-closes on cursor move; a
-- markdown renderer (markview) decorates the content (rules, hidden ``` fences, …).
--
---@module "lvim-lsp.ui.hover"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local float = require("lvim-lsp.ui.float")

local M = {}

--- Request hover for the cursor and show it in a themed native floating preview.
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

        local cfg = lsp_state.config.hover or {}
        -- The native preview owns rendering/sizing/placement/focus/auto-close. `focus_id` makes a second
        -- `:LvimLsp hover` enter the existing float (to scroll).
        local ok, bufnr, winid = pcall(vim.lsp.util.open_floating_preview, lines, "markdown", {
            border = float.border,
            max_width = float.dim(cfg.max_width or 80, vim.o.columns),
            max_height = float.dim(cfg.max_height or 0.4, vim.o.lines),
            focusable = true,
            focus = true,
            focus_id = "lvim-lsp-hover",
            wrap = cfg.wrap ~= false,
        })
        if ok then
            float.dress(winid, bufnr, { title = cfg.title or "Hover", conceal = true, air_bottom = true })
        end
    end)
end

return M
