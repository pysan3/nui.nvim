local utils = {
  -- internal utils
  _ = {},
}

function utils.get_editor_size()
  return {
    width = vim.o.columns,
    height = vim.o.lines,
  }
end

function utils.get_window_size(winid)
  winid = winid or 0
  return {
    width = vim.api.nvim_win_get_width(winid),
    height = vim.api.nvim_win_get_height(winid),
  }
end

function utils.defaults(v, default_value)
  return type(v) == "nil" and default_value or v
end

-- luacheck: push no max comment line length
---@param type_name "'nil'" | "'number'" | "'string'" | "'boolean'" | "'table'" | "'function'" | "'thread'" | "'userdata'" | "'list'" | '"map"'
function utils.is_type(type_name, v)
  if type_name == "list" then
    return vim.tbl_islist(v)
  end

  if type_name == "map" then
    return type(v) == "table" and not vim.tbl_islist(v)
  end

  return type(v) == type_name
end
-- luacheck: pop

---@param v string | number
function utils.parse_number_input(v)
  local parsed = {}

  parsed.is_percentage = type(v) == "string" and string.sub(v, -1) == "%"

  if parsed.is_percentage then
    parsed.value = tonumber(string.sub(v, 1, #v - 1)) / 100
  else
    parsed.value = tonumber(v)
  end

  return parsed
end

---@private
---@param bufnr number
---@param linenr number line number (1-indexed)
---@param char_start number start character position (0-indexed)
---@param char_end number end character position (0-indexed)
---@return number[] byte_range
function utils._.char_to_byte_range(bufnr, linenr, char_start, char_end)
  local line = vim.api.nvim_buf_get_lines(bufnr, linenr - 1, linenr, false)[1]
  local skipped_part = vim.fn.strcharpart(line, 0, char_start)
  local target_part = vim.fn.strcharpart(line, char_start, char_end - char_start)

  local byte_start = vim.fn.strlen(skipped_part)
  local byte_end = math.min(byte_start + vim.fn.strlen(target_part), vim.fn.strlen(line))
  return { byte_start, byte_end }
end

---@private
---@param bufnr number
---@param buf_options table<string, any>
function utils._.set_buf_options(bufnr, buf_options)
  for name, value in pairs(buf_options) do
    vim.api.nvim_buf_set_option(bufnr, name, value)
  end
end

---@private
---@param winid number
---@param win_options table<string, any>
function utils._.set_win_options(winid, win_options)
  for name, value in pairs(win_options) do
    vim.api.nvim_win_set_option(winid, name, value)
  end
end

---@private
---@param dimension number | string
---@param container_dimension number
---@return nil | number
function utils._.normalize_dimension(dimension, container_dimension)
  local number = utils.parse_number_input(dimension)

  if not number.value then
    return nil
  end

  if number.is_percentage then
    return math.floor(container_dimension * number.value)
  end

  return number.value
end

---@param text string
---@param max_length number
---@return string
function utils._.truncate_text(text, max_length)
  if vim.api.nvim_strwidth(text) > max_length then
    return string.sub(text, 1, max_length - 1) .. "…"
  end

  return text
end

---@param text string
---@param align "'left'" | "'center'" | "'right'"
---@param line_length number
---@param gap_char string
---@return string
function utils._.align_text(text, align, line_length, gap_char)
  local gap_length = line_length - vim.api.nvim_strwidth(text)

  local gap_left = ""
  local gap_right = ""

  if align == "left" then
    gap_right = string.rep(gap_char, gap_length)
  elseif align == "center" then
    gap_left = string.rep(gap_char, math.floor(gap_length / 2))
    gap_right = string.rep(gap_char, math.ceil(gap_length / 2))
  elseif align == "right" then
    gap_left = string.rep(gap_char, gap_length)
  end

  return gap_left .. text .. gap_right
end

return utils
