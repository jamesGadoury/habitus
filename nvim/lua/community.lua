-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.completion.blink-cmp-emoji" },
  { import = "astrocommunity.search.grug-far-nvim" },
  { import = "astrocommunity.markdown-and-latex.markdown-preview-nvim" },
  { import = "astrocommunity.pack.cpp" },
  { import = "astrocommunity.pack.cmake" },
  { import = "astrocommunity.pack.typescript-all-in-one" },
  -- rustaceanvim + crates.nvim + the toml pack (taplo). Deliberately does NOT
  -- install rust-analyzer via Mason — rustup owns it (see plugins/rust.lua).
  { import = "astrocommunity.pack.rust" },
}
