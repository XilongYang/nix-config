if vim.fn.executable("vscode-css-language-server") == 0 then
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { "vscode-css-language-server", "--stdio" },
  filetypes = { "css", "scss", "less" },
}
