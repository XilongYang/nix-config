if vim.fn.executable("bash-language-server") == 0 then
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { "bash-language-server", "start" },
  filetypes = { "sh", "bash" },
}
