-- Rust: tweaks layered on top of `astrocommunity.pack.rust` (see community.lua).
--
-- The pack supplies rustaceanvim (which owns the rust-analyzer client — the
-- `rust_analyzer` lspconfig handler is disabled), crates.nvim for Cargo.toml,
-- the toml pack (taplo), and codelldb for DAP. Everything here is the part the
-- pack deliberately leaves to the user: rust-analyzer settings and mappings.
--
-- rust-analyzer itself is NOT a Mason package here — it ships with the
-- toolchain, so version skew with rustc is a real source of bogus diagnostics:
--   rustup component add rust-analyzer
-- That installs it into the *default* toolchain only. `rust-analyzer` on PATH is
-- a rustup proxy, so in a project pinned by `rust-toolchain.toml` it resolves to
-- the pinned toolchain instead and the server dies at startup with
--   error: Unknown binary 'rust-analyzer' in official toolchain '<version>'
-- Note rustup treats `stable` and the same version pinned as `1.97.1` as two
-- separate installs, so this bites even when the versions match. Fix it in the
-- project (reproducible for every clone) by listing the component:
--   [toolchain]
--   components = ["rustfmt", "clippy", "rust-analyzer"]
-- or on this machine only: rustup component add rust-analyzer --toolchain <ver>
-- Formatting on save is already global (see astrolsp.lua) and rust-analyzer
-- proxies it to the toolchain's rustfmt, so `rustfmt.toml` is honoured as-is.

--- rustaceanvim registers the client under the hyphenated rust-analyzer name
--- rather than the lspconfig `rust_analyzer` key; accept either.
---@param client vim.lsp.Client
local function is_rust_analyzer(client) return (client.name:gsub("_", "-")) == "rust-analyzer" end

---@type LazySpec
return {
  {
    "AstroNvim/astrolsp",
    ---@type AstroLSPOpts
    opts = {
      ---@diagnostic disable: missing-fields
      config = {
        -- Declared here (the idiomatic AstroLSP location) but actually handed
        -- to the server by the rustaceanvim spec below — see the note there.
        rust_analyzer = {
          settings = {
            ["rust-analyzer"] = {
              cargo = {
                -- rust-analyzer runs `cargo clippy` on save (set by the pack).
                -- Without a dedicated profile it shares ./target with your own
                -- cargo commands, so a save blocks `cargo build` on the target
                -- lock (and vice versa). A separate profile costs disk, not time.
                extraEnv = { CARGO_PROFILE_RUST_ANALYZER_INHERITS = "dev" },
                extraArgs = { "--profile", "rust-analyzer" },
                -- NOTE: `features = "all"` surfaces code behind feature gates,
                -- but hard-fails on crates with mutually exclusive features, so
                -- it stays off globally. rustaceanvim v6 dropped per-project
                -- `rust-analyzer.json`; override per project in
                -- `.vscode/settings.json` (`load_vscode_settings` is on).
              },
              -- Match what `cargo fmt` + rustfmt's own grouping produce, so
              -- LSP auto-imports don't fight the formatter.
              imports = {
                granularity = { group = "module" },
                prefix = "self",
              },
              inlayHints = {
                closureReturnTypeHints = { enable = "with_block" },
                lifetimeElisionHints = { enable = "skip_trivial", useParameterNames = true },
                -- Redundant next to the type hint on the same line.
                reborrowHints = { enable = "never" },
              },
            },
          },
        },
      },
      mappings = {
        n = {
          -- rustaceanvim's hover is the plain LSP hover plus actionable entries
          -- (go to impl//debug); pressing K again focuses the float.
          K = {
            function() vim.cmd.RustLsp { "hover", "actions" } end,
            desc = "Hover symbol (with actions)",
            cond = is_rust_analyzer,
          },
          -- rust-analyzer groups its code actions; the stock LSP picker
          -- flattens them and drops the nested ones.
          ["<Leader>la"] = {
            function() vim.cmd.RustLsp "codeAction" end,
            desc = "LSP code action (grouped)",
            cond = is_rust_analyzer,
          },
          ["<Leader>lx"] = {
            function() vim.cmd.RustLsp "runnables" end,
            desc = "Cargo runnables",
            cond = is_rust_analyzer,
          },
          ["<Leader>lt"] = {
            function() vim.cmd.RustLsp "testables" end,
            desc = "Cargo testables",
            cond = is_rust_analyzer,
          },
          ["<Leader>lb"] = {
            function() vim.cmd.RustLsp "debuggables" end,
            desc = "Cargo debuggables (codelldb)",
            cond = is_rust_analyzer,
          },
          -- The full rustc/clippy rendering, including the ASCII spans and
          -- sub-notes that get truncated in the virtual text.
          ["<Leader>lg"] = {
            function() vim.cmd.RustLsp { "renderDiagnostic", "current" } end,
            desc = "Render diagnostic (rustc output)",
            cond = is_rust_analyzer,
          },
          ["<Leader>le"] = {
            function() vim.cmd.RustLsp "explainError" end,
            desc = "Explain error (rustc --explain)",
            cond = is_rust_analyzer,
          },
          ["<Leader>lm"] = {
            function() vim.cmd.RustLsp "expandMacro" end,
            desc = "Expand macro recursively",
            cond = is_rust_analyzer,
          },
          ["<Leader>lp"] = {
            function() vim.cmd.RustLsp "parentModule" end,
            desc = "Go to parent module",
            cond = is_rust_analyzer,
          },
          ["<Leader>lo"] = {
            function() vim.cmd.RustLsp "openDocs" end,
            desc = "Open docs.rs for symbol",
            cond = is_rust_analyzer,
          },
          ["<Leader>lc"] = {
            function() vim.cmd.RustLsp "openCargo" end,
            desc = "Open Cargo.toml",
            cond = is_rust_analyzer,
          },
        },
      },
    },
  },

  -- Two repairs to the pack's rustaceanvim wiring. Both have the same cause:
  -- the pack builds its server config from `astrolsp.lsp_opts "rust_analyzer"`,
  -- which under native LSP config is the live `vim.lsp.config.rust_analyzer`
  -- table. rustaceanvim normalizes that table in place (it comes back carrying
  -- rustaceanvim's own `cmd`/`filetypes`/`name`) and `settings` and the
  -- `on_attach` chain don't survive the trip.
  --
  -- 1. settings — the server otherwise comes up with `{"rust-analyzer": {}}`,
  --    dropping everything configured above *and* the pack's own clippy-on-save.
  --    `server.settings` also accepts a plain table, which nothing can strip.
  -- 2. on_attach — AstroLSP's `on_attach` never runs for this client, so rust
  --    buffers get none of AstroNvim's LSP mappings (`<Leader>lr` rename,
  --    `<Leader>lf` format, the `<Leader>l` menu at all) or its LSP autocmds.
  --    Calling it directly is the same idiom the pack uses for crates.nvim.
  --
  -- Recheck on rustaceanvim/astrocommunity bumps — with this block removed,
  -- open a Rust file and confirm both are already true:
  --   :lua =vim.lsp.get_clients({ name = "rust-analyzer" })[1].config.settings
  --   :lua =vim.tbl_count(require("astrolsp").attached_clients) > 0
  {
    "mrcjkb/rustaceanvim",
    optional = true,
    opts = function(_, opts)
      opts.server = opts.server or {}
      local settings = require("astrolsp").lsp_opts("rust_analyzer").settings
      if settings then opts.server.settings = vim.deepcopy(settings) end
      -- Deliberately replaces rather than chains: the value it overwrites is
      -- the AstroLSP chain that isn't reaching us, so chaining would risk
      -- applying the same buffer-local mappings twice once upstream is fixed.
      opts.server.on_attach = function(...) require("astrolsp").on_attach(...) end
    end,
  },

  -- crates.nvim: the pack turns on its LSP integration (hover, completion and
  -- code actions on Cargo.toml). These are the commands that have no LSP
  -- equivalent, so they need real mappings — buffer-local to Cargo.toml.
  {
    "Saecki/crates.nvim",
    optional = true,
    specs = {
      {
        "AstroNvim/astrocore",
        ---@type AstroCoreOpts
        opts = {
          autocmds = {
            crates_mappings = {
              {
                event = "BufRead",
                pattern = "Cargo.toml",
                desc = "Set up crates.nvim mappings",
                callback = function(args)
                  local crates = require "crates"
                  require("astrocore").set_mappings({
                    n = {
                      ["<Leader>lv"] = { crates.show_versions_popup, desc = "Show crate versions" },
                      ["<Leader>lF"] = { crates.show_features_popup, desc = "Show crate features" },
                      ["<Leader>lu"] = { crates.update_crate, desc = "Update crate" },
                      ["<Leader>lU"] = { crates.upgrade_crate, desc = "Upgrade crate (allow major)" },
                      ["<Leader>lo"] = { crates.open_documentation, desc = "Open docs.rs for crate" },
                      ["<Leader>lc"] = { crates.open_repository, desc = "Open crate repository" },
                    },
                  }, { buffer = args.buf })
                end,
              },
            },
          },
        },
      },
    },
  },
}
