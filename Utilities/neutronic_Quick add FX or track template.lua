--[[
Description: quick add FX or track template
Version: 1.01
Author: Neutronic
Donation: https://paypal.me/SIXSTARCOS
Changelog:
  v1.01
    + Added input_ovrd option to allow users hardcode a search query
Links:
  Neutronic's REAPER forum profile: https://forum.cockos.com/member.php?u=66313
About: 
  Adds FX to selected track(s)/take(s) or track template{s)
--]]

-- Licensed under the GNU GPL v3

--require("dev")
function console() end

local vst_order = 23 -- 23 to scan VST2 first, 32 to scan VST3 first
local input_ovrd = "" -- put FX or track template query inside the quotes to hardcode it; otherwise leave it as is
local sel_tr_count = reaper.CountSelectedTracks()
local sel_it_count = reaper.CountSelectedMediaItems()
local m_track = reaper.GetMasterTrack()
local is_m_sel = reaper.IsTrackSelected(m_track)
local name, name_parts, temp_line, prefix, plugs, input, undo_name, t_or_t, retval, data
local r_path = reaper.GetExePath()
local dir_list = {}
local file_list = {}
local OS, sep, dest = package.config:sub(1,1)
if OS == "\\" then -- if WIN
  sep = "\\"
else -- if UNIX
  sep = "/"
end
local vst = reaper.GetExePath() .. sep .. "reaper-vstplugins64.ini"
local js = reaper.GetExePath().. sep .. "reaper-jsfx.ini"
local js_ini = reaper.file_exists(js)
if not js_ini then
  reaper.MB("reaper-jsfx.ini file not found. FX browser is about to be open to create the file.",
                                      "REASCRIPT Query", 0) 
  
  if reaper.GetToggleCommandState(40271) == 0 then
    reaper.Main_OnCommand(40271, 1)
  end                                
  return
end

function add_fx()
  match()
  if name then
    if not dest or dest == "/i" then
      reaper.PreventUIRefresh(1)
        add_track_fx()
      reaper.PreventUIRefresh(-1)
    elseif dest and dest == "/t" then
      reaper.PreventUIRefresh(1)
        add_item_fx()
      reaper.PreventUIRefresh(-1)
    end
  else
    reaper.MB("No FX matched your request.", "REASCRIPT Query", 0)
  end
end

function add_track_fx()
  if sel_tr_count > 0 or is_m_sel then
    reaper.Undo_BeginBlock()
      is_input()
      track_fx()
      master_fx()
      track_or_tracks()
      if dest == "/i" then -- if input fx then
    reaper.Undo_EndBlock("Add input "..undo_name.." to selected "..t_or_t, 2)
      else
    reaper.Undo_EndBlock("Add "..undo_name.." to selected "..t_or_t, 2)
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

function track_fx()
  for i = 0, sel_tr_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    reaper.TrackFX_AddByName(track, name, input, -1)
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
    reaper.TrackFX_AddByName(m_track, name, input, -1)
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
        reaper.TakeFX_AddByName(take, name, -1)
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
  plugs = {}
  
  vst_match(vst, plugs)  
  
  js_match(js, plugs)
     
  gen_name(plugs)  
end

function vst_match(vst, plugs)
  for line in io.lines(vst) do
    if line:find("%(") then
      local _, start = line:find("%w+,%d+,")
      if start then
        start = start + 1
      else
        start = 0
      end
      if line:lower():find("vst3") then
        prefix = "VST3:"
      else
        prefix = "VST2:"
      end
      table.insert(plugs, prefix .. line:sub(start))
    end
  end
end

function js_match(js, plugs)
  for line in io.lines(js) do
    if line:find("NAME") then
      local _, start = line:find('NAME ')
      line = line:sub(start+1)
      table.insert(plugs, "VST2:JS: " .. line)
    end
  end
end

function gen_name(plugs)
  if #name_parts == 1 and name_parts[1]:match("^/") then
    return
  end
  --[[for i, v in ipairs(name_parts) do
    if v == "eeq" then
      name_parts[i] = "reaeq"
      break
    elseif v == "ccomp" then
      name_parts[i] = "reacomp"
      break
    end
  end]]
  if vst_order == 23 then -- if user wants to scan VST2 first
    for i, v in ipairs(name_parts) do
      if not v:lower():find("vst3") and i == #name_parts then
        table.insert(name_parts, "vst2")
        break
      elseif v:lower():find("vst3") then
        break
      end
    end
  end
  --[[for i, v in ipairs(name_parts) do
    if not v:lower():match("mono") and i == #name_parts then
      table.insert(name_parts, "%-mono")
      break
    elseif v:lower():match("mono") then
      break
    end
  end]]
  for i, v in ipairs(plugs) do
    for m = 1, #name_parts do
      if not name_parts[m]:match("^/") then
        local exclude = string.match(name_parts[m], "^%%%-.+")
        if exclude then
          for word in v:gmatch("[%w%-/]+") do
            temp_line = word:lower():find("^"..name_parts[m]:lower():sub(3))
            if temp_line then
              temp_line = nil
              goto LOOP_END
            end
          end
          if temp_line then
          else
            temp_line = 1
            goto LOOP_CONT
          end
        else
          for word in v:gmatch("[%w%-/]+") do
            temp_line = word:lower():match(name_parts[m]:lower()) -- match("^"..name_parts[m]:lower())
            if temp_line then
              break
            end
          end
          if not temp_line then
            break
          end
        end
        ::LOOP_CONT::
      end
    end
    
    ::LOOP_END::
   
    if temp_line then
      if v:find("JS") then
        name = v:sub(v:find("JS:")+3)
        --name = name:match("[%w%p]+")
        name = name:match('.+"JS:'):sub(2, -6):gsub('"', "")
        undo_name = v:gsub(v:match('.+JS:%s'), "") -- cut to JS in the name
        if undo_name:find("%(") then -- if there is a "(" in the string
          undo_name = undo_name:gsub("[^(]+$", "")
          undo_name = undo_name:sub(0, -3)
        else
          undo_name = undo_name:sub(0, -2)
        end
      else
        name = v
        local _, str_end = name:find(".-%!") -- find exclamation point
        if str_end then
          name = name:sub(0, str_end - 1) -- truncate to exclamation point
        end
        local _, str_end = name:find(".-%(") -- find parenthesis
        undo_name = name:sub(6, str_end - 2)
      end
        console("Plug-in name: " .. name, 1)
      break
    elseif not temp_line and i == #plugs then
      name = nil
    end
  end 
end

function sub_d_check(dir)
  local i = 0
  repeat
    local temp_dir = reaper.EnumerateSubdirectories([[]] .. r_path .. dir .. [[]], i)
    if temp_dir then
      local dir = dir .. sep .. temp_dir
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
        if dir:match(match) then
          local dir = sep..dir
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
            table.insert(file_list, {file, [[]] .. r_path .. dir_list[i] .. [[]] .. sep})
          end
          m = m + 1
        end
      until not file
    end
  end
end

function add_tr_temp()
  list_dir("TrackTemplates", "RTrackTemplate")
  local template_inst, track_template
  for i, v in ipairs(file_list) do
    for m = 1, #name_parts do
      if m == 1 then
        name_parts[1] = name_parts[1]:gsub("%%.", "")
      end
      if not name_parts[m]:match("^/") then
        exclude = string.match(name_parts[m], "^%%%-.+")
        if exclude then
          temp_line = v[1]:lower():find(name_parts[m]:sub(3))
          if temp_line then
            temp_line = nil
            goto LOOP_END
          else
            temp_line = 1
            goto LOOP_CONT
          end
        else
          temp_line = v[1]:lower():find(name_parts[m])
          if not temp_line then
            break
          end
        end
      elseif name_parts[m]:match("/%d+") then
        template_inst = name_parts[m]:match("%d+")
      end
      ::LOOP_CONT::
    end
    
    ::LOOP_END::
   
    if temp_line then
      track_template = [[]] .. v[2] .. v[1] .. [[]] .. ".RTrackTemplate"
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
      break
    end
  end
  if not track_template then
    reaper.MB("No track template found", "REASCRIPT Query", 0)
  end
end

function main()
  if input_ovrd == "" then
    retval, data = reaper.GetUserInputs("Quick Add FX or Track Template", 1, "FX or track template keyword(s):,extrawidth=88", "")
  else
    data = input_ovrd
  end
  console("User Data: ".. data, 1, 1)
  if retval or input_ovrd ~= "" then
    name_parts = {}
    local i = 0
    for word in data:gmatch("[%w%p]+") do
      i = i + 1
      word = word:lower()
      word = word:gsub("\\", "") -- remove occurences of \
      word = word:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1") -- escape magic characters with %
      console("Word #" .. i .. ": " .. word, 1)
      if word == "/t" or word == "/i" then
        dest = word
      end
      if word:lower() == "v3" then
        word = "vst3"
      end
      table.insert(name_parts, word)
    end
    if name_parts[1]:match("^%%%.") ~= "%." then
      add_fx()
    else
      add_tr_temp()
    end
  end
end

main()
