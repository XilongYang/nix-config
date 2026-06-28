if vim.fn.executable("typescript-language-server") == 0 then
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { "typescript-language-server", "--stdio" },

  filetypes = {
    "typescript",
    "typescriptreact",
    "typescript.tsx",
    "javascript",
    "javascriptreact",
    "javascript.jsx",
    "mjs",
    "cjs",
  },

  root_markers = {
    "package.json",
    "tsconfig.json",
    "jsconfig.json",
    ".git",
  },

  init_options = {
    hostInfo = "neovim",
  },
}
