--[[
Description: Quick Adder 2 -- optimize GUI size for 720p
About: Optimizes Quick Adder 2 window size for 720p screen resolution.
Version: 1.0
Author: Neutronic
Donation: https://paypal.me/SIXSTARCOS
License: GNU GPL v3
Links:
  Neutronic's REAPER forum profile https://forum.cockos.com/member.php?u=66313
  Quick Adder 2 forum thread https://forum.cockos.com/showthread.php?t=232928
  Quick Adder 2 video demo http://bit.ly/seeQA2
Changelog:
  + initial release
--]]

if not reaper.CF_EnumerateActions then return end

function getQAid()
  local i = 0
  
  while i <= 65535 do
    local id, name = reaper.CF_EnumerateActions(0, i, "")

    if name == "Script: neutronic_Quick Adder 2.lua" then return id end
    i = i + 1
  end
end

local qa_id = getQAid()

if not qa_id then reaper.MB("Quick Adder 2 not found.", "ReaScript Error", 0) return end

reaper.SetExtState("Quick Adder", "ACT", "|720p", false)

if not reaper.HasExtState("Quick Adder", "MSG") and
  reaper.GetExtState("Quick Adder", "MSG") ~= "reopen" then
  reaper.Main_OnCommand(qa_id, 0)
end
