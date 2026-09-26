-- The answer window for the llm module: one reused scratch buffer, markdown so
-- treesitter highlights it and code fences are easy to find, shown in a right
-- vsplit. It holds the whole conversation as a transcript, each turn under a
-- separator line (see M.header). It is an ordinary buffer: edit any of it,
-- and the next send parses what is there, so the text is the conversation.

local M = {}

local NAME = "llm://answer"

--- The name on the separator of the user's turns; any other name is a model.
M.YOU = "you"

local SEP_PAT = "^── (.+) ──$"

--- The separator line that starts a turn. Its shape is one a model does not
--- write on its own, so answer text is never mistaken for a turn boundary.
---@param who string M.YOU, or the model that answered
---@return string
function M.header(who) return ("── %s ──"):format(who) end

---@return integer buf
function M.buf()
  local buf = vim.fn.bufnr(NAME)
  if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
    if vim.api.nvim_buf_is_loaded(buf) then return buf end
    -- :bdelete unloads the buffer but keeps its number (and name), and an
    -- unloaded buffer has no lines to append to. Start over with a new one.
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, NAME)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  return buf
end

---@param buf integer
---@return boolean
function M.is_answer(buf) return buf == vim.fn.bufnr(NAME) end

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
  vim.fn.matchadd("Title", [[\v^── .+ ──$]], 10, -1, { window = win })
  return win
end

function M.close()
  local win = M.win()
  if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, false) end
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

--- Drop blank lines at the end of the buffer, so the next turn is appended
--- one blank line below the text.
function M.trim_end()
  local buf = M.buf()
  local n = vim.api.nvim_buf_line_count(buf)
  local last = n
  while last > 1 and vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1]:match "^%s*$" do
    last = last - 1
  end
  if last < n then vim.api.nvim_buf_set_lines(buf, last, n, false, {}) end
end

---@return string[]
function M.lines() return vim.api.nvim_buf_get_lines(M.buf(), 0, -1, false) end

---@param lines string[]
---@return string[] lines without blank lines at either end
local function strip(lines)
  local first, last = 1, #lines
  while first <= last and lines[first]:match "^%s*$" do
    first = first + 1
  end
  while last >= first and lines[last]:match "^%s*$" do
    last = last - 1
  end
  return vim.list_slice(lines, first, last)
end

---@class llm.Turn
---@field role "user"|"assistant"
---@field first integer 1-based row of the first content line (the one below the separator)
---@field last integer 1-based row of the last content line; first - 1 when there is none
---@field lines string[] the content, without blank lines at either end

--- The conversation as the buffer now reads. Text above the first separator
--- (typed into an empty buffer, say) is a user turn.
---@return llm.Turn[]
function M.turns()
  local lines = M.lines()
  local turns, cur = {}, nil
  for i, line in ipairs(lines) do
    local who = line:match(SEP_PAT)
    if who or not cur then
      cur = {
        role = (who == nil or who == M.YOU) and "user" or "assistant",
        first = who and i + 1 or i,
        last = i - 1,
      }
      turns[#turns + 1] = cur
    end
    if not who then cur.last = i end
  end
  for _, t in ipairs(turns) do
    t.lines = strip(vim.list_slice(lines, t.first, t.last))
  end
  return turns
end

--- The model's answer the cursor is in (its separator counts), else the latest.
---@param win integer
---@return string[]
function M.answer_raw(win)
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local pick
  for _, t in ipairs(M.turns()) do
    if t.role == "assistant" and #t.lines > 0 then
      pick = t
      if row >= t.first - 1 and row <= t.last then break end
    end
  end
  return pick and pick.lines or {}
end

--- The fenced code block the cursor is in (without its fences), else the
--- paragraph under the cursor. Only looks inside the cursor's turn.
---@param win integer
---@return string[]
function M.block_at_cursor(win)
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local turn
  for _, t in ipairs(M.turns()) do
    if row >= t.first and row <= t.last then turn = t end
  end
  if not turn then return {} end
  local lines = vim.list_slice(M.lines(), turn.first, turn.last)
  row = row - turn.first + 1

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

--- Like answer_raw, but if the answer is nothing but one fenced block (the
--- usual shape of "rewrite this code"), the code inside it.
---@param win integer
---@return string[]
function M.answer(win)
  local lines = M.answer_raw(win)
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
