--[[
Description: MIDI Plug and Play
Version: 1.0
Author: Neutronic
Donation: https://paypal.me/SIXSTARCOS
Changelog:
  v1.00 - May 13 2019
    + initial release
Links:
  Neutronic's REAPER forum profile https://forum.cockos.com/member.php?u=66313
  Script's forum thread https://forum.cockos.com/showthread.php?t=220867
About: 
  It's a background script that provides automatic MIDI controller initialization for REAPER.
--]]

-- Licensed under the GNU GPL v3

local inputs_ref, init_time, midi_names, midi_names2, retval, input_name, _ = 0, reaper.time_precise(), {}
local project = reaper.GetProjectName(0, "")

for i = 0, reaper.GetNumMIDIInputs() do
  retval, _ = reaper.GetMIDIInputName(i, "")
  if retval == true then
    inputs_ref = inputs_ref + 1
    table.insert(midi_names, _)
  end
end

reaper.midi_reinit()

function main()
  local inputs_act, new_time = 0, reaper.time_precise()
  
  local project_temp = reaper.GetProjectName(0, "")
  if project_temp ~= project then
    reaper.midi_reinit()
    project = project_temp
  end
  
  if new_time - init_time >= 0.3 then
    init_time = new_time
    for i = 0, reaper.GetNumMIDIInputs() do
      retval, _ = reaper.GetMIDIInputName(i, "")
      if retval == true then
        inputs_act = inputs_act + 1
      end
    end
  
    if inputs_act > inputs_ref then
      reaper.midi_reinit()
      if inputs_act - inputs_ref == 1 then
        midi_names2 = {}
        for i = 0, reaper.GetNumMIDIInputs() do
          retval, _ = reaper.GetMIDIInputName(i, "")
          if retval == true then
            table.insert(midi_names2, _)
          end
        end
        for m = 1, #midi_names2 do
        
          local function has_value(val)
            for i, v in ipairs(midi_names) do
                if v == val then
                    return true
                end
            end
            return false
          end
        
          if has_value(midi_names2[m]) == false then
            input_name = midi_names2[m]
            midi_names = midi_names2
            break
          end
        end
      else
        else_name()
      end
      inputs_ref = inputs_act
      reaper.Help_Set(input_name.. ": CONNECTED", 1)
    elseif inputs_act < inputs_ref then
      reaper.midi_reinit()
      if inputs_act - inputs_ref == -1 then
        midi_names2 = {}
        for i = 0, reaper.GetNumMIDIInputs() do
          retval, _ = reaper.GetMIDIInputName(i, "")
          if retval == true then
            table.insert(midi_names2, _)
          end
        end
        for m = 1, #midi_names do
          local function has_value(val)
            for i, v in ipairs(midi_names2) do
                if v == val then
                    return true
                end
            end
            return false
          end
        
          if has_value(midi_names[m]) == false then
            input_name = midi_names[m]
            midi_names = midi_names2
            break
          end
        end
      else
        else_name()
      end
      inputs_ref = inputs_act
      reaper.Help_Set(input_name..": DISCONNECTED", 1)
    end
    
  end

  reaper.defer(main)
  
end

function else_name()

  midi_names = {}
  for i = 0, reaper.GetNumMIDIInputs() do
    retval, _ = reaper.GetMIDIInputName(i, "")
    if retval == true then
      table.insert(midi_names, _)
    end
  end
  input_name = "MIDI devices"

end
  
main()
