-- Customize Mason

local function ensure_installed()
  local tools = {
    -- install language servers
    "lua-language-server",
    "basedpyright",
    "ruff",
    "clangd",
    "biome",

    -- install formatters
    "stylua",
    "clang-format",

    -- install debuggers
    "debugpy",
    "codelldb",

    -- install any other package
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
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = {
      -- Make sure to use the names found in `:Mason`
      ensure_installed = ensure_installed(),
    },
  },
}
