if vim.fn.executable("clangd") == 0 then
  return nil
end

---@type vim.lsp.Config
return {
  cmd = {
    "clangd",
    "--background-index",
    "--clang-tidy",
    "--completion-style=detailed",
    "--header-insertion=iwyu",
    "--pch-storage=memory",
    "--function-arg-placeholders=true",
    "--query-driver=/nix/store/*/bin/clang,/nix/store/*/bin/gcc",
  },
  root_markers = { "compile_commands.json", "compile_flags.txt", ".git", "CMakeLists.txt" },
  filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
}
