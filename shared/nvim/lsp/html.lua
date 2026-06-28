if vim.fn.executable("vscode-html-language-server") == 0 then
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { "vscode-html-language-server", "--stdio" },
  filetypes = { "html" },
}
