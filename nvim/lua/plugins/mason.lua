-- Customize Mason

-- The exact version of every Mason package, including the ones AstroCommunity
-- packs add (see community.lua). mason-tool-installer reinstalls any package
-- whose installed version differs, and `shell/install.d/40-nvim.sh` runs it
-- with MasonToolsClean, so every machine ends up with exactly this set.
--
-- To update: `:Mason` shows newer versions; change the string here, commit,
-- and rerun install.sh on each machine. The string is the version Mason
-- records for the package, which keeps upstream's `v` prefix where it has one.
local versions = {
  -- language servers
  ["basedpyright"] = "1.39.3",
  ["biome"] = "2.5.4",
  ["clangd"] = "22.1.0",
  ["deno"] = "v2.9.3",
  ["gopls"] = "v0.21.1",
  ["json-lsp"] = "4.10.0",
  ["lua-language-server"] = "3.18.2",
  ["neocmakelsp"] = "v0.10.2",
  ["ruff"] = "0.15.12",
  ["taplo"] = "0.10.0",
  ["vtsls"] = "0.3.0",
  -- formatters
  ["clang-format"] = "22.1.4",
  ["stylua"] = "v2.4.1",
  -- debuggers
  ["codelldb"] = "v1.12.2",
  ["debugpy"] = "1.8.20",
  ["js-debug-adapter"] = "v1.117.0",
  -- other
  ["tree-sitter-cli"] = "v0.26.8",
}

local function ensure_installed()
  local tools = {
    "lua-language-server",
    "basedpyright",
    "ruff",
    "clangd",
    "biome",
    "stylua",
    "clang-format",
    "debugpy",
    "codelldb",
    "tree-sitter-cli",
  }

  -- Mason builds gopls via `go install`; only request it when Go is on PATH,
  -- otherwise the install retries and fails on every startup.
  if vim.fn.executable "go" == 1 then table.insert(tools, "gopls") end

  return tools
end

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- A function, not a table, so it sees the packs' entries too and can pin
    -- them: they arrive as bare names, which would install whatever is latest.
    opts = function(_, opts)
      local seen, pinned, unpinned = {}, {}, {}
      for _, tool in ipairs(vim.list_extend(opts.ensure_installed or {}, ensure_installed())) do
        local name = type(tool) == "table" and tool[1] or tool
        if not seen[name] then
          seen[name] = true
          if versions[name] then
            table.insert(pinned, { name, version = versions[name] })
          else
            table.insert(pinned, name)
            table.insert(unpinned, name)
          end
        end
      end
      if #unpinned > 0 then
        vim.schedule(
          function()
            vim.notify(
              "Mason packages without a pinned version in plugins/mason.lua: " .. table.concat(unpinned, ", "),
              vim.log.levels.WARN
            )
          end
        )
      end
      opts.ensure_installed = pinned
    end,
  },
}
