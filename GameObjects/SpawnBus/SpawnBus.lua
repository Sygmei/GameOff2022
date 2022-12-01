---@class SpawnBus : GameObjectCls
local SpawnBus = GameObject();

local SPEED = 1;

local function with_default_camera_size(code)
    local camera = Engine.Scene:get_camera();
    local camera_size = camera:get_size().y / 2;
    camera:set_size(1);
    code();
    camera:set_size(camera_size);
end

local scene_width;
with_default_camera_size(function()
    local scene_pixels_width = obe.transform.UnitVector(Engine.Scene:get_tiles():get_width() * Engine.Scene:get_tiles():get_tile_width(), 0, obe.transform.Units.ScenePixels);
    scene_width = scene_pixels_width:to(obe.transform.Units.SceneUnits).x;
end);

function SpawnBus:init()
    self.components.SceneNode:set_position(obe.transform.UnitVector(0, 0));
end

function SpawnBus:onboard(character)
    character.components.SceneNode:set_position(self.components.SceneNode:get_position() + obe.transform.UnitVector(0.07, 0.03));
    self.components.SceneNode:add_child(character.components.SceneNode);
    self:schedule():after(5):run(function()
        SpawnBus.components.SceneNode:remove_child(character.components.SceneNode);
        character:spawn();
    end);
end

function Event.Game.Update(evt)
    SpawnBus.components.SceneNode:move(obe.transform.UnitVector(SPEED * evt.dt, 0));
    if SpawnBus.components.SceneNode:get_position().x > (scene_width - 1) then
        SpawnBus.components.SceneNode:set_position(obe.transform.UnitVector(0, 0));
    end
end