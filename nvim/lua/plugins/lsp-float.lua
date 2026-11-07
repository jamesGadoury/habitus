-- Popup styling outside `vim.lsp.util.open_floating_preview`, to match the LSP
-- popups that lua/lsp_float.lua pads and outlines (set up from polish.lua).
--
-- blink.cmp draws the completion docs window itself, so it gets the same
-- colours (editor background, outline in the `FloatBorder` colour) but not
-- the padding. Its border is already rounded (AstroNvim's default).
---@type LazySpec
return {
  {
    "Saghen/blink.cmp",
    opts = {
      completion = {
        documentation = {
          window = {
            winhighlight = "Normal:Normal,FloatBorder:LspFloatFrame,CursorLine:PmenuSel,Search:None",
          },
        },
      },
    },
  },
}
