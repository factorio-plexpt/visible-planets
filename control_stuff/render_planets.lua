-- Configurable constants for planet grow/shrink animations
local PLANET_POS_X = settings.global["visible-planets-planet-pos-x"].value + 0 -- +0 just to tell lua it's a number.
local PLANET_POS_Y = settings.global["visible-planets-planet-pos-y"].value + 0
local PLANET_ARRIVE_DIST = settings.global["visible-planets-planet-init-dist"].value
local PLANET_DEPART_DIST = PLANET_ARRIVE_DIST * 2 -- Departing planets will go twice as fast as arriving planets.
local PLANET_SCALE = settings.global["visible-planets-planet-scale"].value
local PLANET_ANIM_DUR = settings.global["visible-planets-planet-anim-dur"].value -- Ticks for growing and shrinking
local PLANET_ANGLE = settings.global["visible-planets-planet-angle"].value / 360.0 -- Given in degrees, requires 0-1.
local planet_progress_per_tick = 1.0 / PLANET_ANIM_DUR -- Added to animation_progress until fully entered. (1.0)

-- Parallax and rotation configs
local PARALLAX_ENABLED = settings.global["visible-planets-enable-parallax"].value
local PARALLAX_FACTOR = settings.global["visible-planets-parallax-factor"].value
local ROTATION_ENABLED = settings.global["visible-planets-enable-rotation"].value
local ROTATION_SPEED = settings.global["visible-planets-rotation-speed"].value / 360.0 -- % rotation per tick. Value is degrees.

-- on_runtime_mod_setting_changed, update constants. (Yes this technically gets called for each setting changed, but they all need updating anyway.)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	PLANET_POS_X = settings.global["visible-planets-planet-pos-x"].value + 0
	PLANET_POS_Y = settings.global["visible-planets-planet-pos-y"].value + 0
	PLANET_ARRIVE_DIST = settings.global["visible-planets-planet-init-dist"].value
	PLANET_DEPART_DIST = PLANET_ARRIVE_DIST * 2
	PLANET_SCALE = settings.global["visible-planets-planet-scale"].value
	PLANET_ANIM_DUR = settings.global["visible-planets-planet-anim-dur"].value
	PLANET_ANGLE = settings.global["visible-planets-planet-angle"].value / 360.0
	planet_progress_per_tick = 1.0 / PLANET_ANIM_DUR
	PARALLAX_ENABLED = settings.global["visible-planets-enable-parallax"].value -- If disabled midgame, only existing planets will be left offset. New ones should be fine.
	PARALLAX_FACTOR = settings.global["visible-planets-parallax-factor"].value
	ROTATION_ENABLED = settings.global["visible-planets-enable-rotation"].value
	ROTATION_SPEED = settings.global["visible-planets-rotation-speed"].value / 360.0

	-- If regen renders is set true, then clear and regen all planet renders, and set setting to false.
	if settings.global["visible-planets-regen-renders"].value then
		for _, sprite in pairs(storage.visible_planets_renders_still) do sprite.obj.destroy() end
		for _, sprite in pairs(storage.visible_planets_renders_grow) do sprite.obj.destroy() end
		for _, sprite in pairs(storage.visible_planets_renders_shrink) do sprite.obj.destroy() end
		storage.visible_planets_renders_still = {}
		storage.visible_planets_renders_grow = {}
		storage.visible_planets_renders_shrink = {}
		for _, surface in pairs(game.surfaces) do
			if surface.platform then
				render_planet_on_platform(surface.platform)
			end
		end
		settings.global["visible-planets-regen-renders"] = {value = false}
	end
end)

-- On init, create a table to store the renders of the planets in the background.
script.on_init(function()
	storage.visible_planets_renders_grow = {} -- Add new planets here, to be grown and put into still.
	storage.visible_planets_renders_still = {} -- Waiting bay for planets.
	storage.visible_planets_renders_shrink = {} -- Planets put here will be shrunk then removed.
end)

-- Function to render a planet on a platform. Used for the initial render of all platforms. (Also called from migrations.)
function render_planet_on_platform(platform)
	if platform.surface then -- Check platform exists first
		local location = platform.space_location -- Can be nil
		local render_exists = storage.visible_planets_renders_still[platform.index] ~= nil or storage.visible_planets_renders_grow[platform.index] ~= nil

		if location == nil then -- If no location, begin shrinking planet
			if render_exists then
				-- If a relevant planet is in the shrinking list, remove it first. Looks ugly, but better than leaving permanent planet orphans.
				if storage.visible_planets_renders_shrink[platform.index] then
					storage.visible_planets_renders_shrink[platform.index].obj.destroy()
				end
				storage.visible_planets_renders_shrink[platform.index] = storage.visible_planets_renders_still[platform.index] or storage.visible_planets_renders_grow[platform.index]
				storage.visible_planets_renders_still[platform.index] = nil
				storage.visible_planets_renders_grow[platform.index] = nil
			end
		else -- Render planet, if not already rendered
			if not render_exists and helpers.is_valid_sprite_path("visible-planets-" .. location.name) then
				local sprite = rendering.draw_sprite {
					sprite = "visible-planets-" .. location.name,
					surface = platform.surface,
					render_layer = "zero",
					target = {PLANET_POS_X, PLANET_POS_Y - PLANET_ARRIVE_DIST},
					orientation = PLANET_ANGLE,
					x_scale = 0,
					y_scale = 0,
					orientation_target = {PLANET_POS_X, -99999}, -- Pointing up
					oriented_offset = {0, 0}, -- Will be used for parallax effect.
				}
				-- Create render table/object
				storage.visible_planets_renders_grow[platform.index] = {
					obj = sprite, -- The LuaRenderObject
					animation_progress = 0, -- 0-1, used for arrival and departure animations.
					player = nil, -- The player watching this planet. (Used for parallax and rotation.)
				}
				update_render_table_players() -- Check if a player is watching this planet. (Also updates other renders.)
			end
		end
	end
end

-- When a platform changes state, render or derender the planet in the background.
script.on_event(defines.events.on_space_platform_changed_state, function(event)
	render_planet_on_platform(event.platform)
end)

-- Quick helper functo check player surface locations and update render tables accordingly.
function update_render_table_players()
	-- Clear old players
	for _, render in pairs(storage.visible_planets_renders_still) do render.player = nil end
	for _, render in pairs(storage.visible_planets_renders_grow) do render.player = nil end
	for _, render in pairs(storage.visible_planets_renders_shrink) do render.player = nil end
	-- Get new players, if any are watching.
	for _, player in pairs(game.players) do
		if player.surface.platform then
			local p_index = player.surface.platform.index
			-- Get the render of the planet that is currently visible. Will only get one planet; Shrinking planets will be ignored if one is already growing.
			local render = storage.visible_planets_renders_still[p_index] or storage.visible_planets_renders_grow[p_index] or storage.visible_planets_renders_shrink[p_index]
			if render and not render.player then -- Gives priority to earlier players, which is also host.
				render.player = player
			end
		end
	end
end

-- When a player changes surface, update the render tables.
script.on_event(defines.events.on_player_changed_surface, function(event)
	update_render_table_players()
end)

-- Parallax and rotation animation function, given a render.
local function fancy_animations(render)
	if render.player and PARALLAX_ENABLED then -- Will end up correct only for last player watching a given planet.
		local player_position = render.player.position
		local planet_position = render.obj.target.position
		local x_offset = (player_position.x - planet_position.x) / PARALLAX_FACTOR
		local y_offset = (player_position.y - planet_position.y) / PARALLAX_FACTOR
		render.obj.oriented_offset = {x_offset, y_offset} -- Will not affect literal position.
	end
	if ROTATION_ENABLED then -- Will double rotate if two players watching same planet.
		local new_ang = render.obj.orientation + ROTATION_SPEED
		if new_ang >= 1 then
			new_ang = new_ang - 1
		end
		render.obj.orientation = new_ang
	end
end

-- Every tick, 
-- -- Handle arrivals and departures
-- -- Apply parallax if enabled.
-- -- Apply rotation if enabled.
script.on_event(defines.events.on_tick, function(event)
	-- Arrival animation
	for index, render in pairs(storage.visible_planets_renders_grow) do
		if render.animation_progress < 1.0 then
			local eased = render.animation_progress * (2 - render.animation_progress) -- Fast at low dur, slow at high dur.
			local scale = PLANET_SCALE * eased
			render.obj.x_scale = scale
			render.obj.y_scale = scale
			render.obj.target = {x = PLANET_POS_X, y = PLANET_POS_Y - (1 - eased) * PLANET_ARRIVE_DIST}
			fancy_animations(render) -- Animate fancy
			render.animation_progress = render.animation_progress + planet_progress_per_tick
		else
			storage.visible_planets_renders_still[index] = render
			storage.visible_planets_renders_grow[index] = nil
		end
	end

	-- Departure animation
	for index, render in pairs(storage.visible_planets_renders_shrink) do
		if not render.obj.valid then -- Should solve an issue that someone had. Wasn't able toproduce, but this should be good.
			storage.visible_planets_renders_shrink[index] = nil
		else
			if render.animation_progress > 0.0 then
				local eased = render.animation_progress * (2 - render.animation_progress) -- Fast at low dur, slow at high dur.
				local scale = PLANET_SCALE * eased
				render.obj.x_scale = scale
				render.obj.y_scale = scale
				render.obj.target = {x = PLANET_POS_X, y = PLANET_POS_Y + (1 - eased) * PLANET_DEPART_DIST}
				fancy_animations(render) -- Animate fancy
				render.animation_progress = render.animation_progress - planet_progress_per_tick
			else
				render.obj.destroy()
				storage.visible_planets_renders_shrink[index] = nil
			end
		end
	end

	-- Standing animation
	for _, render in pairs(storage.visible_planets_renders_still) do
		fancy_animations(render)
	end
end)

-- AFTER a surface is deleted, check if any planet renders have become invalid. If so, remove them.
script.on_event(defines.events.on_surface_deleted, function(event)
	for index, render in pairs(storage.visible_planets_renders_still) do
		if not render.obj.valid then
			storage.visible_planets_renders_still[index] = nil
		end
	end
	for index, render in pairs(storage.visible_planets_renders_grow) do
		if not render.obj.valid then
			storage.visible_planets_renders_grow[index] = nil
		end
	end
	for index, render in pairs(storage.visible_planets_renders_shrink) do
		if not render.obj.valid then
			storage.visible_planets_renders_shrink[index] = nil
		end
	end
end)