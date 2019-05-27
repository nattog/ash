-- earthsea: pattern instrument
-- 1.1.0 @tehn
-- llllllll.co/t/21349
--
-- subtractive polysynth
-- controlled by midi or grid
--
-- grid pattern player:
-- 1 1 record toggle
-- 1 2 play toggle
-- 1 8 transpose mode

local tab = require "tabutil"
local pattern_time = require "pattern_time"

local polysub = include "we/lib/polysub"

local g = grid.connect()

local mode_transpose_1 = 0
local mode_transpose_2 = 0
local root = {
  a = {x = 5, y = 5},
  b = {x = 5, y = 5}
}
local trans_1 = {x = 5, y = 5}
local trans_2 = {x = 5, y = 5}
local lit = {}

local screen_framerate = 15
local screen_refresh_metro

local ripple_repeat_rate = 1 / 0.3 / screen_framerate
local ripple_decay_rate = 1 / 0.5 / screen_framerate
local ripple_growth_rate = 1 / 0.02 / screen_framerate
local screen_notes = {}

local MAX_NUM_VOICES = 16

engine.name = "PolySub"

-- pythagorean minor/major, kinda
local ratios = {1, 9 / 8, 6 / 5, 5 / 4, 4 / 3, 3 / 2, 27 / 16, 16 / 9}
local base = 27.5 -- low A

local function getHz(deg, oct)
  return base * ratios[deg] * (2 ^ oct)
end

local function getHzET(note)
  return 55 * 2 ^ (note / 12)
end
-- current count of active voices
local nvoices = 0

function init()
  m = midi.connect()
  m.event = midi_event

  pat1 = pattern_time.new()
  pat1.process = grid_note_trans_1

  pat2 = pattern_time.new()
  pat2.process = grid_note_trans_2

  params:add_option("enc2", "enc2", {"shape", "timbre", "noise", "cut"})
  params:add_option("enc3", "enc3", {"shape", "timbre", "noise", "cut"}, 2)

  params:add_separator()

  polysub:params()

  engine.stopAll()
  stop_all_screen_notes()

  params:bang()

  if g then
    gridredraw()
  end

  screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function(stage)
    update()
    redraw()
  end
  screen_refresh_metro:start(1 / screen_framerate)

  local startup_ani_count = 1
  local startup_ani_metro = metro.init()
  startup_ani_metro.event = function(stage)
    start_screen_note(-startup_ani_count)
    stop_screen_note(-startup_ani_count)
    startup_ani_count = startup_ani_count + 1
  end
  startup_ani_metro:start(0.1, 3)
end

function g.key(x, y, z)
  if x == 1 then
    if z == 1 then
      if y == 1 and pat1.rec == 0 then
        mode_transpose_1 = 0
        trans_1.x = 5
        trans_1.y = 5
        pat1:stop()
        engine.stopAll()
        stop_all_screen_notes()
        pat1:clear()
        pat1:rec_start()
      elseif y == 1 and pat1.rec == 1 then
        pat1:rec_stop()
        if pat1.count > 0 then
          root.a.x = pat1.event[1].x
          root.a.y = pat1.event[1].y
          trans_1.x = root.a.x
          trans_1.y = root.a.y
          pat1:start()
        end
      elseif y == 2 and pat1.play == 0 and pat1.count > 0 then
        if pat1.rec == 1 then
          pat1:rec_stop()
        end
        pat1:start()
      elseif y == 2 and pat1.play == 1 then
        pat1:stop()
        engine.stopAll()
        stop_all_screen_notes()
        nvoices = 0
        lit = {}
      elseif y == 3 and pat2.rec == 0 then
        mode_transpose_2 = 0
        trans_2.x = 5
        trans_2.y = 5
        pat2:stop()
        engine.stopAll()
        stop_all_screen_notes()
        pat2:clear()
        pat2:rec_start()
      elseif y == 3 and pat2.rec == 1 then
        pat2:rec_stop()
        if pat2.count > 0 then
          root.b.x = pat2.event[1].x
          root.b.y = pat2.event[1].y
          trans_2.x = root.b.x
          trans_2.y = root.b.y
          pat2:start()
        end
      elseif y == 4 and pat2.play == 0 and pat2.count > 0 then
        if pat2.rec == 1 then
          pat2:rec_stop()
        end
        pat2:start()
      elseif y == 4 and pat2.play == 1 then
        pat2:stop()
        engine.stopAll()
        stop_all_screen_notes()
        nvoices = 0
        lit = {}
      elseif y == 7 then
        mode_transpose_1 = 1 - mode_transpose_1
      elseif y == 8 then
        mode_transpose_2 = 1 - mode_transpose_2
      end
    end
  else
    if mode_transpose_1 == 0 then
      local e = {}
      e.id = x * 8 + y
      e.x = x
      e.y = y
      e.state = z
      pat1:watch(e)
      grid_note(e)
    else
      trans_1.x = x
      trans_1.y = y
    end
    if mode_transpose_2 == 0 then
      local e = {}
      e.id = x * 8 + y
      e.x = x
      e.y = y
      e.state = z
      pat2:watch(e)
      grid_note(e)
    else
      trans_2.x = x
      trans_2.y = y
    end
  end
  gridredraw()
end

function grid_note(e)
  local note = ((7 - e.y) * 5) + e.x
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
      engine.start(e.id, getHzET(note))
      start_screen_note(note)
      lit[e.id] = {}
      lit[e.id].x = e.x
      lit[e.id].y = e.y
      nvoices = nvoices + 1
    end
  else
    if lit[e.id] ~= nil then
      engine.stop(e.id)
      stop_screen_note(note)
      lit[e.id] = nil
      nvoices = nvoices - 1
    end
  end
  gridredraw()
end

function grid_note_trans_1(e)
  local note = ((7 - e.y + (root.a.y - trans_1.y)) * 5) + e.x + (trans_1.x - root.a.x)
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
      engine.start(e.id, getHzET(note))
      start_screen_note(note)
      lit[e.id] = {}
      lit[e.id].x = e.x + trans_1.x - root.a.x
      lit[e.id].y = e.y + trans_1.y - root.a.y
      nvoices = nvoices + 1
    end
  else
    engine.stop(e.id)
    stop_screen_note(note)
    lit[e.id] = nil
    nvoices = nvoices - 1
  end
  gridredraw()
end

function grid_note_trans_2(e)
  local note = ((7 - e.y + (root.b.y - trans_2.y)) * 5) + e.x + (trans_2.x - root.b.x)
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
      engine.start(e.id, getHzET(note))
      start_screen_note(note)
      lit[e.id] = {}
      lit[e.id].x = e.x + trans_2.x - root.b.x
      lit[e.id].y = e.y + trans_2.y - root.b.y
      nvoices = nvoices + 1
    end
  else
    engine.stop(e.id)
    stop_screen_note(note)
    lit[e.id] = nil
    nvoices = nvoices - 1
  end
  gridredraw()
end

function gridredraw()
  g:all(0)
  g:led(1, 1, 2 + pat1.rec * 10)
  g:led(1, 2, 2 + pat1.play * 10)
  g:led(1, 3, 2 + pat2.rec * 10)
  g:led(1, 4, 2 + pat2.play * 10)
  g:led(1, 7, 2 + mode_transpose_1 * 10)
  g:led(1, 8, 2 + mode_transpose_1 * 10)

  if mode_transpose_1 == 1 then
    g:led(trans_1.x, trans_1.y, 4)
  end
  if mode_transpose_2 == 1 then
    g:led(trans_2.x, trans_2.y, 4)
  end

  for i, e in pairs(lit) do
    g:led(e.x, e.y, 15)
  end

  g:refresh()
end

function enc(n, delta)
  if n == 1 then
    mix:delta("output", delta)
  elseif n == 2 then
    params:delta(params:string("enc2"), delta * 4)
  elseif n == 3 then
    params:delta(params:string("enc3"), delta * 4)
  end
end

function key(n, z)
end

function start_screen_note(note)
  local screen_note = nil

  -- Get an existing screen_note if it exists
  local count = 0
  for key, val in pairs(screen_notes) do
    if val.note == note then
      screen_note = val
      break
    end
    count = count + 1
    if count > 8 then
      return
    end
  end

  if screen_note then
    screen_note.active = true
  else
    screen_note = {
      note = note,
      active = true,
      repeat_timer = 0,
      x = math.random(128),
      y = math.random(64),
      init_radius = math.random(6, 18),
      ripples = {}
    }
    table.insert(screen_notes, screen_note)
  end

  add_ripple(screen_note)
end

function stop_screen_note(note)
  for key, val in pairs(screen_notes) do
    if val.note == note then
      val.active = false
      break
    end
  end
end

function stop_all_screen_notes()
  for key, val in pairs(screen_notes) do
    val.active = false
  end
end

function add_ripple(screen_note)
  if tab.count(screen_note.ripples) < 6 then
    local ripple = {radius = screen_note.init_radius, life = 1}
    table.insert(screen_note.ripples, ripple)
  end
end

function update()
  for n_key, n_val in pairs(screen_notes) do
    if n_val.active then
      n_val.repeat_timer = n_val.repeat_timer + ripple_repeat_rate
      if n_val.repeat_timer >= 1 then
        add_ripple(n_val)
        n_val.repeat_timer = 0
      end
    end

    local r_count = 0
    for r_key, r_val in pairs(n_val.ripples) do
      r_val.radius = r_val.radius + ripple_growth_rate
      r_val.life = r_val.life - ripple_decay_rate

      if r_val.life <= 0 then
        n_val.ripples[r_key] = nil
      else
        r_count = r_count + 1
      end
    end

    if r_count == 0 and not n_val.active then
      screen_notes[n_key] = nil
    end
  end
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.line_width(1)

  local first_ripple = true
  for n_key, n_val in pairs(screen_notes) do
    for r_key, r_val in pairs(n_val.ripples) do
      if first_ripple then -- Avoid extra line when returning from menu
        screen.move(n_val.x + r_val.radius, n_val.y)
        first_ripple = false
      end
      screen.level(math.max(1, math.floor(r_val.life * 15 + 0.5)))
      screen.circle(n_val.x, n_val.y, r_val.radius)
      screen.stroke()
    end
  end

  screen.update()
end

function note_on(note, vel)
  if nvoices < MAX_NUM_VOICES then
    --engine.start(id, getHz(x, y-1))
    engine.start(note, getHzET(note))
    start_screen_note(note)
    nvoices = nvoices + 1
  end
end

function note_off(note, vel)
  engine.stop(note)
  stop_screen_note(note)
  nvoices = nvoices - 1
end

function midi_event(data)
  if #data == 0 then
    return
  end
  local msg = midi.to_msg(data)

  -- Note off
  if msg.type == "note_off" then
    -- Note on
    note_off(msg.note)
  elseif msg.type == "note_on" then
    note_on(msg.note, msg.vel / 127)

  --[[
    -- Key pressure
  elseif msg.type == "key_pressure" then
    set_key_pressure(msg.note, msg.val / 127)

    -- Channel pressure
  elseif msg.type == "channel_pressure" then
    set_channel_pressure(msg.val / 127)

    -- Pitch bend
  elseif msg.type == "pitchbend" then
    local bend_st = (util.round(msg.val / 2)) / 8192 * 2 -1 -- Convert to -1 to 1
    local bend_range = params:get("bend_range")
    set_pitch_bend(bend_st * bend_range)

  ]]
   --
  end
end

function cleanup()
  stop_all_screen_notes()
  pat1:stop()
  pat1 = nil
  pat2:stop()
  pat2 = nil
end
