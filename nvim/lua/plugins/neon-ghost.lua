---@type LazySpec
return {
  "jamesGadoury/neon-ghost-theme",
  name = "neon-ghost",
  event = "VeryLazy",
  config = function()
    require("neon-ghost").setup {
      style = "default", -- "default" | "flashy"
    }
  end,
}
