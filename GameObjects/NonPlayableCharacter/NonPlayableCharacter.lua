---@class NonPlayableCharacter : GameObjectCls
local NonPlayableCharacter = GameObject();

---@type NetworkManager
local network_manager = Engine.Scene:get_game_object("network");
local NetworkEvent = network_manager.events;

local SPEEDS = {
    walk = 0.3,
    run = 0.6,
    jump = 0.4
};
local DIRECTIONS = {
    Left = "left",
    Right = "right",
}

local function with_default_camera_size(code)
    local camera = Engine.Scene:get_camera();
    local camera_size = camera:get_size().y / 2;
    camera:set_size(1);
    code();
    camera:set_size(camera_size);
end

local ANIMATION_METADATA = {};

function NonPlayableCharacter:_prepare_animation()
    for _, animation_name in pairs(self.components.Animator:get_all_animations_names()) do
        ANIMATION_METADATA[animation_name] = {};
        local animation = self.components.Animator:get_animation(animation_name);
        for i = 0, animation:get_frames_amount() - 1 do
            local frame_metadata = vili.to_lua(self.components.Animator:get_animation(animation_name):get_frame_metadata(i));
            ANIMATION_METADATA[animation_name][i] = frame_metadata;
        end
    end
end

function NonPlayableCharacter:_sync_hat_position()
    if not self.hat then
        return;
    end
    local current_animation = self.components.Animator:get_current_animation_name();
    local current_frame = self.components.Animator:get_current_animation():get_current_frame_index();
    local frame_metadata = ANIMATION_METADATA[current_animation][current_frame];
    if frame_metadata.anchor_points and frame_metadata.anchor_points.head then
        with_default_camera_size(function()
            local animation_frame_size = self.components.Animator:get_current_animation():get_animation():get_texture_at_index(0):get_size();
            local hat_anchor_point = frame_metadata.anchor_points.head;
            local hat_pixel_offset = obe.transform.UnitVector(hat_anchor_point.x, hat_anchor_point.y, obe.transform.Units.ScenePixels);
            if self.direction == DIRECTIONS.Left then
                hat_pixel_offset.x = animation_frame_size.x - hat_pixel_offset.x;
            end
            local sprite_postion = self.components.Sprite:get_position();
            local base_offset = obe.transform.UnitVector(-13, -23, obe.transform.Units.ScenePixels);
            if self.direction == DIRECTIONS.Left then
                base_offset.x = -19;
            end
            self.hat:set_position(sprite_postion + hat_pixel_offset + base_offset);
        end);
    end
end


---Fetch NPC by id
---@param id string# id of the NPC
---@return NonPlayableCharacter?
local function fetch_npc_by_id(target_id)
    ---@type NonPlayableCharacter
    local character_to_fetch = Engine.Scene:get_game_object(target_id);
    if character_to_fetch.type ~= "NonPlayableCharacter" then
        return;
    end
    return character_to_fetch;
end

function NonPlayableCharacter:update_trajectory(trajectory_name, trajectory_field, value)
    local setters_mapping = {
        acceleration = function (trajectory, value) return trajectory:set_acceleration(value); end,
        angle = function(trajectory, value) return trajectory:set_angle(value); end,
        speed = function(trajectory, value) return trajectory:set_speed(value); end,
        static = function(trajectory, value) return trajectory:set_static(value); end,
    }
    local trajectory = self.trajectories:get_trajectory(trajectory_name);
    setters_mapping[trajectory_field](trajectory, value);
end

function NonPlayableCharacter:init(x, y, hat)
    x = x or 0;
    y = y or 0;

    with_default_camera_size(function()
        self.components.Sprite:set_size(obe.transform.UnitVector(69, 47, obe.transform.Units.ScenePixels));
    end);

    self.sprite_size = self.components.Sprite:get_size();

    self:_prepare_animation();
    self.direction = DIRECTIONS.Right;

    if hat then
        self.hat = Engine.Scene:create_sprite(self.id .. "_hat");
        self.hat:load_texture("sprites://Hats/" .. hat .. ".png");
        -- self.hat:set_size(self.components.Sprite:get_size());
        with_default_camera_size(function()
            self.hat:set_size(obe.transform.UnitVector(32, 32, obe.transform.Units.ScenePixels));
            self.hat_sprite_size = self.hat:get_size();
        end);
        self.hat:set_position(self.components.Sprite:get_position());
        self.hat:set_layer(self.components.Sprite:get_layer());
        self.hat:set_sublayer(self.components.Sprite:get_sublayer() - 1);
        self.components.SceneNode:add_child(self.hat);
    end

    self.components.SceneNode:set_position(obe.transform.UnitVector(x, y, obe.transform.Units.ScenePixels));

    -- Character's Collider tags
    self.components.Collider:get_inner_collider():set_tag("character");

    -- Trajectories
    local collision_space = Engine.Scene:get_collision_space();
    self.trajectories = obe.collision.TrajectoryNode(self.components.SceneNode);
    self.trajectories:set_probe(collision_space, self.components.Collider:get_inner_collider());
    self.trajectories:add_trajectory("Fall"):set_speed(0):set_angle(270):set_acceleration(0.9);
    self.trajectories:add_trajectory("Jump"):set_speed(0):set_angle(90):set_acceleration(-0.9):set_static(true);
    self.trajectories:add_trajectory("Move"):set_speed(0):set_angle(0):set_acceleration(0);

    self.owner = "";
end

function NonPlayableCharacter:set_owner(owner)
    self.owner = owner;
end

function NonPlayableCharacter:get_position()
    return self.components.SceneNode:get_position();
end

function NonPlayableCharacter:set_position(x, y)
    self.components.SceneNode:set_position(obe.transform.UnitVector(x, y));
end

function NonPlayableCharacter:set_animation(animation_name)
    self.components.Animator:set_animation(animation_name);
end

function NonPlayableCharacter:set_direction(direction)
    if direction == DIRECTIONS.Right then
        self.components.Sprite:flip(false, false);
        if self.hat then
            self.hat:flip(false, false);
        end
    else
        self.components.Sprite:flip(true, false);
        if self.hat then
            self.hat:flip(true, false);
        end
    end
    self.direction = direction;
end

local last_animation_frame;

-- Game Events
function Event.Game.Update(evt)
    NonPlayableCharacter.trajectories:update(evt.dt);

    local current_animation_frame = NonPlayableCharacter.components.Animator:get_current_animation():get_current_frame_index();
    if last_animation_frame ~= current_animation_frame then
        NonPlayableCharacter:_sync_hat_position();
        last_animation_frame = current_animation_frame;
    end

    local current_color = NonPlayableCharacter.components.Sprite:get_color();
    if current_color.r < 255 then
        current_color.r = current_color.r + 1;
    end
    if current_color.g < 255 then
        current_color.g = current_color.g + 1;
    end
    if current_color.b < 255 then
        current_color.b = current_color.b + 1;
    end
    NonPlayableCharacter.components.Sprite:set_color(current_color);
end

-- Network Events
function NetworkEvent.Character.Move(evt)
    local character_to_update = fetch_npc_by_id(evt.target);
    if character_to_update then
        character_to_update:set_position(evt.x, evt.y);
    end
end

function NetworkEvent.Character.TrajectoryUpdate(evt)
    local character_to_update = fetch_npc_by_id(evt.target);
    if character_to_update then
        character_to_update:set_position(evt.x, evt.y);
        character_to_update:update_trajectory(evt.trajectory, evt.field, evt.value);
    end
end

function NetworkEvent.Character.AnimationUpdate(evt)
    local character_to_update = fetch_npc_by_id(evt.target);
    if character_to_update then
        character_to_update:set_animation(evt.animation);
    end
end

function NetworkEvent.Character.DirectionUpdate(evt)
    local character_to_update = fetch_npc_by_id(evt.target);
    if character_to_update then
        character_to_update:set_direction(evt.direction);
    end
end

function NetworkEvent.Character.Hit(evt)
    local character_to_update = fetch_npc_by_id(evt.target);
    if character_to_update then
        character_to_update.components.Sprite:set_color(obe.graphics.Color.Red);
    end
end