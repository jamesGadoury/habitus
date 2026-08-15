-- Customize Treesitter

---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      -- highlights ```mermaid fences; markdown-preview.nvim renders them
      "mermaid",
      -- add more arguments for adding more treesitter parsers
    },
  },
}
