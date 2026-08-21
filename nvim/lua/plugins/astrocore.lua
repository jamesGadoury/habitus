-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

-- Most recent *listed* buffer we were sitting in. Tracked separately from
-- `nvim_get_current_buf()` because pickers (snacks) are floating scratch
-- buffers: when they open a file the "current" buffer is the picker itself,
-- which is unlisted and therefore not a meaningful anchor.
local last_listed_buf

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true, -- enable autopairs at start
      cmp = true, -- enable completion at start
      diagnostics = { virtual_text = true, virtual_lines = false }, -- diagnostic settings on startup
      highlighturl = true, -- highlight URLs at start
      notifications = true, -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    -- passed to `vim.filetype.add`
    filetypes = {
      -- see `:h vim.filetype.add` for usage
      extension = {
        foo = "fooscript",
      },
      filename = {
        [".foorc"] = "fooscript",
      },
      pattern = {
        [".*/etc/foo/.*"] = "fooscript",
      },
    },
    -- vim options can be configured here
    options = {
      opt = { -- vim.opt.<key>
        relativenumber = true, -- sets vim.opt.relativenumber
        number = true, -- sets vim.opt.number
        spell = false, -- sets vim.opt.spell
        signcolumn = "yes", -- sets vim.opt.signcolumn to yes
        wrap = false, -- sets vim.opt.wrap
        expandtab = true, -- use spaces instead of tab characters
        tabstop = 4, -- width of a tab character
        shiftwidth = 4, -- spaces per indent step
        softtabstop = 4, -- spaces inserted by <Tab> in insert mode
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Autocommands can be configured through AstroCore as well.
    autocmds = {
      -- The built-in XML indent script (indent/xml.vim) lists <Return> in
      -- 'indentkeys', so it re-indents the new line on every Enter. That
      -- forces attribute-continuation lines deeper automatically. Dropping
      -- <Return> keeps tag-aware snapping (on </, >, etc.) and on-demand `==`,
      -- but lets newlined attributes stay where you put them.
      xml_indent = {
        {
          event = "FileType",
          pattern = { "xml", "html", "svg", "xsd", "xslt" },
          desc = "Stop auto-reindent on <Return> for XML-family filetypes",
          -- The entry is "*<Return>" (the "*" prefix means "reindent, then
          -- insert the key"), so remove both forms to be safe across filetypes.
          callback = function() vim.opt_local.indentkeys:remove { "*<Return>", "<Return>" } end,
        },
      },
      -- New buffers are appended to the end of the tabline's buffer list by
      -- AstroNvim's own `bufferline` autocmd (a plain `table.insert` into
      -- `vim.t.bufs`). Move them to sit directly after the buffer that was
      -- current when they were created, so a file opened from the picker lands
      -- next to where you are instead of at the far right.
      buffer_open_adjacent = {
        {
          event = "BufEnter",
          desc = "Remember the last listed buffer to use as an insertion anchor",
          callback = function(args)
            if vim.bo[args.buf].buflisted then last_listed_buf = args.buf end
          end,
        },
        {
          event = "BufAdd",
          desc = "Place newly added buffers right after the current one in the tabline",
          callback = function(args)
            local bufnr, anchor = args.buf, last_listed_buf
            if not anchor or bufnr == anchor then return end
            -- Deferred: AstroNvim's BufAdd handler is what appends to
            -- `vim.t.bufs`, and astrocore registers autocmd groups by iterating
            -- its opts with `pairs()`, so we can't rely on running after it
            -- synchronously. Scheduling puts us after every BufAdd handler.
            vim.schedule(function()
              local bufs = vim.t.bufs
              if not bufs then return end
              local from, to
              for i, buf in ipairs(bufs) do
                if buf == bufnr then from = i end
                if buf == anchor then to = i end
              end
              if not from or not to or from == to + 1 then return end
              table.remove(bufs, from)
              if from < to then to = to - 1 end
              table.insert(bufs, to + 1, bufnr)
              vim.t.bufs = bufs
              require("astrocore").event "BufsUpdated"
              vim.cmd.redrawtabline()
            end)
          end,
        },
      },
      -- 'wrap' is off globally (see options.opt above), which leaves prose
      -- running off the right edge. Turn it back on for prose filetypes only.
      -- This is display-only soft wrap: no <NL> is inserted into the buffer.
      prose_wrap = {
        {
          event = "FileType",
          pattern = { "markdown", "markdown_inline", "mdx", "text", "gitcommit" },
          desc = "Soft-wrap prose at the window edge",
          callback = function()
            vim.opt_local.wrap = true
            vim.opt_local.linebreak = true -- break at 'breakat' chars, not mid-word
            vim.opt_local.breakindent = true -- keep continuation lines under the list/quote indent
            -- NOTE: no j/k remap needed — AstroNvim already maps them to a
            -- count-aware gj/gk globally, which handles wrapped lines.
          end,
        },
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    mappings = {
      -- first key is the mode
      n = {
        -- second key is the lefthand side of the map

        -- navigate buffer tabs
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- mappings seen under group name "Buffer"
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },

        -- tables with just a `desc` key will be registered with which-key if it's installed
        -- this is useful for naming menus
        -- ["<Leader>b"] = { desc = "Buffers" },

        -- setting a mapping to false will disable it
        -- ["<C-S>"] = false,
      },
    },
  },
}
