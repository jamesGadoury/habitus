-- <Leader>a: ask a local model about the selection, or anything. The module is
-- nvim/lua/llm/ (no third-party plugin); this file only registers mappings, and
-- the module is required on first use, so startup pays nothing for it.

---@param fn string
local function call(fn)
  return function() require("llm")[fn]() end
end

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = function(_, opts)
    local maps = opts.mappings
    maps.x = maps.x or {}
    local prefix = "<Leader>a"

    for _, mode in ipairs { "n", "x" } do
      maps[mode][prefix] = { desc = "󰚩 AI" }
      maps[mode][prefix .. "a"] = { call "menu", desc = "Menu" }
      maps[mode][prefix .. "p"] = { call "prompt", desc = mode == "x" and "Ask about selection" or "Ask" }
    end
    maps.n[prefix .. "o"] = { call "toggle", desc = "Show/hide answer" }
    maps.n[prefix .. "x"] = { call "cancel", desc = "Stop generating" }
    maps.n[prefix .. "m"] = { call "pick_model", desc = "Pick model" }
  end,
}
