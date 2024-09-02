---@diagnostic disable: need-check-nil
local modname = "multi_jointed_player"
local modpath = minetest.get_modpath(modname)
multi_jointed_player = {}
local mjp = multi_jointed_player
--for temp
minetest.rmdir(modpath.."/temp", true)
minetest.mkdir(modpath.."/temp")

local mp_g4d = minetest.get_modpath("guns4d")
if mp_g4d then
    dofile(modpath.."/guns4d.lua")
end
dofile(modpath.."/first_person_arms.lua")

--[[local conf = Settings(modpath.."/model_settings.conf"):to_table() or {}
local mt_conf = minetest.settings:to_table() --allow use of MT config for servers that regularly update 4dguns through it's development
for i, v in pairs(Guns4d.config) do
    --Guns4d.config[i] = conf[i] or minetest.settings["guns4d."..i] or Guns4d.config[i]
    --cant use or because it'd evaluate to false if the setting is alse
    if mt_conf["modname."..i] ~= nil then
        Guns4d.config[i] = mt_conf["modname."..i]
    elseif conf[i] ~= nil then
        Guns4d.config[i] = conf[i]
    end
end]]


local character = {
    _registered_models = {},
    model_name = "mjp_player.b3d",
    textures = {"male_default_nude.png","boxers.png"},
    animations = {
        idle_held = {x=91,y=120},
        idle_empty = {x=121, y=150},
        lay = {x=151, y=151},
        walk = {x=10, y=90},
        dig = {x=0, y=0},
        walk_while_dig = {x=0, y=0},
        sit = {x=0, y=0},
    },
    --current active local animations. Set to a string which is an index found in self.animations
    active_locals = {
        idle = "idle_empty",
        walk = "walk",
        dig = "dig",
        walk_while_dig =  "walk_while_dig"
    },
    mirror_backwards = true, --wether to mirror backwards movement
    frame_speed = 60,
    --[[rotation = {
        chest = 0,
        head = 0,
        hip = 0
    }]]
    player_look = 0,
    --player=nil   HAD TO COMMENT THIS OUT BECAUSE SUMNEKO HAS A FUCKING FIT OTHERWISE
}

function character:set_model(player, model)
    model = ((type(model) == "table") and model) or mjp.default_player_character._registered_models[model]
    assert(model, "invalid model. Enter a class or a valid name of the model to use, recieved input: "..tostring(model))
    assert(player, "no player ref provided when setting model")
    local inst = model:new({
        player = player
    })
    mjp.players[player] = inst
    return inst
end
local function clamp(val, lower, upper)
    if lower > upper then lower, upper = upper, lower end
    return math.max(lower, math.min(upper, val))
end
local pi = math.pi
local tau = pi*2
--rotation target buffer
--modulo which works with negatives
local function mod2(a,b)
    if math.abs(a) <= math.abs(b) then return a end
    local r = a/b
    return a-( b*(math.floor(math.abs(r))*(r/math.abs(r))) )
end
local function signof(a)
    --if a==0 then return 1 end
    return a/math.abs(a)
end
local buffer={}
local function index_out(i, ...)
    local table = {...}
    return table[i]
end
function character:update(dt)
    assert(self.instance, "attempt to call an instance")
    local player = self.player
    local vel = player:get_velocity()
    local theta = 0
    local gun
    local gun_properties
    if mp_g4d then
        gun = Guns4d.players[player:get_player_name()].gun
        gun_properties = (gun and gun.properties) or nil
    end
    --for our purposes we offset clockwise 90 deg making the head our 0 deg
    if math.sqrt(vel.x^2+vel.z^2) > 0 then
        local rot = (tau-player:get_look_horizontal())+(pi/2)
        local angle = math.atan2(vel.x, vel.z)+(pi/2)
        theta = (rot-angle)%(tau)
        if theta ~= theta then theta = 0 end
        if theta > pi then
            theta = (theta-tau)
        end
    end
    if (self.mirror_backwards) and (math.abs(theta) > math.pi*(100/180)) then
        theta = -signof(theta)*(math.pi-math.abs(theta))
    end

    local dtr = math.pi/180
    local offset_angle = math.pi*(20/360)*2
    buffer.hip = (math.abs(theta)>0 and -(theta-(signof(theta)*.01))) or 0 --so it has a bias when moving horizontal

    if gun then
        local rot_limit = 65*dtr
        local gun_hip_offset = 10*dtr
        local chest_offset = 30*dtr
        local props = gun_properties.visuals.multi_jointed_player
        if gun_properties.visuals.multi_jointed_player then
            rot_limit = (props.leftward_strafe_limit or 65)*dtr
            gun_hip_offset = (props.player_rotation_offset or 10)*dtr
            if theta < 0 then --if moving right cancel it out
                gun_hip_offset = 0
            end
            chest_offset = (props.chest_offset or 30)*dtr
        end
        buffer.hip = clamp(buffer.hip+gun_hip_offset, -rot_limit, math.pi)
        theta = clamp(theta, -rot_limit, math.pi)
        offset_angle = clamp(theta+chest_offset, -offset_angle, offset_angle*2)
    else
        offset_angle = clamp(theta, -offset_angle, offset_angle)
    end
    --offset_angle = clamp(theta, 0, offset_angle*signof(theta))
    buffer.chest = offset_angle
    buffer.head_y = clamp(-(buffer.hip+buffer.chest), math.pi/2, -math.pi/2)
    buffer.head_x = (gun and -gun.handler.look_rotation.x*math.pi/180) or player:get_look_vertical()
    --minetest.chat_send_all((head_offset-offset_angle)*(180/math.pi))
    local out = {}
    local _, head = player:get_bone_position("Head_rltv")
    local hip_pos, hip_rot = player:get_bone_position("Hip_rltv")
    local rot = {
        hip = hip_rot.y,
        chest = index_out(2, player:get_bone_position("Chest_rltv")).y,
        head_x = head.x,
        head_y = head.y
    }
    -- (in degrees)
    for i, v in pairs(buffer) do
        local r = rot[i]
        local next_angle
        v=v*(180/math.pi)
        --find direction to rotate
        local diff
        local result
        diff = (( v - r + 180 ) % 360) - 180
        result = ((diff < -180) and (diff + 360)) or diff
        if math.abs(r+(math.abs(diff)*signof(result))) > 180 then
            result = -result
        end
        if math.abs(result) > 0.05 then
            --local result = a
            --local rate = (result/math.abs(result))*dt*180*(math.abs(result)/360)^2
            local sign = signof(result)
            local rate = sign*dt*clamp(math.abs(diff)*8, 0, 360)
            if ((r+rate)*sign)then
                next_angle = r+rate
            else
                next_angle = v
            end
            if i== "Head_rltv" then
                next_angle = clamp(next_angle, 90, -90)
            end
            if i== "Chest_rltv" then
                next_angle = clamp(next_angle, 20, -20)
            end
        else
            --minetest.chat_send_all("reached target")
            next_angle = v
        end
        out[i] = next_angle
        --if v==0 then next_angle=0 end
    end
    player:set_bone_position("Head_rltv", nil, {x=out.head_x, y=mod2(out.head_y, 360),z=0})
    player:set_bone_position("Chest_rltv", nil, {x=0,y=mod2(out.chest, 360),z=0})
    player:set_bone_position("Hip_rltv", hip_pos, {x=0,y=mod2(out.hip, 360),z=0})
end
function character:add_first_person_arms(guns4d_handler)
    assert(self.instance, "attempt to call object method on an instance")
    local player = self.player
    local pos = player:get_pos()
    for i, bone_name in pairs({"Lower_arm.R", "Lower_arm.L", "Upper_arm.R", "Upper_arm.L"}) do
        local obj = minetest.add_entity(pos, "multi_jointed_player:first_person_arm")
        local attach_name = (guns4d_handler and guns4d_handler.override_bones[bone_name]) or bone_name
        local luaent = obj:get_luaentity()
        luaent.player = player
        luaent.bone = bone_name
        if i> 2 then
            obj:set_properties({visual_size={x=.9,y=.8,z=.9}})
        end
        luaent:on_step(0)
        obj:set_attach(player, attach_name, nil, {x=180,y=0,z=0}, true)
    end
end
function character:reattach_arm_bones(guns4d_active)
    assert(self.instance, "attempt to call object method on an instance")
end
function character:construct()
    if not self.instance then
        local animations = self.animations
        self._registered_models[self.model_name] = self
        if player_api then
            player_api.register_model(self.model_name, {
                animation_speed = self.frame_speed,           -- Default animation speed, in keyframes per second
                textures = self.textures,   -- Default array of textures
                animations = {
                    -- [anim_name] = {
                    --   x = <start_frame>,
                    --   y = <end_frame>,
                    --   collisionbox = <model collisionbox>, -- (optional)
                    --   eye_height = <model eye height>,     -- (optional)
                    --   -- suspend client side animations while this one is active (optional)
                    --   override_local = <true/false>
                    -- },
                    stand = animations.idle_empty,
                    --player api has different naming conventions from the engine. I use engine naming conventions because what the fuck why would i adopt it's weird shit.
                    lay = animations.lay, --required
                    walk = animations.walk, --required
                    mine = animations.dig, --required
                    walk_mine = animations.walk_while_dig, --required
                    sit = animations.sit -- used by boats and other MTG mods
                },
                -- Default object properties, see lua_api.txt
                visual_size = {x = 10, y = 10},
                collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
                stepheight = 0.6,
                eye_height = 1.6
            })
        end
        self.rotation = {
            chest = 0,
            head = 0,
            hip = 0
        }
    else
        local player = self.player
        if player_api then
            player_api.set_model(player, self.model_name)
        else
            player:set_properties({
                mesh = self.model_name
            })
            player:set_local_animation(self.idle, self.walk, self.dig, self.walk_while_dig, self.frame_speed)
        end
    end
end
mjp.default_player_character = mtul.class.new_class:inherit(character)

mjp.players={}
minetest.register_on_joinplayer(function(player)
    --this will have to preserve the previously used model eventually, hence why i used a function.
    if player then
        local obj = mjp.default_player_character:set_model(player, "mjp_player.b3d")
        obj:add_first_person_arms()
    end
end)
local arm_check_timer = 0
minetest.register_globalstep(function(dt)
    for player, obj in pairs(mjp.players) do
        arm_check_timer=arm_check_timer+dt
        if arm_check_timer>5 then
            --check arms
        end
        obj:update(dt)
    end
end)