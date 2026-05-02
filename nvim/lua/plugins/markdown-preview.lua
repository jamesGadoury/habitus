---@type LazySpec
return {
  -- Override AstroCommunity's build step for markdown-preview.nvim.
  -- The default uses vim.fn["mkdp#util#install"]() which opens an async
  -- terminal to run install.sh. During Lazy's initial sync on a fresh
  -- machine, that terminal gets killed before the download completes,
  -- so the binary is never installed.
  "iamcco/markdown-preview.nvim",
  build = "cd app && bash install.sh",
}
