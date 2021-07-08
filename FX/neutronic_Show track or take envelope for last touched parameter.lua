--[[
Description: Show track or take envelope for last touched parameter
About: Adds tracks or takes envelopes for the last touched FX parameter
Version: 1.03
Author: Neutronic
Donation: https://paypal.me/SIXSTARCOS
License: GNU GPL v3
Links:
  Neutronic's REAPER forum profile https://forum.cockos.com/member.php?u=66313
Changelog:
  # change ai_insert default to false
  # reliably update arrange when ai_insert is false
  # fix creating undo points in some cases
--]]

---------- USER DEFINABLES ----------

local toggle = true -- if true then then the script toggles envelope visibility
local ai_insert = false -- if true then an automation item is inserted on the envelope

-------------------------------------

local focus, tracknumber, itemnumber, fx_num_f = reaper.GetFocusedFX()
local tk_f_idx = fx_num_f>>16

function undo_close(param_name, fx_name)
  reaper.Undo_EndBlock("Show Envelope for "..param_name.." ("..fx_name:gsub("^.+:%s(.+)%s%(.+$", "%1")..")", -1)
end

function create_ai(track, env)
  local item_count, pos, length = reaper.CountTrackMediaItems(track)  
  for i = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    if reaper.IsMediaItemSelected(item) then
      if not pos then 
        pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      end
      length = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + reaper.GetMediaItemInfo_Value(item, "D_LENGTH") - pos
    end
  end 
  local ai_count = reaper.CountAutomationItems(env)
  if pos then -- if there is a selected item on the track
    if ai_count == 0 then
      reaper.InsertAutomationItem(env, -2, pos, length)
    end
  else
    if ai_count == 0 then
      local one_measure = reaper.TimeMap2_beatsToTime(0, 0, 1)
      reaper.InsertAutomationItem(env, -1, reaper.GetCursorPosition(), one_measure)
    end
  end
end

function track_fx(track, paramnumber, fx_number)
  if fx_num_f ~= fx_number then return end
  local trf_is_open = reaper.TrackFX_GetOpen(track, fx_number)
  if not trf_is_open then return end
  
  local retval, fx_name = reaper.TrackFX_GetFXName(track, fx_number, "")
  local _, param_name = reaper.TrackFX_GetParamName(track, fx_number, paramnumber, "")
  local env = reaper.GetFXEnvelope(track, fx_number, paramnumber, false)
  if reaper.ValidatePtr2(0, env, "TrackEnvelope*") and toggle then
    reaper.Undo_BeginBlock()
    local _, env_chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    local vis = env_chunk:match("VIS (%d)")
    if vis == "1" then -- if env is visible
      reaper.SetEnvelopeStateChunk(env, env_chunk:gsub("(VIS )%d", "%10"), false)
    elseif vis == "0" then -- if env is not visible
      reaper.SetEnvelopeStateChunk(env, env_chunk:gsub("(VIS )%d", "%11"), false)
    end
  else
    reaper.Undo_BeginBlock()
    env = reaper.GetFXEnvelope(track, fx_number, paramnumber, true)

    if tracknumber > 0 and env and ai_insert then -- if not master and ai_insert is on
      reaper.Main_OnCommand(41163, 0) -- unarm all envelopes
      create_ai(track, env)
    else
      reaper.SetEnvelopePoint(env, 0) -- ensures undo point
    end
  end
  
  if tracknumber > 0 then
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
  else
    reaper.SetMasterTrackVisibility(1)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_TVPAGEHOME"), 0)
  end
  
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  undo_close(param_name, fx_name)
end

function take_fx(track, item, tk_number, paramnumber, fx_number)
  local tk = reaper.GetTake(item, tk_number)
  local tkf_is_open = reaper.TakeFX_GetOpen(tk, fx_number)
  if not tkf_is_open then return end
  reaper.Undo_BeginBlock()
    local retval, param_name = reaper.TakeFX_GetParamName(tk, fx_number, paramnumber, "")
    local retval, fx_name = reaper.TakeFX_GetFXName(tk, fx_number, "")
    env = reaper.TakeFX_GetEnvelope(tk, fx_number, paramnumber, false)
    if env and toggle then
      local _, env_chunk = reaper.GetEnvelopeStateChunk(env, "", false)
      local vis = env_chunk:match("VIS (%d)")
      if vis == "1" then -- if env is visible
        reaper.SetEnvelopeStateChunk(env, env_chunk:gsub("(VIS )%d", "%10"), false)
      elseif vis == "0" then -- if env is not visible
        reaper.SetEnvelopeStateChunk(env, env_chunk:gsub("(VIS )%d", "%11"), false)
      end
    else
      local env = reaper.TakeFX_GetEnvelope(tk, fx_number, paramnumber, true)
      reaper.SetEnvelopePoint(env, 0) -- ensures undo point
    end
    reaper.UpdateArrange()
  undo_close(param_name, fx_name)
end

function main()
  if focus == 0 then return end
  
  if tracknumber >= 0 then
    local _, tracknumber_t, fx_n, paramnumber = reaper.GetLastTouchedFX()
    local item_number_t = tracknumber_t>>16
    local tk_t_idx = fx_n>>16
    local track = reaper.CSurf_TrackFromID(tracknumber, false)
    local item, tk_a, tk_a_idx
    if itemnumber >=0 then
      item = reaper.GetTrackMediaItem(track, itemnumber)
      tk_a = reaper.GetActiveTake(item)
      tk_a_idx = reaper.GetMediaItemTakeInfo_Value(tk_a, "IP_TAKENUMBER")
    end
    if tracknumber == tracknumber_t and focus == 1 then
      track_fx(track, paramnumber, fx_n&0xFFFFFF)
    elseif focus == 2 and itemnumber + 1 == item_number_t and
           tk_f_idx == tk_t_idx and tk_t_idx == tk_a_idx then
      if fx_num_f&0xFFFF ~= fx_n&0xFFFF then return end
      take_fx(track, item, tk_t_idx, paramnumber, fx_n&0xFFFF)
    end
  end
end

main()
