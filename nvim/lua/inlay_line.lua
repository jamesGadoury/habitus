-- Show LSP inlay hints for the cursor line only.
--
-- Inlay hints are off by default (astrolsp `features.inlay_hints`), and
-- `vim.lsp.inlay_hint` is all-or-nothing per buffer. `toggle()` asks each
-- attached server for the hints on the current line and draws them the same
-- way the built-in ones look (inline, `LspInlayHint`). They go away when the
-- cursor leaves the line, the buffer changes, insert mode starts, or `toggle()`
-- is called again. The request is made directly because `vim.lsp.inlay_hint.get`
-- only returns hints Neovim cached for buffers where hints are enabled.

local M = {}

local ns = vim.api.nvim_create_namespace "inlay_line"
local augroup = vim.api.nvim_create_augroup("inlay_line", { clear = true })
local METHOD = "textDocument/inlayHint"

---@type table<integer, integer> bufnr -> 0-based line showing hints
local shown = {}

local function clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
  vim.api.nvim_clear_autocmds { group = augroup, buffer = buf }
  shown[buf] = nil
end

local function label(hint)
  if type(hint.label) == "string" then return hint.label end
  local parts = {}
  for _, part in ipairs(hint.label) do
    parts[#parts + 1] = part.value
  end
  return table.concat(parts)
end

local function draw(buf, row, line, hints, encoding)
  for _, hint in ipairs(hints) do
    if hint.position.line == row then
      local col = vim.str_byteindex(line, encoding, hint.position.character, false)
      local text = (hint.paddingLeft and " " or "") .. label(hint) .. (hint.paddingRight and " " or "")
      vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
        virt_text = { { text, "LspInlayHint" } },
        virt_text_pos = "inline",
        hl_mode = "combine",
      })
    end
  end
end

function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  if shown[buf] == row then return clear(buf) end
  clear(buf)

  if vim.lsp.inlay_hint.is_enabled { bufnr = buf } then
    return vim.notify("Inlay hints are already on in this buffer (<Leader>uh)", vim.log.levels.INFO)
  end
  local clients = vim.lsp.get_clients { bufnr = buf, method = METHOD }
  if #clients == 0 then
    return vim.notify("No attached language server provides inlay hints", vim.log.levels.WARN)
  end

  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  shown[buf] = row
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_get_cursor(0)[1] - 1 ~= row then clear(buf) end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertEnter", "BufLeave" }, {
    group = augroup,
    buffer = buf,
    callback = function() clear(buf) end,
  })

  for _, client in ipairs(clients) do
    local enc = client.offset_encoding
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(buf),
      range = {
        start = { line = row, character = 0 },
        ["end"] = { line = row, character = vim.str_utfindex(line, enc) },
      },
    }
    client:request(METHOD, params, function(err, result)
      -- Drop answers that arrive after the hints were dismissed or the text changed.
      if err or not result or shown[buf] ~= row then return end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then return end
      draw(buf, row, line, result, enc)
    end, buf)
  end
end

return M
