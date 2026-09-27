-- Customize None-ls sources

---@type LazySpec
return {
  "jay-babu/mason-null-ls.nvim",
  opts = function(_, opts)
    opts.handlers = opts.handlers or {}
    -- mason-null-ls registers every installed Mason tool as a none-ls source,
    -- so biome (installed for its language server) also formats on save in
    -- every repo. With no biome.json it falls back to its own defaults, which
    -- indent with tabs, so saving any JSON/TS file rewrites all of it. Only let
    -- it format where the project has opted in -- the same gate the biome
    -- language server gets in astrolsp.lua. Elsewhere jsonls formats JSON with
    -- the buffer's own indent options.
    opts.handlers.biome = function()
      local null_ls = require "null-ls"
      local root_pattern = require("null-ls.utils").root_pattern("biome.json", "biome.jsonc")
      null_ls.register(null_ls.builtins.formatting.biome.with {
        runtime_condition = function(params) return root_pattern(params.bufname) ~= nil end,
      })
    end
  end,
}
