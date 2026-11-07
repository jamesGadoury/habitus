-- Padded, outlined LSP popups (hover, signature help, diagnostics).
--
-- Neovim 0.11 floats have no padding option, so the text sits against the
-- border. Every LSP popup, rustaceanvim's hover actions included, goes through
-- `vim.lsp.util.open_floating_preview`, so `setup()` wraps that:
--   - the popup's border is blank cells, which is the padding;
--   - a second window behind it draws the rounded outline. It can't be
--     focused, and closes with the popup.
-- Both are pinned to absolute positions (see `place`).
-- The popup's buffer isn't touched: rustaceanvim maps hover actions to buffer
-- lines, so padding with blank lines would break `<CR>` on them.
-- Both windows use the editor background, not the theme's darker float
-- colour; the outline takes its colour from `FloatBorder`.

local M = {}

-- Columns of padding left and right of the text (>= 1). There is one row of
-- padding above and below: the blank border.
local PAD_X = 2
local EXTRA_X = PAD_X - 1 -- columns the outline window adds beyond the blank border

local BLANK = { " ", " ", " ", " ", " ", " ", " ", " " }
local FRAME_HL = "LspFloatFrame"

---@type table<integer, integer> popup window -> outline window
local frames = {}

local function set_frame_hl()
  local border = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, FRAME_HL, { fg = border.fg, bg = normal.bg })
end

local function close_frame(win)
  local frame = frames[win]
  frames[win] = nil
  if frame and vim.api.nvim_win_is_valid(frame) then pcall(vim.api.nvim_win_close, frame, true) end
end

-- Pin the popup to an absolute position that leaves room for the outline:
-- one row further from the cursor (so the outline doesn't cover the cursor
-- line), and clamped so the outline stays on screen. Neovim's own placement
-- only knows about the popup's border, not the outline around it.
-- Positions are the 0-based screen cell of the top-left of the popup's blank
-- border. They are computed from the config: `nvim_win_get_position` on a
-- float that hasn't been drawn yet returns its anchor point, which for a popup
-- above the cursor is its bottom edge.
---@param win integer
---@return boolean placed false when the position can't be worked out
local function place(win)
  local cfg = vim.api.nvim_win_get_config(win)
  local width, height = cfg.width, cfg.height
  local row, col
  if cfg.relative == "editor" then
    row, col = cfg.row, cfg.col
  elseif cfg.relative == "win" then -- what a popup opened at the cursor becomes
    -- cfg.row counts from the text area, below the winbar; win_screenpos
    -- (1-based) gives the top of the window, winbar included.
    local origin = vim.fn.win_screenpos(cfg.win)
    local winbar = (vim.fn.getwininfo(cfg.win)[1] or {}).winbar or 0
    row, col = origin[1] - 1 + winbar + cfg.row, origin[2] - 1 + cfg.col
  else
    return false
  end
  local anchor = cfg.anchor or "NW"
  local below, right = anchor:sub(1, 1) == "N", anchor:sub(2, 2) == "W"
  if not below then row = row - (height + 2) end
  if not right then col = col - (width + 2) end
  row, col = math.floor(row), math.floor(col)
  local last_row = vim.o.lines - vim.o.cmdheight - 1 -- lowest row the outline may use

  row = row + (below and 1 or -1)
  if below then
    -- outline bottom = row + (height + 2): shrink rather than spill off screen
    height = math.max(1, math.min(height, last_row - row - 2))
  else
    -- the bottom stays put next to the cursor; the top moves down if needed
    local bottom = row + height + 1
    row = math.max(row, 1)
    height = math.max(1, bottom - row - 1)
  end
  col = col + (right and 1 + EXTRA_X or -(1 + EXTRA_X))
  col = math.max(1 + EXTRA_X, math.min(col, vim.o.columns - (width + 2) - 1 - EXTRA_X))

  vim.api.nvim_win_set_config(win, { relative = "editor", anchor = "NW", row = row, col = col, height = height })
  return true
end

-- Draw (or resize) the outline around a popup that `place` pinned.
---@param win integer
local function sync_frame(win)
  local cfg = vim.api.nvim_win_get_config(win)
  local frame_cfg = {
    relative = "editor",
    row = cfg.row - 1,
    col = cfg.col - 1 - EXTRA_X,
    width = cfg.width + 2 + 2 * EXTRA_X,
    height = cfg.height + 2,
    border = "rounded",
    zindex = math.max((cfg.zindex or 50) - 1, 1),
    focusable = false,
    style = "minimal",
  }
  local frame = frames[win]
  if frame and vim.api.nvim_win_is_valid(frame) then
    vim.api.nvim_win_set_config(frame, frame_cfg)
    return
  end
  frame_cfg.noautocmd = true
  frame = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, frame_cfg)
  vim.bo[vim.api.nvim_win_get_buf(frame)].bufhidden = "wipe"
  vim.wo[frame].winhighlight = "NormalFloat:Normal,FloatBorder:" .. FRAME_HL
  frames[win] = frame
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    desc = "Close the outline of an LSP popup",
    callback = function()
      vim.schedule(function() close_frame(win) end)
    end,
  })
end

function M.setup()
  if M._orig then return end
  M._orig = vim.lsp.util.open_floating_preview

  set_frame_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("lsp_float", { clear = true }),
    desc = "Recompute the LSP popup outline colour",
    callback = set_frame_hl,
  })

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.util.open_floating_preview = function(contents, syntax, opts, ...)
    opts = vim.tbl_extend("force", opts or {}, { border = BLANK })
    -- Keep the outline on screen: border (2) + padding beyond it + outline (2).
    local max_width = vim.o.columns - 4 - 2 * EXTRA_X
    opts.max_width = math.min(opts.max_width or max_width, max_width)
    local buf, win = M._orig(contents, syntax, opts, ...)
    -- On a second `K` the existing popup is focused and returned: it is
    -- already placed, and only needs its outline resized.
    if not frames[win] then
      vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:Normal"
      if not place(win) then
        -- Unknown placement (e.g. at the mouse): a plain outline, no padding.
        vim.api.nvim_win_set_config(win, { border = "rounded" })
        vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:" .. FRAME_HL
        return buf, win
      end
    end
    sync_frame(win)
    return buf, win
  end
end

return M
