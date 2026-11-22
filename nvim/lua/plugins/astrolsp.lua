---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = {
    -- Configuration table of features provided by AstroLSP
    features = {
      codelens = true, -- enable/disable codelens refresh on start
      inlay_hints = false, -- off on start: <Leader>uh/uH toggle them, <Leader>uI shows one line
      semantic_tokens = true, -- enable/disable semantic token highlighting
    },
    -- customize lsp formatting options
    formatting = {
      -- control auto formatting on save
      format_on_save = {
        enabled = true, -- enable or disable format on save globally
      },
      disabled = { -- disable formatting capabilities for the listed language servers
        "basedpyright", -- let ruff handle Python formatting
        "vtsls", -- let biome handle TS/JS formatting
        "ts_ls", -- covers repos where the base pack falls back to ts_ls
      },
      timeout_ms = 1000, -- default format timeout
    },
    -- customize language server configuration options passed to `lspconfig`
    ---@diagnostic disable: missing-fields
    config = {
      clangd = {
        cmd = {
          "clangd",
          "--background-index",
          "--clang-tidy",
          "--header-insertion=iwyu",
          "--completion-style=detailed",
          "--function-arg-placeholders",
          "--fallback-style=llvm",
        },
        capabilities = { offsetEncoding = { "utf-16" } },
      },
      gopls = {
        settings = {
          gopls = {
            gofumpt = true,
            staticcheck = true,
          },
        },
      },
      -- Python: basedpyright handles type checking, completion, and hover.
      -- ruff handles linting, formatting, and import organization.
      basedpyright = {
        settings = {
          basedpyright = {
            -- Defer import organization to ruff
            disableOrganizeImports = true,
            analysis = {
              -- basedpyright defaults to "recommended"; pin it explicitly
              typeCheckingMode = "recommended",
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "openFilesOnly",
            },
          },
        },
      },
      ruff = {
        on_attach = function(client, _)
          -- Defer hover to basedpyright (richer type info)
          client.server_capabilities.hoverProvider = false
        end,
      },
      biome = {
        root_dir = require("lspconfig.util").root_pattern("biome.json", "biome.jsonc"),
      },
    },
    -- Configure buffer local auto commands to add when attaching a language server
    autocmds = {
      lsp_codelens_refresh = {
        cond = "textDocument/codeLens",
        {
          event = { "InsertLeave", "BufEnter" },
          desc = "Refresh codelens (buffer)",
          callback = function(args)
            if require("astrolsp").config.features.codelens then vim.lsp.codelens.refresh { bufnr = args.buf } end
          end,
        },
      },
    },
    -- mappings to be set up on attaching of a language server
    mappings = {
      n = {
        gD = {
          function() vim.lsp.buf.declaration() end,
          desc = "Declaration of current symbol",
          cond = "textDocument/declaration",
        },
        ["<Leader>lh"] = {
          "<cmd>ClangdSwitchSourceHeader<cr>",
          desc = "Switch header/source",
          cond = function(client) return client.name == "clangd" end,
        },
        ["<Leader>uI"] = {
          function() require("inlay_line").toggle() end,
          desc = "Toggle inlay hints (line)",
          cond = "textDocument/inlayHint",
        },
        ["<Leader>uY"] = {
          function() require("astrolsp.toggles").buffer_semantic_tokens() end,
          desc = "Toggle LSP semantic highlight (buffer)",
          cond = function(client)
            return client.supports_method "textDocument/semanticTokens/full" and vim.lsp.semantic_tokens ~= nil
          end,
        },
      },
    },
  },
}
