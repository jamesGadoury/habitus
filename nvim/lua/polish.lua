-- Runs last in the setup process (see init.lua): plain Lua that doesn't
-- belong in a plugin spec.

-- Padded, outlined LSP popups; see lua/lsp_float.lua.
require("lsp_float").setup()
