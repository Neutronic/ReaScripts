[CHANGELOG]

v2.34 - October 26 2020 [post](https://forum.cockos.com/showthread.php?p=2357320#post2357320)
```diff+``` LeftWin + Alt + Enter: insert FX on a new track above the first selected track
or the track under mouse cursor (Ctrl + Option + Return on macOS)
&#35; ignore "Auto-float newly created FX windows" in REAPER preferences

v2.33 – August 09 2020 (post)
+ Ctrl(Cmd) + Shift + Alt + Enter: inserts FX or template on new track and sends selected tracks (or track under mouse) to it
# streamline targeting logic
# update mouse cursor when switching views with key commands
# improve hints
# update help file

v2.32 – July 17 2020
# improve handling of filter strings with OR logical operator

v2.31 – July 15 2020
# better handling of empty strings in getFXfolder() and fxExclCheck()

v2.30 – July 07 2020
# fix script crash if reaper-fxfolders.ini does not exist

v2.29 – June 28 2020
+ Shift+Enter inserts templates above first selected track
# more improvements to reaper-fxfolders.ini parsing
# check VST names for illegal characters
# improve overall character sanitizing logic
# fix script crash if AU match doesn't have a space between
developer and plugin names
# improve INS/FOL filters logic

v2.27 – June 24 2020
# fix recalling favorites containing FX folder data
# improve matching queries with numbers

v2.26 – June 21 2020
# fix script crash when parsing fxfolders.ini

v2.25 – June 19 2020 (post)
+ search FX browser folders
+ new FOL search filter for FX browser folders
+ option to disable FX folders searching (PREFS --> Search and ...)
+ new INS search filter for virtual instruments
+ FX search filter now gets effects only
+ configure Filter Tray items (right-click the tray button)
+ configure FX show options (right-click the Show FX button)
# move "Show FX at mouse cursor" to FX show options
# improve illegal characters sanitizing
# internal optimizations

v2.23 – June 03 2020
# escape backslashes in JS descriptions

v2.22 – June 02 2020
# fixed Default Filter setting

v2.21 – May 28 2020
# recall docked state on QA2 reopening

v2.20 – May 26 2020 (post)
Text selection for editing:
+ marquee select search box text
+ "Ctrl(Cmd) + A" or double-click a search query to select all text
+ "Ctrl(Cmd) + Left/Right" to move one word at a time
+ "Shift + Left/Right" to select one letter at a time
+ "Ctrl(Cmd) + Shift + Left/Right" to select one word at a time
+ "Home" to go to start of the search query
+ "End" to go to the end of search query

The docked mode:
+ right-click the hints bar to dock/undock the script's GUI
+ automatically set result rows number when docked
+ option to show result placeholders when docked
+ highlight the GUI when docked and the script is focused
+ temporarily undock the script when user opens QA2 Preferences
+ adjust results text size for the docked mode
+ open the filter tray vertically when docked and GUI width is
less than the tray width

Various:
+ option to float FX at mouse cursor
+ maximum number of result rows increased to 99 for the undocked mode
+ unlock minimum horizontal GUI size
+ HiDPI/Retina displays support
# make sure ALT + Key shortcuts do not collide with SHIFT + ALT + Key
# fixed the "FX" filter sorting
# fixed search box memory clearing when backspasing a whole query
# insert correct result when no tracks selected and "Clear search
box after insertion" is on
# don't reset QA2 result selection after insertion if search box is empty
# bypass gfx.mouse_cap hang on macOS when inserting FX through double-clicking

v2.16 – April 29 2020
+ support script docking with the title bar menu option (Windows only)
# check JS names for double quotes

v2.15 – April 28 2020 (post)
+ search and run actions
+ add actions to favorites
+ new filter to search actions only
+ define position of actions in the global search order
+ display actions toggle state in real time
+ option to toggle the actions functionality on/off
+ ability to resize the search view horizontally
+ notify user if there is no SWS and/or JS API installed
# enhanced exact matching logic
# enhanced FX filter string parsing

v2.10 - April 06 2020 (post)
+ drag and drop support
+ dropping an effect on empty TCP/MCP automatically
creates a named track with the effect on it
+ options for "no track selected" scenario
+ ability to pin Quick Adder
+ place text box carriage with mouse cursor

v2.08 – March 31 2020 (post)
+ option to clear the search box after FX/template insertion
+ put VSTi/AUi on a new named/armed/monitored track when no
tracks are selected
+ respect FX filter string rules in REAPER Preferences --> Plug-ins (video)
+ ESC closes Quick Adder when the search box is empty
# constrain favorites reordering to Alt + Shift + Up/Down only
# improved "FX not found" warning
# updated help file

v2.07 – March 26 2020 (post)
+ option to show favorites when the search box is empty
+ ability to reorder favorites with Alt + Shift + Up/Down

v2.05 – March 22 2020 (post)
+ option to toggle FX/track template GUI floating after insertion
+ prompt to insert tracks to put FX on, when there are no tracks in project
and master track is unselected
+ pass Ctrl(Cmd)+Z and Ctrl(Cmd)+Shift+Z to main window
+ double-click speed variable in the cfg file (dbl_click_speed)
# slightly increased double click speed

v2.01 - March 18 2020 (post)
# temporarily disable VST cross-checking