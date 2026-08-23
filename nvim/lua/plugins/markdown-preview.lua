-- Browser markdown preview, replacing iamcco/markdown-preview.nvim.
--
-- Why the swap: iamcco's preview page is a prebuilt Nuxt bundle pinned to
-- mermaid 10.2.3, so nothing from sankey-beta (10.3) onward renders, and the
-- version cannot be changed without rebuilding the app. Upstream has had no
-- real commit since Oct 2023. This plugin is pure Lua -- no node, no npm, no
-- build step -- and draws with mermaid 11.x.
--
-- Two behaviours that are on by default and so not restated in `opts`:
--   * scroll_sync         -- the page follows the cursor line
--   * auto_refresh_events -- InsertLeave/TextChanged/TextChangedI/BufWritePost,
--                            debounced, diffed into the DOM with morphdom, so
--                            there is no flicker and no scroll jump.
--
-- Note the astrocommunity markdown-preview-nvim import had to be dropped from
-- community.lua for this to work at all: lazy keys plugins by the last path
-- segment, so both repos collapse onto the name "markdown-preview.nvim" and the
-- community fragment's build step would run iamcco's node installer inside this
-- plugin's checkout. The explicit `name` below now breaks that collision on its
-- own, but the import stays out regardless -- it would still pull in iamcco's
-- plugin for nothing.

--- Read a file whole, or nil if it is not there.
---@param path string
---@return string?
local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local data = fd:read "*a"
  fd:close()
  return data
end

--- Stage the vendored browser assets inside the directory the server serves.
---
--- nvim/assets/index.html asks for ./vendor/*, and live-server.nvim resolves
--- every request through fs_realpath and refuses anything outside its root --
--- so a symlink into the config dir is rejected and a real copy is required.
--- Keyed on manifest.txt, so this copies once and then only after the manifest
--- actually changes (i.e. after `fetch-md-preview-vendor` bumps a version).
---
--- The root comes from the plugin rather than being spelled out here: in
--- takeover mode it ignores the `workspace_dir` option entirely and serves out
--- of util.shared_workspace(). Asking it directly keeps the two in step.
local function stage_vendor()
  local ok, util = pcall(require, "markdown_preview.util")
  if not ok or type(util.shared_workspace) ~= "function" then
    vim.notify(
      "markdown-preview: cannot locate the preview workspace; vendored assets not staged",
      vim.log.levels.ERROR
    )
    return
  end

  local src = vim.fn.stdpath "config" .. "/assets/vendor"
  local manifest = read_file(src .. "/manifest.txt")
  if not manifest then
    vim.notify("markdown-preview: vendored assets are missing; run `fetch-md-preview-vendor`", vim.log.levels.WARN)
    return
  end

  local workspace = util.shared_workspace()
  local dst = workspace .. "/vendor"
  if read_file(dst .. "/manifest.txt") == manifest then return end

  vim.fn.mkdir(workspace, "p")
  vim.fn.delete(dst, "rf")
  local out = vim.fn.system { "cp", "-R", src, dst }
  if vim.v.shell_error ~= 0 then
    vim.notify("markdown-preview: could not stage vendored assets: " .. out, vim.log.levels.ERROR)
  end
end

---@type LazySpec
return {
  "selimacerbas/markdown-preview.nvim",
  -- Explicit directory name, because the default is the last path segment and
  -- that is a name iamcco's plugin already owns on any machine that ran the
  -- old config. lazy treats an existing directory as installed and its install
  -- pipeline never checks the remote, so the swap would silently keep serving
  -- the old checkout -- which has no lua/ tree, hence `module 'markdown_preview'
  -- not found` from the config function below. Under a distinct name the stale
  -- clone is merely orphaned and gets picked up by :Lazy clean.
  --
  -- Renaming is safe for everything downstream: `main` and every require() go
  -- through runtimepath, not the directory name, and the <Leader>M mappings
  -- dispatch on the `cmd` names below.
  name = "markdown-preview-lua.nvim",
  -- Pure-Lua HTTP server (vim.uv), no external binary. Declared bare on
  -- purpose: markdown_preview drives `live_server.server` directly and never
  -- calls live_server.setup(), so opts here would only register that plugin's
  -- own FileType auto-start autocmd for nothing.
  dependencies = { "selimacerbas/live-server.nvim" },
  -- cmd-only, no `ft`: opening a README costs nothing. The mappings below live
  -- on astrocore, which is eager, so they trigger the load themselves.
  cmd = { "MarkdownPreview", "MarkdownPreviewRefresh", "MarkdownPreviewStop" },
  main = "markdown_preview",
  opts = {
    -- One browser tab, forever. The first :MarkdownPreview claims port 8421 and
    -- owns the tab; every later invocation -- another file, another nvim --
    -- retargets that same tab. This is the fix for both old annoyances: the tab
    -- no longer closes on buffer switch (mkdp's g:mkdp_auto_close), and
    -- previews no longer pile up one window per file.
    instance_mode = "takeover",
    -- `workspace_dir` is deliberately unset: takeover mode ignores it and
    -- serves out of util.shared_workspace() unconditionally, so setting it here
    -- would read as configuration while doing nothing. stage_vendor() above
    -- asks the plugin for the real directory instead.
    -- Rewrites the served index.html from our runtimepath-shadowed template on
    -- every start, which is also when custom_css below is re-inlined -- so the
    -- edit loop for either is <Leader>Ms then <Leader>Mp, not <Leader>Mr.
    overwrite_index_on_start = true,
    -- Catppuccin Mocha, to match ghostty and nvim. Inlined verbatim into the
    -- page after the bundled <style>, so this only has to override the plugin's
    -- CSS custom properties. stdpath, never a repo path: nvim/ is symlinked to
    -- ~/.config/nvim and the repo itself may live anywhere.
    custom_css = vim.fn.stdpath "config" .. "/assets/markdown-preview.css",
    -- Match the terminal rather than the desktop light/dark preference. The
    -- in-page header toggle still flips it per session.
    default_theme = "dark",
    -- `browser` deliberately left nil -> xdg-open -> the desktop default. The
    -- plugin does not consult $BROWSER, and xdg-open resolves to firefox here
    -- anyway, so naming it would buy determinism at the cost of portability.
    --
    -- `host` deliberately left at 127.0.0.1. On a non-loopback bind the
    -- token-gated asset route will serve any file at or below the previewed
    -- file's directory to whoever holds the URL.
    --
    -- `mermaid_elk` deliberately left false: @mermaid-js/layout-elk ships only
    -- a code-splitting ESM build, so it cannot be vendored as a single file.
  },
  config = function(_, opts)
    -- Before setup, so the assets are in place no matter how the first preview
    -- is triggered. Cheap after the first run: it compares one manifest file.
    stage_vendor()
    require("markdown_preview").setup(opts)
  end,
  specs = {
    {
      "AstroNvim/astroui",
      optional = true,
      ---@type AstroUIOpts
      -- The <Leader>M group icon came from the astrocommunity pack dropped in
      -- community.lua; astroui ships no Markdown icon of its own.
      opts = { icons = { Markdown = "" } },
    },
    {
      "AstroNvim/astrocore",
      optional = true,
      ---@type AstroCoreOpts
      opts = function(_, opts)
        local maps = opts.mappings
        local prefix = "<Leader>M"

        maps.n[prefix] = { desc = require("astroui").get_icon("Markdown", 1, true) .. "Markdown" }
        -- Safe to press repeatedly: starts the preview the first time and
        -- retargets the existing tab every time after, so it never opens a
        -- second window.
        maps.n[prefix .. "p"] = { "<Cmd>MarkdownPreview<CR>", desc = "Preview (open or retarget)" }
        maps.n[prefix .. "s"] = { "<Cmd>MarkdownPreviewStop<CR>", desc = "Stop preview" }
        -- For what auto-refresh misses: an included image changing on disk, or
        -- a stylesheet edit (which needs a stop/start, see overwrite_index_on_start).
        maps.n[prefix .. "r"] = { "<Cmd>MarkdownPreviewRefresh<CR>", desc = "Refresh preview" }
        -- <Leader>Mt (toggle) is retired: this plugin has no toggle command, and
        -- faking one would mean reading a private field on a young plugin.
        -- <Leader>Mp subsumes it now that re-running retargets rather than
        -- duplicating.
      end,
    },
  },
}
