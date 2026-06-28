if vim.fn.executable("vscode-json-language-server") == 0 then
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { "vscode-json-language-server", "--stdio" },
  filetypes = { "json", "jsonc" },
}
