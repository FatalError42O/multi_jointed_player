local offsets = {
    --f=flip, x,y=pixel offsets
    ["Lower_arm.R"]={x=16,y=0,f=false},
    ["Lower_arm.L"]={x=0,y=0,f=true},
    ["Upper_arm.R"]={x=0,y=10,f=false},
    ["Upper_arm.L"]={x=16,y=10,f=true}
}
minetest.register_entity("multi_jointed_player:first_person_arm", {
    initial_properties = {
        physical = false,
        pointable = false,
        visual = "mesh",
        visual_size = {x=.9, y=1, z=.9},
        --textures = {"arm_UV.png"},
        mesh = "mjp_arm.obj"
    },
    on_detach = function(self, parent)
        self.object:remove()
    end,
    on_step = function(self, dt)
        self.timer = self.timer and (self.timer + dt)
        if (not self.timer) or (self.timer > 2.5) then
            self.timer = 0
            if not self.player then
                self.object:remove(); return
            end
            local textures = self.player:get_properties().textures
            local working="arm_UV.png"
            local offset = offsets[self.bone]
            local composition = "("..textures[1]
            for i=2,#textures do
                local v = textures[i]
                composition = composition.."^"..v
            end
            composition = composition..")"
            working="[combine:16x22:0,0="..working..":"..offset.x..","..offset.y.."="..composition
            if offset.f then
                --working = "("..working..")^[transformFX"
            end

            self.object:set_properties({textures={working}})
        end
    end,
})