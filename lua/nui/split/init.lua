local Object = require("nui.object")
local buf_storage = require("nui.utils.buf_storage")
local autocmd = require("nui.utils.autocmd")
local keymap = require("nui.utils.keymap")
local utils = require("nui.utils")
local split_utils = require("nui.split.utils")

local u = {
  clear_namespace = utils._.clear_namespace,
  get_next_id = utils._.get_next_id,
  normalize_namespace_id = utils._.normalize_namespace_id,
  split = split_utils,
}

local split_direction_command_map = {
  editor = {
    top = "topleft",
    right = "vertical botright",
    bottom = "botright",
    left = "vertical topleft",
  },
  win = {
    top = "aboveleft",
    right = "vertical rightbelow",
    bottom = "belowright",
    left = "vertical leftabove",
  },
}

---@param winid integer
---@param win_config _nui_split_internal_win_config
local function move_split_window(winid, win_config)
  if win_config.relative == "editor" then
    vim.api.nvim_win_call(winid, function()
      vim.cmd("wincmd " .. ({ top = "K", right = "L", bottom = "J", left = "H" })[win_config.position])
    end)
  elseif win_config.relative == "win" then
    local move_options = {
      vertical = win_config.position == "left" or win_config.position == "right",
      rightbelow = win_config.position == "bottom" or win_config.position == "right",
    }

    vim.cmd(
      string.format(
        "noautocmd call win_splitmove(%s, %s, #{ vertical: %s, rightbelow: %s })",
        winid,
        win_config.win,
        move_options.vertical and 1 or 0,
        move_options.rightbelow and 1 or 0
      )
    )
  end
end

---@param winid integer
---@param win_config _nui_split_internal_win_config
local function set_win_config(winid, win_config)
  if win_config.pending_changes.position then
    move_split_window(winid, win_config)
  end

  if win_config.pending_changes.size then
    if win_config.width then
      vim.api.nvim_win_set_width(winid, win_config.width)
    elseif win_config.height then
      vim.api.nvim_win_set_height(winid, win_config.height)
    end
  end

  win_config.pending_changes = {}
end

--luacheck: push no max line length

---@alias nui_split_option_relative_type 'editor'|'win'
---@alias nui_split_option_relative { type: nui_split_option_relative_type, winid?: number }

---@alias nui_split_option_position "'top'"|"'right'"|"'bottom'"|"'left'"

---@alias nui_split_option_size { height?: number|string }|{ width?: number|string }

---@alias _nui_split_internal_relative { type: nui_split_option_relative_type, win: number }
---@alias _nui_split_internal_win_config { height?: number, width?: number, position: nui_split_option_position, relative: nui_split_option_relative, win?: integer, pending_changes: table<'position'|'size', boolean> }

--luacheck: pop

---@class nui_split_internal
---@field enter? boolean
---@field loading boolean
---@field mounted boolean
---@field buf_options table<string, any>
---@field win_options table<string, any>
---@field position nui_split_option_position
---@field relative _nui_split_internal_relative
---@field size { height?: number }|{ width?: number }
---@field win_config _nui_split_internal_win_config
---@field pending_quit? boolean
---@field augroup table<'hide'|'unmount', string>

---@class nui_split_options
---@field ns_id? string|integer
---@field relative? nui_split_option_relative_type|nui_split_option_relative
---@field position? nui_split_option_position
---@field size? number|string|nui_split_option_size
---@field enter? boolean
---@field buf_options? table<string, any>
---@field win_options? table<string, any>

---@class NuiSplit
---@field private _ nui_split_internal
---@field bufnr integer
---@field ns_id integer
---@field winid number
local Split = Object("NuiSplit")

---@param options nui_split_options
function Split:init(options)
  local id = u.get_next_id()

  options = u.split.merge_default_options(options)
  options = u.split.normalize_options(options)

  self._ = {
    id = id,
    enter = options.enter,
    buf_options = options.buf_options,
    loading = false,
    mounted = false,
    layout = {},
    position = options.position,
    size = {},
    win_options = options.win_options,
    win_config = {
      pending_changes = {},
    },
    augroup = {
      hide = string.format("%s_hide", id),
      unmount = string.format("%s_unmount", id),
    },
  }

  self.ns_id = u.normalize_namespace_id(options.ns_id)

  self:_buf_create()

  self:update_layout(options)
end

--luacheck: push no max line length

---@param config { relative?: nui_split_option_relative_type|nui_split_option_relative, position?: nui_split_option_position, size?: number|string|nui_split_option_size }
function Split:update_layout(config)
  config = config or {}

  u.split.update_layout_config(self._, config)

  if self.winid then
    set_win_config(self.winid, self._.win_config)
  end
end

--luacheck: pop

function Split:_open_window()
  if self.winid or not self.bufnr then
    return
  end

  self.winid = vim.api.nvim_win_call(self._.relative.type == "editor" and 0 or self._.relative.win, function()
    vim.api.nvim_command(
      string.format(
        "silent noswapfile %s %ssplit",
        split_direction_command_map[self._.relative.type][self._.position],
        self._.size.width or self._.size.height or ""
      )
    )

    return vim.api.nvim_get_current_win()
  end)

  vim.api.nvim_win_set_buf(self.winid, self.bufnr)

  if self._.enter then
    vim.api.nvim_set_current_win(self.winid)
  end

  self._.win_config.pending_changes = { size = true }
  set_win_config(self.winid, self._.win_config)

  utils._.set_win_options(self.winid, self._.win_options)
end

function Split:_close_window()
  if not self.winid then
    return
  end

  if vim.api.nvim_win_is_valid(self.winid) and not self._.pending_quit then
    vim.api.nvim_win_close(self.winid, true)
  end

  self.winid = nil
end

function Split:_buf_create()
  if not self.bufnr then
    self.bufnr = vim.api.nvim_create_buf(false, true)
    assert(self.bufnr, "failed to create buffer")
  end
end

function Split:mount()
  if self._.loading or self._.mounted then
    return
  end

  self._.loading = true

  autocmd.create_group(self._.augroup.hide, { clear = true })
  autocmd.create_group(self._.augroup.unmount, { clear = true })
  autocmd.create("QuitPre", {
    group = self._.augroup.unmount,
    buffer = self.bufnr,
    callback = function()
      self._.pending_quit = true
      vim.schedule(function()
        self:unmount()
        self._.pending_quit = nil
      end)
    end,
  }, self.bufnr)
  autocmd.create("BufWinEnter", {
    group = self._.augroup.unmount,
    buffer = self.bufnr,
    callback = function()
      -- When two splits using the same buffer and both of them
      -- are hidden, calling `:show` for one of them fires
      -- `BufWinEnter` for both of them. And in that scenario
      -- one of them will not have `self.winid`.
      if self.winid then
        autocmd.create("WinClosed", {
          group = self._.augroup.hide,
          pattern = tostring(self.winid),
          callback = function()
            self:hide()
          end,
        }, self.bufnr)
      end
    end,
  }, self.bufnr)

  self:_buf_create()

  utils._.set_buf_options(self.bufnr, self._.buf_options)

  self:_open_window()

  self._.loading = false
  self._.mounted = true
end

function Split:hide()
  if self._.loading or not self._.mounted then
    return
  end

  self._.loading = true

  pcall(autocmd.delete_group, self._.augroup.hide)

  self:_close_window()

  self._.loading = false
end

function Split:show()
  if self._.loading then
    return
  end

  if not self._.mounted then
    return self:mount()
  end

  self._.loading = true

  autocmd.create_group(self._.augroup.hide, { clear = true })

  self:_open_window()

  self._.loading = false
end

function Split:_buf_destroy()
  if self.bufnr then
    if vim.api.nvim_buf_is_valid(self.bufnr) then
      u.clear_namespace(self.bufnr, self.ns_id)

      if not self._.pending_quit then
        vim.api.nvim_buf_delete(self.bufnr, { force = true })
      end
    end

    buf_storage.cleanup(self.bufnr)

    self.bufnr = nil
  end
end

function Split:unmount()
  if self._.loading or not self._.mounted then
    return
  end

  self._.loading = true

  pcall(autocmd.delete_group, self._.augroup.hide)
  pcall(autocmd.delete_group, self._.augroup.unmount)

  self:_buf_destroy()

  self:_close_window()

  self._.loading = false
  self._.mounted = false
end

-- set keymap for this split
---@param mode string check `:h :map-modes`
---@param key string|string[] key for the mapping
---@param handler string | fun(): nil handler for the mapping
---@param opts? table<"'expr'"|"'noremap'"|"'nowait'"|"'remap'"|"'script'"|"'silent'"|"'unique'", boolean>
---@return nil
function Split:map(mode, key, handler, opts, ___force___)
  if not self.bufnr then
    error("split buffer not found.")
  end

  return keymap.set(self.bufnr, mode, key, handler, opts, ___force___)
end

---@param mode string check `:h :map-modes`
---@param key string|string[] key for the mapping
---@return nil
function Split:unmap(mode, key)
  if not self.bufnr then
    error("split buffer not found.")
  end

  return keymap._del(self.bufnr, mode, key)
end

---@param event string | string[]
---@param handler string | function
---@param options? table<"'once'" | "'nested'", boolean>
function Split:on(event, handler, options)
  if not self.bufnr then
    error("split buffer not found.")
  end

  autocmd.buf.define(self.bufnr, event, handler, options)
end

---@param event? string | string[]
function Split:off(event)
  if not self.bufnr then
    error("split buffer not found.")
  end

  autocmd.buf.remove(self.bufnr, nil, event)
end

---@alias NuiSplit.constructor fun(options: nui_split_options): NuiSplit
---@type NuiSplit|NuiSplit.constructor
local NuiSplit = Split

return NuiSplit
