-- The answer window for the llm module: one reused scratch buffer, markdown so
-- treesitter highlights it and code fences are easy to find, shown in a right
-- vsplit. It is an ordinary buffer, so plain `y` copies any part of an answer;
-- the buffer-local maps set up by init.lua only cover putting text back into
-- the buffer the question came from.

local M = {}

local NAME = "llm://answer"

---@return integer buf
function M.buf()
  local buf = vim.fn.bufnr(NAME)
  if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then return buf end
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, NAME)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  return buf
end

---@return integer? win the window showing the answer in this tabpage
function M.win()
  local buf = vim.fn.bufnr(NAME)
  if buf == -1 then return nil end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then return win end
  end
end

--- Show the answer window (without moving the cursor into it).
---@return integer win
function M.open()
  local win = M.win()
  if win then return win end
  local buf = M.buf()
  win = vim.api.nvim_open_win(buf, false, {
    split = "right",
    win = -1,
    width = math.max(50, math.floor(vim.o.columns * 0.4)),
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].conceallevel = 2
  vim.wo[win].winfixwidth = true
  return win
end

function M.close()
  local win = M.win()
  if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, false) end
end

function M.toggle()
  if M.win() then
    M.close()
  else
    M.open()
  end
end

---@param text string shown in the window's winbar
function M.status(text)
  local win = M.win()
  if win then vim.wo[win].winbar = " " .. text:gsub("%%", "%%%%") end
end

function M.clear()
  local buf = M.buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

--- Append streamed text at the end of the buffer. Keeps the window scrolled to
--- the bottom while the cursor sits on the last line, and leaves it alone once
--- you move up to read.
---@param text string
function M.append(text)
  local buf = M.buf()
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local col = #vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1]
  local win = M.win()
  local follow = win and vim.api.nvim_win_get_cursor(win)[1] == last + 1
  vim.api.nvim_buf_set_text(buf, last, col, last, col, vim.split(text, "\n", { plain = true }))
  if follow then vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 }) end
end

--- Drop blank lines at both ends once an answer is complete.
function M.trim()
  local buf = M.buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first, last = 1, #lines
  while first <= last and lines[first]:match "^%s*$" do
    first = first + 1
  end
  while last >= first and lines[last]:match "^%s*$" do
    last = last - 1
  end
  if first == 1 and last == #lines then return end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_slice(lines, first, last))
end

---@return string[]
function M.lines() return vim.api.nvim_buf_get_lines(M.buf(), 0, -1, false) end

--- The fenced code block the cursor is in (without its fences), else the
--- paragraph under the cursor.
---@param win integer
---@return string[]
function M.block_at_cursor(win)
  local lines = M.lines()
  local row = vim.api.nvim_win_get_cursor(win)[1]

  local open
  for i, line in ipairs(lines) do
    if line:match "^%s*```" then
      if not open then
        open = i
      else
        if row >= open and row <= i then return vim.list_slice(lines, open + 1, i - 1) end
        open = nil
      end
    end
  end

  local first, last = row, row
  if (lines[row] or ""):match "^%s*$" then return {} end
  while first > 1 and not lines[first - 1]:match "^%s*$" do
    first = first - 1
  end
  while last < #lines and not lines[last + 1]:match "^%s*$" do
    last = last + 1
  end
  return vim.list_slice(lines, first, last)
end

--- The whole answer; if it is nothing but one fenced block (the usual shape of
--- "rewrite this code"), the code inside it.
---@return string[]
function M.answer()
  local lines = M.lines()
  local fences = 0
  for _, line in ipairs(lines) do
    if line:match "^%s*```" then fences = fences + 1 end
  end
  if fences == 2 and #lines >= 2 and lines[1]:match "^%s*```" and lines[#lines]:match "^%s*```%s*$" then
    return vim.list_slice(lines, 2, #lines - 1)
  end
  return lines
end

return M
