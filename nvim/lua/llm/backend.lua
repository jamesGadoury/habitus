-- Model backend for the llm module: any server that speaks the OpenAI chat
-- completions API (llama-server, vLLM, LM Studio, a hosted API, ...).
--
-- $HABITUS_LLM_URL is the base URL including the version path, as OpenAI's
-- SDKs take it (`http://<host>:<port>/v1`); requests go to /chat/completions and
-- /models under it. The model is, first to last: the one picked from the menu,
-- $HABITUS_LLM_MODEL, the one the server reports loaded, the one used last,
-- the first one the server lists (see M.model). $HABITUS_LLM_API_KEY, if set,
-- is sent as a bearer token.
-- $HABITUS_LLM_SYSTEM replaces the system prompt; set but empty sends none.
-- Thinking is off unless toggled on (M.toggle_thinking), for the session.
-- The env is read on every call, so `:let $HABITUS_LLM_URL = "..."` switches
-- servers without a restart. $OPENAI_BASE_URL/$OPENAI_API_KEY are deliberately
-- not read: OpenAI's SDKs and other tools read them, and pointing those at a
-- local server shouldn't also redirect this, or the reverse.

local M = {}

-- Unprompted, models answer a one-line question with hundreds of words. Don't
-- tighten it to "as brief as possible": small models then guess instead of
-- working the answer out (a wrong flag, wrong arithmetic).
local SYSTEM_DEFAULT = "Be concise: answer in a few sentences or one code block, with no headings, "
  .. "alternatives, or closing summary. Accuracy comes first — if the answer needs a short "
  .. "explanation or a worked step, include it."

-- Model picked from the menu, per server URL. nil means "pick one".
local chosen = {}
-- Model the last request used, per URL: the choice when none is loaded.
local last = {}
-- Sent as chat_template_kwargs.enable_thinking, which vLLM and llama-server
-- hand to the chat template: Qwen-style templates read it, others ignore it.
-- Off by default: a reasoning model otherwise spends most of a short answer's
-- time thinking. Not reasoning_effort: "none" also turns thinking off on vLLM,
-- but what its values mean differs from server to server. A server that
-- rejects unknown fields (OpenAI's own API) refuses the request.
local thinking = false

---@return boolean
function M.thinking() return thinking end

---@return boolean on the new state
function M.toggle_thinking()
  thinking = not thinking
  return thinking
end

--- Whether a server is set. Cheap, so the which-key label can call it every
--- time the popup opens.
---@return boolean
function M.configured()
  local url = vim.env.HABITUS_LLM_URL
  return url ~= nil and url ~= ""
end

---@return string? url base URL without a trailing slash
---@return string? err
local function base_url()
  local url = vim.env.HABITUS_LLM_URL
  if not M.configured() then
    return nil, "$HABITUS_LLM_URL is not set: point it at an OpenAI-compatible server (http://<host>:<port>/v1)"
  end
  return (url:gsub("/+$", ""))
end

--- Request headers, fed to curl on stdin (`-H @-`) so the API key never
--- appears in argv, where any local user can read it with ps.
---@return string
local function headers()
  local h = "Content-Type: application/json\n"
  local key = vim.env.HABITUS_LLM_API_KEY
  if key and key ~= "" then h = h .. "Authorization: Bearer " .. key .. "\n" end
  return h
end

--- The message out of an error body, in the shapes servers actually send:
--- OpenAI's {error: {message}}, {error: "..."}, {message}, FastAPI's {detail}.
---@param body string
---@return string?
local function error_message(body)
  local ok, data = pcall(vim.json.decode, body)
  if not ok or type(data) ~= "table" then return nil end
  local e = data.error
  if type(e) == "table" and type(e.message) == "string" then return e.message end
  if type(e) == "string" then return e end
  if type(data.message) == "string" then return data.message end
  if type(data.detail) == "string" then return data.detail end
  return nil
end

---@class llm.Model
---@field id string
---@field loaded boolean the server says it is in memory (llama-swap's status.value)

--- Models the server offers, in the server's order.
---@return llm.Model[]? models
---@return string? err
function M.models()
  local url, err = base_url()
  if not url then return nil, err end
  local res = vim
    .system({ "curl", "-sS", "--fail-with-body", "--connect-timeout", "2", "--max-time", "5", "-H", "@-", url .. "/models" }, {
      stdin = headers(),
      text = true,
    })
    :wait()
  if res.code ~= 0 then
    local msg = error_message(res.stdout or "") or vim.trim(res.stderr or "")
    return nil, ("GET %s/models failed: %s"):format(url, msg)
  end
  local ok, data = pcall(vim.json.decode, res.stdout)
  if not ok or type(data) ~= "table" or type(data.data) ~= "table" then return nil, "unexpected /models response" end
  local models = {}
  for _, m in ipairs(data.data) do
    if type(m) == "table" and type(m.id) == "string" then
      -- llama-swap lists every model it can start, loaded or not, and marks
      -- each with status.value; other servers list only what they serve.
      local loaded = type(m.status) == "table" and m.status.value == "loaded"
      models[#models + 1] = { id = m.id, loaded = loaded }
    end
  end
  return models
end

--- The model the next request will use. Without a pick or $HABITUS_LLM_MODEL
--- it asks the server every time, because asking llama-swap for a model that
--- isn't loaded makes it unload the running one and start that one: a swap
--- costs a model load, so follow whatever the server has loaded right now.
---@return string? model
---@return string? err
function M.model()
  local url, err = base_url()
  if not url then return nil, err end
  if chosen[url] then return chosen[url] end
  local env = vim.env.HABITUS_LLM_MODEL
  if env and env ~= "" then return env end

  local models, list_err = M.models()
  if not models then return nil, list_err end
  if #models == 0 then return nil, "the server at " .. url .. " lists no models" end
  local pick, listed = nil, {}
  for _, m in ipairs(models) do
    listed[m.id] = true
    -- Several can be loaded at once (llama-swap groups): stay on the last one.
    if m.loaded and (not pick or m.id == last[url]) then pick = m.id end
  end
  if not pick then pick = listed[last[url] or ""] and last[url] or models[1].id end
  last[url] = pick
  return pick
end

--- The model for display only: never makes a request, so a menu label cannot
--- stall on an unreachable server.
---@return string
function M.peek_model()
  local url = base_url()
  if not url then return "no server" end
  if chosen[url] then return chosen[url] end
  local env = vim.env.HABITUS_LLM_MODEL
  if env and env ~= "" then return env end
  return last[url] or "auto"
end

---@param model string
function M.set_model(model)
  local url = base_url()
  if url then chosen[url] = model end
end

---@class llm.Job
---@field cancel fun()

---@class llm.Message
---@field role "system"|"user"|"assistant"
---@field content string

--- Stream the model's reply to a conversation. Callbacks run in a luv
--- callback (fast context): schedule before touching buffers.
---@param model string from M.model(), resolved by the caller so it can label the answer
---@param messages llm.Message[] oldest first; the last one is the user's
---@param on_chunk fun(text: string) the answer
---@param on_done fun(err: string?)
---@param on_reasoning? fun(text: string) the model thinking, never shown as the answer
---@return llm.Job? job
---@return string? err
function M.run(model, messages, on_chunk, on_done, on_reasoning)
  local url, url_err = base_url()
  if not url then return nil, url_err end

  -- os_getenv, not vim.env: vim.env reads an empty variable as unset, and
  -- empty is how you turn the system prompt off.
  local system = vim.uv.os_getenv "HABITUS_LLM_SYSTEM" or SYSTEM_DEFAULT
  local all = {}
  if system ~= "" then all[1] = { role = "system", content = system } end
  vim.list_extend(all, messages)

  -- The body goes in a file because stdin carries the headers. tempname()
  -- lives in a directory only this user can read.
  local body_file = vim.fn.tempname()
  local f, open_err = io.open(body_file, "wb")
  if not f then return nil, "could not write the request: " .. tostring(open_err) end
  f:write(vim.json.encode {
    model = model,
    stream = true,
    messages = all,
    chat_template_kwargs = { enable_thinking = thinking },
  })
  f:close()

  local partial, api_err, rest = "", nil, {}
  local function feed(line)
    line = line:gsub("\r$", "")
    local payload = line:match "^data:%s*(.*)$"
    if not payload then
      -- Not an SSE event: an error body from --fail-with-body, or an SSE
      -- comment/blank line, which only matters if the run fails.
      if line ~= "" then rest[#rest + 1] = line end
      return
    end
    if payload == "[DONE]" then return end
    local ok, msg = pcall(vim.json.decode, payload)
    if not ok or type(msg) ~= "table" then return end
    if msg.error then
      api_err = error_message(payload) or vim.inspect(msg.error)
      return
    end
    local choice = type(msg.choices) == "table" and msg.choices[1]
    local delta = type(choice) == "table" and choice.delta
    if type(delta) ~= "table" then return end
    -- delta.reasoning (vLLM) / delta.reasoning_content (llama-server) is the
    -- model thinking: reported, but kept out of the answer.
    local reasoning = delta.reasoning or delta.reasoning_content
    if on_reasoning and type(reasoning) == "string" and reasoning ~= "" then on_reasoning(reasoning) end
    if type(delta.content) == "string" and delta.content ~= "" then on_chunk(delta.content) end
  end

  local cmd = { "curl", "-sS", "-N", "--fail-with-body", "-H", "@-", "--data-binary", "@" .. body_file }
  cmd[#cmd + 1] = url .. "/chat/completions"
  local ok, obj = pcall(vim.system, cmd, {
    stdin = headers(),
    stdout = function(_, data)
      if not data then return end
      -- SSE, but chunk boundaries fall anywhere: hold the unfinished tail.
      partial = partial .. data
      while true do
        local nl = partial:find("\n", 1, true)
        if not nl then break end
        feed(partial:sub(1, nl - 1))
        partial = partial:sub(nl + 1)
      end
    end,
    stderr = true,
  }, function(res)
    os.remove(body_file)
    feed(partial)
    local code = res.signal ~= 0 and 128 + res.signal or res.code
    if api_err then
      on_done(api_err)
    elseif code ~= 0 then
      local msg = error_message(table.concat(rest, "\n")) or vim.trim(res.stderr or "")
      on_done(("curl exited %d: %s"):format(code, msg))
    else
      on_done(nil)
    end
  end)
  if not ok then
    os.remove(body_file)
    return nil, tostring(obj)
  end
  return {
    cancel = function() pcall(obj.kill, obj, "sigterm") end,
  }
end

return M
