local hls_cmd = nil
if vim.fn.executable("haskell-language-server-wrapper") == 1 then
  hls_cmd = "haskell-language-server-wrapper"
elseif vim.fn.executable("haskell-language-server") == 1 then
  hls_cmd = "haskell-language-server"
else
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { hls_cmd, "--lsp" },
  filetypes = { "haskell", "lhaskell" },
  root_markers = {
    "hie.yaml",
    "stack.yaml",
    "cabal.project",
    ".git",
  },
}
