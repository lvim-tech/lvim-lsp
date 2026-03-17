# lvim-lsp

LSP manager за Neovim. Управлява жизнения цикъл на LSP сървъри, EFM инструменти, DAP адаптери и Mason инсталации без конфигурационни файлове от трети страни.

Изисква [`lvim-utils`](https://github.com/lvim-tech/lvim-utils) за UI компонентите.

---

## Инсталация

```lua
-- lazy.nvim
{
    "lvim-tech/lvim-lsp",
    dependencies = { "lvim-tech/lvim-utils", "williamboman/mason.nvim" },
    config = function()
        require("lvim-lsp").setup({ ... })
    end,
}
```

---

## Бърз старт

```lua
require("lvim-lsp").setup({
    file_types = {
        lua_ls    = { "lua" },
        tsserver  = { "typescript", "javascript", "typescriptreact" },
        rust_analyzer = { "rust" },
    },
    server_config_dirs = { "my_config.lsp.servers" },
})
```

---

## Конфигурация

Всички стойности са незадължителни освен `file_types` и `server_config_dirs`.

```lua
require("lvim-lsp").setup({

    -- ЗАДЪЛЖИТЕЛНИ -----------------------------------------------------------

    --映射: server_key → filetypes[]
    -- Определя кои сървъри се стартират за кои файлови типове.
    file_types = {
        lua_ls   = { "lua" },
        tsserver = { "typescript", "javascript" },
    },

    -- Lua require префикси, в които се търсят конфиг модули за сървъри.
    -- Търси се в реда на списъка — използва се първото съвпадение.
    server_config_dirs = { "my_config.lsp.servers" },

    -- CALLBACKS --------------------------------------------------------------

    -- Викa се за всеки LSP клиент след attach.
    on_attach = function(client, bufnr) end,

    -- Вика се след DirChanged (след спиране на сървъри от стария проект).
    -- Подходящо за fidget.nvim clear или подобни.
    on_dir_change = function() end,

    -- TIMING -----------------------------------------------------------------

    -- Забавяне (ms) преди autocommands да се регистрират при старт.
    startup_delay_ms = 100,

    -- Забавяне (ms) след DirChanged преди сървърите от стария проект да спрат.
    dir_change_delay_ms = 5000,

    -- EFM --------------------------------------------------------------------

    efm = {
        -- Filetypes, за които EFM да се стартира дори без регистриран tool config.
        filetypes = {},
        -- Изпълнимо за PATH проверка.
        executable = "efm-langserver",
    },

    -- FEATURES ---------------------------------------------------------------

    features = {
        -- Автоматично highlight на символа под курсора при CursorHold.
        document_highlight = false,

        -- Автоматично форматиране при запис (BufWritePre).
        -- Може да е true/false или function()->boolean.
        -- Може да се override-не per-проект чрез .lvim-lsp.lua.
        auto_format = false,

        -- Inlay hints (Neovim 0.10+).
        -- Може да е true/false или function()->boolean.
        -- Може да се override-не per-проект чрез .lvim-lsp.lua.
        inlay_hints = false,
    },

    -- CODE LENS --------------------------------------------------------------

    code_lens = {
        -- Refresh при LspAttach / TextChanged.
        -- Double-click върху lens → изпълнява го.
        -- Когато е false — codelens функциите се заглушават напълно.
        enabled = false,
    },

    -- DIAGNOSTICS ------------------------------------------------------------

    diagnostics = {
        -- Заглавие на диагностичния popup.
        popup_title = " Diagnostics",

        -- Overrides за командите за диагностика (nil = default поведение).
        show_line = nil,   -- override за :LvimLsp diagnostic_current
        goto_next = nil,   -- override за :LvimLsp diagnostic_next
        goto_prev = nil,   -- override за :LvimLsp diagnostic_prev

        -- vim.diagnostic.config() опции (nil = не се прилага).
        virtual_text     = nil,
        virtual_lines    = nil,
        underline        = nil,
        severity_sort    = nil,
        update_in_insert = nil,

        -- Sign символи по severity.
        signs = nil,
        -- Пример:
        -- signs = { error = "", warn = "", hint = "󰌶", info = "" },
    },

    -- INFO POPUP -------------------------------------------------------------

    info = {
        -- Заглавие на LSP info прозореца.
        popup_title = "LSP SERVERS INFORMATION",
    },

    -- INSTALLER POPUP --------------------------------------------------------

    installer = {
        -- Ширина на installer popup-а.
        -- Fraction 0.1–1.0 (спрямо ширината на редактора) или абсолютен integer.
        popup_width = 0.3,

        -- Секунди, в които инсталиран инструмент остава видим преди да изчезне.
        hide_installed_delay = 5,

        -- Заглавие на installer popup-а.
        popup_title = "LSP INSTALLER",
    },

    -- POPUP GLOBAL -----------------------------------------------------------

    -- Конфигурация, предавана директно на lvim-utils UI инстанцията.
    -- Контролира border, размери, клавиши, икони и labels за всички popups.
    popup_global = {
        border    = { "", "", "", " ", " ", " ", " ", " " },
        width     = 0.8,
        height    = 0.8,
        max_width = 0.8,
        max_height = 0.8,
        close_keys = { "q", "<Esc>" },
        markview  = false,
        -- ... (пълна lvim-utils UI конфигурация)
    },

    -- HIGHLIGHTS -------------------------------------------------------------

    -- Директни nvim_set_hl дефиниции, регистрирани чрез lvim-utils.highlight.
    -- Оцеляват автоматично при colorscheme промяна.
    -- Дефолтите ползват link към стандартни Neovim групи.
    highlights = {
        MasonTitle        = { fg = "#f38ba8", bold = true },
        LvimLspInfoServerName = { fg = "#fab387", bold = true },
        -- ... вижте пълния списък в секция Highlight групи
    },

    -- DAP --------------------------------------------------------------------

    -- Когато е зададено, добавя :LvimLsp dap subcommand.
    dap_local_fn = nil,

})
```

---

## Конфиг модул за сървър

Всеки сървър се описва с Lua модул, намиращ се в `server_config_dirs`.

```
my_config/lsp/servers/lua_ls.lua
my_config/lsp/servers/tsserver.lua
```

Структура на модула:

```lua
-- my_config/lsp/servers/lua_ls.lua
return {

    -- LSP конфигурация (задължително)
    lsp = {
        -- Mason пакети, необходими за сървъра.
        -- Ако липсва някой → потребителят се пита дали да се инсталира.
        dependencies = { "lua-language-server" },

        -- Root markers — директориите, по които се определя root_dir на проекта.
        root_patterns = { ".git", ".luarc.json", ".luarc.jsonc" },

        -- Стандартна vim.lsp.start конфигурация.
        config = {
            name = "lua_ls",
            cmd  = { "lua-language-server" },
            settings = {
                Lua = { diagnostics = { globals = { "vim" } } },
            },
            on_attach = function(client, bufnr) end,
        },
    },

    -- EFM инструменти (незадължително)
    -- Регистрира linter/formatter конфиги за EFM langserver.
    efm = {
        -- Mason пакети за EFM инструментите.
        dependencies = { "stylua" },

        -- Filetypes, за които важат тези инструменти.
        filetypes = { "lua" },

        -- tool конфиги в EFM формат (вижте efm-langserver документацията).
        tools = {
            {
                server_name   = "stylua",
                formatCommand = "stylua --color Never -",
                formatStdin   = true,
            },
        },
    },

    -- DAP конфигурация (незадължително)
    -- Автоматично се регистрира в nvim-dap при инсталация.
    dap = {
        dependencies = { "local-lua-debugger-vscode" },
        adapters = {
            nlua = function(cb, config)
                cb({ type = "server", host = config.host, port = config.port })
            end,
        },
        configurations = {
            lua = {
                {
                    name    = "Attach to running Neovim instance",
                    type    = "nlua",
                    request = "attach",
                    host    = "127.0.0.1",
                    port    = 8086,
                },
            },
        },
    },
}
```

---

## Команди

Всички команди минават през единна точка: `:LvimLsp <subcommand>`.

### LSP операции

| Subcommand | Описание |
|---|---|
| `hover` | Hover информация за символа под курсора |
| `rename` | Преименуване на символ |
| `format` | Форматиране на файла |
| `range_format` | Форматиране на селектиран range (Visual mode) |
| `code_action` | Code actions |
| `definition` | Отиди на дефиниция |
| `type_definition` | Отиди на type дефиниция |
| `declaration` | Отиди на декларация |
| `references` | Покажи всички референции |
| `implementation` | Отиди на имплементация |
| `signature_help` | Signature help |
| `document_symbol` | Символи в текущия файл |
| `workspace_symbol` | Символи в workspace-а |
| `document_highlight` | Highlight на всички срещания |
| `clear_references` | Изчисти highlights |
| `incoming_calls` | Incoming call hierarchy |
| `outgoing_calls` | Outgoing call hierarchy |
| `add_workspace_folder` | Добави workspace folder |
| `remove_workspace_folder` | Премахни workspace folder |
| `list_workspace_folders` | Покажи workspace folders |

### Диагностика

| Subcommand | Описание |
|---|---|
| `diagnostic_current` | Покажи диагностиката на текущия ред |
| `diagnostic_next` | Отиди на следващата диагностика |
| `diagnostic_prev` | Отиди на предишната диагностика |

### Управление на сървъри

| Subcommand | Описание |
|---|---|
| `toggle_servers` | Интерактивно меню — enable/disable сървъри глобално |
| `toggle_servers_buffer` | Интерактивно меню — attach/detach сървъри за текущия буфер |
| `restart` | Интерактивно меню — рестартирай сървър |
| `reattach` | Реattach на сървърите към текущия буфер |
| `info` | Отвори LSP info прозорец |

### Проект и инсталации

| Subcommand | Описание |
|---|---|
| `project` | Отвори `.lvim-lsp.lua` за текущия проект (създава ако липсва) |
| `declined` | Меню за повторно активиране на отказани инсталации |
| `dap` | DAP команда (налична само когато `dap_local_fn` е зададен) |

---

## Per-проект конфигурация

`:LvimLsp project` създава `.lvim-lsp.lua` в root директорията на проекта:

```lua
-- .lvim-lsp.lua
return {
    -- Деактивирай конкретни сървъри само за този проект.
    disable = { "eslint" },

    -- Override на глобалните feature флагове.
    auto_format = false,
    inlay_hints = true,
    code_lens   = { enabled = true },
}
```

Файлът се засича автоматично при attach. След редакция — `:LvimLsp reattach` за да влезе в сила.

---

## Installer

При отваряне на файл, ако зависимостите на съответния сървър липсват, автоматично се появява popup с въпрос дали да се инсталират чрез Mason.

- **Space** — toggle на инструмент
- **Enter** — инсталирай маркираните
- **q / Esc** — пропусни (сървърът влиза в 5-минутен cooldown)

Инсталираните инструменти остават видими `hide_installed_delay` секунди след завършване.

Отказаните сървъри се съхраняват в `stdpath("data")/lvim-lsp-declined.json` и могат да се управляват чрез `:LvimLsp declined`.

---

## LSP Info прозорец

`:LvimLsp info` отваря floating window с подробна информация за активните клиенти:

- Encoding, PID, команда, root directory
- Workspace folders
- Trigger characters (completion, signature)
- Capabilities tick-list
- Диагностика (по клиент и по буфер)
- Прикачени буфери
- Mason пакет версии
- EFM: linters и formatters по filetype с диагностика

---

## CodeLens

При `code_lens.enabled = true`:

- Автоматично refresh при `LspAttach`, `TextChanged`, `TextChangedI`
- `:LspCodeLensRun` — изпълни lens на или до курсора
- `<2-LeftMouse>` (double-click) — изпълни lens на реда

---

## Lua API

```lua
local lsp = require("lvim-lsp")

-- Инсталирай Mason инструменти и извикай cb след завършване.
lsp.ensure_mason_tools({ "lua-language-server", "stylua" }, function() end)

-- Attach/стартирай сървър за буфер.
lsp.ensure_lsp_for_buffer("lua_ls", bufnr)

-- Стартирай сървър (force=true → attach към всички съвместими буфери).
lsp.start_language_server("lua_ls", true)

-- Регистрирай EFM tool конфиги и рестартирай EFM.
lsp.setup_efm({ "lua" }, { { formatCommand = "stylua -", formatStdin = true } })

-- Глобален disable/enable.
lsp.disable_lsp_server_globally("tsserver")
lsp.enable_lsp_server_globally("tsserver")

-- Per-буфер disable/enable.
lsp.disable_lsp_server_for_buffer("tsserver", bufnr)
lsp.enable_lsp_server_for_buffer("tsserver", bufnr)

-- Съвместими сървъри за filetype.
lsp.get_compatible_lsp_for_ft("typescript")  -- → { "tsserver", "efm" }

-- Отвори LSP info прозорец.
lsp.show_info()

-- Debug snapshot на вътрешното state.
lsp.get_state()

-- Debug summary на installer state.
lsp.installer_status()

-- Highlights се управляват от lvim-utils.highlight автоматично.
```

---

## Highlight групи

### Installer popup
| Група | Описание |
|---|---|
| `MasonPopupBG` | Фон на прозореца |
| `MasonTitle` | Заглавие |
| `MasonPkgName` | Име на пакет |
| `MasonIconProgress` | Spinner икона |
| `MasonIconOk` | Успешна инсталация икона |
| `MasonIconError` | Грешна инсталация икона |
| `MasonCurrentAction` | Текущо действие (stdout/stderr ред) |

### LSP info popup
| Група | Описание |
|---|---|
| `LvimLspInfoServerName` | Имена на сървъри |
| `LvimLspInfoSection` | Секционни заглавия |
| `LvimLspInfoKey` | Ключове (Encoding:, PID: ...) |
| `LvimLspInfoSeparator` | Разделителни линии |
| `LvimLspInfoLinter` | Секция Linters |
| `LvimLspInfoFormatter` | Секция Formatters |
| `LvimLspInfoToolName` | Имена на EFM инструменти |
| `LvimLspInfoBuffer` | Имена на буфери |
| `LvimLspIcon` | Икони (■ ◆ ● ✓ ✗) |
