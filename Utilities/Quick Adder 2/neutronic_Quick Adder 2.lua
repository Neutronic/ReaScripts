--[[
Description: Quick Adder 2
About: Adds FX to selected tracks or takes and inserts track templates.
Version: 2.34
Author: Neutronic
Donation: https://paypal.me/SIXSTARCOS
License: GNU GPL v3
Links:
  Neutronic's REAPER forum profile https://forum.cockos.com/member.php?u=66313
  Quick Adder 2 forum thread https://forum.cockos.com/showthread.php?t=232928
  Quick Adder 2 video demo http://bit.ly/seeQA2
Changelog:
  + LeftWin + Alt + Enter: insert FX on a new track above the first selected track
    or the track under mouse cursor (Ctrl + Option + Return on macOS)
  # ignore "Auto-float newly created FX windows" in REAPER preferences
--]]

local rpr = {}
local scr = {}

rpr.x64 = reaper.GetAppVersion():match(".-/%D-(64)") and true or nil

local cur_os = reaper.GetOS()
local os_is = {win = cur_os:lower():match("win") and true or false,
               mac = cur_os:lower():match("osx") and true or false,
               lin = cur_os:lower():match("other") and true or false}

function getContent(path)
  local file = io.open(path)
  if not file then return end
  local content = file:read("*a")
  file:close()
  return content
end

function findContentKey(content, key, self)
  if self then
    content = content:match("%-%-%[%[.-%-%-%]%]")
    for match in content:gmatch("(%w.-:.-)\n") do
      local key, val = match:match("(.-): (.+)")
      if val and not val:match("http") then scr[key:lower()] = val end
    end
    scr.links = {}
    for match in content:gmatch("(http.-)\n") do
      table.insert(scr.links, match)
    end
    return
  else
    content = content:match(key .. "[:=].-\n")
  end
  
  if not content and key:match("vstpath") then
    content = os_is.win and
    (rpr.x64 and os.getenv("ProgramFiles(x86)").."\\vstplugins;" or "").. 
    os.getenv("ProgramFiles").."\\vstplugins;"..
    os.getenv("CommonProgramFiles").."\\VST3\n" or
    os_is.mac and
    "/Library/Audio/Plug-Ins/VST;/Library/Audio/Plug-Ins/VST3;"..
    os.getenv("HOME").."/Library/Audio/Plug-Ins/VST;"..
    os.getenv("HOME").."/Library/Audio/Plug-Ins/VST3\n"
  end
  return content and content:gsub(key.. "[:=]%s?", "") or false
end

scr.path = select(2, reaper.get_action_context())
scr.dir = scr.path:match(".+[\\/]")
scr.no_ext = scr.path:match("(.+)%.")
scr.config = scr.no_ext .. "_cfg"
scr.fav = scr.no_ext .. "_fav"
scr.plugs = scr.no_ext .. "_db"
findContentKey(getContent(scr.path), "", true)
scr.name = "Quick Adder v" .. scr.version .. "  |  Neutronic"
scr.actions = {}

rpr.ver = tonumber(reaper.GetAppVersion():match("[%d%.]+"))

if rpr.ver < 5.985 then
  reaper.MB("This script is designed to work with REAPER v5.985+", scr.name, 0)
  return
end

if reaper.GetExtState("Quick Adder", "MSG") ~= "1" then
  reaper.SetExtState("Quick Adder", "MSG", 1, false)
else
  reaper.SetExtState("Quick Adder", "MSG", "reopen", false)
  return
end

local _timers = {}
local db = {}
local gui = {}

rpr.path = reaper.GetResourcePath():gsub("\\", "/")

function getResolution(wantWorkArea)
  local _, _ , vp_w, vp_h = reaper.my_getViewport(0,0,0,0,0,0,0,0, wantWorkArea)
  return vp_w, vp_h
end

local res_multi = {["|720p"] = 1,
             ["|1080p"] = 1.4,
             ["|4k"] = 2.82,
             ["|5k"] = 3.8,
             ["|8k"] = 4.8
            }

function getResolutionMulti()
  local h = select(2, getResolution(false))
  if h >= 4320 then -- 8k and up
    return res_multi["|8k"]
  elseif h >= 2880 then -- 5k and up
    return res_multi["|5k"]
  elseif h >= 2160 then -- 4k and up
    return res_multi["|4k"]
  elseif h >= 1080 then -- full HD and up
    return res_multi["|1080p"]
  else -- lower than full HD
    return res_multi["|720p"]
  end
end

function parseKeyVal(key)
  local tbl = {}
  for cap in key:gmatch("(.-)[;,\n]") do
    table.insert(tbl, cap)
  end
  return tbl  
end

if rpr.x64 then
  rpr.vst = rpr.path .. "/reaper-vstplugins64.ini"
  if os_is.mac then
    rpr.au = rpr.path .. "/reaper-auplugins64.ini"
  end
else
  rpr.vst = rpr.path .. "/reaper-vstplugins.ini"
  if os_is.mac then
    rpr.au = rpr.path .. "/reaper-auplugins.ini"
  end
end

rpr.fx_folders = rpr.path .. "/reaper-fxfolders.ini"
         
local white_ch = {del = 6579564,
                  bs = 8}
local ignore_ch = {quit = -1,
                   no_ch = 0,
                   enter = 13,
                   tab = 9,
                   esc = 27,
                   dot = 46,
                   --colon = 58,
                   comma = 44,
                   semicolon = 59,
                   vert_bar = 124,
                   backslash = 92,
                   left = 1818584692,
                   right = 1919379572,
                   up = 30064,
                   down = 1685026670,
                   home = 1752132965,
                   end_key = 6647396,
                   tilde = 96,
                   f1 = 26161,
                   f2 = 26162,
                   f3 = 26163,
                   f4 = 26164,
                   f5 = 26165,
                   f6 = 26166,
                   f7 = 26167,
                   f8 = 26168,
                   f9 = 26169,
                   f10 = 6697264}

local mouse_mod = {ctrl = 4,
            shift = 8,
            alt = 16,
            lmb = 1,
            rmb = 2,
            win = 32,
            mmb = 64,
            no_mod = 0,
            [1] = "LMB",
            [2] = "RMB",
            [4] = function()return os_is.mac and (literal and "Command" or utf8.char(8984)) or "Ctrl" end,
            [8] = function()return os_is.mac and not literal and utf8.char(8679) or "Shift" end,
            [16] = function()return os_is.mac and (literal and "Option" or utf8.char(8997)) or "Alt" end,
            [32] = function()return os_is.mac and (literal and "Control" or "^") or "Win" end,
            [64] = "MMB",
            [0] = "No Mod"
            }
            
mouse_mod.clear = mouse_mod.ctrl
mouse_mod.input = mouse_mod.shift
mouse_mod.track = mouse_mod.no_mod
mouse_mod.take = mouse_mod.alt
mouse_mod.dds = mouse_mod.ctrl + mouse_mod.shift + mouse_mod.alt -- drag and drop send
local enter = os_is.mac and "Return" or "Enter"

local keep_state_names = {
                    {"ISBUS", "Folder state"},
                    {"GROUP_FLAGS", "Grouping"},
                    {"TRACKHEIGHT", "Height"},
                    {"ITEMS", "Items"},
                    {"LAYOUTS", "Layouts"},
                    {"MAINSEND", "Master send"},
                    {"MUTESOLO", "Mute and solo"},
                    {"NAME", "Name"},
                    {"REC", "Record arm"},
                    {"VOLPAN", "Volume and pan"}}

function doFile(str)
  dofile(str)
end

function magicFix(str)
  return str:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
end

function escSeqFix(str)
  return str:gsub("[\a\b\f\n\r\v\0]", ""):gsub("[\'\"\\]", "\\%0")
end

function a_macYoffset()end
function macYoffset(cur_h, new_h, y)
  if not cur_h then return y end
  if os_is.mac then
    y = y + cur_h - new_h
  else
    y = y
  end
  return y
end

function tableToString(name, tbl, escape)
  local str = name .. " = {\n"
  
  local tbl_sorted = {}
  for n in pairs(tbl) do
    table.insert(tbl_sorted, tostring(n))
  end
  table.sort(tbl_sorted)
  
  function keyParse(k, mode)
    local k_temp = tonumber(k)
    if k_temp then
      return k_temp
    elseif mode == 1 then
      return k
    elseif mode == 2 then
      return '"' .. k .. '"'
    end
  end
  
  function valueParse(v)
    if type(v) == "string" then
      return '"' .. escSeqFix(v) ..  '"'
    elseif type(v) == "boolean" then
      return tostring(v)
    else
      return v
    end
  end
  
  for i = 1, #tbl_sorted do
    str = str .. '\t[' .. keyParse(tbl_sorted[i], 2) .. '] = ' ..
          valueParse(tbl[keyParse(tbl_sorted[i], 1)]) .. ",\n" 
  end
  str = (str:match("(.+),\n") or str:match("(.+)\n")) .. "\n}\n"
  return str
end

function writeFile(path, str, manual)
  local f = assert(io.open(path, manual or "w"))
  f:write(str)
  f:close()
end

function getFXfolder(str, type_n)
  local fx_folder = ""
  
  if not str then return fx_folder end
  
  if config and not config.fol_search then return fx_folder end
  
  if type_n == 3 then -- if VST
    local vst_id, vst_file = str:match("(.-)//(.+)")
    for i = 1, fx_folders and #fx_folders or 0 do
      if fx_folders[i].content and (fx_folders[i].content:match(vst_id) or
         fx_folders[i].content:gsub("[^%w%.\n\r]", "_"):match(vst_file .. "[\n\r]")) then
        fx_folder = fx_folder .. "\t" .. fx_folders[i].name
      end
    end
  else
    for i = 1, fx_folders and #fx_folders or 0 do
      if fx_folders[i].content and fx_folders[i].content:match("Item%d+=" .. magicFix(str)) then
        local fx_n = fx_folders[i].content:match("Item(%d+)=" .. magicFix(str))
        if fx_folders[i].content:match("Type" .. fx_n .. "=" .. type_n) then
          fx_folder = fx_folder .. "\t" .. fx_folders[i].name
        end
      end
    end
  end
  
  return fx_folder
end

function listDir(path)
  local dir_list = {}
  local i = 0
  while not dir do
    local dir = reaper.EnumerateSubdirectories(path, i)
    if not dir or dir:match(".+%.component")
       or dir:match(".+%.vst%d?") then break end
    local path = path .. "/" .. dir
    table.insert(dir_list, path)
    local subdir_list = listDir(path)
    for i = 1, #subdir_list do
      table.insert(dir_list, subdir_list[i])
    end
    i = i + 1
  end
  return dir_list
end

function listFiles(path, ext)
  local file_list = {}
  local i = 0
  while not file do
    local path = not path:match("/$") and path .. "/" or path:match("/$") and path
    local file = reaper.EnumerateFiles(path, i)
    if not file then break end
    
    --file = escSeqFix(file)
    
    if file:match("[^%.]-$") == ext then
      if ext == "RfxChain" and not path:match("/FXChains/") then goto SKIP end
      file = file:gsub("%." .. ext, "")
      local fx_type = ext == "RfxChain" and "CHAIN" or ext == "RTrackTemplate" and "TEMPLATE"
      if rpr.def_fx_filt and ext == "RfxChain" and fxExclCheck(fx_type .. ":" .. file:lower()) then goto SKIP end
      if rpr.def_fx_filt and ext == "RfxChain" and not fxExclCheck(fx_type .. ":" .. file:lower(), true) then goto SKIP end
      
      local fx_folder = getFXfolder(file, 1000)
      
      table.insert(file_list, fx_type .. ":" .. file .. fx_folder .. "|,|" .. [[]] .. path .. [[]] .. "|,||,||,|")
      ::SKIP::
    elseif file:match("^.+jsfx$") or not ext and
           (not file:match("%.") or file:match("%d%.%d")) then -- if JS
      table.insert(file_list, path .. file)
    end
    i = i + 1
  end
  return file_list
end

function getFiles(match, ext)
  local dir_list = {}
  local file_list = {}

  local dir_list = {}
  local i = 0
  while not dir do
    local dir = reaper.EnumerateSubdirectories(rpr.path, i)
    if not dir then break end
    if dir:match("^"..match..(match and not ext and "$" or "")) then
    local path = rpr.path .. "/" .. dir-- .. "/"
      table.insert(dir_list, path)
      local subdir_list = listDir(path)
      for i = 1, #subdir_list do
        table.insert(dir_list, subdir_list[i])
      end
    end
    i = i + 1
  end
   
  for i = 1, #dir_list do
    local file = listFiles(dir_list[i], ext)
    for i = 1, #file do
      table.insert(file_list, file[i])
    end
  end
  
  return file_list
end

function getFxDir(path)
  local dir_list
  for i = 1, #path do
    if i == 1 then
      dir_list = listDir(path[i])
      table.insert(dir_list, 1, path[i])
    else
      local dir_list2 = listDir(path[i])
      table.insert(dir_list2, 1, path[i])
      for i, v in ipairs(dir_list2) do dir_list[#dir_list+1] = v end
    end
  end
  return dir_list
end

function a_config() end

function initGlobalTypesOrder()
  global_types = {CHAIN = true,
                  VST2 = true,
                  VST3 = true,
                  JS = true,
                  AU = os_is.mac and true or nil,
                  ACTION = config.act_search and true or nil,
                  TEMPLATE = true}

  for k in pairs(global_types) do
    config.global_types_n = config.global_types_n + 1
  end
  
  function getGlobalType(str)
    if global_types[str] then
      return str
    end
  end
  
  global_types_order = {getGlobalType("CHAIN"),
                        getGlobalType("AU"),
                        getGlobalType("VST2"),
                        getGlobalType("VST3"),
                        getGlobalType("JS"),
                        getGlobalType("TEMPLATE"),
                        getGlobalType("ACTION")}
  
  function sortTable(tbl)
    local tbl_temp = {}
    for i = 1, #tbl do
      if tbl[i] then
        table.insert(tbl_temp, tbl[i])
      end
    end
    tbl = tbl_temp
    return tbl
  end
  
  global_types_order = sortTable(global_types_order)
end

if not pcall(doFile, scr.config) then
  config = {multi = getResolutionMulti(),
            --wnd_w = 372,
            row_h = 37,
            theme = rpr.ver < 6 and "light" or "dark",
            mode = "ALL",
            pin = true,
            reminder = true,
            results_max = 5,
            global_types_n = 0,
            os = cur_os,
            db_scan = 1,
            --wnd_w_prefs = 424,
            search_delay = 0,
            float_mode = 4,
           }
                  
  initGlobalTypesOrder()  
  
  keep_states = { -- what original track info to preserve when applying track templates
  GROUP_FLAGS = true, -- track group membership
  ISBUS = true, -- folder states (affects only templates containing a single track)
  ITEMS = true, -- track items
  LAYOUTS = true, -- track TCP + MCP layouts
  MAINSEND = true, -- master send / parent channels
  MUTESOLO = false, -- mute / solo
  NAME = false, -- track name
  REC = true, -- track record arm status / input / monitoring
  TRACKHEIGHT = true, -- track height
  VOLPAN = false -- volume / pan
  }
   
  keep_states.GROUP_FLAGS_HIGH = keep_states.GROUP_FLAGS
end

if config.db_scan == 2 then
  db.saved = false
elseif config.db_scan == 1 and reaper.GetExtState("Quick Adder", "SCAN") ~= "1" then
  db.saved = false
  reaper.SetExtState("Quick Adder", "SCAN", "1", false)
elseif config.db_scan == 3 or reaper.GetExtState("Quick Adder", "SCAN") == "1" then
  db.saved = pcall(doFile, scr.plugs)
end

config.dbl_click_speed = config.dbl_click_speed and config.dbl_click_speed or 0.25

if config.fav_persist == nil then
  config.fav_persist = true
else
  config.fav_persist = config.fav_persist
end

if config.results_ph == nil then
  config.results_ph = true
else
  config.results_ph = config.results_ph
end

if config.undock == nil then
  config.undock = true
end

if config.act_search == nil and reaper.CF_EnumerateActions then
  db.saved = false
  config.act_search = true
  global_types.ACTION = true
  config.global_types_n = config.global_types_n + 1
  table.insert(global_types_order, "ACTION")
  if filter_modes then filter_modes.ACTION = true end
end

if not filter_modes then
  filter_modes = {ALL = true,
                  CHAIN = true,
                  FAV = true,
                  FOLDER = config.fol_search and true or nil,
                  FX = false,
                  INSTRUMENT = false,
                  JS = true,
                  TEMPLATE = true,
                  VST2 = true,
                  VST3 = true,
                  AU = os_is.mac and true or nil,
                  ACTION = config.act_search and true or nil
                  }
end

if reaper.CF_EnumerateActions then
  config.act_search = config.act_search
  --filter_modes.ACTION = config.act_search or nil
elseif config.act_search then
  config.act_search = nil
  filter_modes.ACTION = nil
  global_types.ACTION = nil
  config.global_types_n = config.global_types_n - 1
  for i, v in ipairs(global_types_order) do
    if v == "ACTION" then
      table.remove(global_types_order, i)
      break
    end
  end
end

if config.fol_search == nil then
  config.fol_search = true
  filter_modes.FOLDER = true
  db.saved = false
  VST2 = nil
  VST3 = nil
  JS = nil
  CHAIN = nil
  TEMPLATE = nil
  AU = nil
  ACTION = nil
else
  config.fol_search = config.fol_search
end

config2 = config
config = nil
local config = config2
config2 = keep_states
keep_states = nil
local keep_states = config2
config2 = global_types
global_types = nil
local global_types = config2
config2 = global_types_order
global_types_order = nil
local global_types_order = config2
config2 = filter_modes
filter_modes = nil
local filter_modes = config2
config2 = nil

if not config.no_sel_tracks then config.no_sel_tracks = 1 end

if os_is.win and config.mode == "AU" then config.mode = "ALL" end

if config.os ~= cur_os then
  --add_h = config.os:lower():match("osx") and "win" or "mac"
  config.os = cur_os
  if os_is.mac then
    config.global_types_n = not global_types.AU and config.global_types_n + 1 or config.global_types_n
    global_types.AU = true
    filter_modes.AU = true
  else
    config.global_types_n = global_types.AU and config.global_types_n - 1 or config.global_types_n
    global_types.AU = nil
    filter_modes.AU = nil
    for i = 1, #global_types_order do
      if global_types_order[i] == "AU" then
        table.remove(global_types_order, i)
        break
      end
    end
  end
end

if not config.version or config.version ~= scr.version then
  if not reaper.CF_EnumerateActions or
     not reaper.JS_Mouse_LoadCursor then
    config.ext_check = true
  end
end

if not config.version then config.version = scr.version end

if config.version ~= scr.version then config.reminder = true end

local sh_list = {["2"] = "VST2", ["3"] = "VST3", c = "CHAIN",
                  u = os_is.mac and "AU" or nil, a = "ALL",
                  x = "FX", j = "JS", f = "FAV", t = "TEMPLATE",
                  i = "INSTRUMENT", o = config.fol_search and "FOLDER" or nil,
                  n = config.act_search and "ACTION" or nil}

if not pcall(doFile, scr.fav) then
  FAV = {}
end

db.FAV = FAV
FAV = nil

function ignoreCh(ch)
  local ch_found
  for key, v in pairs(ignore_ch) do
    if v == ch then
      ch_found = true
      break
    end
  end
  
  return ch_found
end

function whiteCh(ch)
  local ch_found
  for key, v in pairs(white_ch) do
    if v == ch then
      ch_found = true
      break
    end
  end
  
  return ch_found
end

local timer = {}

function timer:new(o)
  local o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function timer:start(dur)
  self.time_init = reaper.time_precise()
  self:count(dur)
  return self
end

function timer:count(dur)
  local time_new = reaper.time_precise()
  if time_new - self.time_init >= dur then
    self.up = true
    return  
  end
  reaper.defer(function()self:count(dur)end)
end

function truncateString(x1, x2, str, str_w, offset)
  if x1 + str_w + offset * config.multi > x2 then
    while x1 + str_w > x2 do
      if not str then break end
      str = str:match("(.+).")
      str_w = gfx.measurestr(str)
    end 
    str = (str and str:match("(.+)...") or "") .. "..."
  end
  return str
end

local retinaDivide = function(val)
  if not val then return end
  val = config.retina and val / 2 or val
  return math.floor(val)
end

function exit_states()
  if scr.quit then return end
  scr.quit = true
  local _, wnd_x, wnd_y, _, h = gfx.dock(-1, 0, 0, 0, 0)
  
  wnd_y = macYoffset(retinaDivide(scr.temp_undock and os_is.mac and gui.wnd_h_save or gui.wnd_h),
                     retinaDivide((config.ext_check or scr.temp_undock and os_is.mac) and gui.wnd_h or 
                     gui.Row1.h + gui.row_h + gui.border * 2),
                     wnd_y)
  
  config.wnd_x = wnd_x
  config.wnd_y = not config.undock and config.wnd_y or wnd_y
  config.version = scr.version
  if config.default_mode then config.mode = config.default_mode end
  if scr.temp_undock then config.undock = false end
  writeFile(scr.config, tableToString("config", config))
  writeFile(scr.config, tableToString("global_types", global_types), "a")
  writeFile(scr.config, tableToString("global_types_order", global_types_order), "a")
  writeFile(scr.config, tableToString("filter_modes", filter_modes), "a")
  writeFile(scr.config, tableToString("keep_states", keep_states), "a")
  writeFile(scr.fav, tableToString("FAV", db.FAV, true))
  reaper.DeleteExtState("Quick Adder", "MSG", false)
end

local m_track = reaper.GetMasterTrack()

function close_undo()
  reaper.Undo_EndBlock("ReaScript: Run", -1)
end

function notFound(is_tt)
  local item = is_tt and "Track template" or "FX"
  reaper.MB(item .. " not found." .. 
            (is_tt and "" or
            "\n\nPlease perform \"Clear cache/re-scan\" in\nREAPER Preferences " ..
            "--> Plug-ins --> VST\nto remove non-existent FX " ..
            "from the data-\nbase" ..
            " and then press F5 in Quick Adder."),
            "Quick Adder 2 error", 0)
end

function sortAbc(tbl, skip)
  local tbl_cap = {}
  local temp_tbl = {}
  local tbl_sorted = {}
  
  for i = 1, #tbl do
    local v = tbl[i]:upper()
    tbl_cap[i] = v
    table.insert(temp_tbl, v)
  end
  
  table.sort(temp_tbl)
  
  for i = 1, #temp_tbl do
    for k, v in pairs(tbl_cap) do
      if temp_tbl[i] == v then
        table.insert(tbl_sorted, tbl[k])
        break
      end
    end
  end
  return tbl_sorted
end

function listArrayDirFiles(dir_list, ext)
  local file_list = {}
  for n = 1, #dir_list do
    local path = dir_list[n] .. "/"
    local i = 0
    while not file do
      local file = os_is.win and reaper.EnumerateFiles(path, i) or
            reaper.EnumerateSubdirectories(path, i)
      if not file then break end
      if file:lower():match(".+%.dll") or file:lower():match(".+%.vst") or
         file:lower():match(".+%.component") then
        file = file:gsub("[^.%w]", "_") -- replace all but alphanumerical and periods
        --table.insert(file_list, file)
        file_list[file] = true
      end
      i = i + 1
    end
  end
  return file_list
end

function parseIniFxFilt(str)
  if not str then return end
  if str:match(" OR ") then return end
  
  str = str:gsub("AND", "")
  str = str:gsub("\"", "")
  local tbl = {excl = {}, incl = {}}
  
  for match in str:gmatch("NOT %( .- %)%s") do
    local match_ins = match:match("NOT %( (.+ )%)")
    if match_ins:match("NOT") then return end
    local tbl2 = {}
    for phrase in match_ins:gmatch("%(.-%)%s") do
      table.insert(tbl2, phrase:match("(%(.-%))%s"):lower())
      match_ins = match_ins:gsub(magicFix(phrase), "")
    end
    for word in match_ins:gmatch(".-%s") do
      table.insert(tbl2, word:match("(.-)%s"):lower())
    end
    table.insert(tbl.excl, tbl2)
    str = str:gsub(magicFix(match), "")
  end
  
  for match in str:gmatch("NOT .-%s") do
    local match_ins = match:match("NOT (.-%s)")
    if match_ins == "(" then return end
    local tbl2 = {}
    for word in match_ins:gmatch(".-%s") do
      table.insert(tbl2, word:match("(.-)%s"):lower())
    end
    table.insert(tbl.excl, tbl2)
    str = str:gsub(magicFix(match), "")
  end
   
  for match in str:gmatch("%( .- %)%s") do
    table.insert(tbl.incl, match:match("%( (.+ )%)"):lower())
    str = str:gsub(magicFix(match), "")
  end
  
  for match in str:gmatch("%(.-%)%s") do
    table.insert(tbl.incl, {match:match("%(.+%)"):lower()})
    str = str:gsub(magicFix(match), "")
  end
  
  for match in str:gmatch(".-%s") do
    local match_ins = match:match("(.-)%s")
    if match_ins == "" then goto SKIP end
    table.insert(tbl.incl, {match:match("(.-)%s"):lower()})
    ::SKIP::
  end
  
  return tbl
end

function getDb(refresh)
  if not db.saved then
    function dbDefer(refresh)
      if not _timers.db_defer then
        get_db = true
        _timers.db_defer = timer:new():start(0.2)
      end
    
      if _timers.db_defer.up then
        _timers.db_defer = nil
        
        if config.fol_search then
          local fx_folders_ini = getContent(rpr.fx_folders)
          
          if fx_folders_ini then
            fx_folders_ini = fx_folders_ini .. "\n\n"
            local folder_names = fx_folders_ini:match("%[Folders%](.-)\n[\n%[]")
            if folder_names then
              fx_folders = {}
              for match in folder_names:gmatch("Name%d+=.-\n") do
                local n, name = match:match("Name(%d+)=(.+)\n")
                fx_folders[n+1] = {name = name}
              end
              
            
              for match in fx_folders_ini:gmatch("(Folder%d+%].-)\n[\n%[]") do
                local n, content = match:match("Folder(%d+)%](.+)")
                fx_folders[n+1].content = content
              end
              fx_folders_ini = nil
            end
          end
        end

        local r_ini = getContent(reaper.get_ini_file())
        --[[rpr.vstpath = parseKeyVal(findContentKey(r_ini, rpr.x64 and "vstpath64" or "vstpath"))
        fx_dir_list = getFxDir(rpr.vstpath)
        fx_file_list = listArrayDirFiles(fx_dir_list)]]
        --rpr.aupath = os_is.mac and {"Library/Audio/Plug-Ins/Components",
        --              "~/Library/Audio/Plug-Ins/Components"} or nil
        --au_dir_list = os_is.mac and getFxDir(rpr.aupath) or nil
        --au_file_list = os_is.mac and listArrayDirFiles(au_dir_list) or nil
                                  
        rpr.def_fx_filt = parseIniFxFilt(findContentKey(r_ini,
                          rpr.x64 and (os_is.win and "def_fx_filt64" or "def_fx_filtx64") or
                          os_is.win and "def_fx_filt32" or "def_fx_filtx32"))
        r_ini = nil
        db.VST2 = {}
        db.VST3 = {}
        getVst()
        fx_dir_list = nil
        fx_file_list = nil
        
        db.VST3 = sortAbc(db.VST3)
        db.VST2 = sortAbc(db.VST2)

        db.JS = {}
        getJs()
        db.JS = sortAbc(db.JS)

        db.CHAIN = getFiles("FXChains", "RfxChain")
        db.CHAIN = sortAbc(db.CHAIN)
        
        db.TEMPLATE = getFiles("TrackTemplates", "RTrackTemplate")
        db.TEMPLATE = sortAbc(db.TEMPLATE)  
      
        if os_is.mac then
          db.AU = {}
          getAu()
          db.AU = sortAbc(db.AU)
        end
        
        if config.act_search then
          db.ACTION = {}
          getAction()
          table.sort(db.ACTION)
        else
          db.ACTION = nil
        end

        get_db = nil
        fx_folders = nil
        if refresh then
          gui.wnd_h_save = gui.wnd_h
          gui.reinit = true
          scr.re_search = true
        end
      else
        reaper.defer(function()dbDefer(refresh)end)
      end
      if not get_db then
        writeFile(scr.plugs, tableToString("VST2", db.VST2))
        writeFile(scr.plugs, tableToString("VST3", db.VST3), "a")
        writeFile(scr.plugs, tableToString("JS", db.JS), "a")
        writeFile(scr.plugs, tableToString("CHAIN", db.CHAIN), "a")
        writeFile(scr.plugs, tableToString("TEMPLATE", db.TEMPLATE), "a")
        if config.act_search then
          writeFile(scr.plugs, tableToString("ACTION", db.ACTION), "a")
        end
        if os_is.mac then
          writeFile(scr.plugs, tableToString("AU", db.AU), "a")
        end
      end
    end
    dbDefer(refresh)
  else
    db.VST2 = VST2
    VST2 = nil
    db.VST3 = VST3
    VST3 = nil
    db.JS = JS
    JS = nil
    db.CHAIN = CHAIN
    CHAIN = nil
    db.TEMPLATE = TEMPLATE
    TEMPLATE = nil
    db.AU = os_is.mac and AU or os_is.mac and not AU and {} or nil
    AU = nil
    db.ACTION = ACTION
    ACTION = nil
  end
  
end

function isClearFx()
  if gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) then
    return false
  end
  if gui.m_cap&mouse_mod.clear == mouse_mod.clear and not mouse_mod.reverse or
     gui.m_cap&mouse_mod.clear ~= mouse_mod.clear and mouse_mod.reverse then
    return true
  end
end

local cntSelTrs = function()
  return reaper.CountSelectedTracks(0)
end

local cntTrs = function()
  return reaper.CountTracks(0)
end

local getTr = function(n)
  return reaper.GetTrack(0, n)
end

local getSelTr = function(n)
  return reaper.GetSelectedTrack(0, n)
end

function getSelectedTracks()
  local tbl = {}
  
  for i = 0, cntSelTrs() - 1 do
    local tr = getSelTr(i)
    table.insert(tbl, tr)
  end
  
  return tbl
end

function doAdd()
  local auto_float
  if reaper.SNM_GetIntConfigVar then
    auto_float = reaper.SNM_GetIntConfigVar("fxfloat_focus", 0)
    if auto_float&4 > 0 then
      reaper.SNM_SetIntConfigVar("fxfloat_focus", auto_float~4)
    end
  end
  
  if scr.results_list[gui.Results.sel]:match("^(%w+).+") == "ACTION" and
     (gui.m_cap == 0 or gui.m_cap == mouse_mod.lmb) then
    local section = select(3, gui.parseResult(scr.results_list[gui.Results.sel])):
          match("(.+)/.+")
    id = select(6, gui.parseResult(scr.results_list[gui.Results.sel]))
    if section == "Main" then
      reaper.Main_OnCommand(id, 0)
      scr.result_is_action = true
    elseif section == "MIDI Editor" or section == "MIDI Event List Editor" then
      local is_list = section == "MIDI Event List Editor" and true or false
      local ME = reaper.MIDIEditor_GetActive()
      local ME_mode = reaper.MIDIEditor_GetMode(ME)
      reaper.MIDIEditor_LastFocused_OnCommand(id, is_list == 1 and true or false)
      scr.result_is_action = true
    elseif reaper.JS_Localize and reaper.JS_Window_Find and
           reaper.JS_Window_OnCommand and section == "Media Explorer" then
      local ME_name = reaper.JS_Localize("Media Explorer", "common")
      local ME = reaper.JS_Window_Find(ME_name, true)
      reaper.JS_Window_OnCommand(ME, id)
      scr.result_is_action = true
    end
  elseif scr.results_list[gui.Results.sel]:match("^(%w+).+") == "TEMPLATE" then
    if gui.m_cap == 0 or gui.m_cap == mouse_mod.shift + (gfx.mouse_cap&mouse_mod.lmb) or
       gui.m_cap == mouse_mod.clear + (gfx.mouse_cap&mouse_mod.lmb) or
       gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) or
       gui.m_cap == mouse_mod.lmb or m_obj then
      ttAdd(scr.results_list[gui.Results.sel])
    end
  else
    if gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) or
       gui.m_cap == mouse_mod.alt + mouse_mod.win + (gfx.mouse_cap&mouse_mod.lmb) then
      scr.create_send = true
    end
    local m_obj_is_tr = reaper.ValidatePtr2(0, m_obj, "MediaTrack*")
    local m_obj_is_tk = reaper.ValidatePtr2(0, m_obj, "MediaItem_Take*")
    if gui.m_cap&mouse_mod.take == 0 and not m_obj and gui.m_cap&mouse_mod.win == 0 or
       gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) or
       gui.m_cap == mouse_mod.alt + mouse_mod.win + (gfx.mouse_cap&mouse_mod.lmb) or
       m_obj_is_tr or type(m_obj) == "string" then
      reaper.PreventUIRefresh(1)
        fxTrack()
      reaper.PreventUIRefresh(-1)
    elseif gui.m_cap&mouse_mod.take == mouse_mod.take or m_obj_is_tk then
      reaper.PreventUIRefresh(1)
        fxItem()
      reaper.PreventUIRefresh(-1)  
    end
  end
  
  if auto_float and auto_float&4 > 0 then
    reaper.SNM_SetIntConfigVar("fxfloat_focus", auto_float)
  end
  
  gui.selected = nil
  gui.click_ignore = nil
  gui.loop_start = nil
  if m_obj then gui.active = nil m_obj = nil end
end

function clearAddorAdd(s)
  return gui.m_cap&mouse_mod.clear ~= mouse_mod.clear and "Add " or
         "Clear FX chain" .. s .." and add "
end

function waitResult()
  if wait_result then
    wait_result = nil
    if config.pin and (not config.fx_hide or gfx.getchar(65536)&2 ~= 2) and
       gfx.dock(-1) == 0 then
      gui.reopen = true gui:init()
    end
  end
end

function createTrackSend(origin_tr, dest_tr)
  for i = 1, #origin_tr do
    if origin_tr[i] == reaper.GetMasterTrack(0) then return end
    reaper.CreateTrackSend(origin_tr[i], dest_tr)
  end
  reaper.Main_OnCommand(40293, 0) -- Track: View routing and I/O for current/last touched track
  if reaper.JS_Window_GetForeground and rpr.ver >= 6 then
    local wnd = reaper.JS_Window_GetForeground()
    reaper.JS_Window_SetZOrder(wnd, "TOPMOST")
    
    if reaper.NamedCommandLookup("_BR_MOVE_WINDOW_TO_MOUSE_H_M_V_M") > 0 then
      reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_MOVE_WINDOW_TO_MOUSE_H_M_V_M"), 0)
    end
    scr.bypass_reopen = true
  end
end

function fxTrack(sel_tr_count, is_m_sel)
  local sel_tr_count = sel_tr_count or reaper.CountSelectedTracks(0)
  local is_m_sel = is_m_sel or reaper.IsTrackSelected(m_track)
  if not scr.create_send and (sel_tr_count > 0 and not m_obj or is_m_sel or m_obj and type(m_obj) == "userdata" and
     gui.m_cap ~= mouse_mod.take) then
    reaper.Undo_BeginBlock()
      local name, undo_name, fx_i
       
      for i = 0, m_obj and 0 or sel_tr_count - 1 do
        local track = m_obj or reaper.GetSelectedTrack(0, i)
        
        name, undo_name, fx_i = fxTrack_Add(track)
        
        if name == "No FX" then return name end
         
        if i == 0 then
          fxFloat(track, name)
        end
      end
       
      if is_m_sel and not m_obj then -- if master track is selected
        name, undo_name, fx_i = fxTrack_Add(m_track)        
        
        if name == "No FX" then return end
        
        if sel_tr_count == 0 then
          fxFloat(m_track, name)
        end
      end
      
      ::SKIP::
      
      if fx_i == -1 then return end
      
      local t_or_t = (sel_tr_count > 1 or sel_tr_count == 1 and is_m_sel) and "s" or ""
       
      local ca_or_a = clearAddorAdd(t_or_t)

      reaper.Undo_EndBlock(ca_or_a .. (isInput() and "input " or "") ..
                           undo_name .. " to selected track" .. t_or_t, -1)
      waitResult()
  else
    wait_result = scr.results_list[gui.Results.sel]

    if m_obj or config.no_sel_tracks == 2 or (cntSelTrs() > 0 and
      (gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) or 
       gui.m_cap == mouse_mod.alt + mouse_mod.win + (gfx.mouse_cap&mouse_mod.lmb))) then
      if scr.create_send then scr.create_send = nil end
      
      local sel_tracks
      
      if gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) and
         type(m_obj) == "userdata" or not m_obj and cntSelTrs() > 0 then
        scr.show_routing = true
        if type(m_obj) == "userdata" and m_obj ~= reaper.GetMasterTrack(0) then
          sel_tracks = {m_obj}
          scr.m_obj = true
        else
          sel_tracks = getSelectedTracks()
        end
      end
      
      local idx = ((not m_obj and cntSelTrs() == 0) or type(m_obj) == "string") and
                  cntTrs() or
                  not m_obj and reaper.CSurf_TrackToID(getSelTr(0), false) - 1 or
                  reaper.GetMediaTrackInfo_Value(m_obj, "IP_TRACKNUMBER") == -1 and 0 or
                  reaper.GetMediaTrackInfo_Value(m_obj, "IP_TRACKNUMBER") - 1
                  
      reaper.InsertTrackAtIndex(idx, false)
      local tr = getTr(idx)
      
      if m_obj then gui.active = nil m_obj = nil end
      
      reaper.GetSetMediaTrackInfo_String(tr, "P_NAME",
                                         gui.parseResult(wait_result):match("(.-) ?%(") or
                                         gui.parseResult(wait_result):match(".+: (.+)") or
                                         gui.parseResult(wait_result), true)
      if select(3, gui.parseResult(wait_result)) ~= "" then
        reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
        reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
        reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 128+63<<5|0)
      end
      reaper.SetOnlyTrackSelected(tr)
 
      local no_fx = fxTrack(cntSelTrs(), false)
      
      if scr.show_routing then 
        if gui.m_cap&mouse_mod.win == 0 then createTrackSend(sel_tracks, tr) end
        scr.show_routing = nil
        scr.m_obj = nil
      end
      
      if no_fx then reaper.DeleteTrack(tr) end
      return
    elseif cntTrs() == 0 and config.no_sel_tracks == 1 then
      local answ = reaper.MB("There are no tracks in the project.\n" ..
                              "Do you want to insert tracks to put the FX on?", "REASCRIPT Query", 1)
      if answ == 1 then
        reaper.Main_OnCommand(41067, 0) -- Track: Insert multiple new tracks
        waitTrack()
      else
        wait_result = nil
      end
    elseif config.no_sel_tracks == 1 then
      local answ = reaper.MB("Select tracks to put the FX on.", "REASCRIPT Query", 1)
      if answ == 1 then
        waitTrack()
      else
        wait_result = nil
      end
    elseif config.no_sel_tracks == 3 then
      wait_result = nil
    end
  end
end

function fxFlush(object, kind)
  if kind < 3 then -- if not take FX
    if kind < 2 then -- if not track input FX
      local fx_count = reaper.TrackFX_GetCount(object)
      for i = 0, fx_count do
        reaper.TrackFX_SetOffline(object, 0, true)
        reaper.TrackFX_Delete(object, 0)
      end
    else -- if track input FX
      local fx_count = reaper.TrackFX_GetRecCount(object)
      for i = 0, fx_count do
        reaper.TrackFX_SetOffline(object, 0x1000000+0, true)
        reaper.TrackFX_Delete(object, 0x1000000+0)
      end
    end
  else -- if take FX
    local fx_count = reaper.TakeFX_GetCount(object)
    for i = 0, fx_count do
      reaper.TakeFX_SetOffline(object, 0, true)
      reaper.TakeFX_Delete(object, 0)
    end
  end
end

function isInput()
  if gui.m_cap&mouse_mod.win > 0 then return false end
  
  if gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) then
    return false
  elseif gui.m_cap&mouse_mod.input == mouse_mod.input then
    return true
  else
    return false
  end
end

function parseResultsList(v)
  local fx_type, name, path, undo_name = v:match("(%w-:)(.-)|,|(.-)|,|.+")
  name = name:gsub("\t.+", "") -- remove folders
  if fx_type == "JS:" then -- if JS
    if not name:match("Video processor") then
      undo_name = name
      name = fx_type .. path -- fx_type + path
    else
      undo_name = path
    end
  elseif fx_type == "CHAIN:" then
    local path = path:gsub(rpr.path .. "/FXChains/", "")
    undo_name = name
    name = path .. name .. ".RfxChain"
  else -- if VST or AU
    fx_type = fx_type:gsub("i", "")
    undo_name = name:gsub(" %(.+%)", "")
    name = fx_type .. name -- fx_type + name - VSTi
  end
  
  return name, undo_name
end

function fxTrack_Add(track)
  local name, undo_name = parseResultsList(wait_result or scr.results_list[gui.Results.sel])

  if isClearFx() then
    if not isInput() then
      fxFlush(track, 1)
    else
      fxFlush(track, 2)
    end
  end
  
  local fx_i = reaper.TrackFX_AddByName(track, name, isInput(), -1)
  if fx_i == -1 then
    notFound()
    close_undo()
    return "No FX"
  else
    return name, undo_name, fx_i
  end
end

function fxFloat(obj, name)
  local obj_type
  if reaper.ValidatePtr2(0, obj, "MediaTrack*") then
    obj_type = "Track"
  else reaper.ValidatePtr2(0, obj, "MediaItem_Take*")
    obj_type = "Take"
  end
   
  local is_fxc_vis
  if not name:match("%.RfxChain$") then -- if not chain
    if isInput() then
      local chunk = select(2, reaper.GetTrackStateChunk(obj, "", false))
      is_fxc_vis = tonumber(chunk:match("<FXCHAIN_REC.-SHOW (%d+)"))
    else
      is_fxc_vis = reaper[obj_type .. "FX_GetChainVisible"](obj)
    end
  end
  
  local fx_idx = (isInput() and 0x1000000 + reaper.TrackFX_GetRecCount(obj) or
            reaper[obj_type .. "FX_GetCount"](obj)) - 1
      
  if config.float_mode == 2 then -- if always show in FX chain
    reaper[obj_type .. "FX_Show"](obj, fx_idx, config.fx_hide and 2 or 1)
  elseif config.float_mode == 3 then -- if always float
    reaper[obj_type .. "FX_Show"](obj, fx_idx, config.fx_hide and 2 or 3)  
  elseif name:match("%.RfxChain$") then -- if chain
    reaper[obj_type .. "FX_Show"](obj, fx_idx, config.fx_hide and 2 or 1)
    --reaper.TrackFX_SetOpen(obj, fx_idx, false)
  else
    if isInput() and (not is_fxc_vis or is_fxc_vis == 0) or is_fxc_vis == -1 then -- if FX chain is hidden
      reaper[obj_type .. "FX_Show"](obj, fx_idx, config.fx_hide and 2 or 3)
    else
      reaper[obj_type .. "FX_Show"](obj, fx_idx, 2)
    end                            
  end
  
  if not config.fx_hide and config.float_at_mouse and 
     reaper.NamedCommandLookup("_BR_MOVE_WINDOW_TO_MOUSE_H_R_V_M") > 0 then
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_MOVE_WINDOW_TO_MOUSE_H_R_V_M"), 0)
  end
end

function fxItem(sel_it_count)
  local sel_it_count = sel_it_count or reaper.CountSelectedMediaItems(0)
  if sel_it_count > 0 or m_obj then
    reaper.Undo_BeginBlock()
      local name, undo_name, fx_i
      
      for i = 0, m_obj and 0 or sel_it_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = m_obj and m_obj or reaper.GetActiveTake(item)
        if not take then goto SKIP end
        name, undo_name = parseResultsList(--[[wait_result or ]]scr.results_list[gui.Results.sel])
        
        if isClearFx() then
          fxFlush(take, 3)
        end
        
        fx_i = reaper.TakeFX_AddByName(take, name, -1)
        
        if fx_i == -1 then
          notFound()
          close_undo()
          return
        end

        if i == 0 then
          fxFloat(take, name)
        end
        
      end
      ::SKIP::
      
      if m_obj then gui.active = nil m_obj = nil goto SKIP end
      
      local i_or_i = sel_it_count > 1 and "s" or ""
      local ca_or_a = clearAddorAdd(i_or_i)
      
    reaper.Undo_EndBlock(undo_name and ca_or_a..undo_name.." to selected item"..i_or_i or "Run: ReaScript", -1)
    waitResult()
  else
    local answ = reaper.MB("Select items to put the FX on.", "REASCRIPT Query", 1)
    if answ == 1 then
      wait_result = scr.results_list[gui.Results.sel]
      waitItem()
    else
      return
    end
  end
end

function waitItem()
  local sel_it_count = reaper.CountSelectedMediaItems()
  if sel_it_count > 0 then
    fxItem(sel_it_count)
  else
    reaper.defer(waitItem)
  end
end

function waitTrack()
  local sel_tr_count = reaper.CountSelectedTracks()
  local is_m_sel = reaper.IsTrackSelected(m_track)
  if sel_tr_count > 0 or is_m_sel then
    fxTrack(sel_tr_count, is_m_sel)
  else
    reaper.defer(waitTrack)
  end
end

function fxExclCheck(str, include)
  if not str then return end
  if include and #rpr.def_fx_filt.incl == 0 then return true end
  if not include and #rpr.def_fx_filt.excl == 0 then return false end
  
  local tbl = include and rpr.def_fx_filt.incl or rpr.def_fx_filt.excl
  for i = 1, #tbl do
    local pass = nil
    for n = 1, #tbl[i] do
      local str2 = magicFix(tbl[i][n])
      local str2 = str2:gsub("%%^", "^")
      if n == #tbl[i] and (n == 1 or pass) and str:match(str2) then
        return true
      elseif str:match(str2) then
        pass = true
      elseif not str:match(str2) then
        goto SKIP
      end
    end
    ::SKIP::
  end
end

function getVst()
  local content = getContent(rpr.vst)
  for line in content:gmatch(".-\n") do
    if not line:match(".-=.-,.-,.+") then goto SKIP end -- if not valid FX entry
    
    local vst_file, vst_id, vst_name, fx_type = line:match("(.-)=.-,(.-),(.+)\n")
    vst_file = vst_file:gsub("<.+", "")
    
    if vst_name:match("^[#<]") then goto SKIP end -- if exclude or shell
    
    if fx_file_list and not fx_file_list[vst_file] and 
       not vst_name:lower():match("cockos") then goto SKIP end
    
    local vst_i, sub_tbl = vst_name:match("!!!VST(i)")
    
    if vst_i then vst_name = vst_name:gsub("!!!VSTi", "") else vst_i = "" end
 
    if not vst_file:lower():match("%.vst3$") then -- if VST2
      fx_type = "VST2" .. vst_i .. ":"
      sub_tbl = db.VST2
    else
      fx_type = "VST3" .. vst_i .. ":"
      sub_tbl = db.VST3
    end

    if rpr.def_fx_filt and fxExclCheck(fx_type:lower():gsub("vst2", "vst") .. vst_name:lower()) then goto SKIP end
    if rpr.def_fx_filt and not fxExclCheck(fx_type:lower():gsub("vst2", "vst") .. vst_name:lower(), true) then goto SKIP end
    
    local fx_folder = getFXfolder(vst_id .. "//" .. vst_file, 3)
    
    --vst_name = escSeqFix(vst_name)
    local val = fx_type .. vst_name .. fx_folder .. "|,|" .. vst_file .. "|,|" .. vst_i .. "|,|" .. vst_id .. "|,|"
 
    table.insert(sub_tbl, val)
    ::SKIP::
  end
end

function getJs()
  local file_list = getFiles("Effects")
  for i = 1, #file_list do
    local js_name
    local content = getContent(file_list[i])
    
    for l in content:gmatch(".-[\n\r]") do
       if l:match("^desc:.+") then js_name = l:match("^desc:%s*(.+)[\n\r]") break end
    end

    if js_name then
      local path = file_list[i]:gsub(".+/Effects/", "")
      --js_name = js_name:gsub("\\", "\\\\"):gsub("\"", "\\%0")
      
      if rpr.def_fx_filt and fxExclCheck("js:" .. js_name:lower()) then goto SKIP end
      if rpr.def_fx_filt and not fxExclCheck("js:" .. js_name:lower(), true) then goto SKIP end
      local fx_folder = getFXfolder(path, 2)
      
      --js_name = escSeqFix(js_name)
      table.insert(db.JS, "JS:" .. js_name .. fx_folder .. "|,|" .. path .. "|,||,||,|")
    end
    ::SKIP::
  end
  
  if rpr.def_fx_filt and fxExclCheck("js:video processor") then goto SKIP end
  
  local fx_folder = getFXfolder("Video processor", 6)
 
  table.insert(db.JS, "JS:Video processor" .. fx_folder .. "|,|" .. "Video processor" .. "|,||,||,|")
  ::SKIP::
end

function getAu()
  local content = getContent(rpr.au)
  if not content then return end
  for line in content:gmatch(".-[\n\r]") do
    if line:match("^.-=.+$") then
      local au_name, au_i = line:match("^(.-)%s-=(.+)$")
      au_i = au_i:match("<inst") and "i" or ""
      if not au_name:match("^#") then
        if rpr.def_fx_filt and fxExclCheck("au" .. au_i .. ":" .. au_name:lower()) then goto SKIP end
        if rpr.def_fx_filt and not fxExclCheck("au" .. au_i .. ":" .. au_name:lower(), true) then goto SKIP end
        
        local fx_folder = getFXfolder(au_name, 5)
        
        --au_name = escSeqFix(au_name)
        table.insert(db.AU, "AU" .. au_i .. ":" .. au_name .. fx_folder .. "|,||,|" .. au_i .. "|,||,|")
      end
    end
    ::SKIP::
  end
end

function getAction()
  local section = {{id = 0, name = "Main"},
  {id = 32060, name = "MIDI Editor"},
  {id = 32061, name = "MIDI Event List Editor"},
  --{id = 32062, name = "MIDI Inline Editor"},
  {id = 32063, name = "Media Explorer"}
  }
  if not reaper.CF_EnumerateActions then return end
  for n = 1, #section do
    local i = 0
    while i <= 65535 do
    local id, name = reaper.CF_EnumerateActions(section[n].id, i, "")
    i = i + 1
    if name ~= "" then
      local id_named = reaper.ReverseNamedCommandLookup(id) or ""
      --name = escSeqFix(name)
      
      local act = "ACTION:" .. name .. "|,|" .. id_named .. "|,|" ..
            section[n].name .. "/" .. section[n].id .. "|,|" .. id .. "|,|"
      table.insert(db.ACTION, act)
    end
    end
  end
end

function doMatch()
  function matchType(excl)
    getResultsList("FAV", excl)
    for i = 1, #global_types_order do
        if match_stop then return end
        getResultsList(global_types_order[i], excl)
    end
  end
  
  if config.mode == "ALL" then
    getResultsListFav()
    matchType()
  elseif config.mode == "FX" or config.mode == "FOLDER" then
    getResultsListFav(nil, true)
    matchType(true)
  elseif config.mode == "INSTRUMENT" then
    getResultsListFav()
    matchType()
  elseif config.mode == "FAV" then
    getResultsListFav()
    getResultsList("FAV")
  else
    getResultsListFav(config.mode)
    getResultsList("FAV")
    getResultsList(config.mode)
  end
  
  if #scr.results_list == 0 then
    scr.match_found = nil
  else
    scr.match_found = true
    no_fx = nil
  end 
end

function getResultsListFav(fx_type, fx_only)
  if gui.str ~= "" then return end
  for i, v in ipairs(db.FAV) do
    local l = v:match("(.-)|,|.+"):lower()
    if fx_type then
      fx_type_match = l:match("^" .. fx_type:lower())
      if not fx_type_match then goto SKIP end
    elseif fx_only then
      if (l:match("^chain") or l:match("^template") or l:match("^action") or
          l:match("^%w-i:")) and config.mode == "FX" or
          config.mode == "FOLDER" and not l:match("\t.+") then
        goto SKIP
      end
    elseif config.mode == "INSTRUMENT" and not l:match("^%w+i:") then
      goto SKIP
    end
    
    if #scr.results_list == config.results_max and config.results_max > 0 then
      fx_type_match = nil
      break
    else
      table.insert(scr.results_list, v)
    end
    ::SKIP::
    fx_type_match = nil
  end
end

function getResultsList(fx_type, fx_only)
  if gui.str == "" then return end
  if fx_type == "FAV" and config.mode ~= "ALL" and config.mode ~= "FOLDER" and
     config.mode ~= "FX" and config.mode ~= "FAV" and
     #scr.query_parts > 0 and
     not (#scr.query_parts == 1 and scr.query_parts[1]:match("^/")) then
    table.insert(scr.query_parts, 1, config.mode:lower())
    scr.fav_type = true
  end
  for i, v in ipairs(db[fx_type]) do
    local l, part_match = v:match("(.-)|,|.+")
    if not l then goto LOOP_END end
    l = l:lower()
    if fx_only then
      if (l:match("^chain") or l:match("^template") or l:match("^action") or
          l:match("^%w-i:")) and config.mode == "FX" or
          config.mode == "FOLDER" and not l:match("\t.+") then
        goto LOOP_END
      end
    elseif config.mode == "INSTRUMENT" and not l:match("^%w+i:") then
      goto LOOP_END
    end
    for m = 1, #scr.query_parts do
      local query = scr.query_parts[m]
      --
      if query:match("^/") then goto PART_SKIP end -- if flag
 
      exclude, exclude_word = query:match("^(%%%-)(.+)")
      --
      if exclude then
        part_match = l:match(exclude_word) --:lower()
        if part_match then
          part_match = nil
          goto LOOP_END
        else
          part_match = 1
        end
      else
        local exact = gui.str:match("\".*\"") and "[%W]" or ""
        part_match = (query:match("^%d+$") and l:match("^.-:(.+)") or l):match(exact .. query)
        --part_match = l:match(exact .. query)
        if not part_match then break end
      end
      ::PART_SKIP::
    end
    ::LOOP_END::
    if part_match then
      if #scr.results_list < config.results_max or config.results_max == 0 then
        local in_list
        
        for i = 1, #scr.results_list do
          if scr.results_list[i]:match("(.+)|,|.*") == v then
            in_list = true
            break
          end
        end
        
        if not in_list then
          if not os_is.mac and v:match("^AU:") then goto SKIP end
          table.insert(scr.results_list, v)
          ::SKIP::
        end
        
        if #scr.results_list == config.results_max and config.results_max > 0 or
           config.results_max == 0 and #scr.results_list > 0 then
          match_stop = true
          break
        end
      end
    end
    if match_stop then break end
  end
  if scr.fav_type then
    table.remove(scr.query_parts, 1)
    scr.fav_type = nil
  end
end

function fxWndHideChunk(chunk)
  chunk = chunk:gsub("SHOW %d+", "SHOW 0"):gsub("FLOAT ", "FLOATPOS ")
  return chunk
end

function ttKeepers(tracks, sel_tr, tr_chunk, state, i)
  if state == "ISBUS" and #tracks > 1 then return end
  local save_state = tr_chunk:match(state..".-\n")
  sel_tr[i+1]["states"][state] = save_state
end

function templateSingle(tracks, sel_tr, i)
  local track_1_sub = tracks[1]
  local tr = m_obj or reaper.GetSelectedTrack(0, i)
  fxFlush(tr, 1)
  for k, v in pairs(sel_tr[i+1]["states"]) do -- recall states
    if tracks[1]:match(k) then
      track_1_sub = track_1_sub:gsub(k..".-\n", v, 1)
    else
      track_1_sub = track_1_sub:gsub("<TRACK.-\n", "%0  "..v, 1)
    end
  end
  if keep_states.ITEMS == true then
    track_1_sub = track_1_sub:gsub("<ITEM.+", ">")
    for m = #sel_tr[i+1]["items"], 1, -1 do -- recall items
      track_1_sub = track_1_sub:gsub("<TRACK.-\n", "%0"..sel_tr[i+1]["items"][m].."\n")
    end
  end
  if config.fx_hide then
    track_1_sub = fxWndHideChunk(track_1_sub)
  end
  reaper.SetTrackStateChunk(tr, track_1_sub, false)
  if reaper.TrackFX_GetChainVisible(tr) == -2 then
    reaper.TrackFX_Show(tr,0,1)
  end
end

function templateMulti(tracks, sel_tr, first_sel_tr, first_sel_tr_idx)
  for i = 0, #tracks do
    if i == #tracks then
      templateSingle(tracks, sel_tr, 0)
    elseif i ~= 0 then
      reaper.InsertTrackAtIndex(first_sel_tr_idx + i, false)
      local tr = reaper.GetTrack(0, first_sel_tr_idx + i)
      if config.fx_hide then
        tracks[i+1] = fxWndHideChunk(tracks[i+1])
      end
      reaper.SetTrackStateChunk(tr, tracks[i+1], false)
    end
  end
end

function ttApply(template, sel_tr_count) 
  local content = getContent(template)
  if not content then notFound(true) return end
  content = content:gsub("{.-}", "")
  
  local first_sel_tr_idx
  
  local tracks = {}
  
  repeat
    local track = content:match("(<TRACK.-)>(\n<TR)")
    if track then
      track = track..">\n"
      table.insert(tracks, track)
      track = track:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
      content = content:gsub(track, "")
    end
  until not track
  table.insert(tracks, content)

  if content == "" or not m_obj and sel_tr_count == 0 then close_undo() return end  
  
  first_sel_tr_idx = reaper.GetMediaTrackInfo_Value(m_obj or reaper.GetSelectedTrack(0, 0), "IP_TRACKNUMBER") - 1
  
  first_sel_tr_idx = math.floor(first_sel_tr_idx)
  
  local sel_tr = {}
  
  for i = 0, m_obj and 0 or sel_tr_count - 1 do
    local tr = m_obj or reaper.GetSelectedTrack(0, i)
    sel_tr[i+1] = {states = {}}
    local tr_chunk = select(2, reaper.GetTrackStateChunk(tr, "", false))
    if keep_states.ITEMS == true then
      sel_tr[i+1].items = {}
      for item in tr_chunk:gmatch("<ITEM.->\n>") do
        table.insert(sel_tr[i+1].items, item)
      end
    end
    for k, v in pairs(keep_states) do
      if v == true then
        ttKeepers(tracks, sel_tr, tr_chunk, k, i)
      end
    end
  end

  for i = 1, #tracks do -- fix sends
    tracks[i] = tracks[i]:gsub("(AUXRECV )(%d+)", function(a, b) b = tonumber(b) + first_sel_tr_idx return a..b end)
  end
  
  if #tracks > 1 then -- if template has multiple tracks then apply to first selected track
    templateMulti(tracks, sel_tr, first_sel_tr, first_sel_tr_idx)
  else
    for i = 0, m_obj and 0 or sel_tr_count - 1 do
      templateSingle(tracks, sel_tr, i)
    end
  end
end

function inFolderPrepare(sel_tr_count)
  local f_depth, tr
  if reaper.CountTracks(0) > 0 then
    if sel_tr_count > 0 then
      tr = reaper.GetSelectedTrack(0, sel_tr_count - 1)
      f_depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") 
      if f_depth < 0 then
        reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
      end
    else
      tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    end
    reaper.SetOnlyTrackSelected(tr)
    reaper.Main_OnCommand(40914, 0) -- Track: Set first selected track as last touched track
  end
  return f_depth
end

function inFolderSet(f_depth, option)
  --[[if option == 0 then
    if f_depth and f_depth < 0 then
      local tr = reaper.GetSelectedTrack(0, reaper.CountSelectedTracks(0) - 1)
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", f_depth)
    end
  elseif option == 1 then]]
    if f_depth and f_depth < 0 then
      local tr = reaper.GetSelectedTrack(0, reaper.CountSelectedTracks(0) - 1)
      local f_depth2 = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
      if f_depth2 < 0 then
        f_depth = f_depth + f_depth2
      end
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", f_depth)
    end
  --end
end

function a_ttAdd()end
function ttAdd(v)
  local template_inst, apply, tt_mode, name
  local sel_tr_count = reaper.CountSelectedTracks(0)
  
  for i, a in ipairs(scr.query_parts) do -- check for TT number flag
    if a:match("^/%d+$") then
      template_inst = a:match("%d+")
      break
    end
  end
  
  if config.tt_apply_reverse and gui.m_cap == mouse_mod.no_mod +
     (gfx.mouse_cap&mouse_mod.lmb) or
     not config.tt_apply_reverse and gui.m_cap == mouse_mod.clear +
     (gfx.mouse_cap&mouse_mod.lmb) then
    apply = true
  end
  
  local name, path = v:match(".-:(.-)|,|(.-)|,|.+")
  
  local track_template = path .. name .. ".RTrackTemplate"
  
  function ttInsert(temp_template)
    if config.fx_hide then
      local content = getContent(track_template)
      content = fxWndHideChunk(content)
      temp_template = scr.dir .. "temp.RTrackTemplate"
      writeFile(temp_template, content)
    end
    reaper.Main_openProject(temp_template or track_template)
    if config.fx_hide then os.remove(temp_template) end
  end
  
  reaper.Undo_BeginBlock()
  if m_obj or gui.m_cap&mouse_mod.shift > 0 then
    reaper.PreventUIRefresh(1)
      if type(m_obj) == "string" then
        pcall(reaper.SetOnlyTrackSelected,reaper.GetTrack(0, reaper.CountTracks() - 1))
        ttInsert()
      elseif apply then
        ttApply(track_template, sel_tr_count)
      elseif m_obj or gui.m_cap&mouse_mod.shift > 0 and sel_tr_count > 0 then
        local sel_tracks_init
        if gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) and not m_obj then
          sel_tracks_init = getSelectedTracks()
        else
          sel_tracks_init = {m_obj}
        end
        
        local tr = m_obj or reaper.GetSelectedTrack(0, 0)
        local sel_trs = {}
        for i = 1, template_inst or 1 do
          ttInsert()
          if reaper.ValidatePtr2(0, m_obj, "MediaTrack*") or
             gui.m_cap&mouse_mod.shift > 0 and sel_tr_count > 0 then
            reaper.ReorderSelectedTracks(reaper.CSurf_TrackToID(tr, false)-1, 0)
          end
          sel_trs[#sel_trs+1] = reaper.GetSelectedTrack(0, 0)
        end
        
        for i = 1, #sel_trs do
          reaper.SetMediaTrackInfo_Value(sel_trs[i], "I_SELECTED", 1)
          if i > 1 and not config.fx_hide then
            reaper.TrackFX_Show(sel_trs[i], -1, 0)
            for n = 0, reaper.TrackFX_GetCount(sel_trs[i]) - 1 do
              reaper.TrackFX_Show(sel_trs[i], n, 2)
            end
          end
        end
        
        if gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) and
           cntSelTrs() == 1 and (not m_obj or type(m_obj) == "userdata") then
          local tr = getSelTr(0)
          createTrackSend(sel_tracks_init, tr)
        end
        
      end
    reaper.PreventUIRefresh(-1)
  elseif apply then
    ttApply(track_template, sel_tr_count)
  else
    local t_temp = {}
    reaper.PreventUIRefresh(1)
    local f_depth = inFolderPrepare(sel_tr_count)
    if template_inst then
      for i = 1, template_inst do
        ttInsert()
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
          table.insert(t_temp, reaper.GetSelectedTrack(0, i))
        end
      end
      for i = 1, #t_temp do
        reaper.SetTrackSelected(t_temp[i], 1)
      end
      inFolderSet(f_depth, 0)
    else
      ttInsert()
      inFolderSet(f_depth, 1)
    end
    reaper.PreventUIRefresh(-1)
  end
  
  if apply then
    tt_mode = "Apply"
  else
    tt_mode = "Insert"
  end
  
  if content ~= "" then
   reaper.Undo_EndBlock(tt_mode .. " " .. name, -1)
  end
end

function urlOpen(url)
  if os_is.win then
    reaper.ExecProcess('cmd.exe /C start "" "' .. url .. '"', 0)
  elseif os_is.mac then
    reaper.ExecProcess("/usr/bin/open " .. url, 0)
  elseif os_is.lin then
    os.execute('xdg-open "" "' .. url .. '"')    
  end
end

function help()
  literal = true
  reaper.ClearConsole()
  reaper.ShowConsoleMsg([[
Welcome to Quick Adder 2 user guide!

The extension is designed to provide a unified solution for adding track/take/input FX
and track templates in REAPER. You can also run actions with the add-on.

This is achieved through utilizing contextual key commands, which perform as follows:
  ]] .. enter .. [[ (double-click): adds track FX or track template and runs actions;
  ]]..
  mouse_mod[mouse_mod.clear]() .. " + " .. enter .. [[: clears FX chains before adding FX or applies track template; 
  ]]..
  mouse_mod[mouse_mod.input]() .. " + " .. enter .. [[: adds input FX to selected tracks or inserts track templates above first selected track;
  ]]..
  mouse_mod[mouse_mod.clear]() .. " + " .. mouse_mod[mouse_mod.input]() .. " + " .. enter .. [[: clears input FX chain and adds FX;
  ]]..
  mouse_mod[mouse_mod.take]() .. " + " .. enter .. [[: adds FX to selected items' active takes;
  ]]..
  mouse_mod[mouse_mod.clear]() .. " + " .. mouse_mod[mouse_mod.take]() .. " + " .. enter .. [[: clears take FX chains before adding FX;
  ]]..
  mouse_mod[mouse_mod.ctrl]() .. " + " .. mouse_mod[mouse_mod.shift]() .. " + " .. mouse_mod[mouse_mod.alt]() .. " + " ..
  enter .. [[: inserts FX or template on a new track and sends selected tracks (or track under mouse) to it;
  ]]..
  
  mouse_mod[mouse_mod.win]() .. " + " .. mouse_mod[mouse_mod.alt]() .. " + "  ..
  enter .. [[: inserts FX on a new track above the first selected track or the track under mouse cursor.
  
Quick Adder 2 also introduces an in-script favorites system.
It will help you promote any search result to the top of the list.

For example, if you prefer to have ReaComp as one of the first results
when you simply search "comp", first find it by using a fuller query ("reacomp")
and then add it to favorites by either:
  a) hovering your mouse over the FX type (VST2 in this case) or
  b) selecting the result and pressing ]] .. mouse_mod[16]() .. [[ + F on your keyboard.

While in search view mode, you can open the Search Filter Tray, by either
clicking on the button with a magnifier on it or pressing TAB. Then simply use
the right/left arrow keys or your mouse (or shortcuts) to navigate through the menu.

Now is a good time to introduce the interactive Hints Bar. It shows handy
information regarding elements under mouse cursor. So, for example, if you hover
over Search Filter Tray items, you will see their description plus corresponding
keyboard shortcuts in square brackets (that will work as long as the menu is open).

NOTE: many things in the script can be accessed/activated with key commands
and the Hints Bar is a great way to get to know them.

Also, when the search results are in focus the hints can help you rememeber
what key commands to use for adding/clearing FX/templates. Simply press a key
modifier and the hint will tell you what it does.

Quick Adder 2 can be customized in many ways. To do that, access the scripts
Preferences by either clicking the PREFS button or F3 on your keyboard.

To the PREFS' left there is a circular button that activates/deactivates the
Keep Open function. It allows you to leave the script open for further use after
you added an FX or a template.

Additional search query syntax:
use /n flag in your queries to add multiple instances of a template (eg. bgv /4);
put keywords in quotes to do an exact search (e.g. "reaktor 6");
use the - prefix to exclude keywords (e.g. comp -cockos).

Additional keyboard shortcuts:
  F1: open the help file;
  F2: switch to the search view;
  F3: open general preferences;
  F4: open templates preferences;
  F5: refresh plugins/templates database;
  F7: decrease the maximum results number;
  F8: increase the maximum results number;
  F9: make GUI smaller;
  F10: make GUI larger;
  ESC: clear the search box or close Quick Adder 2;
  TAB: toggle Search Filter Tray visibility;
  ~: toggle the Keep Open mode;
  ]] .. mouse_mod[16]() .. [[ + W: show FX window toggle;
  ]] .. mouse_mod[mouse_mod.alt]() .. [[ + ]] .. mouse_mod[mouse_mod.shift]() ..
  [[ + Up: move a favorite up;
  ]] .. mouse_mod[mouse_mod.alt]() .. [[ + ]] .. mouse_mod[mouse_mod.shift]() ..
  [[ + Down: move a favorite down.
  
  While Search Filter Tray is open:
    N: set the search filter to ACT (actions);
    A: set the search filter to ALL (global search);
]]..(os_is.win and "    U: set the search filter to AU;\n" or "")..[[
    C: set the search filter to CH (FX chains);
    F: set the search filter to FAV (favorites);
    O: set the search filter to FOL (FX browser folders);
    X: set the search filter to FX (effects only);
    I: set the search filter to INS (virtual instruments);
    J: set the search filter to JS;
    T: set the search filter to TT (track templates);
    2: set the search filter to VST2;
    3: set the search filter to VST3.

This script has taken a lot of work and care to be developed so all PayPal
contributions are very much welcome and appreciated:
]]
.. scr.links[1]:lower() ..
[[


For more information visit the script's page:
]]
.. scr.links[3], "Quick Adder 2 Help")
  literal = nil
end

function parseQuery()
  local data = gui.str:lower()
   scr.query_parts = {}
 
   local exact = data:match("\".-\"")
   
   if exact then
     scr.query_parts[#scr.query_parts+1] = exact:match("\"(.-)\"")
     data = data:gsub(magicFix(exact), "")
   end
   
   data = data:gsub("\"", "")
   
   local i = 0
   
   for word in data:gmatch("[^%s]+") do
     i = i + 1
  
     word = word:gsub("[\\\"]", "\\%1")
     word = magicFix(word)

     table.insert(scr.query_parts, word)
   end
   if #scr.query_parts > 0 then scr.results_list = {} end
   doMatch()
end

---------------------- GUI -----------------------------
function a_gui()end

local countFilterModes = function()
  local n = 0
  for k, v in pairs(filter_modes) do
    if v then n = n + 1 end
  end
  return n + 1
end

scr.filter_n = countFilterModes()

function getMainW(get_w, relevant_filters)
  local filter_n = scr.filter_n >=9 and scr.filter_n or 9
  local w = (gui.row_h - 4 * math.floor(config.multi)) * 
             filter_n + 5 * math.floor(config.multi) + gui.border * 2
  if get_w then return w end
  return scr.main_w_rs or config.main_w_rs or w 
end

gui.border = 1-- * config.multi
gui.row_h = math.floor(config.row_h * config.multi)
gui.wnd_w = getMainW()
gui.w = gui.wnd_w - gui.border * (config.undock and 2 or 5)
gui.theme = {light = {}, dark = {}}
gui.txt_align = {center = 1<<2|1, vert = 1<<2, right = 1<<2|2, none = 0}
gui.grad_div = 1
gui.view = "main"
scr.results_list = {}
gui.str = ""
gui.blink = 1
gui.b_count = 0

gui.result_rows_init = 0

gui.Results = {}
gui.Results.sel = 1
gui.lists = {}
gui.lists.theme = {"dark", "light"}
gui.lists.res_name = {"|720p", "|1080p", "|4k", "|5k", "|8k"}
                
local defineFilterModes = function()
  gui.lists.mode = {}
  for k, v in pairs(filter_modes) do
    if v then
      table.insert(gui.lists.mode, k)
    end
  end

  gui.lists.mode = sortAbc(gui.lists.mode)
end

defineFilterModes()

--if config.act_search then table.insert(gui.lists.mode, "ACTION") end

gui.lists.db_scan = {"once per REAPER startup",
                     "on every Quick Adder launch",
                     "do not auto refresh"}
gui.lists.no_sel_tracks = {"prompts to select tracks to put FX on",
                           "adds FX to a new track",
                           "does nothing"}
for i, v in ipairs(gui.lists.mode) do
  if v == config.mode then
    gui.mode_sel = {i}
    break
  elseif i == #gui.lists.mode then
    gui.mode_sel = {1}
  end
end
gui.mode_sel[2] = config.mode

function fontStyle(str)
  local v = 0
  for i = 1, str:len() do
    v = v * 256 + string.byte(str, i)
  end
  return v
end

function fontSzAdjust(sz, adj, special)
  if os_is.mac then
    sz = sz - adj -- 7 for the pin button, 3 for all, 4 for FX button
  end
  return (sz - (special and not config.undock and 2 or 0)) * config.multi
end

function initFonts()
  gfx.setfont(1, "Arial", fontSzAdjust(12, 2), fontStyle("")) -- prefs
  gfx.setfont(2, "Arial", fontSzAdjust(config.multi == 1 and 13 or 12, config.multi == 1 and 3 or 2), fontStyle("")) -- hints
  gfx.setfont(3, "Arial", fontSzAdjust(13, config.multi == 1 and 3 or 2), fontStyle("b")) -- mode
  gfx.setfont(4, "Arial", fontSzAdjust(16, 3), fontStyle("")) -- reminder bttn
  gfx.setfont(5, "Arial", fontSzAdjust(18, 2, true), fontStyle("")) -- results
  gfx.setfont(6, "Arial", fontSzAdjust(22, 7), fontStyle("")) -- pin bttn
  gfx.setfont(7, "Arial", fontSzAdjust(30, 4), fontStyle("")) -- search
  gfx.setfont(15, "Arial", fontSzAdjust(25, config.multi == 1 and 4 or 2), fontStyle("")) -- search clear
  gfx.setfont(8, "Arial", fontSzAdjust(35, 55), fontStyle("")) -- star
  gfx.setfont(9, "Arial", fontSzAdjust(11, 2), fontStyle("b")) -- nav tabs
  gfx.setfont(10, "Arial", fontSzAdjust(12, 2), fontStyle("b")) -- reminder, type tags
  gfx.setfont(11, "Arial", fontSzAdjust(9, 2), fontStyle("b")) -- little results star
  gfx.setfont(12, "Arial", fontSzAdjust(40, 2), fontStyle("b")) -- telephone recorder
  gfx.setfont(13, os_is.win and "Calibri" or "Arial", fontSzAdjust(15, 4), fontStyle(""))
  gfx.setfont(14, os_is.win and "Calibri" or "Arial", fontSzAdjust(14, 4), fontStyle("")) -- dd
end

initFonts()

function macAdjustGfxH()
  if config.retina then return end
  gui.wnd_h = os_is.mac and (gui.wnd_h <= scr.vp_h and gui.wnd_h or scr.vp_h) or gui.wnd_h
  gui.wnd_h_save = os_is.mac and (gui.wnd_h_save <= scr.vp_h and gui.wnd_h_save or scr.vp_h) or gui.wnd_h
end

function getPrefsW()
  local w = gui.page == "nav_general" and 406 + (config.act_search and 63 or 0) or
           ((gui.page == "nav_templates" and (config.multi == 1 and 370 or 352)) or
           (gui.page == "nav_about" and (config.multi == 1 and 333 or 313))) -
           (os_is.mac and (config.multi == 1 and 30 or 10) or 0)
           
  return config.multi == res_multi["|720p"] and w or
         config.multi == res_multi["|1080p"] and w * config.multi * 0.948 or
         config.multi == res_multi["|4k"] and w * config.multi * 0.944 or
         config.multi == res_multi["|5k"] and w * config.multi * 0.958 or
         config.multi == res_multi["|8k"] and w * config.multi * 0.966
end

function gui:init()
  local isRetina = function(val)
    if val == 2 then
      config.retina = true
    else
      config.retina = nil
    end
  end
  
  local refocus = function()
    if gfx.getchar(65536)&2 ~= 2 and reaper.JS_Window_SetFocus then
      local wnd = reaper.JS_Window_Find(scr.name, true)
      reaper.JS_Window_SetFocus(wnd)
    end
  end
  
  local dock = not config.undock and config.dock and config.dock or 0

  if not gui.open then
    if not config.undock then scr.main_w_rs = gui.wnd_w end
    scr.vp_w, scr.vp_h = getResolution(true)
    local wnd_x = config.wnd_x or (scr.vp_w - gui.wnd_w)/2 - 8
    local wnd_y = config.wnd_y or (scr.vp_h - gui.wnd_h)/2
    gui.open = true
    gfx.ext_retina = 1
    local init_retina = config.retina
    gfx.init(scr.name, retinaDivide(gui.wnd_w), retinaDivide(gui.wnd_h), dock, wnd_x, wnd_y)
    isRetina(gfx.ext_retina)
    
    if not init_retina and config.retina then -- reopen if first time retina
      gfx.quit()
      gfx.init(scr.name, retinaDivide(gui.wnd_w), retinaDivide(gui.wnd_h), dock, wnd_x, wnd_y)
    end
    
    refocus()
    
    if reaper.JS_Window_AttachTopmostPin and reaper.JS_Window_Find then
      local wnd = reaper.JS_Window_Find(scr.name, true)
      reaper.JS_Window_AttachTopmostPin(wnd)
    end
  end

  if gui.reinit then
    gui.reinit = nil
    local _, wnd_x, wnd_y = gfx.dock(-1, 0, 0, 0, 0)
    macAdjustGfxH()
    wnd_y = macYoffset(retinaDivide(gui.wnd_h_save), retinaDivide(gui.wnd_h), wnd_y)
    gui.wnd_h_save = nil
    if gfx.dock(-1)&1 == 0 and scr.main_w_rs then gui.wnd_w = config.main_w_rs end
    gfx.init("", retinaDivide(gui.wnd_w), retinaDivide(gui.wnd_h), dock, wnd_x, wnd_y)
    refocus()
  end
  
  if gui.reopen then
    gui.reopen = nil
    local _, wnd_x, wnd_y = gfx.dock(-1, 0, 0, 0, 0)
    gui.wnd_h_save = scr.o_r and config.wnd_h_save or gui.wnd_h_save
    wnd_y = scr.o_r and config.wnd_y or wnd_y
    wnd_y = macYoffset(retinaDivide(gui.wnd_h_save), retinaDivide(gui.wnd_h), wnd_y)
    config.wnd_h_save = not scr.o_r and gui.wnd_h or gui.wnd_h_save
    config.wnd_y = not scr.o_r and select(3, gfx.dock(-1, 0, 0, 0, 0)) or config.wnd_y
    scr.o_r = nil
    gui.wnd_h_save = nil
    if scr.main_w_rs and gui.view == "main" then
      scr.main_w_rs = nil
      gui.wnd_w = getMainW()
      gui.w = getMainW() - gui.border * 2
    end
    if gfx.dock(-1)&1 == 0 or config.undock or gfx.getchar(65536)&4 ~= 4 then
      gfx.quit()
      gfx.init(scr.name, retinaDivide(gui.wnd_w), retinaDivide(gui.wnd_h),dock, wnd_x, wnd_y)
    end
    
    refocus()
    
    if reaper.JS_Window_AttachTopmostPin and reaper.JS_Window_Find then
      reaper.JS_Window_AttachTopmostPin(reaper.JS_Window_Find(scr.name, true))
    end
  end
end

function gui:setChild(o, wnd_h, parent_grow, margin_lr, margin_tb, self_shrink, margin_bottom)
  local o = o or {}
  setmetatable(o, self)
  self.__index = self
  o:float()
  margin_tb = not margin_tb and margin_lr and margin_lr or margin_tb
  o.h = math.floor(o.h)
  local shrink_multi = config.multi == 1 and 1.4 or
        (os_is.mac and gui.page == "nav_about" and 2.7) or
        (config.multi < 3 and 2 or config.multi < 4 and 1.8 or 1.7)
  local shrink_multi2 = os_is.mac and gui.page == "nav_about" and
        (config.multi == 1 and 1.4 or config.multi < 3 and 2 or config.multi < 4 and 1.8 or 1.7) or
        shrink_multi
  local multi = math.floor(config.multi)
  o.x1 = o.x1 + (margin_lr or 0) * multi
  o.y1 = o.y1 + (margin_tb and margin_tb * shrink_multi2 or 0) * multi
  
  if wnd_h then gui.wnd_h = gui.wnd_h + o.h + (margin_bottom and (os_is.mac and gui.page == "nav_about" and (
  config.multi == 1 and margin_lr or config.multi < 3 and - margin_lr - gui.border or
  config.multi < 4 and -margin_tb * shrink_multi2 + margin_lr or -margin_lr * 2) or margin_lr) or 0) * multi end
  
  if self_shrink then
    o.w = o.w - (margin_lr or 0) * multi * 2
    o.h = o.h - (margin_tb * shrink_multi or 0) * multi
  end
  if parent_grow then
    --self.w = self.w + o.w
    self.h = self.h + o.h + (margin_bottom and margin_tb * shrink_multi2 + margin_lr or margin_tb * shrink_multi2 or 0) * multi
    self.y2 = self.y1 + self.h
  end
  o.x2 = o.x1 + o.w-- + (margin or 0)
  o.y2 = o.y1 + o.h-- + (margin or 0)
  o:hover()
  return o
end

function gui:setCheckBox(o, margin)
  local o = o or {}
  setmetatable(o, self)
  self.__index = self
  o:float()
  o.cb = true
  o.on_click = true
  o.w = 15 * config.multi
  o.h = 15 * config.multi
  if margin then margin = o.margin end
  o.x1 = o.x1 + (margin or 0) * config.multi
  o.y1 = o.y1 + (margin or 0) * config.multi
  o.x2 = o.x1 + o.w-- - (margin or 0) * 2
  o.y2 = o.y1 + o.h-- - (margin or 0) * 2
  return o
end

function gui:setLink(no_pref)
  local str = no_pref and self.txt or utf8.char(os_is.win and 8599 or 8594) .. " " .. self.txt
  self:drawTxt(str, _, true, true, _, _, true)
  self.on_click = true
  self:drawTxt(str, _, true, true)
  return self
end

function color(r, g, b, a)
  gfx.r = r/255
  gfx.g = g and g/255 or r/255
  gfx.b = b and b/255 or r/255
  gfx.a = a and a/255 or 1
end

function gui:blur(multi)
  for i = 1, 1 * multi do
    gfx.x = 0
    gfx.y = 0
    gfx.blurto(gfx.w,gfx.h)
  end
end

function gui:resetDd()
  gui.focused = nil
  gui.dd_items = nil
  gui.important = nil
  gui.dd_active_slot = nil
  gui.dd_m_x = nil
  gui.dd_m_y = nil
end

function gui:color(r, g, b, a)
  self.c = not g and r or self.c
  self.r = g and r or nil
  self.g = g or nil
  self.b = b or nil
  self.a = a or nil
  return self
end

function inBounds()
  if gui.m_x >= 0 and gui.m_x <= gfx.w and gui.m_y >= 0 and gui.m_y <= gfx.h then
    return true
  else
    gui.over = nil
    if gui.m_cap == 0 then
      --gui.clicked = nil
      gui.active = nil
      gui.m_x_click = nil
      gui.m_y_click = nil
      double_clicked_id = nil
      if gui.mouse_clicked then
        gui:resetDd()
      end
      --gui.z_zero = nil
    end
    if gui.focus ~= 2 then
      gui:resetDd()
    end
  end
end

function themeSwitch()
  if config.theme == "dark" then
    config.theme = "light"
  else
    config.theme = "dark"
  end
end

function a_styles()end

function gui.theme:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function gui.theme:search_txt()
  self.font = os_is.mac and self.id == "clear" and 15 or 7
  self.txt_align = gui.txt_align["vert"]
  self.pad_x = 3
  self.pad_y = 0
end

function gui.theme:alert()
  self.font = 5
  self.txt_align = gui.txt_align["none"]
  self.font_c = 225
end

function gui.theme:reminder()
  self.font_c = 255
  self.c = 200
  self.r = 0
  self.g = 150
  self.b = 0
  self.pad_x = 0
  self.pad_y = os_is.mac and config.multi > 1 and 2 or 0
  self.font = 4
  self.txt_align = gui.txt_align["center"]
end

function gui.theme:prefs()
  self.c = gui.bg_hue
  self.pad_x = 0
  self.pad_y = os_is.mac and (self.txt and 3 * config.multi or config.multi == 1 and
                             (self.id:match("^view.+") and -1 or not self.id:match("^view.+") and 0) or
                              2) or 0
  self.font = self.txt and 13 or 1
  self.txt_align = gui.txt_align["center"]
end

function gui.theme:hints_txt()
  self.font = 2
  self.txt_align = gui.txt_align["vert"]
  self.pad_x = 3
  self.pad_y = config.multi == 1 and -1 or 0
end

function gui.theme:mode_txt()
  self.font = 3
  self.txt_align = gui.txt_align["center"]
  self.pad_x = 0
  self.pad_y = config.multi == 1 and -1 or os_is.mac and math.floor(config.multi) or 0
end

gui.theme.light = gui.theme:new()  
gui.theme.dark = gui.theme:new()  

function gui.theme.light:search()
  self.font_c = gui.view == "main" and 77 or 50
  self.c = --[[gui.view == "main" and 210 or ]]240
end

function gui.theme.dark:search()
  self.font_c = gui.view == "main" and 210 or 230
  self.c = 70
end

function gui.theme.light:txt()
  self.font_c = 235
end

function gui.theme.light:mode()
  self.font_c = 235
  self.c = 60
end

function gui.theme.dark:txt()
  self.font_c = 200
end

function gui.theme.dark:cb()
  self.c = 190
  self.font_c = 255 - self.c
end

function gui.theme.light:cb()
  self.c = 77
  self.font_c = 210
end

function gui.theme.light:dd()
  self.c = 225
  self.font_c = 60
end

function gui.theme.dark:dd()
  self.c = 80
  self.font_c = 230
end

function gui.theme.dark:mode()
  self.font_c = 200 --200
  self.c = 30 --30
end

function gui:float()
  if self.float_zero then
    self.y1 = self.h
    self.float_zero = nil
  end
  if self.float_t then
    self.y1 = self.float_t.y1 - self.h
    self.float_t = nil
  end
  if self.float_b then
    self.y1 = self.float_b.y2
    self.float_b = nil
  end
  if self.float_l then
    self.x1 = self.float_l.x1 - self.w
    self.float_l = nil
  end
  if self.float_l_auto_w then
    self.w = self.w - (self.w - self.float_l_auto_w.x1 + gui.border)
    self.float_l_auto_w = nil
  end
  if self.float_r then
    self.x1 = self.float_r.x2 + (self.margin or 0)
    self.float_r = nil
  end
  if self.float_r_auto_w then
    self.x1 = self.float_r_auto_w.x2-- + gui.border
    self.w = self.w - self.x1 + gui.border
    self.float_r_auto_w = nil
  end
end

function gui:isOver()
  if gui.m_x >= self.x1 and gui.m_x < self.x2 and
     gui.m_y >= self.y1 and gui.m_y < self.y2 then
    return true
  end
end

function gui:setCursor()
  if gui.m_cap&mouse_mod.lmb == mouse_mod.lmb then return end
  if self.id and self.id:match("dragV") then
    if gui.m_cursor ~= "ns_arrow" then
      gfx.setcursor(32645) -- North-South arrow
      gui.m_cursor = "ns_arrow"
    end
  elseif gui.m_cursor == "ns_arrow" or
         self.cursor == "arrow" then
    if gui.m_cursor ~= "arrow" then
      gfx.setcursor(32512) -- arrow
      gui.m_cursor = "arrow"
    end
  elseif self.id and self.txt_field then
    if gui.m_cursor ~= "i_beam" then
      gfx.setcursor(32513) -- I-beam
      gui.m_cursor = "i_beam"
    end
  end
end

function gui:hover(special)
  if self.hover_special and not special then return end
  if self:isOver() then
    gui.over = self.id
    self:setCursor()
    if gui.focus == 2 then
      self:onSelect()
      self:onClick()
    elseif gui.m_cap&1 == 0 and gui.selected then
      gui.selected = nil
      gui.loop_start = nil
    end
  end
  return self
end

function a_mouse()end

function gui:onClickSpecial()
  if not self:isOver() then return end
  if (gui.m_cap&mouse_mod.rmb == mouse_mod.rmb or gui.m_cap&64 == 64) and
      gui.over == self.id and not gui.active and not gui.important then
    gui.active = self
    gui.active.m_cap = gui.m_cap 
  elseif gui.m_cap == 0 and gui.active and gui.active:isOver() then
    gui.clicked = {id = gui.active.id, m_cap = gui.active.m_cap}
    gui.active = nil
  elseif gui.m_cap == 0 and gui.active and not gui.active:isOver() then
    gui.active = nil
  end
end

function gui:onClick()
  if _timers.double_click and _timers.double_click.up then
    _timers.double_click = nil
  end
   
  if self.on_select and gui.Results.sel ~= tonumber(self.id:match("result_(%d+)")) then
    return
  end
  
  if gui.m_cap&1 == 1 then
    if not gui.loop_start then
      gui.loop_start = self.id
    elseif gui.loop_start and gui.loop_start == self.id and not gui.active then
      gui.click_ignore = true
    end
    if (self.bttn or self.on_click) and not gui.click_ignore and
        not gui.active and not gui.important and self.id then
      gui.active = self
      gui.active.m_cap = gui.m_cap
      gui.m_x_click = gui.m_x
      gui.m_y_click = gui.m_y
    elseif gui.m_cap&1 == 1 and not gui.selected and
           gui.focused and not gui.focused:isOver() and not gui.active then
      gui.mouse_clicked = gui.focused
    end
  elseif gui.m_cap&3 == 0 and gui.active and gui.active:isOver() and
        (gui.active.id:match("result.+(%d+)") or not gui.active.on_select) then
    if not _timers.double_click then
      _timers.double_click = timer:new():start(config.dbl_click_speed)
      double_clicked_id = gui.active.id
    elseif _timers.double_click then
      double_clicked = true
      _timers.double_click = nil
    end
    gui.clicked = {id = gui.active.id, m_cap = gui.active.m_cap, o = gui.active} 
    gui.active = nil
    self_x1_saved = nil
    gui.m_x_click = nil
    gui.m_y_click = nil
    gui.loop_start = nil
    gui.click_ignore = nil
  elseif gui.m_cap == 0 and gui.active and not gui.active:isOver() then
    gui.active = nil
    self_x1_saved = nil
    gui.m_x_click = nil
    gui.m_y_click = nil
    gui.loop_start = nil
    gui.click_ignore = nil
  elseif gui.m_cap == 0 and gui.mouse_clicked then
    if gui.focused and gui.focused.id == gui.mouse_clicked.id then
      local id = gui.focused.id
      gui.focused = nil
      gui.dd_items = nil
      gui.important = nil
      gui.dd_active_slot = nil
      gui.dd_m_x = nil
      gui.dd_m_y = nil
      if id ~= "dd_1_mode" then goto SKIP end
      for i, v in ipairs(gui.lists.mode) do
        if v == config.mode then
          gui.mode_sel[1] = i
          break
        end
      end
      gui.mode_sel[2] = config.mode
      ::SKIP::
    end
    gui.mouse_clicked = nil
  elseif gui.m_cap == 0 and gui.loop_start then
    gui.loop_start = nil
    gui.click_ignore = nil
  end
end

function gui:onSelect()
  if gui.m_cap == 25 then return end -- if Alt + Shift
  if gui.m_cap&1 == 1 and not gui.active and not gui.click_ignore and
      self.on_select and not gui.selected and self.id then
    if gui.important and (gui.important:isOver() and gui.important.id ~= self.id or
       not gui.important:isOver() and gui.important.parent_id and gui.important.parent_id ~= self.id or
       not gui.important:isOver() and not gui.important.parent_id and self.id ~= "reminder") then
      return
    end
    gui.active = self
    gui.active.m_cap = gui.m_cap
    gui.clicked = {id = self.id, m_cap = gui.m_cap, o = self}
    gui.selected = true
    gui.m_x_click = gui.m_x
    gui.m_y_click = gui.m_y
    if not _timers.double_click and not self.id:match("result") then
      _timers.double_click = timer:new():start(config.dbl_click_speed)
      double_clicked_id = gui.active.id
    elseif _timers.double_click then
      double_clicked = true
      _timers.double_click = nil
    end
    
  elseif gui.m_cap&1 == 0 and self.on_select and gui.selected then
    gui.active = nil
    gui.selected = nil
    gui.m_x_click = nil
    gui.m_y_click = nil
  elseif gui.m_cap&1 == 0 and gui.selected and gui.focused and not gui.focused:isOver() then
    gui.selected = nil
  end
end

function a_draw()end
  
function gui:drawCbBox()
  local cb_name = self.id:gsub("cb_", "")
  local bg_c = self.c
  self:setStyle("cb")
  local fg_c = config.theme == "light" and self.c or self:setStyle("search") and self.font_c - 25
  
  if gui.active and gui.active.id == self.id or
     not gui.active and not gui.important and self.id == gui.over then
    fg_c = fg_c + (config.theme == "light" and 55 or 25)
  end
  color(fg_c)
  gfx.rect(self.x1, self.y1, self.w, self.h, 1) -- border
  color(bg_c)
  local multi = math.floor(gui.border * config.multi)
  gfx.rect(self.x1 + multi, self.y1 + multi,
           self.w - multi * 2, self.h - multi * 2, 1) -- bg
  color(fg_c)
  if self.table and (not self.reverse and self.table[cb_name] or
     self.reverse and not self.table[cb_name]) or config[cb_name] then
    gfx.rect(self.x1 + multi * 3, self.y1 + multi * 3,
             self.w - multi * 6, self.h - multi * 6, 1) -- fill
  end
end

function gui:drawDdMenu(fill, label, parent)
  local r = self.r or self.c
  local g = self.g or nil
  local b = self.b or nil
  local a = self.a or nil
  r, g, b = self:bttnOver(r, g, b)
  color(r, g, b, a)
 
  gfx.rect(self.x1, self.y1, self.w, self.h, fill or 1)
  if parent then
    self.c = r - 52-- config.theme == "light" and r - 52 or self:setStyle("txt") and self.font_c - 65
    self:drawBorder()--:setStyle("dd")
    self.c = r
  end
  local tbl = gui[self.table] or self.table
  local slot_n, pad_x_mem
  if parent and self.numbered and gui.dd_items and gui.dd_items[1].table == self.table then
    self.txt_align = gui.txt_align["right"]
    local num = self.id:match("dd_(%d+).+")
    self:drawTxt("|" .. num, self.pad_x)
    self.txt_align = gui.txt_align["vert"]
  elseif parent then
    self.txt_align = gui.txt_align["right"]
    local arrow
    
    if self.direction == "float_b" or not gui.dd_items or self.id ~= gui.dd_items[1].parent_id then
      arrow = utf8.char(9660) -- triangle down
    elseif self.direction == "float_t" and self.id == gui.dd_items[1].parent_id then
      arrow = utf8.char(9650) -- triangle up
    end

    self:drawTxt(arrow, fontSzAdjust(self.pad_x, 1))

    self.txt_align = gui.txt_align["vert"]

  elseif not parent and not self.id:match("dd_.-_(%d-)") or
         self.table_name == "mode" and gui.dd_items[1].parent_id == "dd_1_mode" then

    self.txt_align = gui.txt_align["center"]
    pad_x_mem = self.pad_x
    self.pad_x = 0
  else
    self.txt_align = gui.txt_align["vert"]
  end
  

  self:drawTxt(tbl[label] == "CHAIN" and "CH" or tbl[label] == "TEMPLATE" and "TT" or
               tbl[label] == "ACTION" and "ACT" or tbl[label] == "FOLDER" and "FOL" or
               tbl[label] == "INSTRUMENT" and "INS" or tbl[label] or
               (self.table_name == "mode" and
               (label == "CHAIN" and "CH" or label == "TEMPLATE" and "TT" or
                label == "ACTION" and "ACT" or label == "FOLDER" and "FOL" or
                label == "INSTRUMENT" and "INS") or label))

  self.pad_x = pad_x_mem
  self:hover()
  return self
end

function gui:drawRect(fill, round, nav)
  local r = self.r or self.c
  local g = self.g or nil
  local b = self.b or nil
  local a = self.a or nil
  r, g, b = self:bttnOver(r, g, b)
  color(r, g, b, a)
  if not round then
    gfx.rect(self.x1, self.y1, self.w, self.h, fill or 1)
  else
    gfx.roundrect(self.x1, self.y1, self.w - 1, self.h, 4, 1)
  end
  if nav and gui.page ~= self.id then
    color(gui.bg_hue + (config.theme == "light" and 100 or 10))
    local width = math.floor(config.multi)
    gfx.rect(self.x1, self.y1, width, self.h, 1) -- left
  end
  return self
end

function gui:drawBorder(w)
  if self.border_coord then
    color(config.theme == "light" and self.c - 52 or 200)
  else
    color(self.r or self.c, self.g, self.b)
  end
  local self_temp = self.border_coord and self or nil
  self = self.border_coord and self.border_coord or self
  self.x2 = w and self.x1 + w or self.x2
  local width = math.floor(config.multi)
  gfx.rect(self.x1, self.y1, w or self.w, width, 1) -- top
  gfx.rect(self.x1, self.y1, width, self.h, 1) -- left
  gfx.rect(self.x2 - width, self.y1, width, self.h, 1) -- right
  gfx.rect(self.x1, self.y2 - width, w or self.w, width, 1) -- bottom
  self = self_temp and self_temp or self
  return self
end

function gui:drawMGright()
  color(self.font_c)
  local r = 7 * config.multi
  local x = self.w/2 + gui.border*(config.undock and 1 or 4) - r/8
  local y = (self.y1 + self.h/2) - r/3
  gfx.circle(x, y, r, 1, 1) -- draw outer circle
  color(self:bttnOver(self.c))
  local width = r - (config.multi == 1 and 2 or 3) * math.floor(config.multi)
  gfx.circle(x, y, width, 1, 1) -- draw inner circle
  color(self.font_c)
  width = (config.multi == 1 and width * 2.5 or
           config.multi < 2 and width * 2.1 or
           config.multi < 4 and width * 1.1 or width * 0.9)
  local deg = math.floor(45 - width / 2)
  local x1 = x + r * math.cos(math.rad(deg))
  local y1 = y + r * math.sin(math.rad(deg))
  local x2 = x + r * math.cos(math.rad(deg + width))
  local y2 = y + r * math.sin(math.rad(deg + width))
  gfx.triangle(x1, y1,
               x1 + r, y1 + r,
               x2 + r, y2 + r,
               x2, y2) -- draw handle
  return self
end

function gui:drawFloat(state)
  color(self.font_c - (state and 90 or 0))
  local r = config.multi == res_multi["|720p"] and 10 or
            config.multi == res_multi["|1080p"] and 14 or
            config.multi == res_multi["|4k"] and 32 or
            config.multi == res_multi["|5k"] and 44 or
            config.multi == res_multi["|8k"] and 64
  local width = config.multi == res_multi["|720p"] and 1 or
                config.multi == res_multi["|1080p"] and 1 or
                config.multi == res_multi["|4k"] and 3 or
                config.multi == res_multi["|5k"] and 4 or
                config.multi == res_multi["|8k"] and 6
  local k2_y = config.multi == res_multi["|720p"] and 6 or
               config.multi == res_multi["|1080p"] and 9 or
               config.multi == res_multi["|4k"] and 19 or
               config.multi == res_multi["|5k"] and 27 or
               config.multi == res_multi["|8k"] and 36
  local km_y = config.multi == res_multi["|720p"] and 4 or
               config.multi == res_multi["|1080p"] and 7 or
               config.multi == res_multi["|4k"] and 12 or
               config.multi == res_multi["|5k"] and 17 or
               config.multi == res_multi["|8k"] and 24
  local pad = config.multi == res_multi["|720p"] and 2 or
               config.multi == res_multi["|1080p"] and 1 or
               config.multi == res_multi["|4k"] and 0 or
               config.multi == res_multi["|5k"] and 1 or
               config.multi == res_multi["|8k"] and -3
  local x = self.x1 + pad
  local y = self.y1 + (self.h - r)/2 - 1              
  
  color(self.font_c - (state and 90 or 0))
  local m = (config.multi == res_multi["|1080p"] and 1 or 3)*config.multi
  local knob = width * 3
  gfx.rect(x + width * (config.multi == res_multi["|1080p"] and 4 or 3),
           y + width + (config.multi == res_multi["|1080p"] and 2 or 0),
           width, r - width * 4 + m, 1)
  gfx.rect(x + r + m - width * 4,
           y + width + (config.multi == res_multi["|1080p"] and 2 or 0),
           width, r - width * 4 + m, 1)
  
  gfx.rect(x + width * (config.multi == res_multi["|1080p"] and 3 or 2),
           y + (state and km_y or width*(config.multi == res_multi["|1080p"] and 5 or 2)),
           knob, knob, 1)
           
  gfx.rect(x + r + m - width * 5,
           y + (state and km_y or k2_y),
           knob, knob, 1)
          
end

function gui:drawPin(state)
  color(self.font_c - (state and 0 or 90))
  local x = self.x1 + self.w / 2 - (config.multi == res_multi["|1080p"] and rpr.ver >= 6 and 0 or 1)
  local y = self.y1 + self.h / 2 - (config.multi == res_multi["|1080p"] and rpr.ver >= 6 and 0 or 1)
  local r = config.multi == res_multi["|720p"] and 5 or
            config.multi == res_multi["|1080p"] and 7 or
            config.multi == res_multi["|4k"] and 16 or
            config.multi == res_multi["|5k"] and 22 or
            config.multi == res_multi["|8k"] and 32
  local width = config.multi == res_multi["|720p"] and 1 or
                config.multi == res_multi["|1080p"] and 1 or
                config.multi == res_multi["|4k"] and 3 or
                config.multi == res_multi["|5k"] and 4 or
                config.multi == res_multi["|8k"] and 6
  gfx.circle(x, y, r, 1)
  color(self:bttnOver(self.c))
  gfx.circle(x, y, r - width, 1)
  color(self.font_c - (state and 0 or 90))
  local width_2 = config.multi == res_multi["|720p"] and width * 2 or
          config.multi == res_multi["|1080p"] and width * 3 or
          config.multi == res_multi["|4k"] and width * 2 or
          config.multi == res_multi["|5k"] and width * 2 or
          config.multi == res_multi["|8k"] and width * 2
  gfx.circle(x, y, r - width_2, 1)
  if not state then
    color(self:bttnOver(self.c))
    local width_3 = config.multi == res_multi["|720p"] and width * 3 or
            config.multi == res_multi["|1080p"] and width * 4 or
            config.multi == res_multi["|4k"] and width * 3 or
            config.multi == res_multi["|5k"] and width * 3 or
            config.multi == res_multi["|8k"] and width * 3
    gfx.circle(x, y, r - width_3, 1)
  end
end

function gui:drawTxt(str, shrink, change_w, change_h, pad_w, pad_h, measure_only, highlight)
  color(self.font_c)
  str = self.upper and str:upper() or self.lower and str:lower() or
        self.cap and str:gsub("^%a", string.upper) or str
  gfx.x = self.x1 + math.floor((self.pad_x or 0) * config.multi)
  local pad_y = 0
  pad_y = --[[os_is.mac and self.font == 13 and pad_y + 3 or os_is.win and self.font == 13 and pad_y - 1 or ]]self.pad_y
  gfx.y = self.y1 + (pad_y or 0)
  --if os_is.mac then self.y2 = self.y2 + (self.pad_y or 0) * config.multi end
   
  gfx.setfont(self.font)
  local w, h = gfx.measurestr(str)
   
  if change_w then
    pad_w = pad_w and pad_w * config.multi * 2 or nil
    w = pad_w and w + pad_w or w
    self.w = w
    self.x2 = self.x1 + self.w
  end
  
  if change_h then
    pad_h = pad_h and pad_h * config.multi * 2 or nil
    h = pad_h and h + pad_h or h
    self.h = h
    self.y2 = self.y1 + self.h
  end
  
  if self.link and self.on_click then
    if self.id == "link_pp" then
      color(0, 
            gui.active and gui.active.id == self.id and config.theme == "dark" and 205 or
            gui.active and gui.active.id == self.id and 100 or
            config.theme == "dark" and 235 or
            150, 0)
    else
      color(gui.active and gui.active.id == self.id and self.font_c - 50 or self.font_c)
    end
    if self:isOver() and not gui.active or gui.active and gui.active.id == self.id then
      self:hover()
      --self.font = 15
      --gfx.setfont(self.font)
      gfx.rect(self.x1, self.y2, self.w, math.floor(config.multi), 1)
    end
  end
  
  if not measure_only then
    gfx.drawstr(str, self.txt_align, self.x2 - (shrink or 0), self.y2 + 1)
    if highlight then
      color(255)
      local x = gfx.x
      gfx.x = self.x1 + highlight + self.pad_x * config.multi
      gfx.drawstr(gui.str_hl, self.txt_align, self.x2 - (shrink or 0), self.y2 + 1)
      gfx.x = x
    end
  end
  
  return self, w, h
end

function gui:drawTitle()
  self:setStyle("search"):drawTxt(self.txt, _, true, true, 8, 2, true)
  :drawRect():drawTxt(self.txt)
  return self
end

function gui:drawCb(str, w_override)
  color(self.font_c)
  gfx.setfont(self.font)
  local str_w = gfx.measurestr(str)
  gfx.x = self.x2 + (self.margin or 0)
  local pad_y = 0
  pad_y = os_is.mac and self.font == 13 and pad_y + 2 / config.multi or self.pad_y
  gfx.y = self.y1 + (pad_y or 0) * config.multi
  self.x2 = self.x2 + (self.margin or 0) * 2 + str_w
  gfx.drawstr(str, gui.txt_align["vert"], w_override or self.x2, self.y2 + 1)
  self:hover()
  if self.cb then
    self:drawCbBox()
  end
  return self
end

function gui:setStyle(id)
  pcall(function()self.theme[id](self)end)
  pcall(function()self.theme[config.theme][id](self)end)
  return self
end

function gui:getMode()
  if config.mode == "ALL" then
    self:drawMGright()
    --self.font = 12
    --self:drawTxt(utf8.char(8981)) -- telephone recorder
    --self.font = 3
  elseif config.mode == "CHAIN" then
    self:drawTxt("CH")
  elseif config.mode == "TEMPLATE" then
    self:drawTxt("TT")
  elseif config.mode == "ACTION" then
    self:drawTxt("ACT")
  elseif config.mode == "FOLDER" then
    self:drawTxt("FOL")
  elseif config.mode == "INSTRUMENT" then
    self:drawTxt("INS")  
  elseif config.mode == "FAV" then
    self.font = 8
    self.pad_y = fontSzAdjust(-4, -4)
    self.pad_x = os_is.win and 1 or 0
    self:drawTxt(utf8.char(9733)) -- filled star
    self:setStyle("mode_txt")
  else
    --self.font = 3
    gui.theme.light.mode_overlay_r = nil
    gui.theme.light.mode_overlay_g = nil
    gui.theme.light.mode_overlay_b = nil
    gui.theme.light.mode_overlay_a = nil
    self:drawTxt(config.mode:upper())
  end
  return self
end 

function gui:bttnOver(r, g, b)
  if self.bttn and gui.active and gui.active.id == self.id and not self.on_select or
     self.on_select and gui.focused and self.id == gui.focused.id and not self.id:match("reminder")then
    if self.id == "dd_1_mode" then
      r = config.theme == "light" and r or 5
    else
        r = r - (gui.dd_items and config.theme == "light" and self.x1 == gui.focused.x1 and 20 or
                 gui.dd_items and self.x1 == gui.focused.x1 and 10 or
                 not gui.dd_items and 20 or 0)
    end
  elseif self.bttn and not gui.active and gui.over and gui.over == self.id then
    if self.r or gui.theme.light.mode_overlay_r and gui.over == "mode" then
      r = r + 20
      g = g + 20
      b = b + 20
    elseif gui.important and gui.important.id ~= self.id then
    else
      if not gui.dd_items then -- or gui.dd_items and gui.dd_items[1].parent_id == "dd_1_mode" then
        r = r + (config.theme == "dark" and self.id == "dd_1_mode" and 10 or 20)
      else
        --r = 130-- 51
        --g = 153
        --b = 255
        --self.font_c = 255
      end
    end
    if self.bttn_txt then
      self.font_c = self.font_c + 60
    end
  elseif self.nav_bttn and self.id == gui.page then
  elseif self.nav_bttn and gui.over == self.id and not gui.important then
    r = r - (config.theme == "light" and 40 or 20)
  elseif self.nav_bttn and (gui.page ~= self.id or self:isOver() and gui.important and gui.important.id ~= self.id) then
    r = r - (config.theme == "light" and 60 or 20) 
    self.font_c = self.font_c - (config.theme == "light" and 0 or 60)
  end

  return r, g, b
end

function gui:carriage()
  if gui.txt_hl then color(204,102,0) else color(self.font_c) end
  gfx.measurechar(gui.ch) -- updates the carriage when no characters
  --color(0,120,215)
  if gui.ch ~= 0 and gui.ch ~= ignore_ch.up and
     gui.ch ~= ignore_ch.down then -- if left or right key
    carriage_suspend = true
    _timers.carriage_suspend = timer:new():start(0.3)
  end
  
  if not carriage_suspend and not carriage_pause or
     _timers.carriage_suspend and _timers.carriage_suspend.up then
    if _timers.carriage_suspend then
      _timers.carriage_suspend = nil
      carriage_suspend = nil
    end
    
    if not _timers.carriage then
      _timers.carriage = timer:new():start(0.5)
    elseif _timers.carriage.up then
      _timers.carriage = nil
      if gui.blink == 0 then
        gui.blink = 1
      else
        gui.blink = 0
      end
    end

    if gui.blink == 1 then
      gfx.rect(gfx.x, gfx.y + self.pad_x * config.multi, config.multi, self.h - self.pad_x * config.multi * 2, 1)
    end
  else
    gfx.rect(gfx.x, gfx.y + self.pad_x * config.multi, config.multi, self.h - self.pad_x * config.multi * 2, 1)
  end
end
 
function isShorthand(str, mode)
  if mode == 1 then -- check key
    if sh_list[str] then
      return true
    end
  elseif mode == 2 then -- check value
    if str == "FX" or str == "FAV" or str == "ALL" then return end
    for k, v in pairs(sh_list) do
      if v == str then
        return true
      end
    end
  end
end

function a_textbox()end

function gui:textBox(ch, shrink)
  gfx.setfont(self.font)
  if gui.str == "" then gui.str_temp = "" gui.str_a = "" end
  
  if gui.dd_items and not ignoreCh(ch) and isShorthand(string.char(ch), 1) then --or
    --(isShorthand(gui.str, 1) and (ch == 32 or ch == ignore_ch.enter)) then
    config.mode = sh_list[gui.dd_items and string.char(ch) or gui.str]
    for i, v in ipairs(gui.lists.mode) do
      if v == config.mode then
        gui.mode_sel[1] = i
        break
      end
    end
    gui.mode_sel[2] = config.mode
    --gui.str = not gui.dd_items and "" or gui.str
    scr.actions.clear(_,true)
    gui.dd_active_slot = nil
    scr.re_search = true
    gui.focused = nil
    gui.dd_items = nil
    gui.important = nil
    goto SKIP
  end

  if not ignoreCh(ch) and not gui.focused and gui.m_cap&mouse_mod.lmb == 0 then
    local valid_ch, str_w, ch_w = pcall(function()string.char(ch)end)
    if valid_ch then
      str_w = gfx.measurestr(gui.str)
      ch_w = gfx.measurestr(string.char(ch))
    end
    
    local clearHlTxt = function()
      if gui.str:len() - gui.str_hl_end ~= gui.b_count then
        gui.b_count = gui.b_count - gui.str_hl:len()
      end
      gui.str_a = gui.str:sub(1, gui.str_hl_start - 1)
      gui.str_b = gui.str:sub(gui.str_hl_end + 1, gui.str:len())
      gui.str = gui.str_a .. gui.str_b
      gui.txt_hl = nil
      gui.str_hl = nil
      gui.str_hl_dbl_click = nil
      gui.active = nil
    end
    
    local search_delay = config.search_delay ~= 0 and config.search_delay or config.act_search and 0.05 or 0
    local r_pad = gui.border * math.floor(config.multi) * 3
    
    if gui.m_cap&mouse_mod.ctrl == mouse_mod.ctrl or 
       gui.m_cap&mouse_mod.alt == mouse_mod.alt then goto SKIP end
    
    if ch ~= white_ch.bs then -- if not backspace and not CTRL
      if gui.txt_hl then
        clearHlTxt()
      elseif gui.b_count > 0 and ch == white_ch.del then -- if delete
        gui.str_b = gui.str_b:sub(2)
        gui.b_count = gui.b_count - 1
        gui.str = gui.str_a .. gui.str_b
      end
      if gui.b_count > 0 and valid_ch and str_w + ch_w < self.w - (shrink or 0) - r_pad then -- if string is split
        gui.str_a = gui.str_a .. string.char(ch)
        gui.str = gui.str_a .. gui.str_b
      elseif valid_ch and str_w + ch_w < self.w - (shrink or 0) - r_pad then
        gui.str = gui.str .. string.char(ch)
        gui.str_a = gui.str
        _timers.search_suspend = timer:new():start(search_delay)
      end
      if gui.str == "" then scr.actions.clear() end
    elseif gui.m_cap == 0 and not gui.txt_hl then -- if backspace
      if gui.b_count == 0 then -- if string is not split
        gui.str = gui.str:sub(0, gui.str:len() - 1)
        gui.str_a = gui.str
      else -- if string is split
        gui.str_a = gui.str_a:sub(0, gui.str_a:len() - 1)
        gui.str = gui.str_a .. gui.str_b
      end
      if gui.str == "" then scr.actions.clear() end
      _timers.search_suspend = timer:new():start(search_delay)
    else
      clearHlTxt()
      if gui.str == "" then scr.actions.clear() end
    end
    ::SKIP::
  end

  if _timers.search_suspend and not _timers.search_suspend.up then
    gui.search_suspend = true
  else
    _timers.search_suspend = nil
    gui.search_suspend = nil
  end
  
  if not gui.search_suspend and gui.str ~= "" then
    scr.do_search = true
  else
    scr.do_search = nil
  end
   
  if gui.b_count and gui.b_count > 0 or gui.b_count == 0 and gui.str_b ~= "" then -- split the string
    gui.str_a = gui.str:sub(0, gui.str:len() - gui.b_count)
    gui.str_b = gui.str:sub(gui.str:len() + 1 - gui.b_count)
    --gui.str_car = gui.str:sub(gui.str:len() + 1 - gui.b_count) -- carriage string
  elseif gui.b_count == 0 and ch == white_ch.del then
    --gui.str_car = gui.str:sub(gui.str:len() + 1 - gui.b_count) -- carriage correct
  end
  
  function a_highlight()end
  
  local clearHl = function()
    gui.str_hl = nil
    gui.str_hl_start = nil
    gui.txt_hl = nil
    gui.str_hl_end = nil
    gui.str_hl_dbl_click = nil
  end

  if double_clicked and gui.over == double_clicked_id and
     gui.over == self.id and gui.str ~= "" then
    gui.txt_hl = true
    gui.str_hl = gui.str
    gui.b_count = 0
    gui.str_hl_start = 1
    gui.str_hl_end = gui.str:len()
    gui.str_hl_dbl_click = true
  elseif gui.clicked and gui.txt_hl then
    clearHl()
  end
 
  local str_start_px
  if gui.txt_hl then
    color(51,153,255)
    local space_w = gfx.measurestr(" ")
    str_start_px = gui.str_hl_start > 0 and
                   gfx.measurestr(gui.str:sub(0, gui.str_hl_start - 1).." ") - space_w or 0
    gfx.rect(self.x1 + str_start_px + self.pad_x * config.multi,
             self.y1 + self.pad_x * config.multi,
             gfx.measurestr(gui.str_hl .. " ") - space_w,
             self.h - self.pad_x * config.multi * 2, 1)
  end
  
  self:drawTxt(gui.str, _, _, _, _, _, _, str_start_px)
  
  if gui.dd_items then return end 
   
  if gui.str:len() == 0 or ch == ignore_ch.end_key  then -- calculate the split
    gui.b_count = 0
    clearHl()
  elseif ch == ignore_ch.home then
    gui.b_count = gui.str:len()
    clearHl()
  elseif ch == ignore_ch.left then -- if left arrow key
    local process, b_count_old
    if (not gui.txt_hl or gui.m_cap > 0) and gui.b_count < gui.str:len() then
      b_count_old = gui.b_count
      gui.b_count = gui.b_count + (gui.m_cap&mouse_mod.ctrl == 0 and 1 or
                    (" " .. gui.str_a):reverse():find(".%s"))
      if gui.m_cap&mouse_mod.shift ~= mouse_mod.shift then
        clearHl()
      else
        process = true
      end
    elseif gui.txt_hl and gui.m_cap == 0 then
      if gui.str:len() - gui.str_hl_end == gui.b_count then
        gui.b_count = gui.b_count + gui.str_hl:len()
      end
      clearHl()
    end
    if gui.m_cap&mouse_mod.shift == mouse_mod.shift and process then
      if not gui.str_hl or gui.str:len() - b_count_old < gui.str_hl_start then -- if no HL or growing HL
        gui.str_hl_start = gui.m_cap&mouse_mod.ctrl == 0 and
                        (gui.str_hl and gui.str_hl_start - 1 or gui.str:len() - gui.b_count + 1) or
                        gui.str_a:len() - (" " .. gui.str_a):reverse():find(".%s") + 1
                        
        gui.str_hl_end = gui.str_hl and gui.str_hl_end or gui.str:len() - b_count_old
      else -- if shrinking HL
        gui.str_hl_end = gui.m_cap&mouse_mod.ctrl == 0 and gui.str_hl_end - 1 or
                         gui.str_a:len() - (" " .. gui.str_a):reverse():find(".%s")
                         
        if gui.str_hl_start > gui.str_hl_end then -- correction for midword HL
          local hl_start, hl_end = gui.str_hl_start, gui.str_hl_end
          gui.str_hl_start, gui.str_hl_end = hl_end + 1, hl_start - 1
        end
      end
      gui.str_hl = gui.str:sub(gui.str_hl_start, gui.str_hl_end)
      gui.txt_hl = true
      if gui.str_hl == "" then clearHl() end
    end
  elseif ch == ignore_ch.right then -- if right arrow key
    local process, b_count_old
    if (not gui.txt_hl or gui.m_cap > 0) and gui.str_b:len() > 0 then
      b_count_old = gui.b_count
      
      gui.b_count = gui.b_count - (gui.m_cap&mouse_mod.ctrl == 0 and 1 or
                    (gui.str_b .. " "):find("%s.?"))
                    
      gui.b_count = gui.b_count < 0 and 0 or gui.b_count
      if gui.m_cap&mouse_mod.shift ~= mouse_mod.shift then
        clearHl()
      else
        process = true
      end
    elseif gui.txt_hl and gui.m_cap == 0 then
      if gui.str:len() - gui.str_hl_end ~= gui.b_count then
        gui.b_count = gui.b_count - gui.str_hl:len()
      end
      clearHl()
    end
    if gui.m_cap&mouse_mod.shift == mouse_mod.shift and process then
      if not gui.str_hl or gui.str:len() - b_count_old >= gui.str_hl_end then -- if no HL or growing HL
        gui.str_hl_start = gui.str_hl and gui.str_hl_start or
                           gui.str:len() - b_count_old + 1
                           
        gui.str_hl_end = gui.m_cap&mouse_mod.ctrl == 0 and
                        (gui.str_hl and gui.str_hl_end + 1 or gui.str_hl_start) or
                        (gui.str_b .. " "):find(".%s") + 1 + gui.str_a:len()
                        
        if gui.m_cap&mouse_mod.ctrl == mouse_mod.ctrl and gui.b_count == 0 and
           gui.str:match(".+%S$") then
          gui.str_hl_end = gui.str_hl_end - 1
        end
      else -- if shrinking HL
        gui.str_hl_start = gui.m_cap&mouse_mod.ctrl == 0 and gui.str_hl_start + 1 or
                           (gui.str_b .. " "):find("%s.?") + 1 + gui.str_a:len()
        if gui.str_hl_start > gui.str_hl_end then -- correction for midword HL
          local hl_start, hl_end = gui.str_hl_start, gui.str_hl_end
          gui.str_hl_start, gui.str_hl_end = hl_end + 1, hl_start - 1
        end
      end
      gui.str_hl = gui.str:sub(gui.str_hl_start, gui.str_hl_end)
      gui.txt_hl = true
      if gui.str_hl == "" then clearHl() end
    end 
  end
  
  gui.str_x2 = gfx.x
  
  --[[gfx.x = gfx.x - (gui.str_a:len() > 0 and gfx.measurestr(gui.str) - gfx.measurestr(gui.str_a) or
                   gfx.measurestr(gui.str_b))]]
  

  gfx.x = self.x1 + self.pad_x * config.multi + gfx.measurestr(gui.str_a .. " ") - gfx.measurestr(" ")

  
  if gui.active and gui.active.id == self.id and not gui.str_hl_dbl_click then-- and not gui.txt_hl then
    local defineHl = function()
      if not gui.str_a_temp then
        gui.str_a_temp = gui.str:sub(0, gui.str:len() - gui.b_count)
        gui.str_b_temp = gui.str:sub(gui.str:len() + 1 - gui.b_count)
      end
      
      if not gui.b_count_i then
        gui.b_count_i = gui.b_count
      elseif gui.b_count_i and gui.b_count_i ~= gui.b_count then
        local str_sub
        gui.txt_hl = true
        if gui.b_count_i > gui.b_count then
          str_sub = gui.str:sub(gui.str:len() + 1 - gui.b_count)
          gui.str_hl = gui.str_b_temp:gsub(str_sub .. "$", "")
        else
          gui.str_hl = gui.str_a_temp:sub(gui.str:len() - gui.b_count + 1, gui.str_a_temp:len())
        end
        gui.str_hl_start = gui.str:len() - math.max(gui.b_count_i, gui.b_count) + 1
        gui.str_hl_end = gui.str:len() - math.min(gui.b_count_i, gui.b_count)
      elseif gui.b_count_i and gui.b_count_i == gui.b_count then
        clearHl()
      end
    end
    
    if gui.str_x2 - gfx.measurestr(gui.str:match(".+(.)"))/2 <= gfx.mouse_x and
       #gui.str > 1 then
      gui.b_count = 0
      defineHl()
      carriage_suspend = true
      _timers.carriage_suspend = timer:new():start(0.5)
    else
      local str = gui.str
      for i = 1, #gui.str + 1 do
        local str_a = gfx.measurestr(str:match("(.+).") or "")
        local str_b = gfx.measurestr(str:match(".+(.)") or gui.str:match("."))
        if gfx.mouse_x >= gui.str_x2 - (gfx.measurestr(gui.str) - str_a - str_b/2) or
           i == #gui.str + 1 then
          gui.b_count = i - 1
          carriage_suspend = true
          _timers.carriage_suspend = timer:new():start(0.5)
          break
        else
          str = str:match("(.+).") or gui.str:match(".")
        end
      end
      defineHl()
    end
  elseif gui.b_count_i then
    gui.b_count_i = nil
    gui.str_a_temp = nil
    gui.str_b_temp = nil
  end

  if gui.focus == 2 and (gui.m_cap&mouse_mod.lmb == 0 or
     gui.m_cap&mouse_mod.lmb > 0 and carriage_suspend) then
    self:carriage(ch)
  else
    gui.blink = 0
  end
  
  ::SKIP::
end

function a_actions()end

scr.actions.defMode = function(str)
  if str == "LAST USED" then
    config.default_mode = nil
  else
    config.default_mode = str
  end
end

scr.actions.result = function()
  gui.Results.sel = tonumber(gui.over:match("%d+"))
end

scr.actions.fav = function(id)
  local id = type(id) == "number" and id or tonumber(id.id:match("%d+"))
  local result = scr.results_list[id]:gsub("|,|fav", "")
  local fav = result .. "|,|fav"
  if #db.FAV == 0 then
    --db.FAV[#db.FAV+1] = fav -- insert last
    table.insert(db.FAV, 1, fav) -- insert first
    scr.results_list[id] = fav
    scr.re_search = true
    return
  end
  for i = 1, #db.FAV do
    if db.FAV[i] == fav then
      table.remove(db.FAV, i)
      scr.results_list[id] = result
      scr.re_search = true
      scr.actions.clear(_, true)
      return
    end
    if i == #db.FAV then
      --db.FAV[#db.FAV+1] = fav
      table.insert(db.FAV, 1, fav)
      scr.results_list[id] = fav
    end
  end
  scr.re_search = true
end

scr.actions.favReorder = function()
  if #db.FAV <= 1 then return end
  local prev, new_id, fav_id
  
  if gui.ch == ignore_ch.up and
     scr.results_list[gui.Results.sel-1]:match(".+|,|(.+)") == "fav" then
    prev = scr.results_list[gui.Results.sel-1]
  elseif gui.ch == ignore_ch.down and
         scr.results_list[gui.Results.sel+1]:match(".+|,|(.+)") == "fav" then
    prev = scr.results_list[gui.Results.sel+1]
  else
    return
  end
  
  local fav = scr.results_list[gui.Results.sel]
  local dif = gui.ch == ignore_ch.up and -1 or 1

  for i = 1, #db.FAV do
    if db.FAV[i] == fav then
      fav_id = i
      if prev_id then break end
    elseif db.FAV[i] == prev then
      new_id = i
      if fav_id then break end
    end
  end
  
  table.remove(db.FAV, (fav_id > new_id and fav_id or new_id))
  table.remove(db.FAV, (fav_id < new_id and fav_id or new_id))
  table.insert(db.FAV, (fav_id > new_id and new_id or fav_id), (fav_id > new_id and fav or prev))
  table.insert(db.FAV, (fav_id < new_id and new_id or fav_id), (fav_id < new_id and fav or prev))
  
  scr.actions.clear(_, true, gui.Results.sel + dif)
  scr.re_search = true
end
  

scr.actions.pin = function()
  if config.pin then
    config.pin = false
  else
    config.pin = true
  end
end

scr.actions.float = function()
  if config.fx_hide then
    config.fx_hide = false
  else
    config.fx_hide = true
  end
end

scr.actions.clear = function(_, keep_str, keep_sel)
  if not keep_str then gui.str = "" end
  gui.Results = {sel = keep_sel or 1}
  scr.results_list = {}
  scr.query_parts = {}
  scr.match_found = nil
  gui.str_hl = nil
  gui.txt_hl = nil
end

scr.actions.view = function(o)
  gui.hints_txt = ""
  if type(o) ~= "string" then o = o.id end
  gui.view = o:match("view_(.+)")
  gui.view_change = true

  if scr.temp_undock and o == "view_main" then
    scr.temp_undock = nil
    config.undock = false
    gui.reopen = true
  elseif gfx.dock(-1)&1 == 1 and o == "view_prefs" then
    config.undock = true
    scr.temp_undock = true
    gui.reopen = true
    scr.o_r = true -- override wnd_h_save and wnd_y when docked
  end
end

scr.actions.nav = function(o)
  if type(o) ~= "string" then o = o.id end
  gui.page = o
  gui.view_change = true
  if not gui.reopen then gui.reinit = true end
end

scr.actions.cb = function(o)
  if o.table then
    o.table[o.id:gsub("cb_", "")] = not o.table[o.id:gsub("cb_", "")]
  else
    config[o.id:gsub("cb_", "")] = not config[o.id:gsub("cb_", "")]
  end
  
  if o.table_name == "keep_states" and o.id == "cb_GROUP_FLAGS" then
    keep_states.GROUP_FLAGS_HIGH = keep_states.GROUP_FLAGS
  end
  if o.id == "cb_fav_persist" and not config.fav_persist then scr.actions.clear(_, true) end
  
  if o.id == "cb_fol_search" and config.fol_search then
    filter_modes.FOLDER = true
    defineFilterModes()
    scr.filter_n = countFilterModes()
    sh_list.o = "FOLDER"
  elseif o.id == "cb_fol_search" then
    filter_modes.FOLDER = nil
    sh_list.o = nil
    if config.mode == "FOLDER" then
      config.mode = "ALL"
      gui.mode_sel[2] = "ALL"
      gui.dd_active_slot = nil
    end
    defineFilterModes()
    scr.filter_n = countFilterModes()
  end
  
  if o.id == "cb_act_search" and config.act_search then
    gui.wnd_w = getPrefsW()
    gui.w = gui.wnd_w - gui.border * 2
    gui.reinit = true
    gui.hints.ALL = "FX, track templates and actions"
    sh_list.n = "ACTION"
    table.insert(gui.lists.mode, 1, "ACTION")
    filter_modes["ACTION"] = true
    
    if not global_types.ACTION then
      for i, v in ipairs(global_types_order) do
        if v == "ACTION" then
          break
        elseif i == #global_types_order and v ~= "ACTION" then
          table.insert(global_types_order, "ACTION")
        end
      end
      global_types.ACTION = true
      config.global_types_n = config.global_types_n + 1
    end
    if not db.ACTION then scr.actions.refreshDb() end
    defineFilterModes()
    scr.filter_n = countFilterModes()
  elseif o.id == "cb_act_search" then
    gui.wnd_w = getPrefsW()
    gui.w = gui.wnd_w - gui.border * 2
    gui.reinit = true
    gui.hints.ALL = "FX and track templates"
    sh_list.n = nil
    if config.mode == "ACTION" then
      config.mode = "ALL"
      gui.mode_sel[2] = "ALL"
      gui.dd_active_slot = nil
    end
    table.remove(gui.lists.mode, 1)
    filter_modes["ACTION"] = nil
    if global_types.ACTION then
      for i, v in ipairs(global_types_order) do
        if v == "ACTION" then
          table.remove(global_types_order, i)
          break
        end
      end
      global_types.ACTION = nil
      config.global_types_n = config.global_types_n - 1
      defineFilterModes()
      scr.filter_n = countFilterModes()
    end
  end
end

scr.actions.addType = function()
  local tbl = {}
  for k, v in pairs(global_types) do
    table.insert(tbl, k)
  end
  table.sort(tbl)
  
  for n = 1, #tbl do
    for i = 1, #global_types_order + 1 do
      if tbl[n] == global_types_order[i] then
        goto SKIP
      elseif i == #global_types_order + 1 then
        table.insert(global_types_order, tbl[n])
        return
      end
    end
    ::SKIP::
  end
end

scr.actions.modeSet = function(name)
  config.mode = name
  for i, v in ipairs(gui.lists.mode) do
    if v == config.mode then
      gui.mode_sel[1] = i
      break
    end
  end
  gui.mode_sel[2] = name
  scr.actions.clear(_,true)
  gui.focused = nil
  gui.dd_items = nil
  gui.important = nil
  scr.re_search = true
end

scr.actions.scanSet = function(val)
  for i = 1, #gui.lists.db_scan do
    if gui.lists.db_scan[i] == val then
      config.db_scan = i
      break
    end
  end
end

scr.actions.noSelTracks = function(val)
  for i = 1, #gui.lists.no_sel_tracks do
    if gui.lists.no_sel_tracks[i] == val then
      config.no_sel_tracks = i
      break
    end
  end
end


scr.actions.refreshDb = function()
  db.saved = false
  getDb(true)
end

scr.actions.reorderFilters = function(_, o)
  local parent_num, parent_name = o.parent_id:match(".-_(%d+)_(.+)")
  parent_num = tonumber(parent_num)
  if o.id:match("NONE") then
    table.remove(o.table, parent_num)
    gui.focused = nil
    gui.important = nil
    gui.dd_items = nil
    return
  end
  local child_name, child_num = o.id:match(".-_(.-)_(%d+)")
  child_num = tonumber(child_num)
  local tbl = o.table
  table.remove(tbl, parent_num)
  table.insert(tbl, child_num, parent_name)
  
  ::SKIP::
  gui.focused = nil
  gui.important = nil
  gui.dd_items = nil
  return
end

scr.actions.dd = function(o, redraw)
  gui.dd_items = {}
  if gui.focused and gui.focused.id ~= o.id then
    gui.focused = nil
    gui.dd_items = nil
    gui.important = nil
  end
  
  if not gui.important or not redraw then
    gui.important = o
  end
  
  local parent_num, parent_name = o.id:match(".-_(%d+)_(.+)")

  if not parent_num then
    local child_name, child_num = o.id:match(".-_(.-)_(%d+)")
    if o.action then
      scr.actions[o.action](child_name, o)
    else
      config[o.table_name] = child_name
    end
    gui.focused = nil
    gui.important = nil
    gui.dd_items = nil
    return
  end
  
  local parent = o

  local float = parent
  
  local tbl = o.table
  
  if not gui.dd_active_slot then
    gui.dd_active_slot = gui.mode_sel[2]
  end
  
  for i = (o.direction == "float_b" or o.direction == "float_r") and 1 or #tbl,
      (o.direction == "float_b" or o.direction == "float_r") and #tbl or 1,
      (o.direction == "float_b" or o.direction == "float_r") and 1 or -1 do
    if float == parent and o.y_reset then float.y2 = o.y_reset end
    if float == parent and o.x_reset then float.x2 = o.x_reset end
    
    
    if i > #tbl then
    else
      local n, str
      for a = 1, #o.table do
        if o.table[a] == tbl[i] then
          n = a
          break
        end
        if a == #o.table then
          n = #gui.dd_items + 1
        end
      end

      gui.dd_items[#gui.dd_items+1] = parent:setChild{id ="dd_"..tbl[i].."_"..n, [o.direction] = float,
                                                      parent_id = parent.id,
                                                      is_important = true}

      if parent.id == "dd_1_mode" and
         gui.over and gui.over:match(".-_(.-)_%d+") == tbl[i] and
         ((not gui.dd_m_x or gui.dd_m_x ~= gui.m_x) or (not gui.dd_m_y or gui.dd_m_y ~= gui.m_y)) then
        gui.dd_m_x = gui.m_x
        gui.dd_m_y = gui.m_y
        gui.dd_active_slot = tbl[i]
        gui.mode_sel[1] = i
        gui.mode_sel[2] = gui.dd_active_slot
      end
      
      if tbl[i] == gui.dd_active_slot and parent.id == "dd_1_mode" or
         (parent.id ~= "dd_1_mode" and gui.over and tbl[i] == gui.over:match(".-_(.-)_%d+")) then -- mark active/over
        gui.dd_items[#gui.dd_items].c = gui.accent_c
        gui.dd_items[#gui.dd_items].font_c = 255
      elseif tbl[i] == parent_name and o.y_reset then -- mark active if dd overlays
        gui.dd_items[#gui.dd_items].c = config.theme == "light" and o.c + 10 or gui.Prefs.Body.c
      else
        if parent.id == "dd_1_mode" then
          gui.dd_items[#gui.dd_items].c = config.theme == "light" and 230 or 80
        else
          gui.dd_items[#gui.dd_items].c = config.theme == "light" and 255 or gui.dd_items[#gui.dd_items].c + 10
        end
        gui.dd_items[#gui.dd_items].font_c = config.theme == "light" and 50 or gui.dd_items[#gui.dd_items].font_c
      end

      if gui.dd_items[#gui.dd_items]:isOver() then
        gui.important = gui.dd_items[#gui.dd_items]
      end

      str = "to slot " .. tostring(i)
      gui.dd_items[#gui.dd_items]:drawDdMenu(
      1, (parent.numbered and str or (tbl[i]--[[:gsub("^%l", string.upper)]]:gsub("|" , ""))))
      float = gui.dd_items[#gui.dd_items]
    end
 
  end
  
  if o.extra_field then
    gui.dd_items[#gui.dd_items+1] = parent:setChild{id = "dd_" .. o.extra_field .. "_" .. #gui.dd_items+1,
                                                    parent_id = parent.id, float_b = o.direction == "float_b" and float or nil,
                                                    float_t = o.direction == "float_t" and float or nil}

    if gui.over and o.extra_field == gui.over:match(".-_(.-)_%d+") then -- mark over
      gui.dd_items[#gui.dd_items].c = gui.accent_c
      gui.dd_items[#gui.dd_items].font_c = 255
    elseif o.extra_field == parent_name and o.y_reset then -- mark active if dd overlays
      gui.dd_items[#gui.dd_items].c = config.theme == "light" and o.c + 10 or gui.Prefs.Body.c
    else
      if parent.id == "dd_1_mode" then
        gui.dd_items[#gui.dd_items].c = config.theme == "light" and 230 or gui.dd_items[#gui.dd_items].c + 10
      else
        gui.dd_items[#gui.dd_items].c = config.theme == "light" and 255 or gui.dd_items[#gui.dd_items].c + 10
      end
      gui.dd_items[#gui.dd_items].font_c = config.theme == "light" and 50 or gui.dd_items[#gui.dd_items].font_c
    end

    if gui.dd_items[#gui.dd_items]:isOver() then
      gui.important = gui.dd_items[#gui.dd_items]
    end
    
    gui.dd_items[#gui.dd_items]:drawDdMenu(1, "--" .. o.extra_field .. "--")
  end
  
  if o.id == "dd_1_mode" then -- search filter tray border
    for i = 1, #gui.dd_items - 1 do -- dd separators
      if gui.mode_sel[1] ~= tonumber(gui.dd_items[i].id:match("dd_.-_(%d+)")) and
         gui.mode_sel[1] ~= tonumber(gui.dd_items[i].id:match("dd_.-_(%d+)")) + 1 then 
        color(config.theme == "light" and o.font_c - 40 or o.c + 30)
        gfx.rect(o.direction == "float_r" and gui.dd_items[i].x2 - math.floor(config.multi) or
                 gui.dd_items[i].x1 + math.floor(config.multi) * 8,
                 o.direction == "float_r" and gui.dd_items[i].y1 + math.floor(config.multi) * 8 or
                 gui.dd_items[i].y2 + math.floor(config.multi),
                 o.direction == "float_r" and math.floor(config.multi) or
                 gui.dd_items[i].h - math.floor(config.multi) * 16,
                 o.direction == "float_r" and gui.dd_items[i].h - math.floor(config.multi) * 16 or
                 math.floor(config.multi), 1)
      end
    end 
    
    color(config.theme == "light" and o.c or 5) -- border
    gfx.rect(gui.dd_items[1].x1,
             o.direction == "float_r" and gui.dd_items[1].y1 or
             gui.dd_items[#gui.dd_items].y2,
             gui.dd_items[#gui.dd_items].x2 - gui.dd_items[1].x1,
             math.floor(config.multi), 1)
    gfx.rect(o.direction == "float_r" and gui.dd_items[#gui.dd_items].x2 or
             gui.dd_items[1].x2 - math.floor(config.multi),
             gui.dd_items[1].y1,
             math.floor(config.multi),
             o.direction == "float_r" and gui.dd_items[1].h or
             gui.dd_items[#gui.dd_items].y2 - gui.dd_items[1].y1, 1)
    gfx.rect(gui.dd_items[1].x1,
             o.direction == "float_r" and gui.dd_items[1].y2 - math.floor(config.multi) or
             gui.dd_items[1].y1,
             o.direction == "float_r" and gui.dd_items[#gui.dd_items].x2 - gui.dd_items[1].x1 or
             math.floor(config.multi),
             o.direction == "float_r" and math.floor(config.multi) or
             gui.dd_items[#gui.dd_items].y2 - gui.dd_items[1].y1, 1)
       
  else -- dropdown border
    o.border_coord = {x1 = o.x1,
             y1 = (o.direction == "float_b" and not o.y_reset and o.y1 + 1 or
             o.direction == "float_b" and o.y_reset and gui.dd_items[1].y1 or
             gui.dd_items[#gui.dd_items].y1) - gui.border,
             w = o.w,
             h = (o.direction == "float_b" and not o.y_reset and gui.dd_items[#gui.dd_items].y2 - o.y1 or
             o.direction == "float_b" and o.y_reset and gui.dd_items[#gui.dd_items].y2 - gui.dd_items[1].y1 + 1 or
             o.y2 - gui.dd_items[#gui.dd_items].y1 + 1)}

    o.border_coord.x2 = o.border_coord.x1 + o.border_coord.w
    o.border_coord.y2 = o.border_coord.y1 + o.border_coord.h
    o:drawBorder()
    gfx.rect(o.x1, o.direction == "float_b" and o.y2 - 1 * math.floor(config.multi) or o.y1,
             o.w, math.floor(config.multi), 1)
  end
  
  if not gui.focused then
    gui.focused = o
  elseif gui.clicked.id == gui.focused.id then
    gui:resetDd()
    if o.table_name == "mode" then
      for i, v in ipairs(gui.lists.mode) do
        if v == config.mode then
          gui.mode_sel[1] = i
          break
        end
      end
      gui.mode_sel[2] = config.mode
    end
  elseif not redraw then
    gui:resetDd()
  end
end

scr.actions.dragV = function(o)
  local multi = 20
  local param = o.id:match(".-_(.+)")
  if gui.m_y - gui.m_y_click > multi * config.multi then
    if o.table[param] > o.ts_floor then
      o.table[param] = o.table[param] - 1
    end
    gui.m_y_click = gui.m_y
  elseif gui.m_y_click - gui.m_y > multi * config.multi then
    if o.table[param] < o.ts_ceil then
      o.table[param] = o.table[param] + 1
    end
    gui.m_y_click = gui.m_y
  end
end

scr.actions.resSet = function(name, kb)
  local setW = function()
    config.main_w_rs = nil
    gui.wnd_w = gui.view == "main" and getMainW() or getPrefsW()
    gui.w = gui.wnd_w - gui.border * (config.undock and 2 or 5)
    gui.wnd_h_save = gui.wnd_h
    gui.reinit = true
    scr.refresh_results_max = true
  end
  
  if type(kb) == "table" then
    if config.multi == res_multi[name] then return end
    config.multi = res_multi[name]
  elseif kb == -1 then
    if name == "|720p" then if config.undock then setW() end return end
    config.multi = name == "|8k" and res_multi["|5k"] or
                   name == "|5k" and res_multi["|4k"] or
                   name == "|4k" and res_multi["|1080p"] or
                   name == "|1080p" and res_multi["|720p"]
  elseif kb == 1 then
    if name == "|8k" then if config.undock then setW() end return end
    config.multi = name== "|720p" and res_multi["|1080p"] or
                   name == "|1080p" and res_multi["|4k"] or
                   name == "|4k" and res_multi["|5k"] or
                   name == "|5k" and res_multi["|8k"]
  end
  gui.wnd_h_save = gui.wnd_h
  gui.row_h = math.floor(config.row_h * config.multi)
  initFonts()
  setW()
end

scr.actions.reminder = function(o)
  if config.reminder and not gui.reminder_exp_show then
    gui.reminder_seen = true   
    gui.reminder_exp_show = true
    gui.focused = o
  elseif gui.reminder_exp_show and gui.clicked and gui.clicked.id ~= "reminder_exp" then
    config.reminder = false
    gui.reminder_exp_show = nil
    gui.important = nil
    gui.focused = nil
    gui.active = nil
    gui.selected = nil
  end
  
  if gui.reminder_exp_show then
    gui.Row1.Reminder_exp = gui.Row1:setChild{id = "reminder_exp", on_select = true,
                            bttn = gui.reminder_clicked and nil or true,
                            w = gui.Row1.h * 6, float_l = gui.Row1.Reminder}
    gui.Row1.Reminder_exp:setStyle("reminder")
    
    gui.important = gui.Row1.Reminder_exp
    
    gui.Row1.Reminder_exp.font = 10
    
    if gui.clicked and gui.clicked.m_cap&1 == 1 and gui.clicked.id == "reminder_exp" then
      gui.focused = gui.Row1.Reminder_exp
      config.reminder = false
      gui.reminder_exp_txt = "Thank you!"
      gui.reminder_clicked = true
      if not _timers.thank_you then
        _timers.thank_you = timer:new():start(0.5)
      end
    elseif not gui.reminder_clicked then
      gui.reminder_exp_txt = "Donate with PayPal"
    end
    gui.Row1.Reminder_exp:drawRect():drawTxt(gui.reminder_exp_txt)
  end
  
  if _timers.thank_you and _timers.thank_you.up then
    gui.focused = nil
    _timers.thank_you = nil
    config.reminder = false
    gui.reminder_exp_show = nil
    gui.important = nil
    urlOpen(scr.links[1])
  end
end

scr.actions.link = function(o)
  if o.url == "help" then
    help()
  elseif o.ext_ok then
    config.ext_check = false
    if config.db_scan_wait then
      config.db_scan_wait = nil
      db.saved = false
      getDb(true)
      gui.wnd_w = getMainW()
      gui.w = gui.wnd_w - gui.border * (config.undock and 2 or 5)
      gui.reinit = true
    end
  elseif o.id:match(".-_(js)") then
    if reaper.ReaPack_GetRepositoryInfo and 
       reaper.ReaPack_GetRepositoryInfo("ReaTeam Extensions") then
      reaper.ReaPack_BrowsePackages("js_reascriptapi")
    else
      urlOpen(o.url)
    end
  else
    urlOpen(o.url)
  end
end

gui.hints = {FOLDER = "FX folders",
             FX = "effects",
             INSTRUMENT = os_is.mac and "VSTi, VST3i and AUi" or "VSTi and VST3i",
             TEMPLATE = "track templates",
             ALL = config.act_search and "FX, track templates and actions" or
                   "FX and track templates",
             ACTION = "actions",
             VST2 = "VST2", --"VST2 effects and instruments",
             VST3 = "VST3", --"VST3 effects and instruments",
             JS = "JS", --"JS effects and instruments",
             AU = "AU", --"AU effects and instruments",
             CHAIN = "FX chains",
             FAV = "favorites"}

gui.hints.generate = function(id)
  if get_db and gui.view == "main" then
    gui.hints_txt = "Building database..."
    return
  end
  
  if gui.view == "main" and #scr.results_list > 0 and gui.Results.sel then
    if config.ext_check then goto SKIP end
    if gui.m_cap == mouse_mod.alt + mouse_mod.shift and
       select(4, gui.parseResult(scr.results_list[gui.Results.sel])) ~= "" then
       gui.hints_txt = "Move the favorite up or down " ..
                       "[" .. mouse_mod[mouse_mod.alt]() .. " + "
                       .. mouse_mod[mouse_mod.shift]() .. " + Up/Down]"
       return
    elseif gui.m_cap == mouse_mod.track + mouse_mod.clear + (gfx.mouse_cap&mouse_mod.lmb) and
           not scr.results_list[gui.Results.sel]:match("TEMPLATE") then
      gui.hints_txt = "Clear track FX chain and add FX " ..
                      "[" .. mouse_mod[mouse_mod.clear]() .. " + " .. enter .. "]"
      return
    elseif gui.m_cap == mouse_mod.input + (gfx.mouse_cap&mouse_mod.lmb) and
           not scr.results_list[gui.Results.sel]:match("TEMPLATE") then
      gui.hints_txt = "Add input FX to selected tracks " ..
                      "[" .. mouse_mod[mouse_mod.input]() .. " + " .. enter .. "]"
      return
    elseif gui.m_cap == mouse_mod.input + mouse_mod.clear + (gfx.mouse_cap&mouse_mod.lmb) and
           not scr.results_list[gui.Results.sel]:match("TEMPLATE") then
      gui.hints_txt = "Clear input FX chain and add FX " .. "[" .. mouse_mod[mouse_mod.clear]() ..
                       " + " .. mouse_mod[mouse_mod.input]() .. " + " .. enter .. "]"
      return
    elseif gui.m_cap == mouse_mod.take and
           not scr.results_list[gui.Results.sel]:match("TEMPLATE") then
      gui.hints_txt = "Add FX to selected items' active takes " ..
                      "[" .. mouse_mod[mouse_mod.take]() .. " + " .. enter .. "]"
      return
    elseif gui.m_cap == mouse_mod.take + mouse_mod.clear + (gfx.mouse_cap&mouse_mod.lmb) and
           not scr.results_list[gui.Results.sel]:match("TEMPLATE") then
      gui.hints_txt = "Clear take FX chain and add FX " .. "[" .. mouse_mod[mouse_mod.clear]() ..
                      " + " .. mouse_mod[mouse_mod.take]() .. " + " .. enter .. "]"                  
      return
    elseif gui.m_cap == mouse_mod.clear + (gfx.mouse_cap&mouse_mod.lmb) and
           scr.results_list[gui.Results.sel]:match("TEMPLATE") then
      gui.hints_txt = (config.tt_apply_reverse and "Add" or "Apply") .. " track template " ..
                      "[" .. mouse_mod[mouse_mod.clear]() .. " + " .. enter .. "]"
      return
    elseif gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) then
      gui.hints_txt = "Add " .. (select(2, gui.parseResult(scr.results_list[gui.Results.sel])) == "TEMPLATE" and
                      "template" or "FX") .. " to a new send track " ..
                      "[" .. mouse_mod[mouse_mod.ctrl]() .. " + " ..
                      mouse_mod[mouse_mod.shift]() .. " + " ..
                      mouse_mod[mouse_mod.alt]() .. " + " .. enter .. "]"
      return
    elseif gui.m_cap == mouse_mod.win + mouse_mod.alt + (gfx.mouse_cap&mouse_mod.lmb) then
      gui.hints_txt = "Add FX track above selected tracks " ..
                      "[" .. mouse_mod[mouse_mod.win]() .. " + " ..
                      mouse_mod[mouse_mod.alt]() .. " + " .. enter .. "]"
      return
    end
  end
  
  ::SKIP::
  
  if gui.view == "main" then 
    if gui.dd_items then
      local mode, shortcut = gui.over and gui.over:match("dd_(.-)_%d+") or nil
      if mode then
        for k, v in pairs(sh_list) do
          if v == mode then
            shortcut = k:upper()
            break
          end
        end
        if gui.over:match("dd_(.-)_%d+") ~= config.mode then
          gui.hints_txt = "Switch filter to " .. gui.hints[mode] ..
                          " [" .. shortcut .. "]"
        else
          gui.hints_txt = "Switch filter to " .. gui.hints[mode] ..
                          " (active) [" .. shortcut .. "]"
        end
      return
      end
    end
    
    if config.results_max == 0 and #scr.results_list > 0 and
       gui.str ~= "" then
      local fx_name, fx_type = gui.parseResult(scr.results_list[1])
      gui.hints_txt = fx_type .. ": " .. fx_name
      return
    end
    
    if id == "hints" then
      gui.hints_txt = "Right-click here to " ..
      (scr.dock == 0 and "dock" or "undock") .. " the script"
    elseif id == "dd_1_mode" then
        gui.hints_txt = "Change search filter [TAB]"
    elseif id == "reminder" or id == "reminder_exp" then
      gui.hints_txt = "Reminder to support the development"
    elseif id == "pin" then
      local txt = "Keep the script open "
      local sh = " [~]"
      if not config.pin then
        gui.hints_txt = txt .. "(off)" .. sh
      else
        gui.hints_txt = txt .. "(on)" .. sh
      end
    elseif id == "float" then
      local txt = "Show FX window after insertion "
      local sh = " [" .. mouse_mod[16]() .. " + W]"
      if config.fx_hide then
        gui.hints_txt = txt .. "(off)" .. sh
      else
        gui.hints_txt = txt .. "(on)" .. sh
      end  
    elseif id == "view_prefs" then
      gui.hints_txt = "Open Quick Adder preferences [F3]"
    elseif id and id:match("fav") then
      gui.hints_txt = (id:match("_s") and "Remove the result from favorites" or
                       "Add the result to favorites") .. " [" .. mouse_mod[16]() .. " + F]"
    elseif id == "clear" and gui.str ~= "" then
      gui.hints_txt = "Clear search query [Esc]"
    elseif gui.over ~= "view_main" then
      gui.hints_txt = "Press F1 for the help file" --"Search " .. gui.hints[config.mode]
    end
  else
    if not gui.dd_items then
      if gui.over == "nav_general" then
        gui.hints_txt = "[F3]"
      elseif gui.over == "nav_templates" then
        gui.hints_txt = "[F4]"    
      elseif gui.over == "refreshDb" then
        gui.hints_txt = "[F5]"
      elseif gui.over == "dragV_results_max" then
        gui.hints_txt = "[F7/F8]"
      elseif gui.over and gui.over:match("dd_.-_|%d+%a") then
        gui.hints_txt = "[F9/F10]"
      elseif gui.over == "view_main" then
        gui.hints_txt = "[F2]"
      else
        gui.hints_txt = ""
      end
    else
      gui.hints_txt = ""
    end
  end
end

function a_guiParseResult()end
function gui.parseResult(str)
  if not str then return "", "", "", "", "", "" end
  
  local fx_type, name, path, i, id, fav = str:match("(.-):(.-)|,|(.-)|,|(.-)|,|(.-)|,|(.*)")
  
  if fx_type == "JS" then
    path = name:match("Video processor") and "Built-in effect" or "/Effects/" .. path
  elseif name:match("SWS.-:") or name:match("^Custom.-:") then
    local ext = name:match("SWS.-:") and "SWS" or name:match("^Custom.-:") and "Custom"
          or "Ext"
    name = name:gsub("%(.-%)", "/%0/")      
    name = name:gsub("(.-" .. ext .. ".-): (.+)", function(a,b) return b ..
    " (" .. i:match("(.+)/.+"):lower() .. ") (" .. a:lower() .. ")" end)
  elseif path:match("CYCLACTION") then
    name = name .. " (" .. i:match("(.+)/.+") .. ") (S&M | Cycle)"
  elseif name:match("Script:") then
    name = name:gsub("Script: ", "")
    name = name:gsub("%(.-%)", "/%0/")
    name = name:gsub("(.+)%.(.-)$", "%1 (%2)")
    name = name:gsub("(.-)_(.-) (%(.+%))", function(a,b,c) return b ..
    " (" .. i:match("(.+)/.+"):lower() .. ") (" .. a:lower() .. ") " .. c:lower() end)
  elseif fx_type == "ACTION" then
    local pref = name:lower():match("^(.-):")
    name = name:gsub("^.-: ", ""):gsub("%(.-%)", "/%0/")
    name = name .. " (" .. i:lower():match("(.+)/.+") .. ")" .. (pref and " (" .. pref .. ")" or "")
  else
    path = path:gsub(rpr.path, "")
  end
   
  if fx_type == "ACTION" then
    fx_type = "ACT"
    local section = i:match(".+/(.+)")
    local state = reaper.GetToggleCommandStateEx(section, id)
    name = name .. (state == 1 and " (on)" or state == 0 and " (off)" or "")
  elseif fx_type ~= "TEMPLATE" then
    local folder_name = name:match("\t.+") or ""
    folder_name = folder_name:gsub("^\t", " (\\t"):gsub("\t", ", ")
    name = name:gsub("\t.+", "") .. (folder_name ~= "" and folder_name or "")
  end

  return name, fx_type, i, fav, path, id
end

function a_mainView()end
function mainView()
  if gui.view ~= "main" then return end
  
  if gui.view_change then
    gui.page = nil
    gui.view_change = nil
    gui.reinit = true
    scr.re_search = true
    gui.wnd_w = getMainW()
    gui.w = gui.wnd_w - gui.border * 2
    gui.wnd_h_save = gui.wnd_h
  end
  
  if gfx.dock(-1)&1 == 1 and gui.open then
    if not config.results_max_saved then
      config.results_max_saved = config.results_max
    end
    
    if not scr.dock_h or scr.dock_h ~= gfx.h or scr.refresh_results_max then
      scr.refresh_results_max = nil
      scr.dock_h = gfx.h
      config.results_max = math.floor((gfx.h - gui.Row1.h - gui.border*6) / gui.row_h) - 1
      scr.re_search = true
    end
  elseif config.results_max_saved and not scr.temp_undock then
    config.results_max = config.results_max_saved
    config.results_max_saved = nil
    scr.re_search = true
    scr.dock_h = nil
  end
  
  if #scr.results_list > 0 and #scr.results_list <= config.results_max then
    gui.result_rows = #scr.results_list
  elseif #scr.results_list > 0 and #scr.results_list > config.results_max then
    gui.result_rows = config.results_max
  elseif #scr.results_list > 0 then
    gui.result_rows = gui.result_rows_init
  else
    gui.result_rows = 0
  end
  
  if gui.wnd_w ~= gfx.w and not gui.reinit and gui.open then
    if gfx.dock(-1)&1 == 0 then
      config.main_w_rs = gfx.w
    else
      scr.main_w_rs = gfx.w
    end
    gui.wnd_w = scr.main_w_rs or config.main_w_rs
    gui.w = (scr.main_w_rs or config.main_w_rs) - gui.border * (config.undock and 2 or 5)
    --gui.wnd_h_save = gui.wnd_h
  --[[elseif gfx.w > 0 and gfx.w < getMainW(true) and config.main_w_rs then
    config.main_w_rs = nil
    gui.wnd_w = getMainW()
    gui.w = gui.wnd_w - gui.border * 2
    gui.wnd_h_save = gui.wnd_h]]
  end
  
  if gui.result_rows_init ~= gui.result_rows then
    gui.result_rows_init = gui.result_rows
    gui.reinit = true
    gui.wnd_h_save = gui.wnd_h
  end
  
  gui.wnd_h = gui.border * 2
  
  pcall(gui.hints.generate, gui.over)
  gui.Row1 = gui:setChild({id = "row1", h = math.floor(gui.row_h * 0.5), cursor = "arrow"}, true)
  gui.Row1.Reminder = gui.Row1:setChild{id = "reminder", bttn = true, on_select = true, w = gui.Row1.h,
                      x1 = config.reminder and gui.border + gui.Row1.w - gui.Row1.h or gui.Row1.x2-
                      (config.undock and 0 or gui.border*3)}
  gui.Row1.Prefs = gui.Row1:setChild{id = "view_prefs", bttn = true,
                   w = math.floor(gui.Row1.h * (os_is.mac and config.multi == 1 and 2.2 or 2.1)),
                   float_l = gui.Row1.Reminder}
  gui.Row1.Pin = gui.Row1:setChild{id = "pin", bttn = true,
                                   w = gui.Row1.h*(config.multi == res_multi["|8k"] and 1.1 or
                                                   config.multi == res_multi["|720p"] and 0.95 or
                                                   1),
                                   float_l = gui.Row1.Prefs}                 
  gui.Row1.Float = gui.Row1:setChild{id = "float", bttn = true,
                                     w = gui.Row1.h*(config.multi == res_multi["|720p"] and 0.95 or
                                                     config.multi == res_multi["|1080p"] and 0.72 or
                                                     config.multi == res_multi["|8k"] and 0.82 or
                                                     0.8),
                                     float_l = gui.Row1.Pin}    
  gui.Row1.Float:onClickSpecial()                                   
  gui.Row1.Hints = gui.Row1:setChild{id = "hints", float_l_auto_w = gui.Row1.Float}
  gui.Row1.Hints:onClickSpecial()
  gui.Row2 = gui:setChild({id = "row2", h = gui.row_h, float_b = gui.Row1}, true)
  gui.Row2.dd_Mode = gui.Row2:setChild{
                                  id = "dd_1_mode", cursor = "arrow",
                                  w = gui.Row2.h - 4 * math.floor(config.multi),
                                  h = gui.Row2.h - 4 * math.floor(config.multi),
                                  x1 = gui.Row2.x1 + 2 * math.floor(config.multi),
                                  y1 = gui.Row2.y1 + 2 * math.floor(config.multi),
                                  bttn = true, on_select = true,
                                  direction = not config.undock and gui.w < getMainW(true, true) and
                                              "float_b" or "float_r",
                                  action = "modeSet",
                                  separator = gui.border,
                                  table = gui.lists.mode, table_name = "mode"}
  --gui.Row2.dd_Mode:onClickSpecial()
  
  if not config.undock and gui.focused and gui.focused.id == "dd_1_mode" then
    gui.focused.direction = not config.undock and gui.w < getMainW(true, true) and "float_b" or "float_r"
  end
  
  gui.Row2.Search = gui.Row2:setChild{id = "search", txt_field = true, hover_special = true,
                                      float_r_auto_w = gui.Row2.dd_Mode, auto_w = true}
 
  if config.reminder and gui.reminder_seen and not gui.focused then config.reminder = false end
  if config.reminder then
    gui.Row1.Reminder:setStyle("reminder"):drawRect()
    gui.Row1.Reminder.pad_y = gui.reminder_seen and os_is.win and (
                               config.multi == res_multi["|720p"] and 1 or
                               config.multi == res_multi["|1080p"] and -2 or
                               config.multi > 2 and -4
                               ) or 
                               os_is.mac and config.multi == 1 and 2 or
                               gui.Row1.Reminder.pad_y
    gui.Row1.Reminder.pad_x = os_is.mac and gui.reminder_seen and (
                               config.multi == res_multi["|1080p"] and 2 or
                               config.multi > 2 and 1
                               ) or gui.Row1.Reminder.pad_x                           
    gui.Row1.Reminder:drawTxt(gui.reminder_seen and "✕" or "!")
    gui.Row1.Reminder:hover()
 end
  gui.Row1.Prefs:setStyle("prefs"):setStyle("txt"):drawRect():drawTxt("PREFS")
  gui.Row1.Float:setStyle("prefs"):setStyle("txt")
  gui.Row1.Float:drawRect():drawFloat(config.fx_hide)
  gui.Row1.Pin:setStyle("prefs"):setStyle("txt")
  gui.Row1.Pin:drawRect():drawPin(config.pin)
  gui.Row1.Hints:setStyle("prefs"):setStyle("hints_txt"):setStyle("txt")
  gfx.setfont(gui.Row1.Hints.font)
  gui.Row1.Hints:drawTxt(truncateString(gui.Row1.Hints.x1,
                 gui.Row1.Hints.x2,
                 gui.hints_txt,
                 gfx.measurestr(gui.hints_txt),
                 10))
 
  gui.Row2.dd_Mode:setStyle("mode"):setStyle("mode_txt"):drawRect():getMode()--:color(5):drawBorder()
  gui.Row2.dd_Mode:onClickSpecial()

  gui.Row2.Search:setStyle("search"):setStyle("search_txt"):drawRect()
  gfx.rect(gui.Row2.x1, gui.Row2.y1,
           gui.Row2.dd_Mode.w + 2 * math.floor(config.multi),
           2 * math.floor(config.multi), 1)
  gfx.rect(gui.Row2.x1, gui.Row2.y1 + 2 * math.floor(config.multi),
           2 * math.floor(config.multi),
           gui.Row2.h - 4 * math.floor(config.multi), 1)
  gfx.rect(gui.Row2.x1, gui.Row2.y2 - 2 * math.floor(config.multi),
           gui.Row2.dd_Mode.w + 2 * math.floor(config.multi),
           2 * math.floor(config.multi), 1)
 
  gui.Row2.Search.Clear = gui.Row2.Search:setChild{id = "clear", w = config.row_h * config.multi,
                                                   x1 = gui.Row2.Search.x2 - config.row_h * config.multi,
                                                   cursor = "arrow"}
  gui.Row2.Search.Clear:setStyle("search_txt")
  gui.Row2.Search.Clear.txt_align = gui.txt_align["center"]
  gui.Row2.Search.Clear.pad_x = config.multi < 2 and 1 or 0
  gui.Row2.Search.Clear.pad_y = os_is.mac and config.multi == res_multi["|720p"] and 2 or
                                os_is.mac and config.multi == res_multi["|1080p"] and 3 or
                                os_is.mac and config.multi == res_multi["|4k"] and 5 or
                                os_is.mac and config.multi == res_multi["|5k"] and 9 or
                                os_is.mac and config.multi == res_multi["|8k"] and 12 or
                                config.multi == res_multi["|720p"] and -2 or
                                config.multi == res_multi["|1080p"] and -3 or
                                config.multi > 2 and -7
  if gui.str ~= "" then
    gui.Row2.Search.Clear.bttn = true
    gui.Row2.Search.Clear.on_select = true
    gui.Row2.Search.Clear:hover(true):drawRect():drawTxt("✕")
    gui.Row2.Search.x2 = gui.Row2.Search.x2 - gui.Row2.Search.Clear.w
  end
  
  gui.Row2.Search.on_select = true
  gui.Row2.Search:hover(true)
  
  --[[color(gui.Row2.Search.c - (config.theme == "light" and 70 or 20))
  gfx.rect(gui.Row2.x1,
           gui.Row2.y2,
           gui.w - (config.undock and 0 or gui.border*3),
           gfx.h - gui.wnd_h - gui.border*6,1)]]
  
  for i = 1, #scr.results_list > 0 and gui.result_rows or 0 do
    if i == 1 then
      gui.Results[i] = gui:setChild({id = "result_row_" .. i, h = gui.row_h, cursor = "arrow",
                                     float_b = gui.Row2, w = gui.w - (config.undock and 0 or gui.border*3)}, true)
    else
      gui.Results[i] = gui:setChild({id = "result_row_" .. i, h = gui.row_h, cursor = "arrow",
                                     float_b = gui.Results[i-1], w = gui.w - (config.undock and 0 or gui.border*3)}, true)
    end
    local fav_s = select(4, gui.parseResult(scr.results_list[i]))
    fav_s = fav_s ~= "" and "_s" or ""
    gui.Results[i].fav = gui.Results[i]:setChild{id = "fav_" .. i .. fav_s, bttn = true, w = gui.Results[i].h}
    gui.Results[i].result = gui.Results[i]:setChild{id = "result_" .. i, on_select = true, on_click = true, auto_w = true,
                                                    float_r_auto_w = gui.Results[i].fav}
  end

  for i = 1, #scr.results_list > 0 and #gui.Results or 0 do
    local name, fx_type, instr, fav, path = gui.parseResult(scr.results_list[i])
    gui.Results[i]:setStyle("search")
    if gui.Results.sel == i then
      gui.Results[i].font_c = config.theme == "light" and gui.Results[i].c or gui.Results[i].font_c
      if not config.ext_check and gui.m_cap == mouse_mod.alt + mouse_mod.shift +
         (gui.m_cap&mouse_mod.lmb) + (gui.m_cap&mouse_mod.rmb) + (gui.m_cap&mouse_mod.mmb) and
         select(4, gui.parseResult(scr.results_list[gui.Results.sel])) ~= "" then
        gui.Results[i].font_c = gui.bg_hue
        gui.Results[i].r = 253--51
        gui.Results[i].g = 186--153
        gui.Results[i].b = 42--255
      else
        gui.Results[i].c = gui.accent_c
      end
    end
    gui.Results[i]:drawRect()
    if i == 1 and gui.Results.sel ~= i then
      color(gui.Row2.Search.c + (config.theme == "light" and -20 or 20))
      gfx.rect(gui.Row2.x1 + 2 * math.floor(config.multi),
               gui.Results[i].y1,
               gui.Results[i].w - 4 * math.floor(config.multi),
               math.floor(config.multi), 1)
    end
    
    gui.Results[i].fav:setStyle("mode_txt")
    gui.Results[i].fav.font_c = gui.Results[i].fav.font_c + 10
     
    if (gui.over == gui.Results[i].fav.id and not gui.active or
        gui.active and gui.active.id == gui.Results[i].fav.id) and
        not gui.dd_items  then
      gui.Results[i].fav.font = 8
      gui.Results[i].fav.pad_y = fontSzAdjust(-4, -4)
      if gui.active and gui.active.id == gui.Results[i].fav.id then
        gui.Results[i].fav:drawRect()
      end
      if fav ~= "" then
        gui.Results[i].fav:drawTxt(utf8.char(9733)) -- filled star
      else
        gui.Results[i].fav:drawTxt(utf8.char(9734)) -- hollow star
      end      
    else
      gui.Results[i].fav.font = 10
      fx_type = fx_type == "CHAIN" and "CH" or fx_type == "TEMPLATE" and "TT" or fx_type
      gui.Results[i].fav:drawTxt(fx_type)-- .. instr)
      if fav ~= "" then
        gui.Results[i].fav.txt_align = "none"
        gui.Results[i].fav.font = os_is.win and 10 or 11
        gui.Results[i].fav.pad_x = 2
        gui.Results[i].fav:drawTxt(utf8.char(9733)) -- filled star
      end
    end
    
    gui.Results[i].result:setStyle("search_txt")
    function a_result_names()end
    --name = name:gsub("\\([\'\"])", "%1"):gsub("\\\\", "\\")
    local name1, name2
    if fx_type ~= "AU" and fx_type ~= "AUi" then
      name1, name2 = name:match("(.-) (%(.+)")
    else
      name2, name1 = name:match("(.-):%s?(.+)")
      name2 = name1:match(" %(.+") and "(" .. name2 .. ")" .. name1:match(" %(.+") .. ")" or name2
      name1 = name1:gsub(" %(.+", "")
    end
    if not name1 then
      name1, name2 = name, fx_type:match("VST") and "" or path:match("(.+)/")
    else
      name2 = name2:gsub("%) ?%(\\t", " •• "):gsub(" ?%(\\t", "•• "):gsub("%) %(", " | "):gsub("[%(%)]", ""):upper()
      --name2 = name2:match("^/") and name2:gsub("(.+|)(.+)", function(a,b)return a .. b:upper()end) or name2:upper()
    end
    name1 = name1:gsub("/%(", "("):gsub("%)/", ")"):gsub("^.", string.upper)
    gfx.setfont(5)
    local w1, h1 = gfx.measurestr(name1)
    name1 = truncateString(gui.Results[i].result.x1, gui.Results[i].result.x2, name1, w1, 10)
    gfx.setfont(1)
    local w2, h2 = gfx.measurestr(name2)
    name2 = truncateString(gui.Results[i].result.x1, gui.Results[i].result.x2, name2, w2, 10)
    local y_offset = not config.undock and -1*math.floor(config.multi) or 0
    gui.Results[i].result.pad_y = (gui.Results[i].result.h - h1 - h2) / 2 + (os_is.mac and 1 + y_offset or y_offset)
    gui.Results[i].result.font = 5
    gui.Results[i].result.font_c = gui.Results[i].result.font_c + 10
    gui.Results[i].result.txt_align = gui.txt_align["none"]
    gui.Results[i].result:drawTxt(name1)
    if gui.Results.sel ~= i then
      gui.Results[i].result.font_c = gui.Results[i].result.font_c + (config.theme == "light" and 40 or -40)
    end
    gui.Results[i].result.font = 1
    --gui.Results[i].result.y1 = gui.Results[i].result.y1 + h1
    y_offset = not config.undock and (os_is.mac and 3 or 2)*config.multi or 0
    gui.Results[i].result.pad_y = gui.Results[i].result.pad_y + gui.Results[i].result.h - h1 - 
                                  (os_is.mac and -2 + y_offset or
                                  (config.multi > 1 and config.multi < 3 and math.floor(config.multi) + y_offset or
                                  config.multi > 4 and 3 + y_offset or y_offset))
    gui.Results[i].result:drawTxt(name2)
  end

  if not config.undock and config.results_ph then -- result placeholders
    gui.Row3 = gui:setChild({id = "row3", h = gfx.h - gui.wnd_h - 4,
                             y1 = gui.Results[1] and gui.Results[#gui.Results].y2 or gui.Row2.y2,
                             cursor = "arrow"}, true)
    color(gui.bg_hue + 4)
    local y_offset = 6 * math.floor(config.multi)
    local y = ((#gui.Results > 0 and gui.Results[#gui.Results].y2 or gui.Row2.Search.y2)) +
          y_offset
    local h = gui.Row2.h - 6 * math.floor(config.multi)
    for i = 1, config.results_max - #gui.Results + 1 do
      gfx.rect(gui.Row2.x1 + 5 * math.floor(config.multi),
               y,
               h - 4*math.floor(config.multi),
               h, 1)
      local x = gui.Row2.x1 + gui.Row2.h + 1 * math.floor(config.multi)
      local w = gui.Row2.h - 8 * math.floor(config.multi)
      gfx.rect(x,
               y,
               gui.Row2.w - x - 4 * math.floor(config.multi),
               h, 1)         
      y = y + h + y_offset
    end
  end
  
  gui.Row2.Search:textBox(gui.ch, gui.Row2.Search.Clear.w)
  if gui.str == "" and (not gui.focused or gui.Row2.dd_Mode.direction == "float_b") then
    gui.Row2.Search.font_c = gui.Row2.Search.font_c + (config.theme == "light" and 100 or -100)
    gui.Row2.Search.pad_x = gui.Row2.Search.pad_x + 3
    gui.Row2.Search.pad_y = 1 * math.floor(config.multi)
    gui.Row2.Search.txt_align = gui.txt_align["vert"]
    gui.Row2.Search.font = 5
    gfx.setfont(gui.Row2.Search.font)
    gui.Row2.Search:drawTxt(truncateString(gui.Row2.Search.x1,
                   gui.Row2.Search.x2,
                   "Search " .. gui.hints[config.mode],
                   gfx.measurestr("Search " .. gui.hints[config.mode]),
                   10))
  end
  
 
  --if gui.wnd_h > gfx.h and gui.open then gui.reopen = true end
  --if gui.wnd_w > gfx.w and gui.open and gfx.dock(-1)&1 ~= 1 then gui.reopen = true end
  
  if gui.m_y > gui.wnd_h then
    gui.over = nil
    if gui.active and gui.m_cap == 0 then
      gui.active = nil
      self_x1_saved = nil
      gui.m_x_click = nil
      gui.m_y_click = nil
      gui.loop_start = nil
      gui.click_ignore = nil
    end
  end
  gui.init() 
  gui.ch = gfx.getchar()
  
  if not config.undock then
    if #gui.Results > 0 then
      color(gui.Row2.Search.c)
      gfx.line(gui.Row2.x1,
               gui.Results[#gui.Results].result.y2-1,
               gui.Row2.w,
               gui.Results[#gui.Results].result.y2-1, 0)
    end
    
    color(gui.bg_hue)
    gfx.rect(0,0,gfx.w,gfx.h,false)
    gfx.rect(3,3,gfx.w-6,gfx.h-6,false)
    
    if gui.focus == 2 then
      --[[color(config.theme == "light" and 185 or 48,
            config.theme == "light" and 211 or 92,
            config.theme == "light" and 225 or 114)--blue]]
      color(config.theme == "light" and 220 or 120)--grey
    else
      color(gui.bg_hue + 20)--grey
    end
    gfx.rect(1,1,gfx.w-2,gfx.h-2,false)
    gfx.rect(2,2,gfx.w-4,gfx.h-4,false)
  end
end

function a_kb()end

function kbActions()
  ---- UP, DOWN, LEFT, RIGHT ----
  if gui.ch == 0 then
    _timers.arrow_key = nil
  end

  if gui.ch == ignore_ch.down and not gui.dd_items then
    if not _timers.arrow_key then
      _timers.arrow_key = timer:new():start(0.01)
      if not gui.dd_items then
        if gui.Results.sel < gui.result_rows then
          if gui.m_cap == 0 then
            gui.Results.sel = gui.Results.sel + 1
          elseif scr.results_list[gui.Results.sel]:match(".+|,|(.+)") == "fav" and
                 gui.m_cap == mouse_mod.alt + mouse_mod.shift then
            scr.actions.favReorder()
          end
        elseif gui.m_cap&mouse_mod.alt ~= mouse_mod.alt and
               gui.m_cap&mouse_mod.shift ~= mouse_mod.shift then
          gui.Results.sel = 1
        end
      end
    end
  end
  
  if gui.ch == ignore_ch.up and not gui.dd_items then
    if not _timers.arrow_key then
      _timers.arrow_key = timer:new():start(0.01)
      if not gui.dd_items then
        if gui.Results.sel > 1 then
          if gui.m_cap == 0 then
            gui.Results.sel = gui.Results.sel - 1
          elseif scr.results_list[gui.Results.sel]:match(".+|,|(.+)") == "fav" and
                 gui.m_cap == mouse_mod.alt + mouse_mod.shift then
            scr.actions.favReorder()
          end
        elseif gui.m_cap&mouse_mod.alt ~= mouse_mod.alt and
               gui.m_cap&mouse_mod.shift ~= mouse_mod.shift then
          gui.Results.sel = gui.result_rows
        end
      end
    end
  end

  if gui.focused and gui.focused.id == "dd_1_mode" and
     (not config.undock and gui.ch == ignore_ch.up or
      config.undock and gui.ch == ignore_ch.left) then
    if not _timers.arrow_key then
      _timers.arrow_key = timer:new():start(0.01)
      for i, v in ipairs(gui.lists.mode) do
        if v == gui.mode_sel[2] then
          if i > 1 then
            gui.mode_sel[1] = i - 1
            gui.mode_sel[2] = gui.lists.mode[i-1]
            gui.dd_active_slot = gui.mode_sel[2]
          else
            gui.mode_sel[1] = #gui.lists.mode
            gui.mode_sel[2] = gui.lists.mode[#gui.lists.mode]
            gui.dd_active_slot = gui.mode_sel[2]
          end
          break
        end
      end
    end
  end
  
  if gui.focused and gui.focused.id == "dd_1_mode" and
     (not config.undock and gui.ch == ignore_ch.down or
      config.undock and gui.ch == ignore_ch.right) then
    if not _timers.arrow_key then
      _timers.arrow_key = timer:new():start(0.01)
      for i, v in ipairs(gui.lists.mode) do
        if v == gui.mode_sel[2] then
          if i < #gui.lists.mode then
            gui.mode_sel[1] = i + 1
            gui.mode_sel[2] = gui.lists.mode[i+1]
            gui.dd_active_slot = gui.mode_sel[2]
          else
            gui.mode_sel[1] = 1
            gui.mode_sel[2] = gui.lists.mode[1]
            gui.dd_active_slot = gui.mode_sel[2]
          end
          break
        end
      end
    end
  end
  
  if _timers.arrow_key and _timers.arrow_key.up then
    _timers.arrow_key = nil
  end
  ----
  
  if gui.m_cap == mouse_mod.ctrl and gui.ch == 1 and gui.str ~= "" then -- CTRL+A
    gui.b_count = 0
    gui.str_hl_start = 1
    gui.str_hl_end = gui.str:len()
    gui.str_hl = gui.str
    gui.txt_hl = true
  --[[elseif gui.m_cap == mouse_mod.ctrl and gui.ch == 3 and gui.str_hl then -- CTRL+C
    reaper.CF_SetClipboard(gui.str_hl)
  elseif gui.m_cap == mouse_mod.ctrl and gui.ch == 22 then -- CTRL+V
    local cb = reaper.CF_GetClipboard("")
    gui.str = gui.str_a .. cb .. gui.str_b
    gui.str_a = gui.str_a .. cb]]
  elseif gui.m_cap == mouse_mod.alt and gui.ch == 326 and
     #scr.results_list > 0 and gui.view == "main" then -- ALT+F
    scr.actions.fav(gui.Results.sel)  
  elseif gui.m_cap == mouse_mod.alt and
         gui.ch == 343 and gui.view == "main" then -- ALT+W
    gui.clicked = {id = "float", m_cap = 1, o = gui.Row1.Float}
  elseif gui.ch == ignore_ch.esc and gui.m_cap == 0 and gui.view == "main" then
    if gui.str == "" and not gui.dd_items then
      gfx.quit()
    elseif not gui.dd_items then
      scr.actions.clear()
    else
      gui.clicked = {id = "dd_1_mode", m_cap = 1, o = gui.Row2.dd_Mode}
    end
  elseif gui.ch == ignore_ch.esc and gui.m_cap == 0 and gui.view ~= "main" then
    gfx.quit()
  elseif gui.ch == ignore_ch.enter and gui.dd_items and gui.view == "main" then
    gui.ch = 0
    scr.actions.modeSet(gui.mode_sel[2])
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.tab and gui.view == "main" and
         gui.m_cap&mouse_mod.ctrl ~= mouse_mod.ctrl then
    gui.clicked = {id = "dd_1_mode", m_cap = 1, o = gui.Row2.dd_Mode}
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.tilde and gui.view == "main" then
    gui.clicked = {id = "pin", m_cap = 1, o = gui.Row1.Pin}
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.f1 then
    help()
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.f2 and gui.view == "prefs" then
    if scr.temp_undock then
      scr.temp_undock = nil
      config.undock = false
      gui.reopen = true
    end
    gui.clicked = {id = "view_main", m_cap = 1, o = gui.Prefs.Nav.Back}
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.f3 and not gui.dd_items then
    if gfx.dock(-1)&1 == 1 then
      config.undock = true
      scr.temp_undock = true
      gui.reopen = true
    end
    scr.actions.view("view_prefs")
    scr.actions.nav("nav_general")
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.f4 and not gui.dd_items then
    if gfx.dock(-1)&1 == 1 then
      config.undock = true
      scr.temp_undock = true
      gui.reopen = true
    end
    scr.actions.view("view_prefs")
    scr.actions.nav("nav_templates")
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.f5 and not get_db and not gui.dd_items then
    scr.actions.refreshDb()
  elseif gui.m_cap == 0 and config.undock and
         gui.ch == ignore_ch.f7 and not get_db and not gui.dd_items then
    if config.results_max == 0 then return end
    config.results_max = config.results_max - 1
    scr.re_search = true
  elseif gui.m_cap == 0 and config.undock and 
         gui.ch == ignore_ch.f8 and not get_db and not gui.dd_items then
    if config.results_max == 99 then return end
    config.results_max = config.results_max + 1
    scr.re_search = true  
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.f9 and not get_db and not gui.dd_items then
    for k, v in pairs(res_multi) do
      if v == config.multi then
        scr.actions.resSet(k, -1)
        break
      end
    end
  elseif gui.m_cap == 0 and gui.ch == ignore_ch.f10 and not get_db and not gui.dd_items then
    for k, v in pairs(res_multi) do
      if v == config.multi then
        scr.actions.resSet(k, 1)
        break
      end
    end  
  elseif gui.ch == 26 and gui.m_cap == mouse_mod.ctrl then
    reaper.Main_OnCommand(40029, 0) -- Edit: Undo
    gui.ch = 0
  elseif gui.ch == 26 and gui.m_cap == mouse_mod.ctrl + mouse_mod.shift then
    reaper.Main_OnCommand(40030, 0) -- Edit: Redo
    gui.ch = 0
  end
end

function a_prefs()end

gui.prefs_page = function(page)
  gui.wnd_h = gui.Prefs.Body.Nav.h + gui.border * 2
  local padding = 8
  if page == "nav_general" then
    gui.Prefs.Body.Section_1 = gui.Prefs.Body:setChild({id = "section_1", h = (82 + padding) * config.multi,
                             float_b = gui.Prefs.Nav}, true, true, padding, padding * 1.5, true)

    gui.Prefs.Body.Section_2 = gui.Prefs.Body:setChild({id = "section_2", h = (57 + padding) * config.multi,
                             float_b = gui.Prefs.Body.Section_1}, true, true, padding, padding * 1.5, true)
                             
    gui.Prefs.Body.Section_3 = gui.Prefs.Body:setChild({id = "Section_3", h = (138 + padding) * config.multi,
                             float_b = gui.Prefs.Body.Section_2}, true, true, padding, padding * 1.5, true)
    
    
    gui.Prefs.Body.Section_4 = gui.Prefs.Body:setChild({id = "Section_4", h = (57 + padding) *config.multi,
                             float_b = gui.Prefs.Body.Section_3}, true, true, padding, padding * 1.5, true, true)
    
    
    gui.Prefs.Body:drawRect(1):hover()
    gui.Prefs.Body:setStyle("mode")
    gui.Prefs.Body.c = gui.border_c
    gui.Prefs.Body.Section_1:drawBorder()
    gui.Prefs.Body.Section_2:drawBorder()
    gui.Prefs.Body.Section_3:drawBorder()
    gui.Prefs.Body.Section_4:drawBorder()
    

    gui.Prefs.Body.Section_1.Title = gui.Prefs.Body.Section_1:setChild{id = "", x1 = gui.Prefs.Body.Section_1.x1 + 5 * config.multi,
                                                                       txt = "Appearance",
                                                                       y1 = gui.Prefs.Body.Section_1.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()
    
                             
    gui.Prefs.Body.Section_2.Title = gui.Prefs.Body.Section_2:setChild{id = "", x1 = gui.Prefs.Body.Section_2.x1 + 5 * config.multi,
                                                                       txt = "Global search order",
                                                                       y1 = gui.Prefs.Body.Section_2.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()
                             
    gui.Prefs.Body.Section_3.Title = gui.Prefs.Body.Section_3:setChild{id = "", x1 = gui.Prefs.Body.Section_3.x1 + 5 * config.multi,
                                                                       txt = "Search and insertion options",
                                                                       y1 = gui.Prefs.Body.Section_3.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()




    gui.Prefs.Body.Section_4.Title = gui.Prefs.Body.Section_4:setChild{id = "", x1 = gui.Prefs.Body.Section_4.x1 + 5 * config.multi,
                                                                       txt = "Database",
                                                                       y1 = gui.Prefs.Body.Section_4.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()
    
    gui.Prefs.Body.Section_1.x1 = gui.Prefs.Body.Section_1.x1 + (math.floor(config.multi) - 1)
    gui.Prefs.Body.Section_2.x1 = gui.Prefs.Body.Section_2.x1 + (math.floor(config.multi) - 1)
    gui.Prefs.Body.Section_3.x1 = gui.Prefs.Body.Section_3.x1 + (math.floor(config.multi) - 1)
    gui.Prefs.Body.Section_4.x1 = gui.Prefs.Body.Section_4.x1 + (math.floor(config.multi) - 1)
 
    
    gui.Prefs.Body.Section_1:setStyle("dd")
    gui.Prefs.Body.Section_1.Cb = gui.Prefs.Body.Section_1:setCheckBox({
                                  id = "",
                                  x1 = gui.Prefs.Body.Section_1.x1 + 1 * config.multi,
                                  float_b = gui.Prefs.Body.Section_1.Title,
                                  margin = padding * math.floor(config.multi)})    
    gui.Prefs.Body.Section_1.Cb:setStyle("cb")                              
                                  
    gui.Prefs.Body.Section_1.dd = gui.Prefs.Body.Section_1:setChild{
                                    id = "",
                                    x1 = gui.Prefs.Body.Section_1.x1 + 1,
                                    w = 55 * config.multi, h = gui.Prefs.Nav.h, font = 14,
                                    float_b = gui.Prefs.Body.Section_1.Title,
                                    --pad_y = os_is.mac and 1 or nil,
                                    pad_x = 4}
                                    
    gui.Prefs.Body.Section_1.Caption = gui.Prefs.Body.Section_1:setChild({
                                             id = "",
                                             w = 75 * config.multi,
                                             x1 = gui.Prefs.Body.Section_1.x1 + 1,
                                             h = gui.Prefs.Body.Section_1.dd.h
                                             })
    
    
    do -- RESOLUTION
    
      gui.Prefs.Body.Section_1.Resolution = gui.Prefs.Body.Section_1.Caption:setChild({
                                               float_b = gui.Prefs.Body.Section_1.Title,
                                               }, nil, nil, padding)
    
      gui.Prefs.Body.Section_1.Resolution.txt_align = gui.txt_align["vert"]
      gui.Prefs.Body.Section_1.Resolution:setStyle("search"):drawTxt("Window size optimized for:", nil, true)
      gui.Prefs.Body.Section_1:setStyle("dd")
      local i = gui.Prefs.dd_num
      local name
      for k, v in pairs(res_multi) do
        if v == config.multi then
          name = k
          break
        end
      end
    
    
      gui.Prefs.Body.Section_1["dd_1"] = gui.Prefs.Body.Section_1.dd:setChild({
                                            id = "dd_1_"..name,
                                            w = (55 + (config.act_search and 32 or 0)) * config.multi,
                                            on_select = true, bttn = true,
                                            table = gui.lists.res_name, table_name = "res_name",
                                            action = "resSet",
                                            direction = "float_b",
                                            float_b = gui.Prefs.Body.Section_1.Title,
                                            float_r = gui.Prefs.Body.Section_1.Resolution},
                                            nil, nil, padding)
    
      gui.Prefs.Body.Section_1["dd_1"]:drawDdMenu(1, name:gsub("|", ""), true)
    end
    
    do -- THEME
    
      gui.Prefs.Body.Section_1.Current_theme = gui.Prefs.Body.Section_1.Caption:setChild({
                                               float_r = gui.Prefs.Body.Section_1["dd_1"],
                                               float_b = gui.Prefs.Body.Section_1.Title,
                                               }, nil, nil, padding * 2, padding)
    
      gui.Prefs.Body.Section_1.Current_theme:setStyle("search"):drawTxt("Current theme:", nil, true)
    
      local name = config.theme
    
    
      gui.Prefs.Body.Section_1["dd_2"] = gui.Prefs.Body.Section_1.dd:setChild({
                                            id = "dd_2_"..name,
                                            w = (55 + (config.act_search and 31 or 0)) * config.multi,
                                            on_select = true, bttn = true,
                                            table = gui.lists.theme, table_name = "theme",
                                            direction = "float_b", cap = true,
                                            float_b = gui.Prefs.Body.Section_1.Title,
                                            float_r = gui.Prefs.Body.Section_1.Current_theme},
                                            nil, nil, padding)
    
      gui.Prefs.Body.Section_1["dd_2"]:drawDdMenu(1, name, true)
    end
    
    -- RESULT PLACEHOLDERS
    
    gui.Prefs.Body.Section_1.Cb_1 = gui.Prefs.Body.Section_1.Cb:setChild({
                                         id = "cb_results_ph",
                                         float_b = gui.Prefs.Body.Section_1.Resolution,
                                         float_r = config.act_search and gui.Prefs.Body.Section_1.Resolution or nil
                                         }, nil, nil, config.act_search and 0 or padding, padding)
      
    gui.Prefs.Body.Section_1.Cb_1:drawRect():setStyle("search")
    gui.Prefs.Body.Section_1.Cb_1:drawCb("Show result placeholders when docked")
    
    
    ------- GLOBAL SEARCH ORDER                        
    
    for i = 1, #global_types_order do
      local name = global_types_order[i]
      if i == 1 then
        gui.Prefs.Body.Section_2["dd_"..i] = gui.Prefs.Body.Section_1.dd:setChild({
                                              on_select = true, bttn = true,
                                              id = "dd_"..i.."_"..name,
                                              table = global_types_order,
                                              extra_field = "NONE",
                                              direction = "float_b",
                                              action = "reorderFilters",
                                              float_b = gui.Prefs.Body.Section_2.Title,
                                              numbered = true},
                                              nil, nil, padding)
      else
        gui.Prefs.Body.Section_2["dd_"..i] = gui.Prefs.Body.Section_1.dd:setChild({
                                              on_select = true, bttn = true,
                                              id = "dd_"..i.."_"..name,
                                              float_r = gui.Prefs.Body.Section_2["dd_"..i-1],
                                              table = global_types_order,
                                              extra_field = "NONE",
                                              direction = "float_b",
                                              action = "reorderFilters",
                                              float_b = gui.Prefs.Body.Section_2.Title,
                                              numbered = true},
                                              nil, nil, padding)
      end
      gui.Prefs.Body.Section_2["dd_"..i]:drawDdMenu(1, i, true)
    end
    
      gui.Prefs.Body.Section_2.Add_type =
        gui.Prefs.Body.Section_2:setChild({id = "addType", w = gui.Prefs.Body.Section_1.dd.w,
                                          h = gui.Prefs.Body.Section_1.dd.h, on_select = true, bttn = true,
                                          font = 6, c = gui.Prefs.Body.c, font_c = gui.Prefs.Body.font_c,
                                          pad_y = os_is.win and config.multi == 1 and -3 or nil,
                                          float_r = gui.Prefs.Body.Section_2["dd_"..#global_types_order],
                                          float_b = gui.Prefs.Body.Section_2.Title,}, nil, nil, padding)
      
    if config.global_types_n > #global_types_order then
      gui.Prefs.Body.Section_2.Add_type:setStyle("search"):drawRect():drawTxt("+")
    end

    -- SHOW FAVORITES
    
    gui.Prefs.Body.Section_3.Cb_1 = gui.Prefs.Body.Section_1.Cb:setChild({
                                         id = "cb_fav_persist",
                                         float_b = gui.Prefs.Body.Section_3.Title,
                                         --float_r = gui.Prefs.Body.Section_3.Default_mode,
                                         }, nil, nil, padding, padding)
      
    gui.Prefs.Body.Section_3.Cb_1:drawRect():setStyle("search")
    gui.Prefs.Body.Section_3.Cb_1:drawCb("Always show favorites")
    
    -- CLEAR SEARCH
    
    gui.Prefs.Body.Section_3.Cb_2 = gui.Prefs.Body.Section_1.Cb:setChild({
                                         id = "cb_clear_search",
                                         float_b = gui.Prefs.Body.Section_3.Title,
                                         float_r = gui.Prefs.Body.Section_3.Cb_1,
                                         }, nil, nil, padding, padding)
      
    gui.Prefs.Body.Section_3.Cb_2:drawRect():setStyle("search")
    gui.Prefs.Body.Section_3.Cb_2:drawCb("Clear search box after insertion")
    
    -- SEARCH ACTION LIST
    if reaper.CF_EnumerateActions then
      gui.Prefs.Body.Section_3.Cb_3 = gui.Prefs.Body.Section_1.Cb:setChild({
                                           id = "cb_act_search",
                                           float_b = gui.Prefs.Body.Section_3.Cb_1,
                                           --float_r = gui.Prefs.Body.Section_3.Cb_1,
                                           }, nil, nil, padding, padding)
        
      gui.Prefs.Body.Section_3.Cb_3:drawRect():setStyle("search")
      gui.Prefs.Body.Section_3.Cb_3:drawCb("Search the action list")
    end
    
    -- SEARCH FX FOLDERS
    gui.Prefs.Body.Section_3.Cb_4 = gui.Prefs.Body.Section_1.Cb:setChild({
                                         id = "cb_fol_search",
                                         float_b = gui.Prefs.Body.Section_3.Cb_1,
                                         float_r = gui.Prefs.Body.Section_3.Cb_1,
                                         }, nil, nil, padding, padding)
      
    gui.Prefs.Body.Section_3.Cb_4:drawRect():setStyle("search")
    gui.Prefs.Body.Section_3.Cb_4:drawCb("Search FX browser folders")
    
    -- DEFAULT MODE
    
    gui.Prefs.Body.Section_3.Default_mode = gui.Prefs.Body.Section_1.Caption:setChild({
                                             float_b = gui.Prefs.Body.Section_3.Cb_4,
                                             },
                                             nil, nil, padding)
    gui.Prefs.Body.Section_3.Default_mode.txt_align = gui.txt_align["vert"]
    gui.Prefs.Body.Section_3.Default_mode:setStyle("search"):drawTxt("Default filter:", nil, true)
    
    gui.Prefs.Body.Section_3["dd_1"] = gui.Prefs.Body.Section_1.dd:setChild({
                                          id = "dd_1_"..(config.default_mode or "LAST USED"),
                                          w = (80 + (config.act_search and 123 or 0)) * config.multi,
                                          on_select = true, bttn = true,
                                          table = gui.lists.mode, table_name = "mode",
                                          action = "defMode",
                                          extra_field = "LAST USED",
                                          direction = "float_t",
                                          --y_reset = (gui.wnd_h - gui.Prefs.Body.Section_1.dd.h *
                                          --(#gui.lists.mode + 1)) +gui.Prefs.Body.Section_1.dd.h ,
                                          float_b = gui.Prefs.Body.Section_3.Cb_4,
                                          float_r = gui.Prefs.Body.Section_3.Default_mode},
                                          nil, nil, padding)
    
    gui.Prefs.Body.Section_3["dd_1"]:drawDdMenu(1, config.default_mode or "LAST USED", true)
     
    -- RESULT ROWS
    
    gui.Prefs.Body.Section_3.Result_rows = gui.Prefs.Body.Section_1.Caption:setChild({
                                             float_b = gui.Prefs.Body.Section_3.Cb_4,
                                             float_r = gui.Prefs.Body.Section_3["dd_1"]
                                             }, nil, nil, padding * 2, padding)
    gui.Prefs.Body.Section_3.Result_rows.txt_align = gui.txt_align["vert"]
    local auto = (gfx.dock(-1)&1 == 1 or scr.temp_undock) and "  auto" or ""
    gui.Prefs.Body.Section_3.Result_rows:setStyle("search"):drawTxt("Result rows:" .. auto, nil, true)
    
    if gfx.dock(-1)&1 == 0 and not scr.temp_undock then
      gui.Prefs.Body.Section_3.Results_max = gui.Prefs.Body.Section_3:setChild({
                                          id = "dragV_results_max", bttn = true, drag_v = true,
                                          table = config, ts_floor = 0, ts_ceil = 99, font = 14,
                                          w = gui.Prefs.Body.Section_1.dd.h,
                                          h = gui.Prefs.Body.Section_1.dd.h,
                                          --pad_y = os_is.mac and 0 or 1 * config.multi,
                                          float_b = gui.Prefs.Body.Section_3.Cb_4,
                                          float_r = gui.Prefs.Body.Section_3.Result_rows}, nil, nil, padding)
      gui.Prefs.Body.Section_3.Results_max:setStyle("dd"):drawRect()
      gui.Prefs.Body.Section_3.Results_max.c = gui.Prefs.Body.Section_3.Results_max.c - 52
      gui.Prefs.Body.Section_3.Results_max:drawBorder():drawTxt(config.results_max)
    end
   
    -- WHEN NO TRACK SELECTED
    
    gui.Prefs.Body.Section_3.No_sel_tracks = gui.Prefs.Body.Section_1.Caption:setChild({
                                             float_b = gui.Prefs.Body.Section_3.Default_mode,
                                             },
                                             nil, nil, padding)
    gui.Prefs.Body.Section_3.No_sel_tracks.txt_align = gui.txt_align["vert"]
    gui.Prefs.Body.Section_3.No_sel_tracks:setStyle("search")
    :drawTxt("If no tracks selected, " .. enter .. ":", nil, true)
    
    gui.Prefs.Body.Section_3["dd_2"] = gui.Prefs.Body.Section_1.dd:setChild({
                                          id = "dd_1_no_sel_tracks",
                                          w = (205 + (config.act_search and 63 or 0)) * config.multi, cap = true,
                                          on_select = true, bttn = true,
                                          table = gui.lists.no_sel_tracks, table_name = "no_sel_tracks",
                                          action = "noSelTracks",
                                          direction = "float_b",
                                          --y_reset = (gui.wnd_h - gui.Prefs.Body.Section_1.dd.h *
                                          --(#mode + 1)) / 2 ,
                                          float_b = gui.Prefs.Body.Section_3.Default_mode,
                                          float_r = gui.Prefs.Body.Section_3.No_sel_tracks},
                                          nil, nil, padding)
    
    gui.Prefs.Body.Section_3["dd_2"]:drawDdMenu(1, config.no_sel_tracks, true)
    
    -- DATABASE REFRESH OPTIONS
  
    gui.Prefs.Body.Section_4.Db_Refresh = gui.Prefs.Body.Section_1.Caption:setChild({
                                             float_b = gui.Prefs.Body.Section_4.Title,
                                             --float_r = gui.Prefs.Body.Section_3["dd_1"],
                                             }, nil, nil, padding)
  
    gui.Prefs.Body.Section_4.Db_Refresh.txt_align = gui.txt_align["vert"]
    gui.Prefs.Body.Section_4.Db_Refresh:setStyle("search"):drawTxt("Auto refresh:", nil, true)
    gui.Prefs.Body.Section_4:setStyle("dd")
    

  
  
    gui.Prefs.Body.Section_4["dd_1"] = gui.Prefs.Body.Section_1.dd:setChild({
                                          w = (165 + (config.act_search and 63 or 0)) * config.multi,
                                          id = "dd_1_db_scan",
                                          on_select = true, bttn = true,
                                          table = gui.lists.db_scan, table_name = "db_scan",
                                          action = "scanSet",
                                          direction = "float_t", cap = true,
                                          float_b = gui.Prefs.Body.Section_4.Title,
                                          float_r = gui.Prefs.Body.Section_4.Db_Refresh},
                                          nil, nil, padding)
  
    gui.Prefs.Body.Section_4["dd_1"]:drawDdMenu(1, config.db_scan, true)
    
    gui.Prefs.Body.Section_4.Refresh_bttn = gui.Prefs.Body.Section_4:setChild({font = 14,
                                            w = 100 * config.multi, bttn = true,
                                            h = gui.Prefs.Nav.h, id = "refreshDb",
                                            --pad_y = os_is.mac and 0 or 1 * config.multi,
                                            float_b = gui.Prefs.Body.Section_4.Title,
                                            float_r = gui.Prefs.Body.Section_4["dd_1"]},
                                            nil, nil, padding * 2, padding)
    if get_db then
      gui.Prefs.Body.Section_4.Refresh_bttn.c = config.theme == "light" and gui.bg_hue or 200
    end
    gui.Prefs.Body.Section_4.Refresh_bttn:drawRect()
    gui.Prefs.Body.Section_4.Refresh_bttn.c = gui.Prefs.Body.Section_4.Refresh_bttn.c - 52
    if get_db then
      gui.Prefs.Body.Section_4.Refresh_bttn.c = gui.bg_hue
      gui.Prefs.Body.Section_4.Refresh_bttn.font_c = config.theme == "light" and 255 or gui.bg_hue
    end
    gui.Prefs.Body.Section_4.Refresh_bttn:drawBorder():drawTxt(get_db and "Refreshing... " or "Force Refresh")
        
    
    
  elseif page == "nav_templates" then
    gui.Prefs.Body.Section_1 = gui.Prefs.Body:setChild({id = "section_1", h = (114 + padding) * config.multi,
                             float_b = gui.Prefs.Nav}, true, true, padding, padding * 1.5, true)
                             
    gui.Prefs.Body.Section_2 = gui.Prefs.Body:setChild({id = "Section_2", h = (54 + padding) * config.multi,
                             float_b = gui.Prefs.Body.Section_1}, true, true, padding, padding * 1.5, true, true)
                             
    gui.Prefs.Body:drawRect(1):hover()
    gui.Prefs.Body:setStyle("mode")
    gui.Prefs.Body.c = gui.border_c
   
    gui.Prefs.Body.Section_1.Title = gui.Prefs.Body.Section_1:setChild{id = "", x1 = gui.Prefs.Body.Section_1.x1 + 5 * config.multi,
                                                                       txt = "Parameters to copy when applying templates",
                                                                       y1 = gui.Prefs.Body.Section_1.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()
    
    gui.Prefs.Body.Section_2.Title = gui.Prefs.Body.Section_2:setChild{id = "", x1 = gui.Prefs.Body.Section_2.x1 + 5 * config.multi,
                                                                       txt = "Modifiers",
                                                                       y1 = gui.Prefs.Body.Section_2.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()

    gui.Prefs.Body.Section_1.x1 = gui.Prefs.Body.Section_1.x1 + math.floor(config.multi)
    gui.Prefs.Body.Section_2.x1 = gui.Prefs.Body.Section_2.x1 + math.floor(config.multi)
    
    gui.Prefs.Body.Section_1.Cb = gui.Prefs.Body.Section_1:setCheckBox({
                                  id = "",
                                  float_b = gui.Prefs.Body.Section_1.Title,
                                  margin = 5 * config.multi})
    
    gui.Prefs.Body.Section_1.Cb:setStyle("cb")
    local float_b, float_r, float_r_temp
    local tbl = {}

    for i = 1, #keep_state_names do
      local k = keep_state_names[i][1]
      local name = keep_state_names[i][2]
      if (i-1)%4 == 0 then
        float_r = float_r_temp
        float_r_temp = nil
        float_b = gui.Prefs.Body.Section_1.Cb.float_b
      end
      gui.Prefs.Body.Section_1["Cb_"..i] = gui.Prefs.Body.Section_1.Cb:setChild({
                                           id = "cb_" .. k, table = keep_states,
                                           reverse = true,
                                           table_name = "keep_states",
                                           float_b = float_b or gui.Prefs.Body.Section_1.Cb.float_b,
                                           float_r = float_r or nil}, nil, nil, padding, padding * (i ~= 1 and 0.5 and float_b and 0.5 or 1))
        
      gui.Prefs.Body.Section_1["Cb_"..i]:drawRect():setStyle("search"):drawCb(name)
      float_b = gui.Prefs.Body.Section_1["Cb_"..i]
      if not float_r_temp or float_r_temp.x2 < gui.Prefs.Body.Section_1["Cb_"..i].x2 then
        float_r_temp = gui.Prefs.Body.Section_1["Cb_"..i]
      end
    end
    
    gui.Prefs.Body.Section_2.Cb_1 = gui.Prefs.Body.Section_1.Cb:setChild({
                                         id = "cb_tt_apply_reverse",
                                         float_b = gui.Prefs.Body.Section_2.Title,
                                         }, nil, nil, padding, padding)
      
    gui.Prefs.Body.Section_2.Cb_1:drawRect():setStyle("search")
    gui.Prefs.Body.Section_2.Cb_1:drawCb(enter .. " applies / " .. mouse_mod[mouse_mod.clear]() ..
                                              " + " .. enter .. " adds track templates")
    
    gui.Prefs.Body.Section_1.x1 = gui.Prefs.Body.Section_1.x1 - math.floor(config.multi)
    gui.Prefs.Body.Section_2.x1 = gui.Prefs.Body.Section_2.x1 - math.floor(config.multi)
    gui.Prefs.Body.Section_1:drawBorder()
    gui.Prefs.Body.Section_2:drawBorder()
    gui.Prefs.Body.Section_1.Title:drawTitle()
    gui.Prefs.Body.Section_2.Title:drawTitle()
  elseif page == "nav_about" then 
    gui.Prefs.Body.Section_1 = gui.Prefs.Body:setChild({id = "section_1", h = (99 + padding) * config.multi,
                             float_b = gui.Prefs.Nav}, true, true, padding, padding * 1.5, true)
                             
    gui.Prefs.Body.Section_2 = gui.Prefs.Body:setChild({id = "Section_2", h = (67 + padding) * config.multi,
                             float_b = gui.Prefs.Body.Section_1}, true, true, padding, padding * 1.5, true, true)
                                 
    gui.Prefs.Body:drawRect(1):hover()
    gui.Prefs.Body:setStyle("search")
    gui.Prefs.Body.c = gui.border_c
    gui.Prefs.Body.Section_1:drawBorder()
    gui.Prefs.Body.Section_2:drawBorder()
    
    
    gui.Prefs.Body.Section_1.Title = gui.Prefs.Body.Section_1:setChild{id = "", x1 = gui.Prefs.Body.Section_1.x1 + 5 * config.multi,
                                                                       txt = "Quick Adder",
                                                                       y1 = gui.Prefs.Body.Section_1.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()
    
    gui.Prefs.Body.Section_1.x1 = gui.Prefs.Body.Section_1.x1 + padding
    
    gui.Prefs.Body.Section_1.Link_1 = gui.Prefs.Body.Section_1:setChild({id = "link_pp", link = true,
                                      url = scr.links[1],
                                      txt = "Support the development with a PayPal donation",
                                      float_b = gui.Prefs.Body.Section_1.Title},
                                      nil, nil, padding, padding * 0.5):setLink()
        
    
    gui.Prefs.Body.Section_1.Link_2 = gui.Prefs.Body.Section_1:setChild({id = "link_2", link = true,
                                      url = "help",
                                      txt = "Learn all the ways you can use the script [F1]",
                                      float_b = gui.Prefs.Body.Section_1.Link_1},
                                      nil, nil, padding, padding * 0.1):setLink()

    
    
    gui.Prefs.Body.Section_1.Link_3 = gui.Prefs.Body.Section_1:setChild({id = "link_3", link = true,
                                      url = scr.links[4],
                                      txt = "Watch the demo video on YouTube",
                                      float_b = gui.Prefs.Body.Section_1.Link_2},
                                      nil, nil, padding, padding * 0.1):setLink()
    

    
    gui.Prefs.Body.Section_1.Link_4 = gui.Prefs.Body.Section_1:setChild({id = "link_4", link = true,
                                      url = scr.links[3],
                                      txt = "Discuss the script in the REAPER forum thread",
                                      float_b = gui.Prefs.Body.Section_1.Link_3},
                                      nil, nil, padding, padding * 0.1):setLink()
                            
    gui.Prefs.Body.Section_2.Title = gui.Prefs.Body.Section_2:setChild{id = "", x1 = gui.Prefs.Body.Section_2.x1 + 5 * config.multi,
                                                                       txt = "Neutronic",
                                                                       y1 = gui.Prefs.Body.Section_2.y1 - 10 * config.multi}
                                                                       :setStyle("prefs"):drawTitle()
    
    gui.Prefs.Body.Section_2.x1 = gui.Prefs.Body.Section_2.x1 + padding
    
    gui.Prefs.Body.Section_2.Link_1 = gui.Prefs.Body.Section_2:setChild({id = "link_5", link = true,
                                      url = scr.links[2],
                                      txt = "REAPER forum profile",
                                      float_b = gui.Prefs.Body.Section_2.Title},
                                      nil, nil, padding, padding * 0.5):setLink()
        
    
    gui.Prefs.Body.Section_2.Link_2 = gui.Prefs.Body.Section_2:setChild({id = "link_6", link = true,
                                      url = "https://github.com/Neutronic/ReaScripts",
                                      txt = "GitHub ReaScripts repository",
                                      float_b = gui.Prefs.Body.Section_2.Link_1},
                                      nil, nil, padding, padding * 0.1):setLink()
                            
  end
end

function prefsView()
  if gui.view ~= "prefs" then return end
  gui.ch = gfx.getchar()

  if gui.view_change then
    if not gui.page then
      gui.page = "nav_general"
    end
    gui.view_change = nil
    if not gui.reopen then gui.reinit = true end
    gui.wnd_w = getPrefsW()
    gui.w = gui.wnd_w - gui.border * 2
  end
  
  gui.wnd_h_save = gui.wnd_h
  
  gui.wnd_h = gui.border * 2
 
  gui.Prefs = gui:setChild{w = gui.wnd_w - gui.border * 2, h = gui.wnd_h, cursor = "arrow"}
  
  gui.Prefs.Nav = gui.Prefs:setChild({id = "nav", h = math.floor(gui.row_h * 0.5), bgr = true}, true)
  gui.Prefs.Nav:setStyle("prefs")
  gui.Prefs.Nav.font = 9
  
  gui.Prefs.Nav.General = gui.Prefs.Nav:setChild{id = "nav_general", nav_bttn = true,
                                                 on_select = true, w = 60 * config.multi}
  gui.Prefs.Nav.General:setStyle("search"):drawRect():drawTxt("GENERAL")
  
  
  gui.Prefs.Nav.TT = gui.Prefs.Nav:setChild{id = "nav_templates", nav_bttn = true, w = 65 * config.multi,
                                            on_select = true, float_r = gui.Prefs.Nav.General}
  
  gui.Prefs.Nav.TT:setStyle("search"):drawRect(_,_,true):drawTxt("TEMPLATES")
  
  gui.Prefs.Nav.About = gui.Prefs.Nav:setChild{id = "nav_about", nav_bttn = true, w = 65 * config.multi,
                                            on_select = true, float_r = gui.Prefs.Nav.TT}
  
  gui.Prefs.Nav.About:setStyle("search"):drawRect(_,_,true):drawTxt("ABOUT")
  
  gui.Prefs.Nav.Hints = gui.Prefs.Nav:setChild{id = "hints", w = 50 * config.multi,
                                               float_r = gui.Prefs.Nav.About}
  gui.Prefs.Nav.Hints:setStyle("mode"):setStyle("hints_txt")

  gui.Prefs.Nav.Hints.txt_align = gui.txt_align["center"]
  gui.Prefs.Nav.Hints:drawTxt(gui.hints_txt) 
  
  gui.Prefs.Nav.Back = gui.Prefs.Nav:setChild({id = "view_main", w = math.floor(config.row_h * config.multi), bttn = true,
                                               x1 = gui.Prefs.Nav.x2 - math.floor(config.row_h * config.multi)})
  gui.Prefs.Nav.Back:setStyle("prefs"):setStyle("txt"):drawRect():drawTxt("BACK")

  
  gui.Prefs.Body = gui.Prefs:setChild({id = "body", h = 0, float_b = gui.Prefs.Nav}):setStyle("prefs")
  gui.border_c = gui.Prefs.Body.c + (config.theme == "light" and 160 or 80)
  gui.Prefs.Body.font = 13
  gui.Prefs.Body:setStyle("search")
  
  gui.hints.generate(gui.over)
  
  gui.prefs_page(gui.page)
  gui:init()
end

function getMobj()
  local setCursor = function(num, name)
    local cur = reaper.JS_Mouse_LoadCursor(num)
    reaper.JS_Mouse_SetCursor(cur)
    gui.m_cursor = "name"
  end
  
  if gui.m_cap&mouse_mod.lmb == 1 and gui.m_cap ~= 25 and
     gui.active and gui.active.id:match("^result") and
     #scr.results_list > 0 and not scr.results_list[gui.Results.sel]:match("^ACTION") then
    if gui.m_x_click ~= gui.m_x or gui.m_y_click ~= gui.m_y then
      if reaper.JS_Mouse_LoadCursor then
        if m_obj then 
          if gui.m_cursor ~= "dragdrop" and
             gui.m_cap ~= mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) then
             setCursor(182, "dragdrop")
          elseif gui.m_cursor ~= "dragdropsend" and
                 gui.m_cap == mouse_mod.dds + (gfx.mouse_cap&mouse_mod.lmb) then
            setCursor(1011, "dragdropsend")
            local cur = reaper.JS_Mouse_LoadCursor(1011)
            reaper.JS_Mouse_SetCursor(cur)
            gui.m_cursor = "dragdropsend"  
          end
        else
          if gui.m_cursor ~= "cantdrop" then
            setCursor(32648, "cantdrop")
          end
        end
      end
    end
    
    local dest, segment
    if reaper.BR_GetMouseCursorContext then
      dest, segment = reaper.BR_GetMouseCursorContext()
    end
    if segment == "empty" then m_obj = "new_track" goto SKIP end
    local x, y = reaper.GetMousePosition()
    local tk, fx_wnd = select(2, reaper.GetItemFromPoint(x, y, true))
    
    --[[if not tk then
      local checkParent = function(parent)
        if reaper.GetMainHwnd() == reaper.JS_Window_GetRelated(parent, "OWNER") and
           ((reaper.JS_Window_FindChild(parent, scr.more_wnd, true) and
           reaper.JS_Window_FindChild(parent, scr.param_wnd, true)) or
           reaper.JS_Window_FindChild(parent, scr.add_wnd, true) and
           reaper.JS_Window_FindChild(parent, scr.remove_wnd, true) and
           reaper.JS_Window_FindChild(parent, "List1", true)) then
          fx_wnd = parent
          return true
        else
          return false
        end
      end
      
      local wnd = reaper.JS_Window_FromPoint(reaper.GetMousePosition())
      local wnd_parent1 = reaper.JS_Window_GetParent(wnd)
      local wnd_parent2 = reaper.JS_Window_GetParent(wnd_parent1)
      if checkParent(wnd) or
         checkParent(wnd_parent1) or
         checkParent(wnd_parent2) then
        reaper.JS_Window_SetFocus(fx_wnd)
        local obj_type, tr_num, it_num, fx_num = reaper.GetFocusedFX()
        if obj_type > 0 then
          local tr = reaper.GetTrack(0, tr_num - 1)
          local item = reaper.GetTrackMediaItem(tr, it_num)
          if item then
            tk = reaper.GetTake(item, fx_num>>16)
          end
        end
      end
    end]]
    
    if tk then
      m_obj = tk
    else
      local tr = reaper.GetTrackFromPoint(x, y)
      if tr then m_obj = tr elseif segment ~= "track" then m_obj = nil end
    end
    ::SKIP::
  elseif gui.m_drag_x then
    gui.m_drag_x = nil
    gui.m_drag_y = nil
  end
end

function getExt()
  if not db.saved then
    config.db_scan_wait = true
    db.saved = true
  end
  gui.Row1 = {h = math.floor(gui.row_h * 0.5)}
  gui.wnd_h = 200 * config.multi
  gui.wnd_w = 400 * config.multi
  local sws = reaper.CF_EnumerateActions and 1 or 0
  local js = reaper.JS_Mouse_LoadCursor and 1 or 0
  local api = ((sws == "" or js == "") and " API.") or " APIs."
  local str = "Some functionality of the script requires:"
  
  gui.overlay = gui:setChild({x1 = 0, y1 = 0, h = gfx.h, w = gfx.w})
  gui.overlay.c = 70
  --gui.overlay:drawRect()
  gui.overlay.border = gui.overlay:setChild({h = 157 * config.multi}, _, true, 25, 30, true)
  gui.overlay.border:drawRect(_,true)
  gui.need_ext = gui.overlay:setChild({x1 = 0, y1 = 0, h = gfx.h, w = gfx.w})
  gui.need_ext:setStyle("alert")
  local w, h = gfx.measurestr(str)
  
  local bttn_h = 19 * config.multi
 
  local y1 = (gui.wnd_h - h - bttn_h) / 2.3
  local x1 = (gui.wnd_w - w) / 2
  local x_offset = 20
  gui.need_ext.msg = gui.need_ext:setChild{w = w, h = h, y1 = y1, x1 = x1}
  
  gui.need_ext.bttn = gui.need_ext:setChild({bttn = true, float_b = gui.need_ext.msg,
                                             x1 = gui.need_ext.msg.x1 + x_offset * config.multi}
                                             , nil, nil, nil, 17)
  gui.need_ext.bttn.h = bttn_h
  gui.need_ext.bttn.w = 55 * config.multi
  gui.need_ext.bttn:setStyle("prefs")
  gui.need_ext.bttn.txt_align = gui.txt_align["center"]
  gui.need_ext.bttn.font = 1
  gui.need_ext.bttn.font_c = 30
  gui.need_ext.bttn.c = config.theme == "light" and 200 or 190
  
  if sws == 0 then
    gui.need_ext.bttn.sws = gui.need_ext.bttn:setChild{id = "link_sws"}
    gui.need_ext.bttn.sws.url = "https://www.sws-extension.org/download/pre-release/"
    gui.need_ext.bttn.sws:drawRect():drawTxt("SWS API")
  end
  
  if js == 0 then 
    gui.need_ext.bttn.js = gui.need_ext.bttn:setChild{id = "link_js",
                           x1 = gui.need_ext.bttn.sws and gui.need_ext.bttn.sws.x2 + 10 * config.multi or
                           gui.need_ext.bttn.x1}
    gui.need_ext.bttn.js.url = "https://forum.cockos.com/showthread.php?t=212174"
    gui.need_ext.bttn.js:drawRect():drawTxt("JS API")
  end
  
  gui.need_ext.bttn.ok = gui.need_ext.bttn:setChild{id = "link_3", w = 45 * config.multi,
                                                    x1 = x1 + w - (45 + x_offset) * config.multi}
  gui.need_ext.bttn.ok.ext_ok = true
  gui.need_ext.bttn.ok.font_c = 255
  gui.need_ext.bttn.ok.c = 100
  gui.need_ext.bttn.ok:drawRect():drawTxt("OK")
  gui.need_ext.msg:drawTxt(str)
  
  gui.init()
  gui.ch = gfx.getchar()
end

function guiDock()
  if gfx.dock(-1)&1 == 0 then
    config.dock = config.dock and config.dock or 2<<8|1
    config.undock = false
    config.wnd_y = select(3, gfx.dock(-1, 0, 0, 0, 0))
    config.wnd_h_save = gui.wnd_h
  else
    scr.o_r = true
    config.undock = true
  end
  
  gui.reopen = true
end

function floatModePopUp()
  gfx.x = gui.Row1.Float.x1
  gfx.y = gui.Row1.Float.y1
  local str = "#FX show options||" ..
        (config.float_mode == 2 and "!" or "") .. "Always in FX chain|" ..
        (config.float_mode == 3 and "!" or "") .. "Always float|" ..
        ((not config.float_mode or config.float_mode == 4) and "!" or "") .. "Auto (context dependent)" ..
        (reaper.NamedCommandLookup("_BR_MOVE_WINDOW_TO_MOUSE_H_R_V_M") > 0 and
        ((config.float_at_mouse and "||!" or "||") .. "Show FX at mouse cursor") or "")
  retval = gfx.showmenu(str)
  if retval > 0 and retval < 5 then
    config.float_mode = retval
  elseif retval == 5 then
    if config.float_at_mouse then
      config.float_at_mouse = nil
    else
      config.float_at_mouse = true
    end
  end
end

function filterTrayPopUp()
  gfx.x = gui.Row2.dd_Mode.x1
  gfx.y = gui.Row2.dd_Mode.y1
  local str = "#Search Filter Tray items||"
  local filter_items = {}
  for k, v in pairs(filter_modes) do
    table.insert(filter_items, k)
  end
  
  filter_items = sortAbc(filter_items)
   
  for i = 1, #filter_items do
    local k = filter_items[i]
    if k == "ACTION" then
      k = "ACT (actions)"
    elseif k == "ALL" then
      k = "ALL (full database)"
    elseif k == "CHAIN" then
      k = "CH (FX chains)"
    elseif k == "FAV" then
      k = "FAV (favorites)"
    elseif k == "FOLDER" then
      k = "FOL (FX browser folders)"
    elseif k == "FX" then
      k = "FX (effects)"
    elseif k == "INSTRUMENT" then
      k = "INS (virtual instruments)"
    elseif k == "JS" then
      k = "JS (everything JS)"
    elseif k == "TEMPLATE" then
      k = "TT (track templates)"
    elseif k == "VST2" then
      k = "VST2 (everything VST2)"
    elseif k == "VST3" then
      k = "VST3 (everything VST3)"
    elseif k == "AU" then
      k = "AU (everything AU)"
    end
    str = str .. (filter_modes[filter_items[i]] and "!" or "") .. k .. "|"
  end
  
  str = str .. "|Show all filters"
  
  local retval = gfx.showmenu(str)
  if retval == #filter_items + 2 then
    for k, v in pairs(filter_modes) do
      filter_modes[k] = true
    end
    defineFilterModes()
    scr.filter_n = countFilterModes()
  elseif retval > 0 then
    local filter_modes_on = 0
    for k, v in pairs(filter_modes) do
      if v then filter_modes_on = filter_modes_on + 1 end
    end
    local key = filter_items[retval-1]:match("[^!]+")
    local state = not filter_modes[key]
    if filter_modes_on == 1 and not state then return end
    filter_modes[key] = not filter_modes[key]
    defineFilterModes()
    scr.filter_n = countFilterModes()
  end
end

function a_main()end
function main()
  if reaper.GetExtState("Quick Adder", "MSG") == "reopen" then
    reaper.SetExtState("Quick Adder", "MSG", 1, false)
    gui.reopen = true
  end
  
  if gui.open and (not scr.dock or scr.dock ~= gfx.dock(-1)&1) then
    scr.dock = gfx.dock(-1)&1
    if scr.dock == 1 then
      config.undock = false
      scr.main_w_rs = gfx.w
    else
      scr.main_w_rs = nil
      config.undock = true
    end
    initFonts()
  elseif gfx.dock(-1)&1 == 1 and (not config.dock or
     config.dock and config.dock ~= gfx.dock(-1)) then -- store dock id
    config.dock = gfx.dock(-1)
    gui.reinit = true
    gui.wnd_h_save = gui.wnd_h
  end
   
  gui.bg_hue = config.theme == "light" and 50 or 30
  gui.accent_c = config.theme == "light" and 130 or 40
  gfx.clear = reaper.ColorToNative(gui.bg_hue, gui.bg_hue, gui.bg_hue)
  gui.x1 = gui.border * (config.undock and 1 or 4)
  gui.y1 = gui.border * (config.undock and 1 or 4)
  
  gui.focus = gfx.getchar(65536)&2
 
  gui.m_cap = gfx.mouse_cap
  gui.m_x = gfx.mouse_x
  gui.m_y = os_is.mac and gfx.mouse_y - 1 or gfx.mouse_y

  getMobj()
  
  inBounds()

  if config.ext_check then
    getExt()
  else
    mainView()
  end
  prefsView()
  
  if gui.m_y_click and gui.active and gui.active.drag_v then
    pcall(scr.actions.dragV, gui.active)
  end
  
  if gui.clicked and not gui.click_ignore then
    if gui.clicked.m_cap&1 == 1 then -- if left mouse click
      pcall(scr.actions[gui.clicked.id:gsub("(.-)_.+", "%1")], gui.clicked.o)
    elseif gui.clicked.m_cap&2 == 2 and gui.clicked.id == ("hints" or "nav") then -- if right click
      --themeSwitch()
      guiDock()
    elseif gui.clicked.m_cap&2 == 2 and gui.clicked.id == "dd_1_mode" then
      filterTrayPopUp()
    elseif gui.clicked.m_cap&2 == 2 and gui.clicked.id == "float" then
      floatModePopUp()  
    end
    gui.clicked = nil
  end
  
  if gui.focused then
    pcall(scr.actions[gui.focused.id:gsub("%p%d", ""):gsub("(.-)_.+", "%1")], gui.focused, true)
  end
  
  if not config.ext_check then kbActions() end

  if not gui.search_suspend or gui.search_suspend and gui.str == "" then
    if gui.str ~= "" and (scr.re_search or
       scr.do_search and gui.str ~= gui.str_temp and not get_db) then -- generate matches
      gui.str_temp = gui.str
      --[[if (not gui.str:match(".+[%s/]$") and not gui.str:match(".+/%d+$")
         or scr.re_search) and #scr.results_list > 0 then]]
        gui.Results = {sel = (gui.ch == ignore_ch.f7 or gui.ch == ignore_ch.f8) and
                       (gui.Results.sel <= config.results_max and gui.Results.sel or
                        config.results_max) or 1}
      --end
      scr.re_search = nil
      parseQuery()
       
      match_stop = nil
    elseif config.fav_persist and (
           gui.str == "" and #scr.results_list == 0 and #db.FAV > 0
           or scr.re_search) then
      scr.actions.clear(_, true, gui.Results.sel <= config.results_max and gui.Results.sel or
                                 config.results_max > 0 and config.results_max or 1)
      scr.re_search = nil
      if config.results_max > 0 then doMatch() end  
    end
  end

  if (gui.ch == ignore_ch.enter and not gui.dd_items or
      double_clicked and gui.over == double_clicked_id and gui.over:match("result") or
      m_obj and gui.m_cap&mouse_mod.lmb == 0) and
      scr.match_found then
    if not config.pin then
      scr.over = true
      gfx.quit()
    end
    doAdd()
    
    if config.clear_search and gui.str ~= "" then scr.actions.clear() end
 
    if config.pin and (not config.fx_hide or gfx.getchar(65536)&2 ~= 2) and
       config.no_sel_tracks < 3 then
      if not scr.result_is_action and gui.m_cap ~= mouse_mod.shift + mouse_mod.alt and
         not scr.bypass_reopen then
        gui.reopen = true gui:init()
      else
        scr.result_is_action = nil
        scr.bypass_reopen = nil
      end
    else
      reaper.atexit(exit_states)
    end
  end  
   
  if double_clicked then
    double_clicked = nil
  end
  if not _timers.double_click and double_clicked_id then
    double_clicked_id = nil
  end

  if gui.ch == -1 then
    if scr.temp_undock then
      scr.temp_undock = nil
      config.undock = false
      gui.reopen = true
      gui.view = "main"
      gui:init()
      reaper.defer(main)
    elseif gui.view == "main" then
      reaper.atexit(exit_states)
    end
  else
    if not scr.over then
      reaper.defer(main)
    end
  end
end

main()

getDb()

reaper.atexit(exit_states)
