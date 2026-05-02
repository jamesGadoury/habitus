---@type LazySpec
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
    },
  },
  {
    "AstroNvim/astroui",
    ---@type AstroUIOpts
    opts = {
      colorscheme = "catppuccin",
    },
  },
  {
    "brenoprata10/nvim-highlight-colors",
    opts = {
      render = "foreground",
      enable_named_colors = true,
      enable_tailwind = false,
    },
  },
}
