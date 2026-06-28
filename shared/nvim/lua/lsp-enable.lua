local function enable_all_lsps()
  local lsp_dir = vim.fn.stdpath("config") .. "/lsp"
  local enabled_servers = {}

  local handle = vim.loop.fs_scandir(lsp_dir)
  if not handle then
    return
  end

  while true do
    local name, entry_type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    if entry_type == "file" and name:sub(-4) == ".lua" then
      local server = name:sub(1, -5) -- strip .lua
      local path = lsp_dir .. "/" .. name
      local ok, config = pcall(dofile, path)
      if ok and type(config) == "table" then
        vim.lsp.config(server, config)
        table.insert(enabled_servers, server)
      end
    end
  end

  if #enabled_servers > 0 then
    vim.lsp.enable(enabled_servers)
  end
end

enable_all_lsps()
