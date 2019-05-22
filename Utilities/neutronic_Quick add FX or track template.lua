--[[
Description: quick add FX or track template
Version: 1.1
Author: Neutronic
Donation: https://paypal.me/SIXSTARCOS
Changelog:
  v1.01 - May 14 2019
    + Added input_ovrd option to allow users hardcode a search query
  v1.1 - May 22 2019
    + 32-bit support
    + .RfxChain support
    + exact match search ability using quotes
    + ability to choose the FX search order
    + in-script help with complete syntax list
    # improved overall script's logic
Links:
  Neutronic's REAPER forum profile: https://forum.cockos.com/member.php?u=66313
  Script's forum thread: https://forum.cockos.com/showthread.php?t=220800
About: 
  Adds FX to selected track(s)/take(s) or track template{s)
--]]

-- Licensed under the GNU GPL v3

--require("dev")
function console() end

local input_ovrd = "" -- put FX or track template query inside the quotes to hardcode it; otherwise leave it as is
local sel_tr_count = reaper.CountSelectedTracks()
local sel_it_count = reaper.CountSelectedMediaItems()
local m_track = reaper.GetMasterTrack()
local is_m_sel = reaper.IsTrackSelected(m_track)
local name, name_parts, part_match, l, input, undo_name, t_or_t, retval, data, js_name, v_s, dest,
      dest_count, fx_ch_list, fx_i, plugs, vst
local r_path = reaper.GetResourcePath()
local fx_a = "VST2"
local fx_b = "VST3"
local fx_c = "JS"
local fx_d = "CHAIN"
local fx_type = {fx_d, fx_a, fx_b, fx_c} -- the search order of FX types. Can be reordered.
local dir_list = {}
local file_list = {}
local plugs_rel = {}
local exact = ""
local OS = package.config:sub(1,1)
local bit_vers = reaper.GetAppVersion():gsub(".+/", "")

if bit_vers:gsub("%D", "") == "64" then
  vst = r_path .. "/reaper-vstplugins64.ini"
else
  vst = r_path .. "/reaper-vstplugins.ini"
end

function close_undo()
  reaper.Undo_EndBlock("ReaScript: Run", -1)
end

function no_fx()
  reaper.MB("No FX matched your request.", "REASCRIPT Query", 0)
end

function add_fx()
  list_dir("FXChains", "RfxChain")
  fx_ch_list = file_list
  file_list = {}
  dir_list = {}
  match()
  if #plugs_rel == 0 then
    no_fx()
    return
  end
  for i = 1, #plugs_rel do
    console("Match " .. i .. ": " .. plugs_rel[i][1], 1)
  end
  if not dest or dest == "/i" then
    reaper.PreventUIRefresh(1)
      add_track_fx()
    reaper.PreventUIRefresh(-1)
  elseif dest and dest == "/t" then
    reaper.PreventUIRefresh(1)
      add_item_fx()
    reaper.PreventUIRefresh(-1)
  end
end

function add_track_fx()
  if sel_tr_count > 0 or is_m_sel then
    reaper.Undo_BeginBlock()
      is_input()
      track_fx()
      master_fx()
      if fx_i == -1 then return end
      track_or_tracks()
      if dest == "/i" then -- if input fx then
        reaper.Undo_EndBlock("Add input "..undo_name.." to selected "..t_or_t, -1)
      else
        reaper.Undo_EndBlock("Add "..undo_name.." to selected "..t_or_t, -1)
      end
  else
    local answ = reaper.MB("Select a track to put the fx on.", "REASCRIPT Query", 1)
    if answ == 1 then
      track_wait()
    else
      return
    end
  end
end

function is_input()
  if dest == "/i" then
    input = true
  else
    input = false
  end
end

function plugs_rel_parse(v)
  if v.fx_type == "JS" then -- if JS
    name = v[1]:match(".+||"):gsub("|", "")
    undo_name = v[1]:gsub(".+||", ""):gsub(" %(.+%)", "")
  elseif v.fx_type == "CHAIN" then
    name = [[]] .. v[1][2]:gsub(r_path .. "/FXChains/", "") .. v[1][1] .. [[]] .. ".RfxChain"
    undo_name = v[1][1]
  else -- if VST
    name = v.fx_type..":"..v[1]:gsub("!.+", "")
    undo_name = name:gsub("VST%d:", ""):gsub(" %(.+%)", "")
  end
  console("Plug-in name: " .. name .. "\nPlug-in undo name: " .. undo_name, 1)
end

function track_fx()
  for i = 0, sel_tr_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    for i, v in ipairs(plugs_rel) do
      plugs_rel_parse(v)
      fx_i = reaper.TrackFX_AddByName(track, name, input, -1)
      if fx_i >= 0 then break end
    end
    if fx_i == -1 then
      no_fx()
      close_undo()
      break
    end
    if i == 0 then
      if dest == "/i" then -- if input FX
        reaper.TrackFX_Show(track, 0x1000000+reaper.TrackFX_GetRecCount(track)-1, 3)
      else
        reaper.TrackFX_Show(track, reaper.TrackFX_GetCount(track)-1, 3)
      end
    end
  end
end

function master_fx()
  if is_m_sel then -- if master track is selected
    for i, v in ipairs(plugs_rel) do
      plugs_rel_parse(v)
      fx_i = reaper.TrackFX_AddByName(m_track, name, input, -1)
      if fx_i >= 0 then break end
    end
    if fx_i == -1 then
      no_fx()
      close_undo()
    end
    if sel_tr_count == 0 then -- if no other tracks are selected then float the master FX
      reaper.TrackFX_Show(m_track, reaper.TrackFX_GetCount(m_track)-1, 3)
    end
  end
end

function track_or_tracks()
  if sel_tr_count > 1 or sel_tr_count == 1 and is_m_sel then
    t_or_t = "tracks"
  else
    t_or_t = "track"
  end
end

function add_item_fx()
  if sel_it_count > 0 then
    reaper.Undo_BeginBlock()
      for i = 0, sel_it_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        for i, v in ipairs(plugs_rel) do
          plugs_rel_parse(v)
          fx_i = reaper.TakeFX_AddByName(take, name, -1)
          if fx_i >= 0 then break end
        end
        if fx_i == -1 then
          no_fx()
          close_undo()
          return
        end
        if i == 0 then
          reaper.TakeFX_Show(take, reaper.TakeFX_GetCount(take)-1, 3)
        end
      end
      if sel_it_count > 1 then
        dest_count = "items"
      else
        dest_count = "item"
      end
    reaper.Undo_EndBlock("Add "..undo_name.." to selected "..dest_count, -1)
  else
    local answ = reaper.MB("Select an item to put the FX on.", "REASCRIPT Query", 1)
    if answ == 1 then
      item_wait()
    else
      return
    end
  end
end

function item_wait()
  sel_it_count = reaper.CountSelectedMediaItems()
  if sel_it_count == 0 then
    reaper.defer(item_wait)
  else
    add_item_fx()
  end
end

function track_wait()
  sel_tr_count = reaper.CountSelectedTracks()
  is_m_sel = reaper.IsTrackSelected(m_track)
  if sel_tr_count > 0 or is_m_sel then
    add_track_fx()
  else
    reaper.defer(track_wait)
  end
end

function match()
  plugs = {VST2 = {}, VST3 = {}, JS = {}}
  
  match_vst()  
  
  match_js()
  
  for i, v in ipairs(name_parts) do
    if v:upper() == fx_type[1] then
      gen_name(fx_type[1])
      break
    elseif v:upper() == fx_type[2] then
      gen_name(fx_type[2])
      break
    elseif v:upper() == fx_type[3] then
      gen_name(fx_type[3])
      break
    elseif v:upper() == fx_type[4] then
      gen_name(fx_type[4])
      break
    elseif i == #name_parts then
      for i = 1, #fx_type do
        gen_name(fx_type[i])
        if name then break end
      end
    end
  end
end

function match_vst()
  for line in io.lines(vst) do
    if line:find("%(") then
      if line:lower():find("vst3") then
        local vst_name = line:gsub(".+%d%d%d%d%d,", "")--:gsub("!.+", "")
        table.insert(plugs.VST3, vst_name)
      else
        local vst_name = line:gsub(".+%d%d%d%d%d,", "")--:gsub("!.+", "")
        table.insert(plugs.VST2, vst_name)
      end
    end
  end
end

function match_js()
  list_dir("Effects")
  for i = 1, #file_list do
    local file = io.open(r_path.."/Effects/"..file_list[i][1])
    for l in file:lines() do
       if l:find("desc:") then js_name = l:gsub("desc:", "") break end
    end
    file:close() 
    table.insert(plugs.JS, file_list[i][1] .. "||" .. js_name)
  end
end

function gen_name(fx_type)
  local s_path
  if fx_type == "CHAIN" then
    s_path = fx_ch_list
  elseif fx_type == "TEMPLATE" then
    s_path = file_list
  else
    s_path = plugs[fx_type]
  end
  for i, v in ipairs(s_path) do
    for m = 1, #name_parts do
      --
      if name_parts[m]:match("^/") or
      name_parts[m]:upper():match("VST%d") or
      name_parts[m]:upper():match("JS") or
      name_parts[m]:upper():match("CHAIN") then goto PART_SKIP end -- if flag or fx type then skip
      if type(v) == "table" then l = v[1] else l = v end
      exclude = string.match(name_parts[m], "^%%%-.+")
      --
      if exclude then
        part_match = l:lower():match(name_parts[m]:gsub("%%%-", ""))
        if part_match then
          part_match = nil
          goto LOOP_END
        else
          part_match = 1
        end
      else
        if name_parts[m]:match("^\".+\"$") and not name_parts[m]:match("%s") then -- if exact word
          for word in l:gmatch("[%w%p]+") do
            part_match = word:lower():match("^"..name_parts[m]:gsub("\"", "").."$")
            if part_match then
              break
            end
          end
        elseif name_parts[m]:match("^\".+\"$") then -- if exact phrase
          part_match = l:lower():match((name_parts[m]:gsub("\"", "")))
        else
          part_match = l:lower():match(name_parts[m])
        end
        if not part_match then
          break
        end
      end
      ::PART_SKIP::
    end
    ::LOOP_END::
    if part_match then
      if fx_type == "TEMPLATE" then
        add_tr_temp(v)
        break
      else
        table.insert(plugs_rel, {fx_type = fx_type,v})
      end
    elseif not part_match and i == #s_path and fx_type == "TEMPLATE" then
      reaper.MB("No track template found", "REASCRIPT Query", 0)
    end
  end
end

function sub_d_check(dir)
  local i = 0
  repeat
    local temp_dir = reaper.EnumerateSubdirectories([[]] .. r_path .. dir .. [[]], i)
    if temp_dir then
      local dir = dir .. "/" .. temp_dir
      table.insert(dir_list, dir)
      sub_d_check(dir)
    end
    i = i + 1
  until not temp_dir
end

function list_dir(match, ext)
  do
    local i = 0
    repeat
      dir = reaper.EnumerateSubdirectories([[]] .. r_path .. [[]], i)
      if dir then
        if dir:match("^"..match) then
          local dir = "/"..dir
          table.insert(dir_list, dir)
          sub_d_check(dir)
        end
      end
      i = i + 1
    until not dir
  end
  
  for i = 1, #dir_list do
    do
      local m = 0
      repeat
        file = reaper.EnumerateFiles([[]] .. r_path .. dir_list[i] .. [[]], m)
        if file then
          if file:match("[^%.]-$") == ext then
            file = file:gsub("%." .. ext, "")
            table.insert(file_list, {file, [[]] .. r_path .. dir_list[i] .. [[]] .. "/"})
          elseif file:match("^.+jsfx$") or not file:match("%.") then -- if JS
            local dir = dir_list[i]:gsub("/" .. match, "")
            if dir ~= "" then
              table.insert(file_list, {dir .. "/" .. file, [[]] .. r_path .. dir_list[i] .. [[]] .. "/"})
            else
              table.insert(file_list, {file, [[]] .. r_path .. dir_list[i] .. [[]] .. "/"})  
            end
          end
          m = m + 1
        end
      until not file
    end
  end
end

function add_tr_temp(v)
  local template_inst
  for i, a in ipairs(name_parts) do -- check for TT number flag
    if a:match("/%d+") then
      template_inst = a:match("%d+")
      break
    end
  end
  local track_template = [[]] .. v[2] .. v[1] .. [[]] .. ".RTrackTemplate"
  if track_template then
    reaper.Undo_BeginBlock()
      local t_temp = {}
      if template_inst then
        for i = 1, template_inst do
          reaper.Main_openProject(track_template)
          table.insert(t_temp, reaper.GetSelectedTrack(0, 0))
        end
        for i = 1, #t_temp do
          reaper.SetTrackSelected(t_temp[i], 1)
        end    
      else
        reaper.Main_openProject(track_template)
      end      
    reaper.Undo_EndBlock("Insert " .. v[1], -1)
  end
  console("Template path: " .. track_template, 1)
end

function match_exact(word)
  if exact_start and exact_insert and not word:match("^\"") and not word:match("\"$") then
    exact = exact .. word .. " "
    exact_insert = nil
  end
  if word:match("^\"") then
    if not exact_start then
      if not word:match("\"$") then
        exact = exact..word.." "
        exact_start = 1
      else
        exact = exact..word
      end
    end
  end
  if exact_start and exact_insert and word:match("\"$") then
    exact = exact..word
    exact_start = nil
    exact_insert = nil
  elseif exact_start and not word:match("\"$") then
    exact_insert = 1
  end
end

function url_open(url)
  local os = reaper.GetOS()
  if os == "Win32" or os == "Win64" then
    reaper.ExecProcess('cmd.exe /C start "" "' .. url .. '"', 0)
  elseif os == "OSX32" or os == "OSX64" then
    os.execute('open "" "' .. url .. '"')
  elseif os == "Other" then
    os.execute('xdg-open "" "' .. url .. '"')    
  end
end

function stop_str(str)
  local ch = {"^/", "^%%%.$", "^\"$"}
  for i, v in ipairs(ch) do
    if str:match(v) then
      return true
    end
  end
end

function main()
  if input_ovrd == "" then
    retval, data = reaper.GetUserInputs("Quick Add FX or Track Template", 1, "FX or track template ('?' for help):,extrawidth=88", "")
  else
    data = input_ovrd
  end
  if data == "" then return end
  console("Input Data: ".. data, 1, 1)
  if retval or input_ovrd ~= "" then
    name_parts = {}
    local i = 0
    for word in data:gmatch("[%w%p]+") do
      i = i + 1
      word = word:lower()
      word = word:gsub("\\", "") -- remove occurences of \
      word = word:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1") -- escape magic characters with %
      match_exact(word)
      console("Word #" .. i .. ": " .. word, 1)
      if word == "/t" or word == "/i" then
        dest = word
      end
      table.insert(name_parts, word)
    end    
    
    if exact ~= "" then
      temp_parts = {}
      table.insert(temp_parts, exact)
      for i, v in ipairs(name_parts) do
        if not exact:match(v:gsub("%.", "%%.")) then
          table.insert(temp_parts, v)
        end
      end
      name_parts = temp_parts
      temp_parts = nil
    end
    
    --[[
    This part allows putting period before any keyword to insert a track template
    for i, v in ipairs(name_parts) do
      if v:match("^%%%.") and i > 1 then
      bla = i
        name_parts[#name_parts+1] = name_parts[1]
        name_parts[1] = v
        name_parts[i] = name_parts[#name_parts]
        name_parts[#name_parts] = nil
        break
      end
    end]]
    
    if #name_parts == 1 and stop_str(name_parts[1]) then
      return
    elseif name_parts[1]:match("^%%%$$") and #name_parts == 1 then -- donate
      url_open("https://paypal.me/SIXSTARCOS")
    elseif name_parts[1]:match("^%%%?$") and #name_parts == 1 then
      reaper.MB("You can use the script to add track FX, input FX, take FX, FX chains"..
                " and track templates. The script supports both full words and partial keywords.\n\n"..
                "When adding FX you can use:\n/i flag to add input track FX (e.g. gate /i);\n" ..
                "/t flag for take FX (e.q. EQ /t);\n"..
                "vst2/vst3/js keyword to force either format (e.g pro-q vst3).\n\n"..
                "Track templates specifics:\n"..
                "To add a track template use . prefix with the first word (eg .soft piano).\n"..
                "To add multiple instance of a template use /n flag (eg .bgv /4).\n\n"..
                "Common syntax:\n"..
                "put keywords in quotes to do an exact search (e.g. \".vox adlib\" /2);\n"..
                "use the - prefix to exclude keywords (e.g. comp -cockos).\n\n"..
                "Type in the $ sign to donate. Thanks!", "Quick Add Help", 0)
    elseif name_parts[1]:match("^%%%.") or name_parts[1]:match("^\"%%%.") then -- if template
      list_dir("TrackTemplates", "RTrackTemplate")
      name_parts[1] = name_parts[1]:gsub("%%.", "")
      console("Name part 1: " .. name_parts[1], 1)
      gen_name("TEMPLATE")
    else
      add_fx()
    end
  end
end

main()
