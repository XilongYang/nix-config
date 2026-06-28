if vim.fn.executable("nixd") == 0 then
  return nil
end

---@type vim.lsp.Config
return {
  cmd = { "nixd" },
  filetypes = { "nix" },

  root_markers = {
    "flake.nix",
    "default.nix",
    "shell.nix",
    ".git",
  },
}
