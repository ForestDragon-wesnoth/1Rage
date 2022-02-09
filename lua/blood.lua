local helper = wesnoth.require "lua/helper.lua"

wesnoth.wml_actions.event{
	name="attacker hits" ,
	id="usdgfc3_hits",
	first_time_only=false,
	{ "usdgfc3_hit", {
		id="$second_unit.id"
	} },
	{ "usdgfc3_fix_halo", {
		id="$unit.id"
	} },
	{ "usdgfc3_hit_gibs", {
		id="$second_unit.id"
	} }
}

wesnoth.wml_actions.event{
	name="attacker misses" ,
	id="usdgfc3_misses",
	first_time_only=false,
	{ "usdgfc3_fix_halo", {
		id="$unit.id"
	} }
}

wesnoth.wml_actions.event{
	name="attack end" ,
	id="usdgfc3_attack_end",
	first_time_only=false,
	{ "usdgfc3_fix_halo", {
		id="$second_unit.id"
	} },
	{ "usdgfc3_fix_halo", {
		id="$unit.id"
	} }
}

wesnoth.wml_actions.event{
	name="last breath" ,
	id="usdgfc3_die",
	first_time_only=false,
	{ "usdgfc3_die", {
		id="$unit.id"
	} }
}

wesnoth.wml_actions.event{
	name="turn refresh" ,
	id="usdgfc3_turn_refresh",
	first_time_only=false,
	{ "usdgfc3_fix_halo", {
		side="$side_number"
	} }
}

function is_bloodless(u)
	local resistance = helper.get_child(u, "resistance")
	local skeleton_score = resistance.fire + resistance.impact + resistance.arcane - resistance.cold - resistance.pierce - resistance.blade
	local ghost_score = resistance.fire * 2 + resistance.arcane * 2 - resistance.impact - resistance.cold - resistance.pierce - resistance.blade

	local defense = helper.get_child(u, "defense")
	local average = 0
	local values = 0
	for name, value in pairs(defense) do
		average = average + value
		values = values + 1
	end
	average = average / values
	local mean_deviation = 0
	values = 0
	for name, value in pairs(defense) do
		mean_deviation = mean_deviation + (average - value) * (average - value)
		values = values + 1
	end
	mean_deviation = math.sqrt(mean_deviation / values)
	ghost_score = ghost_score - mean_deviation * 5
	if ghost_score > 0 or skeleton_score > 100 then
		return true
	else
		return false
	end
end

function wesnoth.wml_actions.usdgfc3_hit(cfg)
	local u = wesnoth.get_units(cfg)[1]
	if is_bloodless(u.__cfg) then
		return
	end
	wesnoth.usdgfc3_gibs(u.x, u.y, 1)
end

function wesnoth.wml_actions.usdgfc3_die(cfg)
	local units = wesnoth.get_units(cfg)
	if #units < 1 then
		return
	end
	local u = units[1].__cfg
	if is_bloodless(u) then
		return
	end
	wesnoth.usdgfc3_gibs(u.x, u.y, 5)
	local ucode = wesnoth.unit_types[u.type].__cfg
	local death_code
	for i = 1,#ucode do
		if ucode[i][1] == "death" then
			death_code = ucode[i][2]
		end
	end
	if not death_code then
		local anim = {
			begin = -250,
			finish = 151,
			{ "frame", {
				duration = 100,
				image = "usdgfc3-death-gibs-1.png~BLIT(" .. u.image .. "~CROP(4,4,32,40),0,0)~BLIT(" .. u.image .. "~CROP(36,4,34,40),38,0)~BLIT(" .. u.image .. "~CROP(4,44,32,28),0,44)~BLIT(" .. u.image .. "~CROP(36,44,34,28),38,44)"
				-- Test usdgfc3-death-gibs-1.png~BLIT(units/orcs/grunt.png~CROP(4,4,32,40),0,0)~BLIT(units/orcs/grunt.png~CROP(36,4,34,40),38,0)~BLIT(units/orcs/grunt.png~CROP(4,44,32,28),0,44)~BLIT(units/orcs/grunt.png~CROP(36,44,34,28),38,44)
			}},
			{ "frame", {
				duration = 100,
				image = "usdgfc3-death-gibs-2.png~BLIT(" .. u.image .. "~CROP(8,8,28,36),0,0)~BLIT(" .. u.image .. "~CROP(36,8,30,36),42,0)~BLIT(" .. u.image .. "~CROP(8,44,28,24),0,48)~BLIT(" .. u.image .. "~CROP(36,44,30,24),42,48)"
				-- Test usdgfc3-death-gibs-2.png~BLIT(units/orcs/grunt.png~CROP(8,8,28,36),0,0)~BLIT(units/orcs/grunt.png~CROP(36,8,30,36),42,0)~BLIT(units/orcs/grunt.png~CROP(8,44,28,24),0,48)~BLIT(units/orcs/grunt.png~CROP(36,44,30,24),42,48)
			}},
			{ "frame", {
				duration = 100,
				image = "usdgfc3-death-gibs-3.png"
			}},
			{ "frame", {
				duration = 100,
				image = "usdgfc3-death-gibs-4.png"
			}},
			{ "frame", {
				duration = 100,
				image = "usdgfc3-death-gibs-5.png"
			}},
			{ "frame", {
				duration = 100,
				image = "usdgfc3-death-gibs-6.png"
			}},
			{ "frame", {
				duration = 1,
				image = "misc/blank-hex.png"
			}}
		}
		local object = {
			usdgfc3_death_object=true,
			silent = true,
			{ "effect", {
				apply_to="new_animation",
				id="usdgfc3_death_animation_" .. u.id,
				{ "death", anim }
			}}
		}
		wesnoth.wml_actions.object(object)
	end
end

function wesnoth.wml_actions.usdgfc3_fix_halo(cfg)
	local units = wesnoth.get_units(cfg)
	for i = 1,#units do
		local u = units[i].__cfg
		if not is_bloodless(u) and (not u.halo or u.halo == "" or string.find(u.halo, "usdgfc3")) then
			-- The halo will be changed only if the unit already has one
			local percentage = (u.hitpoints * 100) / u.max_hitpoints
			if percentage >= 50 then
				u.halo = ""
			elseif percentage >= 20 then
				u.halo = "usdgfc3-bleed-light-1.png:100,usdgfc3-bleed-light-2.png:100,usdgfc3-bleed-light-3.png:100,usdgfc3-bleed-light-4.png:100,usdgfc3-bleed-light-5.png:100"
				wesnoth.usdgfc3_gibs(u.x, u.y, 1)
			else
				u.halo = "usdgfc3-bleed-heavy-1.png:100,usdgfc3-bleed-heavy-2.png:100,usdgfc3-bleed-heavy-3.png:100,usdgfc3-bleed-heavy-4.png:100,usdgfc3-bleed-heavy-5.png:100"
				wesnoth.usdgfc3_gibs(u.x, u.y, 2)
			end
			wesnoth.put_unit(u)
		end
	end
end

function wesnoth.wml_actions.usdgfc3_hit_gibs(cfg)
	local unit = wesnoth.get_units(cfg)[1]
	local u = unit.__cfg
	if is_bloodless(u) then
		return
	end
	if not u.halo or u.halo == "" or string.find(u.halo, "usdgfc3") then
		u.halo = "usdgfc3-hit-gibs-1.png:100,usdgfc3-hit-gibs-2.png:100,usdgfc3-hit-gibs-3.png:100,usdgfc3-hit-gibs-4.png:100,usdgfc3-hit-gibs-5.png:100,usdgfc3-hit-gibs-6.png:100,misc/blank-hex.png:100000"
		wesnoth.put_unit(u)
		-- The last frame will be there like forever, until fix_halo is called
	end
end

function wesnoth.usdgfc3_get_gibs_level(x, y)
	wesnoth.wml_actions.store_items{ x = x, y = y, variable = "usdgfc3_items"}
	local tier = 1
	local style = math.random(3) -- 3 styles at the moment
	local items = wesnoth.get_variable( "usdgfc3_items[0]" )
	local trying = 0
	while items do
		if string.find(items.image, "usdgfc3%-ground%-") then
			-- This is what we wanted
			style = string.byte(items.image, 16) - 48
			tier = string.byte(items.image, 18) - 48
			break
		end
		trying = trying + 1
		items = wesnoth.get_variable( "usdgfc3_items[" .. tostring(trying) .. "]" )
	end
	wesnoth.set_variable("usdgfc3_items")
	return tier, style
end

function wesnoth.usdgfc3_gibs(x, y, amount)
	local tier, style = wesnoth.usdgfc3_get_gibs_level(x, y)
	local former_tier = tier
	for i = 1,amount do
		if math.random(tier) == 1 then
			-- Do not increase the gib tiers too fast if there is something already
			tier = tier + 1
		end
	end
	if tier > 8 then
		tier = 8
	end
	if tier ~= former_tier then
		wesnoth.wml_actions.remove_item{ x=x, y=y, image = "usdgfc3-ground-" .. tostring(style) .. "-" .. tostring(former_tier) .. ".png"}
		wesnoth.wml_actions.item{ x=x, y=y, image = "usdgfc3-ground-" .. tostring(style) .. "-" .. tostring(tier) .. ".png"}
		if tier >= 5 and former_tier < 5 then
			local directions = {"n", "nw", "sw", "s", "se", "ne"}
			local opposite_directions = {"s", "se", "ne", "n", "nw", "sw"}
			for i = 1,6 do
				wesnoth.wml_actions.store_locations{
					{ "filter_adjacent_location", {
						x = x,
						y = y,
						adjacent = directions[i]
					}},
					variable = "usdgfc3_adjacent"
				}
				local adjacent = wesnoth.get_variable( "usdgfc3_adjacent" )
				if adjacent then
					local neighbour_tier = wesnoth.usdgfc3_get_gibs_level(adjacent.x, adjacent.y)
					if neighbour_tier >= 5 then
						wesnoth.wml_actions.item{ x=x, y=y, image = "usdgfc3-groundconnect-" .. opposite_directions[i] .. ".png"}
						wesnoth.wml_actions.item{ x = adjacent.x, y = adjacent.y, image = "usdgfc3-groundconnect-" .. directions[i] .. ".png"}
					end
					wesnoth.set_variable("usdgfc3_adjacent")
				end
			end
		end
	end
end
