local M = {}

local values = {
  insert = "aW5zZXJ0",
  normal = "bm9ybWFs",
}

-- Mode flapping (telescope prompts, cmp, snippet jumps, feedkeys) produces
-- bursts of insert<->normal transitions. Switching the system input source is
-- slow and asynchronous, so forward only the settled mode.
local DEBOUNCE_MS = 60

local timer = vim.uv.new_timer()
local pending_mode
local applied_mode

local function is_kitty()
  return vim.env.TMUX ~= nil
    or vim.env.KITTY_WINDOW_ID ~= nil
    or (vim.env.TERM or ""):find("kitty", 1, true) ~= nil
end

local function passthrough(seq)
  if vim.env.TMUX == nil then
    return seq
  end

  return "\x1bPtmux;\x1b" .. seq .. "\x1b\\"
end

local function write(mode)
  applied_mode = mode
  local seq = "\x1b]1337;SetUserVar=NVIM_MODE=" .. values[mode] .. "\x07"

  io.stdout:write(passthrough(seq))
  io.stdout:flush()
end

local function flush()
  if pending_mode and pending_mode ~= applied_mode then
    write(pending_mode)
  end
  pending_mode = nil
end

function M.send(mode, force)
  if not is_kitty() or values[mode] == nil then
    return
  end

  if force then
    timer:stop()
    pending_mode = nil
    write(mode)
    return
  end

  pending_mode = mode
  timer:stop()
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(flush))
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
end

return M
