local M = {}

local function run(pattern)
  local escaped = vim.fn.shellescape(pattern)
  local has_rg = vim.fn.executable("rg") == 1
  local cmd = has_rg
    and ("rg --vimgrep --smart-case " .. escaped)
    or  ("grep -rn --exclude-dir=.git " .. escaped .. " .")
  local lines = vim.fn.systemlist(cmd)
  if #lines == 0 then return {} end

  local results = {}
  for _, line in ipairs(lines) do
    local file, lnum, col, text
    if has_rg then
      file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)")
    else
      -- grep -rn has no column number
      file, lnum, text = line:match("^(.-):(%d+):(.*)")
      col = 1
    end
    if file then
      table.insert(results, { file = file, lnum = tonumber(lnum), col = tonumber(col), display = line })
    end
  end
  return results
end

local function highlight(buf, results)
  vim.api.nvim_set_hl(0, "GrepFile", { fg = "#89b4fa", bold = true })
  vim.api.nvim_set_hl(0, "GrepLnum", { fg = "#a6e3a1" })
  vim.api.nvim_set_hl(0, "GrepSep",  { fg = "#585b70" })

  for i, r in ipairs(results) do
    local l = i - 1
    local line = r.display
    -- file
    local fs, fe = 0, #r.file
    vim.api.nvim_buf_add_highlight(buf, -1, "GrepFile", l, fs, fe)
    -- first colon after file
    local sep1 = fe
    vim.api.nvim_buf_add_highlight(buf, -1, "GrepSep", l, sep1, sep1 + 1)
    -- lnum
    local lnum_str = tostring(r.lnum)
    local ls = sep1 + 1
    vim.api.nvim_buf_add_highlight(buf, -1, "GrepLnum", l, ls, ls + #lnum_str)
  end
end

function M.grep()
  local pattern = vim.fn.input("Search: ")
  if pattern == "" then return end

  local results = run(pattern)
  if #results == 0 then
    vim.notify("No results for: " .. pattern, vim.log.levels.WARN)
    return
  end

  local lines = vim.tbl_map(function(r) return r.display end, results)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
  local width  = math.floor(vim.o.columns * 0.82)
  local row    = math.floor((vim.o.lines - height) / 2 - 1)
  local col    = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    border    = "rounded",
    title     = " Search: " .. pattern .. " ",
    title_pos = "center",
    style     = "minimal",
  })
  vim.wo[win].cursorline = true

  highlight(buf, results)

  local function jump()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local r   = results[idx]
    vim.api.nvim_win_close(win, true)
    vim.cmd("edit " .. vim.fn.fnameescape(r.file))
    vim.api.nvim_win_set_cursor(0, { r.lnum, r.col - 1 })
  end

  local o = { buffer = buf, nowait = true }
  vim.keymap.set("n", "<CR>",  jump, o)
  vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true) end, o)
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, o)
end

return M
