vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf

    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
    end

    map("n", "gd", vim.lsp.buf.definition, "LSP: definition")
    map("n", "gD", vim.lsp.buf.declaration, "LSP: declaration")
    map("n", "gr", vim.lsp.buf.references, "LSP: references")
    map("n", "gi", vim.lsp.buf.implementation, "LSP: implementation")
    map("n", "K", vim.lsp.buf.hover, "LSP: hover")
    map("n", "<leader>rn", vim.lsp.buf.rename, "LSP: rename")
    map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "LSP: code action")

    map("n", "<leader>f", function()
      vim.lsp.buf.format({ async = true })
    end, "LSP: format")
  end,
})
