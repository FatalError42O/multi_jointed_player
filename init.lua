---@diagnostic disable: need-check-nil
local modname = "multi_jointed_player"
local modpath = minetest.get_modpath(modname)
local mjp = {}


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
    textures = {"UV.png"},
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
local targets = {
    Hip_rltv = 0,
    Chest_rltv = 0,
    Head_rltv = 0
}
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
function character:update(dt)
    assert(self.instance, "attempt to call an instance")
    local player = self.player
    local vel = player:get_velocity()
    local theta = 0
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

    targets["Hip_rltv"] = (math.abs(theta)>0 and -(theta-(signof(theta)*.01))) or 0 --so it has a bias when moving horizontal
    local offset_angle = math.pi*(20/360)*2
    offset_angle = clamp(theta, 0, offset_angle*signof(theta))
    targets["Chest_rltv"] = offset_angle
    minetest.chat_send_all(offset_angle)
    targets["Head_rltv"] = clamp(theta-offset_angle, math.pi/2, -math.pi/2)
    --minetest.chat_send_all((head_offset-offset_angle)*(180/math.pi))

    -- in degrees now...
    for _, i in pairs({"Hip_rltv", "Head_rltv", "Chest_rltv"}) do
        local v = targets[i]
        local _, r = player:get_bone_position(i)
        r=r.y
        local next_angle
        v=v*(180/math.pi)
        --find direction to rotate
        local diff = (( v - r + 180 ) % 360) - 180
        local result = ((diff < -180) and (diff + 360)) or diff
        if math.abs(result) > 0.05 then
            --local result = a
            --local rate = (result/math.abs(result))*dt*180*(math.abs(result)/360)^2
            local sign = signof(result)
            local rate = signof(result)*dt*clamp(math.abs(diff)*8, 0, 360)
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
        --if v==0 then next_angle=0 end
        player:set_bone_position(i, nil, {x=0,y=mod2(next_angle, 360),z=0})
    end
end

function character:update_framerate()
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
                eye_height = 1.47
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
    local obj = mjp.default_player_character:set_model(player, "mjp_player.b3d")
end)
minetest.register_globalstep(function(dt)
    for player, obj in pairs(mjp.players) do
        obj:update(dt)
    end
end)