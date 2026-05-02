-- Disable undo on grug-far buffers to prevent E439 (undo list corrupt)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "grug-far",
  callback = function()
    vim.bo.undolevels = -1
  end,
})

-- Custom keybinding for grug-far search/replace in current file
---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    mappings = {
      n = {
        ["<Leader>sr"] = {
          function()
            require("grug-far").open({ prefills = { paths = vim.fn.expand("%") } })
          end,
          desc = "Search/Replace in current file",
        },
        ["<Leader>fd"] = {
          function()
            require("snacks").picker.grep({ cwd = vim.fn.expand("%:p:h") })
          end,
          desc = "Find words in directory",
        },
        ["<Leader>sd"] = {
          function()
            require("grug-far").open({ prefills = { paths = vim.fn.expand("%:p:h") } })
          end,
          desc = "Search/Replace in directory",
        },
      },
    },
  },
}
