-- Ask a model about a selection, or just ask it something, from inside nvim.
--
-- <Leader>aa opens a small menu; the answer streams into a markdown buffer on
-- the right (see ui.lua), from where it can be copied back into the buffer the
-- question came from. The backend is the `llama` wrapper unless
-- $HABITUS_OLLAMA_URL is set (see backend.lua). Mappings live in plugins/llm.lua.
--
-- The answer buffer is the conversation: after each answer it offers a new
-- `── you ──` turn, and <C-s> (or <Leader>as, from anywhere) sends the whole
-- buffer back to the model. Every part of it is editable, and the model sees
-- the buffer as it is at send time -- a reworded question, a trimmed answer,
-- a deleted turn. Typing into an empty one (<Leader>ao before asking
-- anything) starts a conversation too.
--
-- In the answer buffer:
--   <C-s>     send the conversation (normal or insert mode)
--   <CR>      insert the code block (or paragraph) under the cursor below the source selection
--   gA        insert the answer (the one under the cursor, else the latest) there
--   gR        replace the source selection with that answer
--   {Visual}<CR> / {Visual}gR   the same, with just the selected text
--   Y         copy that answer to the clipboard (plain `y` works for parts)
--   <C-c>     stop generating          q   close the window
--
-- Closing the answer window (q, :q, :bd, …) stops generating; hiding it with
-- <Leader>ao or the menu does not, so an answer can keep streaming out of view.

local backend = require "llm.backend"
local ui = require "llm.ui"

local M = {}

local ns = vim.api.nvim_create_namespace "llm"

---@class llm.Source
---@field buf integer
---@field has_selection boolean
---@field start integer extmark: start of the selection
---@field stop integer extmark: end of the selection (exclusive)
---@field after integer extmark: the line inserts go below

---@type { job: llm.Job?, id: integer, src: llm.Source? }
local state = { job = nil, id = 0, src = nil }

---@class llm.Context
---@field buf integer
---@field row integer 0-based cursor row, the anchor when there is no selection
---@field ft string
---@field text string? the selected text
---@field range integer[]? { start_row, start_col, end_row, end_col } 0-based, end exclusive

--- Where the request comes from. Must run while visual mode is still active:
--- it reads the selection, then leaves visual mode.
---@return llm.Context
local function context()
  local buf = vim.api.nvim_get_current_buf()
  local ctx = { buf = buf, row = vim.api.nvim_win_get_cursor(0)[1] - 1, ft = vim.bo[buf].filetype }
  local mode = vim.fn.mode()
  if not mode:match "^[vV\22]" then return ctx end

  local p1, p2 = vim.fn.getpos "v", vim.fn.getpos "."
  ctx.text = table.concat(vim.fn.getregion(p1, p2, { type = mode }), "\n")
  local region = vim.fn.getregionpos(p1, p2, { type = mode })
  local s, e = region[1][1], region[#region][2]
  local srow, erow = s[2] - 1, e[2] - 1
  local last_len = #vim.api.nvim_buf_get_lines(buf, erow, erow + 1, false)[1]
  if mode == "v" then
    -- getregionpos ends on the last byte of the last character, inclusive.
    ctx.range = { srow, s[3] - 1, erow, math.min(e[3], last_len) }
  else
    -- Linewise; blockwise too, since a block cannot be replaced by free text.
    ctx.range = { srow, 0, erow, last_len }
  end
  vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
  return ctx
end

---@param ctx llm.Context
---@return llm.Source
local function anchor(ctx)
  if state.src and vim.api.nvim_buf_is_valid(state.src.buf) then
    vim.api.nvim_buf_clear_namespace(state.src.buf, ns, 0, -1)
  end
  local r = ctx.range or { ctx.row, 0, ctx.row, 0 }
  return {
    buf = ctx.buf,
    has_selection = ctx.range ~= nil,
    start = vim.api.nvim_buf_set_extmark(ctx.buf, ns, r[1], r[2], { right_gravity = false }),
    stop = vim.api.nvim_buf_set_extmark(ctx.buf, ns, r[3], r[4], { right_gravity = true }),
    after = vim.api.nvim_buf_set_extmark(ctx.buf, ns, r[3], 0, {}),
  }
end

---@param msg string
---@param level? integer
local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "llm" }) end

local function label() return backend.name() .. ":" .. backend.peek_model() end

--- Open a new user turn at the end of the conversation, cursor-ready.
local function reply_turn()
  ui.trim_end()
  ui.append("\n\n" .. ui.header(ui.YOU) .. "\n\n")
end

--- Stop the running request, if any.
---@param reply boolean open a new user turn below the partial answer
local function stop(reply)
  if not state.job then return end
  state.job.cancel()
  state.job = nil
  -- Bumping the id drops any output still in flight from the cancelled run.
  state.id = state.id + 1
  if reply then reply_turn() end
  ui.status("■ " .. label() .. " · stopped")
end

--- Put lines from the answer back into the source buffer.
---@param lines string[]
---@param how "insert"|"replace"
local function put(lines, how)
  local src = state.src
  if not src then return notify("no source buffer: this conversation was not started from one", vim.log.levels.WARN) end
  if not vim.api.nvim_buf_is_valid(src.buf) then return notify("the source buffer is gone", vim.log.levels.WARN) end
  if vim.trim(table.concat(lines, "\n")) == "" then return notify("nothing to put", vim.log.levels.WARN) end
  local buf = src.buf
  local function mark(id) return vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {}) end

  if how == "replace" then
    if not src.has_selection then
      return notify("there was no selection to replace; use <CR> or A to insert", vim.log.levels.WARN)
    end
    local s, e = mark(src.start), mark(src.stop)
    vim.api.nvim_buf_set_text(buf, s[1], s[2], e[1], e[2], lines)
    -- Re-aim the marks at the new text, so a second R replaces it again.
    local erow = s[1] + #lines - 1
    local ecol = (#lines == 1 and s[2] or 0) + #lines[#lines]
    vim.api.nvim_buf_set_extmark(buf, ns, erow, ecol, { id = src.stop, right_gravity = true })
    -- The insert point only moves down: text already inserted below the
    -- selection stays above whatever is inserted next.
    if mark(src.after)[1] < erow then vim.api.nvim_buf_set_extmark(buf, ns, erow, 0, { id = src.after }) end
    notify(("replaced the selection with %d line(s)"):format(#lines))
  else
    local row = mark(src.after)[1]
    vim.api.nvim_buf_set_lines(buf, row + 1, row + 1, false, lines)
    -- Further inserts go below this one, so they land in the order made.
    vim.api.nvim_buf_set_extmark(buf, ns, row + #lines, 0, { id = src.after })
    notify(("inserted %d line(s)"):format(#lines))
  end
end

--- Text of the visual selection in the answer buffer, leaving visual mode.
---@return string[]
local function visual_lines()
  local mode = vim.fn.mode()
  local lines = vim.fn.getregion(vim.fn.getpos "v", vim.fn.getpos ".", { type = mode })
  vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
  return lines
end

---@param buf integer
local function answer_maps(buf)
  local function map(mode, lhs, fn, desc) vim.keymap.set(mode, lhs, fn, { buffer = buf, desc = "llm: " .. desc }) end
  map("n", "<CR>", function() put(ui.block_at_cursor(0), "insert") end, "insert block under cursor")
  map("x", "<CR>", function() put(visual_lines(), "insert") end, "insert selection")
  map("n", "gA", function() put(ui.answer(0), "insert") end, "insert the answer")
  map("n", "gR", function() put(ui.answer(0), "replace") end, "replace source selection with the answer")
  map("x", "gR", function() put(visual_lines(), "replace") end, "replace source selection with this")
  map("n", "Y", function()
    local text = table.concat(ui.answer_raw(0), "\n")
    vim.fn.setreg('"', text)
    pcall(vim.fn.setreg, "+", text)
    notify "answer copied"
  end, "copy the answer")
  map("n", "<C-s>", M.send, "send the conversation")
  map("i", "<C-s>", function()
    vim.cmd.stopinsert()
    M.send()
  end, "send the conversation")
  map("n", "<C-c>", M.cancel, "stop generating")
  map("n", "q", ui.close, "close")
end

--- Send the conversation in the answer buffer and stream the reply below it.
--- The buffer is parsed afresh every time, so what the model sees is exactly
--- what the buffer says, edits included.
local function converse()
  local turns = vim.tbl_filter(function(t) return #t.lines > 0 end, ui.turns())
  local last = turns[#turns]
  if not last or last.role ~= "user" then
    return notify(("nothing to send: write under the last '%s' line"):format(ui.header(ui.YOU)), vim.log.levels.WARN)
  end
  local messages = vim.tbl_map(function(t) return { role = t.role, content = table.concat(t.lines, "\n") } end, turns)

  state.id = state.id + 1
  local id = state.id
  local win = ui.open()
  ui.trim_end()
  -- Having just sent from the answer window, you want to watch the reply:
  -- park the cursor on the last line so ui.append follows the stream.
  if vim.api.nvim_get_current_win() == win then
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(ui.buf()), 0 })
  end
  ui.append("\n\n" .. ui.header(label()) .. "\n\n")

  local what = last.lines[1]
  if #last.lines > 1 then what = what .. "…" end
  if vim.fn.strchars(what) > 60 then what = vim.fn.strcharpart(what, 0, 57) .. "…" end
  local started = vim.uv.hrtime()
  local function status(mark, hint)
    ui.status(("%s %s · %s%s"):format(mark, label(), what, hint and " · " .. hint or ""))
  end
  local function finish(mark, hint)
    state.job = nil
    reply_turn()
    status(mark, hint)
  end

  -- Models often open with a newline; the header already has its blank line.
  local fresh = true
  local job, err = backend.run(messages, function(chunk)
    vim.schedule(function()
      if id ~= state.id then return end
      if fresh then
        chunk = chunk:gsub("^%s+", "")
        if chunk == "" then return end
        fresh = false
      end
      ui.append(chunk)
    end)
  end, function(run_err)
    vim.schedule(function()
      if id ~= state.id then return end
      local secs = ("%.1fs"):format((vim.uv.hrtime() - started) / 1e9)
      if run_err then
        finish("✗ " .. secs, "<C-s>/<Leader>as retry")
        notify(run_err, vim.log.levels.ERROR)
      else
        finish("✓ " .. secs, "<C-s>/<Leader>as reply")
      end
    end)
  end)
  if not job then
    finish("✗", "<C-s>/<Leader>as retry")
    return notify(err or "could not start the request", vim.log.levels.ERROR)
  end
  state.job = job
  status "⋯"
end

--- Start a new conversation and stream the answer into the answer window.
---@param ctx llm.Context
---@param prompt string may be empty when there is a selection
function M.ask(ctx, prompt)
  local text
  if ctx.text and prompt ~= "" then
    text = ("%s\n\n```%s\n%s\n```"):format(prompt, ctx.ft, ctx.text)
  else
    text = ctx.text or prompt
  end
  if vim.trim(text) == "" then return end

  stop(false)
  state.src = anchor(ctx)
  ui.clear()
  answer_maps(ui.buf())
  vim.api.nvim_set_current_win(ui.open())
  ui.append(ui.header(ui.YOU) .. "\n\n" .. text)
  converse()
end

--- Send the conversation in the answer buffer, with whatever was edited or
--- added to it, and stream the reply.
function M.send()
  if state.job then return notify("still answering; <C-c> stops it", vim.log.levels.WARN) end
  converse()
end

--- Prompt for a question; from visual mode the selection goes with it.
function M.prompt()
  local ctx = context()
  local hint = ctx.text and "Prompt (empty: send the selection alone): " or "Prompt: "
  vim.ui.input({ prompt = hint }, function(input)
    if input == nil or (input == "" and not ctx.text) then return end
    M.ask(ctx, input)
  end)
end

function M.cancel() stop(true) end

-- Set while the answer window is being hidden rather than closed.
local hiding = false

--- Show or hide the answer window. Hiding leaves a running request alone.
function M.toggle()
  if ui.win() then
    hiding = true
    local ok, err = pcall(ui.close)
    hiding = false
    if not ok then error(err, 0) end
  else
    answer_maps(ui.buf())
    ui.open()
  end
end

function M.pick_model()
  local models, err = backend.models()
  if not models then return notify(err or "could not list models", vim.log.levels.ERROR) end
  vim.ui.select(models, { prompt = "Model (" .. backend.name() .. ")" }, function(choice)
    if choice then backend.set_model(choice) end
  end)
end

--- The <Leader>aa menu.
function M.menu()
  local ctx = context()
  local items = {}
  local function add(text, fn) items[#items + 1] = { text = text, fn = fn } end
  if ctx.text then
    add("Ask about the selection…", function()
      vim.ui.input({ prompt = "Prompt (empty: send the selection alone): " }, function(input)
        if input ~= nil then M.ask(ctx, input) end
      end)
    end)
  end
  add("Ask…", function()
    vim.ui.input({ prompt = "Prompt: " }, function(input)
      if input and input ~= "" then M.ask({ buf = ctx.buf, row = ctx.row, ft = ctx.ft }, input) end
    end)
  end)
  add(ui.win() and "Hide the answer" or "Show the last answer", M.toggle)
  if state.job then add("Stop generating", M.cancel) end
  add("Model: " .. label() .. " (change…)", M.pick_model)

  vim.ui.select(items, {
    prompt = "LLM",
    format_item = function(item) return item.text end,
  }, function(item)
    if item then item.fn() end
  end)
end

local group = vim.api.nvim_create_augroup("llm", { clear = true })

vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function() stop(false) end })

-- Closing the last window showing the answer stops the request.
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(args)
    if hiding or not state.job then return end
    local win = tonumber(args.match)
    if not win or not vim.api.nvim_win_is_valid(win) then return end
    local buf = vim.api.nvim_win_get_buf(win)
    if not ui.is_answer(buf) then return end
    for _, other in ipairs(vim.fn.win_findbuf(buf)) do
      if other ~= win then return end
    end
    M.cancel()
  end,
})

-- So does deleting the answer buffer, even from a window that isn't showing it.
vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
  group = group,
  callback = function(args)
    -- No reply turn: the buffer is on its way out.
    if state.job and ui.is_answer(args.buf) then stop(false) end
  end,
})

return M
