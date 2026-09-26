-- Model backends for the llm module.
--
-- Default is the `llama` wrapper (shell/bin/llama): no server, every request
-- loads the GGUF and exits, and models/sampling live in shell/llama/models.conf
-- rather than here. When $OLLAMA_URL is set (and non-empty) requests go to that
-- Ollama server instead; $OLLAMA_MODEL picks the model, else the first one the
-- server lists. The env is read on every call, so `:let $OLLAMA_URL = ""`
-- switches back to llama without a restart.
--
-- Not $OLLAMA_HOST: the ollama CLI reads that for its own bind/client address,
-- and a machine running a local ollama would silently flip backends.

local M = {}

-- Model picked from the menu, per backend. nil means "backend default".
local chosen = {}
-- First model /api/tags reported, per URL, so the fallback costs one request.
local ollama_default = {}

---@return string? url Ollama base URL without a trailing slash, or nil for llama
local function ollama_url()
  local url = vim.env.OLLAMA_URL
  if not url or url == "" then return nil end
  return (url:gsub("/+$", ""))
end

---@return "llama"|"ollama"
function M.name() return ollama_url() and "ollama" or "llama" end

--- Models the current backend can use.
---@return string[]? models
---@return string? err
function M.models()
  local url = ollama_url()
  if url then
    local res = vim.system({ "curl", "-sS", "--fail", "--max-time", "5", url .. "/api/tags" }, { text = true }):wait()
    if res.code ~= 0 then return nil, ("GET %s/api/tags failed: %s"):format(url, vim.trim(res.stderr or "")) end
    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok or type(data) ~= "table" or type(data.models) ~= "table" then
      return nil, "unexpected /api/tags response"
    end
    local names = {}
    for _, m in ipairs(data.models) do
      names[#names + 1] = m.name
    end
    return names
  end

  local res = vim.system({ "llama", "list" }, { text = true }):wait()
  if res.code ~= 0 then return nil, vim.trim(res.stderr or "") end
  local names = {}
  for line in vim.gsplit(res.stdout, "\n", { trimempty = true }) do
    local alias, state = line:match "^(%S+)%s+(%S+)"
    -- `llama list` prints missing models too; offering one would just fail.
    if alias and state ~= "missing" then names[#names + 1] = alias end
  end
  return names
end

--- The model the next request will use, resolving Ollama's fallback if needed.
---@return string? model
---@return string? err
function M.model()
  local name = M.name()
  if chosen[name] then return chosen[name] end
  if name == "llama" then return vim.env.LLAMA_MODEL or "default" end

  if vim.env.OLLAMA_MODEL and vim.env.OLLAMA_MODEL ~= "" then return vim.env.OLLAMA_MODEL end
  local url = ollama_url() --[[@as string]]
  if not ollama_default[url] then
    local models, err = M.models()
    if not models then return nil, err end
    if #models == 0 then return nil, "the Ollama server at " .. url .. " has no models" end
    ollama_default[url] = models[1]
  end
  return ollama_default[url]
end

--- The model for display only: never makes a request, so a menu label cannot
--- stall on an unreachable server.
---@return string
function M.peek_model()
  local name = M.name()
  if chosen[name] then return chosen[name] end
  if name == "llama" then return vim.env.LLAMA_MODEL or "default" end
  if vim.env.OLLAMA_MODEL and vim.env.OLLAMA_MODEL ~= "" then return vim.env.OLLAMA_MODEL end
  return ollama_default[ollama_url()] or "auto"
end

---@param model string
function M.set_model(model) chosen[M.name()] = model end

---@class llm.Job
---@field cancel fun()

--- Start a process in its own process group, so cancel() reaches the whole
--- pipeline -- `llama` is a bash wrapper around `llama-completion | perl`, and
--- signalling only the wrapper would leave the model running.
---@param cmd string[]
---@param stdin string? nil gives the child /dev/null
---@param on_stdout fun(data: string)
---@param on_exit fun(code: integer, stderr: string)
---@return llm.Job? job
---@return string? err
local function spawn(cmd, stdin, on_stdout, on_exit)
  local stderr = {}
  local ok, obj = pcall(vim.system, cmd, {
    stdin = stdin or false,
    detach = true,
    stdout = function(_, data)
      if data then on_stdout(data) end
    end,
    stderr = function(_, data)
      if data then stderr[#stderr + 1] = data end
    end,
  }, function(res) on_exit(res.signal ~= 0 and 128 + res.signal or res.code, table.concat(stderr)) end)
  if not ok then return nil, tostring(obj) end
  return {
    cancel = function()
      if not pcall(vim.uv.kill, -obj.pid, "sigterm") then pcall(obj.kill, obj, "sigterm") end
    end,
  }
end

---@class llm.Message
---@field role "user"|"assistant"
---@field content string

--- One prompt for a backend that takes a single message. `llama` is one-shot
--- (no chat state between calls), so earlier turns travel as quoted context.
---@param messages llm.Message[]
---@return string
local function flatten(messages)
  if #messages == 1 then return messages[1].content end
  local parts = { "Our conversation so far:" }
  for i = 1, #messages - 1 do
    local m = messages[i]
    parts[#parts + 1] = (m.role == "user" and "### User\n\n" or "### Assistant\n\n") .. m.content
  end
  parts[#parts + 1] = "Reply to my latest message:\n\n" .. messages[#messages].content
  return table.concat(parts, "\n\n")
end

--- Stream the model's reply to a conversation. Callbacks run in a luv
--- callback (fast context): schedule before touching buffers.
---@param messages llm.Message[] oldest first; the last one is the user's
---@param on_chunk fun(text: string)
---@param on_done fun(err: string?)
---@return llm.Job? job
---@return string? err
function M.run(messages, on_chunk, on_done)
  local model, err = M.model()
  if not model then return nil, err end

  local url = ollama_url()
  if not url then
    local text = flatten(messages)
    if vim.fn.executable "llama" == 0 then return nil, "`llama` is not on PATH (see shell/bin/llama)" end
    -- The message goes in argv, not stdin: libuv hands children a socketpair,
    -- and the wrapper only reads stdin when it is a pipe or a file -- its guard
    -- against hanging on an inherited, never-closing stdin, which a socket is
    -- indistinguishable from. The 8k context caps a message well below
    -- Linux's 128 KiB per-argument limit; a conversation long enough to
    -- approach it has overflowed the context already.
    return spawn({ "llama", "-m", model, "--", text }, nil, on_chunk, function(code, stderr)
      -- stderr also carries any <think> block the wrapper split off, so only
      -- surface it when the run actually failed.
      on_done(code ~= 0 and ("llama exited %d: %s"):format(code, vim.trim(stderr)) or nil)
    end)
  end

  local body = vim.json.encode {
    model = model,
    stream = true,
    messages = messages,
  }
  local partial, api_err = "", nil
  local function feed(line)
    if line == "" then return end
    local ok, msg = pcall(vim.json.decode, line)
    if not ok or type(msg) ~= "table" then return end
    if msg.error then
      api_err = tostring(msg.error)
    elseif type(msg.message) == "table" and type(msg.message.content) == "string" and msg.message.content ~= "" then
      on_chunk(msg.message.content)
    end
  end
  local curl = { "curl", "-sS", "-N", "--fail-with-body", "-H", "Content-Type: application/json" }
  vim.list_extend(curl, { "--data-binary", "@-", url .. "/api/chat" })
  return spawn(curl, body, function(data)
    -- NDJSON, but chunk boundaries fall anywhere: hold the unfinished tail.
    partial = partial .. data
    while true do
      local nl = partial:find("\n", 1, true)
      if not nl then break end
      feed(partial:sub(1, nl - 1))
      partial = partial:sub(nl + 1)
    end
  end, function(code, stderr)
    feed(partial)
    if api_err then
      on_done("ollama: " .. api_err)
    elseif code ~= 0 then
      on_done(("curl exited %d: %s"):format(code, vim.trim(stderr)))
    else
      on_done(nil)
    end
  end)
end

return M
