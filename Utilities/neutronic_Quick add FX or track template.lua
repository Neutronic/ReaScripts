--[[
Description: Quick add FX or track template
About: Adds FX or track templates to selected tracks or takes.
Version: 1.50
Author: Neutronic
Donation: https://paypal.me/SIXSTARCOS
License: GNU GPL v3
Links:
  Neutronic's REAPER forum profile https://forum.cockos.com/member.php?u=66313
  Script's forum thread https://forum.cockos.com/showthread.php?t=220800
Changelog:
  + option to clear master track FX chain before adding FX
  # open plugins inside FX Chains if chains are visible
--]]

--require("dev")
function console() end
local cur_os = reaper.GetOS()

---------- USER DEFINABLES ----------

local input_ovrd = "" -- put FX or track template query inside the quotes to hardcode it
local fx_a = "VST2"
local fx_b = "VST3"
local fx_c = "JS"
local fx_d = "CHAIN"
local fx_e = "AU"
local fx_type = {fx_d, fx_e, fx_a, fx_b, fx_c} -- the search order of FX types. Can be reordered

----- change the values below to true to activate the options or false to disable

local search_track_name = false -- silently feed track names to the script
local a_flag_reverse = false -- set it to "true" to reverse the behavior of the /a flag

local keep_states = { -- what original track info to preserve when applying track templates
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

-------------------------------------

keep_states.GROUP_FLAGS_HIGH = keep_states.GROUP_FLAGS
local sel_tr_count = reaper.CountSelectedTracks()
local sel_it_count = reaper.CountSelectedMediaItems()
local m_track = reaper.GetMasterTrack()
local is_m_sel = reaper.IsTrackSelected(m_track)
local name, name_parts, part_match, l, input, undo_name, t_or_t, retval, data, js_name, v_s, dest,
      dest_count, fx_ch_list, fx_i, plugs, vst, au, sel_tr, track_1_sub, content, tracks, clear_fx
local r_path = reaper.GetResourcePath()
local dir_list = {}
local file_list = {}
local plugs_rel = {}
local exact = ""
local bit_vers = reaper.GetAppVersion():gsub(".+/", "")

if bit_vers:gsub("%D", "") == "64" then
  vst = r_path .. "/reaper-vstplugins64.ini"
  if cur_os == "OSX64" then
    au = r_path .. "/reaper-auplugins64.ini"
  end
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
    local l
    if type(plugs_rel[i][1]) == "table" then  l = plugs_rel[i][1][1] else l = plugs_rel[i][1] end
    console("Match " .. i .. ": " .. l, 1)
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
  local pass
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

function flush_fx(object, kind)
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

function template_single(i)
  track_1_sub = tracks[1]
  local tr = reaper.GetSelectedTrack(0, i)
  flush_fx(tr, 1)
  for k, v in pairs(sel_tr[i+1]["states"]) do -- recall states
    if tracks[1]:match(k) then
      track_1_sub = track_1_sub:gsub(k..".-\n", v, 1)
    else
      track_1_sub = track_1_sub:gsub("<TRACK.-\n", "%0  "..v, 1)
    end
  end
  if keep_states.ITEMS == true then
    for m = #sel_tr[i+1]["items"], 1, -1 do -- recall items
      track_1_sub = track_1_sub:gsub("<TRACK.-\n", "%0"..sel_tr[i+1]["items"][m].."\n")
    end
  end
  reaper.SetTrackStateChunk(tr, track_1_sub, false)
end

function template_multi(first_sel_tr, first_sel_tr_idx)
  for i = 0, #tracks do
    if i == #tracks then
      template_single(0)
    elseif i ~= 0 then
      reaper.InsertTrackAtIndex(first_sel_tr_idx + i, false)
      local tr = reaper.GetTrack(0, first_sel_tr_idx + i)
      reaper.SetTrackStateChunk(tr, tracks[i+1], false)
    end
  end
end

function keepers(tracks, tr_chunk, state, i)
  if state == "ISBUS" and #tracks > 1 then return end
  local save_state = tr_chunk:match(state..".-\n")
  sel_tr[i+1]["states"][state] = save_state
end

function apply_template(template) 
  local fn = string.gsub(template, "\\", "/")
  local file = io.open(fn)
  content = file:read("*a")
  file:close()
  
  local first_sel_tr_idx
  
  tracks = {}
  
  content = content:gsub("{.-}", "")
  
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
  
  if content == "" or sel_tr_count == 0 then close_undo() return end  
  
  if not search_track_name then
    first_sel_tr_idx = reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, 0), "IP_TRACKNUMBER") - 1
  else
    first_sel_tr_idx = reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, pass), "IP_TRACKNUMBER") - 1
  end
  
  first_sel_tr_idx = math.floor(first_sel_tr_idx)
  
  sel_tr = {}
  for i = 0, sel_tr_count -1 do
    local tr = reaper.GetSelectedTrack(0, i)
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
        keepers(tracks, tr_chunk, k, i)
      end
    end
  end

  for i = 1, #tracks do -- fix sends
    tracks[i] = tracks[i]:gsub("(AUXRECV )(%d+)", function(a, b) b = tonumber(b) + first_sel_tr_idx return a..b end)
  end
  
  if not search_track_name and #tracks > 1 then
    template_multi(first_sel_tr, first_sel_tr_idx)
  elseif search_track_name then
    if #tracks > 1 then
      template_multi(first_sel_tr, first_sel_tr_idx)
    else
      template_single(pass)
    end
    if sel_tr_count - pass > 1 then
      pass = pass + 1
      main()
    end
  else
    for i = 0, sel_tr_count - 1 do
      template_single(i)
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
    if name ~= "Video processor" then
      name = v.fx_type..":"..v[1]:match(".+||"):gsub("|", "")
    end
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

function fxTrack_Float(track)
  if input then -- if input FX
    if not name:match("%.RfxChain") then -- if not chain
      local chunk = select(2, reaper.GetTrackStateChunk(track, "", false))
      local is_fxc_vis = tonumber(chunk:match("<FXCHAIN_REC.-SHOW (%d+)"))
      if not is_fxc_vis or is_fxc_vis == 0 then -- if FX chain is hidden
        reaper.TrackFX_Show(track, 0x1000000+reaper.TrackFX_GetRecCount(track)-1, 3)
      else
        reaper.TrackFX_Show(track, 0x1000000+reaper.TrackFX_GetRecCount(track)-1, 2)
      end
    else
      reaper.TrackFX_Show(track, 0x1000000+reaper.TrackFX_GetRecCount(track)-1, 1)
    end
  else
    if not name:match("%.RfxChain") then -- if not chain
      local is_fxc_vis = reaper.TrackFX_GetChainVisible(track)
      if is_fxc_vis == -1 then -- if FX chain is hidden
        reaper.TrackFX_Show(track, reaper.TrackFX_GetCount(track)-1, 3)
      else
        reaper.TrackFX_Show(track, reaper.TrackFX_GetCount(track)-1, 2)
      end
    else
      reaper.TrackFX_Show(track, reaper.TrackFX_GetCount(track)-1, 1)
    end
  end
end

function track_fx()
  for i = 0, sel_tr_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    for i, v in ipairs(plugs_rel) do
      plugs_rel_parse(v)
      if clear_fx == true then
        if dest ~= "/i" then
          flush_fx(track, 1)
        else
          flush_fx(track, 2)
        end
      end
      fx_i = reaper.TrackFX_AddByName(track, name, input, -1)
      if fx_i >= 0 then break end
    end
    if fx_i == -1 then
      no_fx()
      close_undo()
      break
    end
    if i == 0 then
      fxTrack_Float(track)
    end
  end
end

function master_fx()
  if is_m_sel then -- if master track is selected
    for i, v in ipairs(plugs_rel) do
      plugs_rel_parse(v)
      if clear_fx == true then
        if dest ~= "/i" then
          flush_fx(m_track, 1)
        else
          flush_fx(m_track, 2)
        end
      end
      fx_i = reaper.TrackFX_AddByName(m_track, name, input, -1)
      if fx_i >= 0 then break end
    end
    if fx_i == -1 then
      no_fx()
      close_undo()
    end
    if sel_tr_count == 0 then -- if no other tracks are selected then float the master FX
      fxTrack_Float(m_track)
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
          if clear_fx == true then
            flush_fx(take, 3)
          end
          fx_i = reaper.TakeFX_AddByName(take, name, -1)
          if fx_i >= 0 then break end
        end
        if fx_i == -1 then
          no_fx()
          close_undo()
          return
        end
        if i == 0 then
          if not name:match("%.RfxChain") then -- if not chain
            local is_fxc_vis = reaper.TakeFX_GetChainVisible(take)
            if is_fxc_vis == -1 then -- if FX chain is hidden
              reaper.TakeFX_Show(take, reaper.TakeFX_GetCount(take)-1, 3)
            else
              reaper.TakeFX_Show(take, reaper.TakeFX_GetCount(take)-1, 2)
            end
          else
            reaper.TakeFX_Show(take, reaper.TakeFX_GetCount(take)-1, 1)
          end
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
  plugs = {VST2 = {}, VST3 = {}, JS = {}, AU = {}}
  
  match_vst()  
  
  match_js()
  
  if cur_os == "OSX64" then
    match_au()
  end
  
  for i, v in ipairs(name_parts) do
    for m = 1, #fx_type do
      if v:upper() == fx_type[m] then
        if cur_os ~= "OSX64" then
          if fx_type[m] ~= "AU" then
            gen_name(fx_type[m])
            goto BREAK
            break
          end
        else
          gen_name(fx_type[m])
          goto BREAK
          break
        end
      end
    end
    if stop then stop = nil break end
    if i == #name_parts then
      for m = 1, #fx_type do
        if cur_os ~= "OSX64" then
          if fx_type[m] ~= "AU" then
            gen_name(fx_type[m])
          end
        else
          gen_name(fx_type[m])
        end
        if name then break end
      end
    end
  end
  ::BREAK::
end

function match_vst()
  for line in io.lines(vst) do
    if line:match("^.-=.-,.-,.+$") then
      local vst_name = line:match("^.-=.-,.-,(.+)$")
      if not vst_name:match("^#") then
        if line:lower():match("vst3") then
          table.insert(plugs.VST3, vst_name)
        else
          table.insert(plugs.VST2, vst_name)
        end
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
    if js_name then
      table.insert(plugs.JS, file_list[i][1] .. "||" .. js_name)
    end
  end
  table.insert(plugs.JS, "Video processor" .. "||" .. "Video processor")
end

function match_au()
  for line in io.lines(au) do
    if line:match("^.-=.+$") then
      local au_name = line:match("^(.-)=.+$")
      if not au_name:match("^#") then
        table.insert(plugs.AU, au_name)
      end
    end
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
      name_parts[m]:upper():match("^VST%d$") or
      name_parts[m]:upper():match("^JS$") or
      name_parts[m]:upper():match("^CHAIN$") then goto PART_SKIP end -- if flag or fx type then skip
      if name_parts[m]:upper():match("^AU$") and
      cur_os == "OSX64" then goto PART_SKIP end -- if AU and macOS then skip
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
            local dir = dir_list[i]:gsub("/" .. match, ""):gsub("^/", "")
            if dir ~= "" then
              dir = dir .. "/"
            end
            table.insert(file_list, {dir .. file, [[]] .. r_path .. dir_list[i] .. [[]] .. "/"})
          end
          m = m + 1
        end
      until not file
    end
  end
end

function inFolderPrepare()
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
    reaper.Main_OnCommand(40914, 0)
  end
  return f_depth
end

function inFolderSet(f_depth, option)
  if option == 0 then
    if f_depth and f_depth < 0 then
      local tr = reaper.GetSelectedTrack(0, reaper.CountSelectedTracks(0) - 1)
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", f_depth)
    end
  elseif option == 1 then
    if f_depth and f_depth < 0 then
      local tr = reaper.GetSelectedTrack(0, reaper.CountSelectedTracks(0) - 1)
      local f_depth2 = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
      if f_depth2 < 0 then
        f_depth = f_depth + f_depth2
      end
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", f_depth)
    end
  end
end

function add_tr_temp(v)
  local template_inst, apply, tt_mode, name
  for i, a in ipairs(name_parts) do -- check for TT number flag
    if a:match("^/%d+$") then
      template_inst = a:match("%d+")
      break
    end
  end
  
  for i, a in ipairs(name_parts) do -- check for apply flag
    if a:match("^/a$") then
      apply = true
      break
    end
  end
  
  local track_template = [[]] .. v[2] .. v[1] .. [[]] .. ".RTrackTemplate"
  
  reaper.Undo_BeginBlock()
  if apply and not a_flag_reverse or not apply and a_flag_reverse then
    apply_template(track_template)
  else
    local t_temp = {}
    reaper.PreventUIRefresh(1)
    local f_depth = inFolderPrepare()
    if template_inst then
      for i = 1, template_inst do
        reaper.Main_openProject(track_template)
        table.insert(t_temp, reaper.GetSelectedTrack(0, 0))
      end
      for i = 1, #t_temp do
        reaper.SetTrackSelected(t_temp[i], 1)
      end
      inFolderSet(f_depth, 0)
    else
      reaper.Main_openProject(track_template)
      inFolderSet(f_depth, 1)
    end
    reaper.PreventUIRefresh(-1)
  end
  
  if apply or search_track_name then
    tt_mode = "Apply"
  else
    tt_mode = "Insert"
  end
  
  if search_track_name and sel_tr_count > 1 then
    name = "track templates"
  else
    name = v[1]
  end
  if content ~= "" then
   reaper.Undo_EndBlock(tt_mode .. " " .. name, -1)
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
  if cur_os == "Win32" or cur_os == "Win64" then
    reaper.ExecProcess('cmd.exe /C start "" "' .. url .. '"', 0)
  elseif cur_os == "OSX32" or cur_os == "OSX64" then
    os.execute('open "" "' .. url .. '"')
  elseif cur_os == "Other" then
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

function help()
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("You can use the script to add track FX, input FX, take FX, FX chains"..
            " and track templates.\n\nThe script supports both full words and partial keywords.\n\n"..
            "When adding FX you can use:\n/i flag to add input track FX (e.g. gate /i);\n" ..
            "/t flag for take FX (e.q. EQ /t);\n"..
            "2/3/a/j/c as the first keyword to force VST2/VST3/AU/JS/Chain type (e.g. 3 pro-q);\n"..
            "a whitespace character before keywords to clear relevant FX chains prior to adding FX.\n\n" ..
            "Track templates specifics:\n"..
            "to add a track template use . prefix with the first word (eg .soft piano);\n"..
            "/n flag to add multiple instances of a template (eg .bgv /4);\n"..
            "/a flag to apply templates to existing tracks (eg .strings /a).\n\n"..
            "Common syntax:\n"..
            "put keywords in quotes to do an exact search (e.g. \".vox adlib\" /2);\n"..
            "use the - prefix to exclude keywords (e.g. comp -cockos).\n\n"..
            "Type in the $ sign to donate. Thanks!\n\n\n\n"..
            "For more information visit the script's page:\n"..
            "https://forum.cockos.com/showthread.php?t=220800", "Quick Add Help")
end

function fx_type_sh()
  if #name_parts > 1 then
    if name_parts[1]:match("^2$") then
      name_parts[1] = fx_a
    elseif name_parts[1]:match("^3$") then
      name_parts[1] = fx_b
    elseif name_parts[1]:match("^j$") then
      name_parts[1] = fx_c
    elseif name_parts[1]:match("^c$") then
      name_parts[1] = fx_d
    elseif cur_os == "OSX64" and name_parts[1]:match("^a$") then
      name_parts[1] = fx_e
    end
  end
end

function main()
  if search_track_name == true and sel_tr_count > 0 then
    local tr
    if not pass then
      pass = 0
      tr = reaper.GetSelectedTrack(0, pass)
    else
      tr = reaper.GetSelectedTrack(0, pass)
    end
    local tr_name = select(2, reaper.GetTrackName(tr))
    data = "."..tr_name.." /a"
  elseif search_track_name == false and input_ovrd == "" then
    retval, data = reaper.GetUserInputs("Quick Add FX or Track Template", 1,
                   "FX or track template ('?' for help):,extrawidth=88", "")
  elseif input_ovrd ~= "" then
    data = input_ovrd
  else
    data = ""
  end
  if data == "" then return end
  console("Input Data: ".. data, 1, 1)
  if retval or input_ovrd ~= "" or search_track_name then
    name_parts = {}
    local i = 0
    if data:match("^%s.+$") then
      clear_fx = true
    end
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
     
    if #name_parts == 0 or #name_parts == 1 and stop_str(name_parts[1]) then
      return
    elseif #name_parts == 1 and name_parts[1]:match("^%%%$$") then -- donate
      url_open("https://paypal.me/SIXSTARCOS")
    elseif #name_parts == 1 and name_parts[1]:match("^%%%?$") then
      help()
    elseif name_parts[1]:match("^%%%.") or name_parts[1]:match("^\"%%%.") then -- if template
      list_dir("TrackTemplates", "RTrackTemplate")
      name_parts[1] = name_parts[1]:gsub("%%.", "")
      console("Name part 1: " .. name_parts[1], 1)
      gen_name("TEMPLATE")
    else
      fx_type_sh()
      for i, v in ipairs(name_parts) do
        console("Name part" .. i.. ": ".. name_parts[i], 1)
      end
      add_fx()
    end
  end
end

main()
