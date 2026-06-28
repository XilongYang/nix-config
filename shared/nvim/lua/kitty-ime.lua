local M = {}

local values = {
  insert = "aW5zZXJ0",
  normal = "bm9ybWFs",
}

local last_sent

local function is_kitty()
  return vim.env.KITTY_WINDOW_ID ~= nil or (vim.env.TERM or ""):find("kitty", 1, true) ~= nil
end

function M.send(mode, force)
  if not is_kitty() or values[mode] == nil then
    return
  end

  if not force and last_sent == mode then
    return
  end

  last_sent = mode
  local seq = "\x1b]1337;SetUserVar=NVIM_MODE=" .. values[mode] .. "\x07"

  io.stdout:write(seq)
  io.stdout:flush()
end

function M.setup()
  local group = vim.api.nvim_create_augroup("KittyNvimIme", { clear = true })

  vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter" }, {
    group = group,
    callback = function()
      M.send(vim.fn.mode():sub(1, 1) == "i" and "insert" or "normal", true)
    end,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      M.send(vim.v.event.new_mode:sub(1, 1) == "i" and "insert" or "normal")
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertEnter" }, {
    group = group,
    callback = function()
      M.send("insert")
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertLeave" }, {
    group = group,
    callback = function()
      M.send("normal", true)
    end,
  })
end

return M
