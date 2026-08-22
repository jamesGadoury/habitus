-- Customize Treesitter

---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    -- Install serially. `auto_install` (on, because the tree-sitter CLI is on
    -- PATH) fires once directly and again from a FileType autocmd, and its
    -- `is_installed` guard only checks for the .so on disk -- so with async
    -- installs a second job starts mid-download and both collide on the shared
    -- <repo>-tmp dir ("mkdir: File exists"). Serial installs of anything listed
    -- below land before that can happen. Costs ~2s once per parser, then never.
    sync_install = true,
    ensure_installed = {
      "lua",
      "vim",
      -- highlights ```mermaid fences; markdown-preview.nvim renders them
      "mermaid",
      -- listed so they install serially; see sync_install above
      "go",
      "gomod",
      "gosum",
      -- add more arguments for adding more treesitter parsers
    },
  },
}
