---@type LazySpec
return {
  "f-person/git-blame.nvim",
  event = "BufRead",
  opts = {
    enabled = true,
    date_format = "%Y-%m-%d",
    message_when_not_committed = "Not yet committed",
    virtual_text_column = nil,
  },
}
