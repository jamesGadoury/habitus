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
      -- Highlights the body of ```mermaid fences. Not load-bearing for
      -- rendering -- the preview locates fences by info string (it only needs
      -- `markdown`, and falls back to a regex scan) and mermaid is drawn in
      -- the browser. Kept because the raw fence is what you look at while
      -- writing, now that nothing renders it in the buffer.
      "mermaid",
      -- listed so they install serially; see sync_install above
      "go",
      "gomod",
      "gosum",
      -- add more arguments for adding more treesitter parsers
    },
  },
}
