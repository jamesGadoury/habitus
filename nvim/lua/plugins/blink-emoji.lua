-- Emoji completion (via the astrocommunity blink-cmp-emoji pack) plus a fuzzy
-- emoji picker. The community pack enables the source globally; restrict it to
-- prose filetypes so a bare `:` doesn't pull emoji into type annotations,
-- ternaries, and table keys while writing code.
---@type LazySpec
return {
  {
    "Saghen/blink.cmp",
    opts = {
      sources = {
        providers = {
          emoji = {
            enabled = function() return vim.tbl_contains({ "gitcommit", "markdown", "text" }, vim.bo.filetype) end,
            score_offset = 15,
          },
        },
      },
    },
  },
  {
    "AstroNvim/astrocore",
    ---@type AstroCoreOpts
    opts = {
      mappings = {
        n = {
          ["<Leader>fe"] = {
            function() require("snacks").picker.icons { icon_sources = { "emoji" } } end,
            desc = "Find emoji",
          },
        },
      },
    },
  },
}
