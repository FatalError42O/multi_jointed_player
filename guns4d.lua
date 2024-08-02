local model_handler = Guns4d.player_model_handler:inherit({
    bone_aliases = { --names of bones used by the model handler and other parts of guns4d.
        __overfill = true,

        arm_right = "guns4d_arm_right",
        arm_right_lower = "guns4d_arm_lower_right",

        arm_left = "guns4d_arm_left",
        arm_left_lower = "guns4d_arm_lower_left",

        head = "guns4d_head",
        aim = "guns4d_aiming_bone",
        hipfire = "guns4d_hipfire_bone",
    },
    --define guns4d model generation parameters
    override_bones = { --a list of bones to be read and or generated
        __overfill = true,
        ["Upper_arm.R"] = "guns4d_arm_right",
        ["Lower_arm.R"] = "guns4d_arm_lower_right",

        ["Upper_arm.L"] = "guns4d_arm_left",
        ["Lower_arm.L"] = "guns4d_arm_lower_left",
        Head = "guns4d_head"
    },
    scale = 10,
    compatible_meshes = {
        ["mjp_player.b3d"] = true
    },
    fallback_mesh = "mjp_player.b3d",
    output_path = minetest.get_modpath("multi_jointed_player").."/temp/",
    construct = function(self)
        if self.instance then
            --regenerate first person bones
            minetest.chat_send_all("regenerated arms")
            multi_jointed_player.players[self.player]:add_first_person_arms(self)
        else
            --[[for _, i in pairs({"arm_left_lower", "arm_right_lower"}) do
                self.offsets.relative[i].y = self.offsets.relative[i].y-.02
                self.offsets.global[i].y = self.offsets.global[i].y-.2
            end]]
        end
    end,
    --needs to be in the table when inherited so construction can call it
    custom_b3d_generation_parameters = function(self, b3d)
        --stabilize the arms
        local new_right={
            name = "arm_right_corrector",
            position = {0,0,0},
            scale = {1,1,1},
            rotation = {0,0,0,1},
            children = {mtul.b3d_nodes.get_node_by_name(b3d, "guns4d_arm_right", true)},
            bone = {},
            keys = {}
        }
        local new_left = {
            name = "arm_left_corrector",
            position = {0,0,0},
            scale = {1,1,1},
            rotation = {0,0,0,1},
            children = {mtul.b3d_nodes.get_node_by_name(b3d, "guns4d_arm_left", true)},
            bone = {},
            keys = {}
        }
        local hip_bone = mtul.b3d_nodes.get_node_by_name(b3d, "Hip", true)
        for _,node in pairs({left=new_left, right=new_right}) do
            for i, keyframe in pairs(hip_bone.keys) do
                local offset = (hip_bone.position[2]-keyframe.position[2])
                node.keys[i] = {
                    frame=keyframe.frame,
                    rotation = {0,0,0,1},
                    position = {0,offset,0},
                    scale = {1,1,1}
                }
            end
        end
        --
        local children = mtul.b3d_nodes.get_node_by_name(b3d, "Chest_rltv", true).children
        for i, child in pairs(children) do
            if child.name=="guns4d_arm_right" then
                children[i] =new_right
            elseif child.name=="guns4d_arm_left" then
                children[i] = new_left
            end
        end
        return b3d
    end
})
function model_handler:prepare_deletion()
    multi_jointed_player.players[self.player]:add_first_person_arms(self)
    self.parent_class.prepare_deletion(self)
end
function model_handler:update(dt)
    --assert(dt, "delta time (dt) not provided.")x
    --assert(self.instance, "attempt to call object method on a class")
    self:update_aiming(dt)
    self:update_arm_bones(dt)
end
--where b is the base and a and c are the other sides
local function height_of_scalene(a,b,c)
    --c=hypotenus
    local s = (a+b+c)/2
    return (2*math.sqrt(s*(s-a)*(s-b)*(s-c)))/b
end
--local mat4 = mtul.math.mat4
local length = {upper=.3, lower=.4}
local quat = mtul.math.quat
local function arm_rotation(a, b, right)
    --b=b-{x=0,y=0,z=-.01}
    local dir = vector.direction(a, b)
    local distance = Guns4d.math.clamp(vector.distance(a, b), 0, length.upper+length.lower-.001)
    local rheight = height_of_scalene(length.upper, distance, length.lower)
    --offset rotation of the upper and lower arm sections
    local upper = math.asin(rheight/length.upper)
    local lower = math.acos(rheight/length.lower)+math.acos(rheight/length.upper)

    local xr = -math.atan2(dir.y, math.sqrt(dir.x^2+dir.z^2)) --pitch to direction
    local yr = -math.atan2(dir.x, dir.z) --yaw to direction
    local z = -math.pi/6 * ((right and 1) or 0)

    local rot = (quat.from_euler_rotation({x=0,y=yr,z=0}) * quat.from_euler_rotation({x=xr,y=0,z=0}) )*quat.from_euler_rotation({x=0,y=0,z=z})
    rot = rot*quat.from_euler_rotation({x=upper,y=0,z=0})
    local x,y,z=rot:to_euler_angles_unpack()
    --so it turns out that the reason why it was so shit is because the pitch was expecting clockwise. Minetest's system of rotation is fucked up so i was outputting euler angles
    --from quats that didn't make sense in minetest's system of rotation.
    return x*180/math.pi,y*180/math.pi,z*180/math.pi,lower*180/math.pi
end
function model_handler:update_arm_bones(dt)
    local player = self.player
    local handler = self.handler
    local gun = handler.gun

    local pprops = handler:get_properties()

    local a, b =  player:get_bone_position("Chest_rltv")
    local player_offset, player_rot = player:get_bone_position("Hip_rltv")
    player_rot = player_rot.y+b.y

    local left_bone, right_bone = vector.multiply(self.offsets.global.arm_left, pprops.visual_size), vector.multiply(self.offsets.global.arm_right, pprops.visual_size)
    local left_trgt, right_trgt = gun:get_arm_aim_pos() --this gives us our offsets relative to the gun.
    --get the real position of the gun's bones relative to the player (2nd param true)
    left_trgt = gun:get_pos(left_trgt, true)
    right_trgt = gun:get_pos(right_trgt, true)

    left_trgt = vector.rotate(left_trgt, {x=0,y=player_rot*math.pi/180,z=0})-player_offset
    right_trgt = vector.rotate(right_trgt,  {x=0,y=player_rot*math.pi/180,z=0})-player_offset
    --local left_rotation = vector.dir_to_rotation(vector.direction(left_bone, left_trgt))*180/math.pi
    --local right_rotation = vector.dir_to_rotation(vector.direction(right_bone, right_trgt))*180/math.pi
    --all of this is pure insanity. There's no logic, or rhyme or reason. Trial and error is the only way to write this garbo.
    --left_rotation.x = left_rotation.x
    --right_rotation.x = right_rotation.x
    local rx,ry,rz,rlx = arm_rotation(right_bone, right_trgt, true)
    player:set_bone_position(self.bone_aliases.arm_right, self.offsets.relative.arm_right,  {x=rx+90,y=-ry,z=-rz})
    player:set_bone_position(self.bone_aliases.arm_right_lower, self.offsets.relative.arm_right_lower,  {x=-(180-rlx),y=0,z=0})

    local lx,ly,lz,llx = arm_rotation(left_bone, left_trgt)
    player:set_bone_position(self.bone_aliases.arm_left, self.offsets.relative.arm_left,  {x=lx+90,y=-ly,z=-lz})
    player:set_bone_position(self.bone_aliases.arm_left_lower, self.offsets.relative.arm_left_lower,  {x=-(180-llx),y=0,z=0})

    --player:set_bone_position(self.bone_aliases.arm_left, self.offsets.relative.arm_left, {x=90+(0),y=0,z=0}-left_rotation)
    --player:set_bone_position(self.bone_aliases.arm_left_lower, self.offsets.relative.arm_left_lower,  {x=(-0),y=0,z=0})

end