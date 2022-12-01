---@class Character : GameObjectCls
local Character = GameObject();

---@type NetworkManager
local network_manager = Engine.Scene:get_game_object("network");
local NetworkEvent = network_manager.events;


local DIRECTIONS = {
    Left = "left",
    Right = "right",
}
local ACTIONS = {
    "Left",
    "Right",
    "Jump"
}
local SPEEDS = {
    walk = 0.3,
    run = 0.6,
    jump = 0.4
};
local MAX_HP = 3;

local function with_default_camera_size(code)
    local camera = Engine.Scene:get_camera();
    local camera_size = camera:get_size().y / 2;
    camera:set_size(1);
    code();
    camera:set_size(camera_size);
end

---Transmit all trajectory changes over network
---@param trajectory obe.collision.Trajectory
function Character:_transmit_trajectories_changes(trajectory_name)
    local getters_mapping = {
        acceleration = function (trajectory) return trajectory:get_acceleration(); end,
        angle = function(trajectory) return trajectory:get_angle() end,
        speed = function(trajectory) return trajectory:get_speed() end,
        static = function(trajectory) return trajectory:is_static() end,
    }
    self.trajectories:get_trajectory(trajectory_name):on_change(function(trajectory, field)
        local position = Character:get_position();
        NetworkEvent.Character.TrajectoryUpdate [{nolocal=true}] {
            target = self.id,
            trajectory = trajectory_name,
            field = field,
            value = getters_mapping[field](trajectory),
            x = position.x,
            y = position.y
        }
    end);
end

function Character:set_animation(animation_name)
    if animation_name ~= self.components.Animator:get_current_animation_name() then
        NetworkEvent.Character.AnimationUpdate [{nolocal=true}] {
            target = self.id,
            animation = animation_name
        }
        self.components.Animator:set_animation(animation_name);
    end
end

function Character:set_direction(direction)
    if direction ~= self.direction then
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
        NetworkEvent.Character.DirectionUpdate [{nolocal=true}] {
            target = self.id,
            direction = direction
        }
        self.direction = direction;
    end
end

local FALL_DETECTION_EPSILON = 0.001;

function Character:_start_position_sync_job()
    local last_position = {x = 0, y = 0};
    self:schedule():every(1):run(function()
        local position = Character:get_position();
        if last_position.x ~= position.x or last_position.y ~= position.y then
            NetworkEvent.Character.Move [{nolocal=true}] {
                x = position.x,
                y = position.y,
                target = self.id
            }
            last_position = {x = position.x, y = position.y};
        end
    end);
end

local ANIMATION_METADATA = {};

function Character:_prepare_animation()
    for _, animation_name in pairs(self.components.Animator:get_all_animations_names()) do
        ANIMATION_METADATA[animation_name] = {};
        local animation = self.components.Animator:get_animation(animation_name);
        for i = 0, animation:get_frames_amount() - 1 do
            local frame_metadata = vili.to_lua(self.components.Animator:get_animation(animation_name):get_frame_metadata(i));
            ANIMATION_METADATA[animation_name][i] = frame_metadata;
        end
    end
end

function Character:_sync_hat_position()
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

local function ignore_singleway_colliders(trajectory, collider)
    if collider:get_tag() == "singleway" then
        return false;
    end
    return true;
end

function Character:init(x, y, hat)
    x = x or 0;
    y = y or 0;

    self.hp = MAX_HP;

    Engine.Scene:get_camera():set_size(0.5);

    self:_prepare_animation();
    print("ANIMATION METADATA", inspect(ANIMATION_METADATA));

    with_default_camera_size(function()
        self.components.Sprite:set_size(obe.transform.UnitVector(69, 47, obe.transform.Units.ScenePixels));
    end);

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

    self.sprite_size = self.components.Sprite:get_size();
    self.components.SceneNode:set_position(obe.transform.UnitVector(x, y, obe.transform.Units.ScenePixels));

    -- Character's Collider tags
    self.components.Collider:get_inner_collider():set_tag("character");
    local collision_space = Engine.Scene:get_collision_space();
    collision_space:add_tag_to_blacklist("character", "not_solid");
    collision_space:add_tag_to_blacklist("character", "character");

    -- Character's toggles
    self.is_jumping = false;
    self.is_falling = false;
    self.is_moving = false;
    self.is_running = false;
    self.is_crouching = false;
    self.is_going_down = false;
    self.is_attacking = false;
    self.is_spawing = true;

    self.owner = "";

    self.direction = DIRECTIONS.Right;

    self.trajectories = obe.collision.TrajectoryNode(self.components.SceneNode);
    self.trajectories:set_probe(collision_space, self.components.Collider:get_inner_collider());
    self.trajectories:add_trajectory("Fall"):set_speed(0):set_angle(270):set_acceleration(0.9);
    self.trajectories:add_trajectory("Jump"):set_speed(0):set_angle(90):set_acceleration(-0.9):set_static(true);
    self.trajectories:add_trajectory("Move"):set_speed(0):set_angle(0):set_acceleration(0);
    self:_transmit_trajectories_changes("Fall");
    self:_transmit_trajectories_changes("Jump");
    self:_transmit_trajectories_changes("Move");

    local collision_space = Engine.Scene:get_collision_space();
    local collider = self.components.Collider:get_inner_collider();

    self.trajectories:get_trajectory("Fall"):add_check(function(self, offset)
        local fall_detection_y = math.max(FALL_DETECTION_EPSILON, offset.y);
        local fall_detection_offset = obe.transform.UnitVector(0, fall_detection_y, offset.unit);
        local offset_before_collision = collision_space:get_offset_before_collision(collider, fall_detection_offset);
        if not Character.is_jumping and self:is_static() and offset_before_collision.y >= fall_detection_y then
            print("Start falling !")
            self:set_static(false);
            Character.is_falling = true;
        end
    end);

    self.trajectories:get_trajectory("Fall"):set_reachable_collider_acceptor(function(self, collider)
        if collider:get_tag() == "singleway" then
            if Character.is_going_down then
                return false;
            end
            local self_collider_bottom = Character.components.Collider:get_inner_collider():get_bounding_box():get_position(obe.transform.Referential.Bottom).y;
            local other_collider_bottom = collider:get_bounding_box():get_position(obe.transform.Referential.Top).y;
            if self_collider_bottom > other_collider_bottom then
                return false;
            end
        end
        return true;
    end);
    self.trajectories:get_trajectory("Move"):set_reachable_collider_acceptor(ignore_singleway_colliders);
    self.trajectories:get_trajectory("Jump"):set_reachable_collider_acceptor(ignore_singleway_colliders);

    self.trajectories:get_trajectory("Jump"):add_check(function(self, offset)
        if not self:is_static() and self:get_speed() <= 0 then
            Character.is_jumping = false;
            Character.is_falling = true;
            self:set_speed(0);
            self:set_static(true);
        end
    end);

    self.trajectories:get_trajectory("Fall"):on_collide(function(self)
        print("Fall collides")
        self:set_speed(0);
        self:set_static(true);
        Character.is_falling = false;
        Character.is_jumping = false;
    end);

    self.trajectories:get_trajectory("Jump"):on_collide(function(self)
        print("Jump collides !");
        self:set_speed(0);
        Character.is_jumping = false;
        Character.is_falling = true;
    end);

    self:_start_position_sync_job();

    Engine.Scene:get_game_object("bus"):onboard(self);

    self.sword_sound = Engine.Audio:load(obe.system.Path("game://Sounds/sword.ogg"));
    self.damage_sound = Engine.Audio:load(obe.system.Path("game://Sounds/damage.ogg"));
    self.death_sound = Engine.Audio:load(obe.system.Path("game://Sounds/death.ogg"));
end

function Character:left()
    self.is_moving = true;
    self:set_direction(DIRECTIONS.Left);
end

function Character:right()
    self.is_moving = true;
    self:set_direction(DIRECTIONS.Right);
end

function Character:jump()
    -- print("Jumping", self.is_jumping, self.is_falling);
    if not self.is_attacking --[[not self.is_jumping and not self.is_falling]] then
        local jump_speed = SPEEDS.jump;
        local jump_angle = 90;
        self.trajectories
            :get_trajectory("Jump")
            :set_angle(jump_angle)
            :set_speed(jump_speed)
            :set_static(false);
        self.is_jumping = true;
        self.components.Animator:set_animation("jump");
    end
end

function Character:hop_on_bus()
    self.components.SceneNode:set_position(obe.transform.UnitVector(0, 0));
    Character.is_spawing = true;
    Engine.Scene:get_game_object("bus"):onboard(self);
    Engine.Scene:get_camera():set_size(0.5);
end

function Character:_get_sword_offset()
    local sword_offset = obe.transform.UnitVector(0, 0, obe.transform.Units.ScenePixels);
    if self.direction == DIRECTIONS.Right then
        sword_offset.x = self.sprite_size.x / 2;
    else
        sword_offset.x = -self.sprite_size.x / 2;
    end
    return sword_offset;
end

function Character:attack()
    self.sword_sound_handle = self.sword_sound:make_handle();
    self.sword_sound_handle:play();
    if not self.is_attacking then
        Character:set_animation("attack");
        self.is_attacking = true;
        self:schedule():after(0.8):run(function()
            local npcs = Engine.Scene:get_all_game_objects("NonPlayableCharacter");
            for _, npc in pairs(npcs) do
                local hit_box = self.components.Collider:get_inner_collider():get_bounding_box();
                hit_box:set_size(obe.transform.UnitVector(0.05, 0.0510), obe.transform.Referential.Center);
                if self.direction == DIRECTIONS.Right then
                    hit_box:move(obe.transform.UnitVector(0.03, 0));
                else
                    hit_box:move(obe.transform.UnitVector(-0.03, 0));
                end
                local npc_bounding_box = npc.components.Collider:get_inner_collider():get_bounding_box();
                if npc_bounding_box:intersects(hit_box) then
                    self.damage_sound_handle = self.damage_sound:make_handle();
                    self.damage_sound_handle:play();
                    NetworkEvent.Character.Hit {
                        target = npc.id,
                    };
                end
            end
        end);
    end
end

function Character:set_owner(owner)
    self.owner = owner;
end

function Event.Actions.Left()
    Character:left();
end

function Event.Actions.Right()
    Character:right();
end

function Event.Actions.Jump()
    Character:jump();
end

function Event.Actions.Down()
    Engine.Scene:get_camera():set_size(0.25);
    Character.is_going_down = true;
    Character.trajectories:get_trajectory("Fall"):set_static(false);
    Character.is_falling = true;
end

function Event.Actions.Attack()
    Character:attack();
end

local last_animation_frame = nil;

local scene_size;
with_default_camera_size(function()
    local scene_pixels_size = obe.transform.UnitVector(
        Engine.Scene:get_tiles():get_width() * Engine.Scene:get_tiles():get_tile_width(),
        Engine.Scene:get_tiles():get_height() * Engine.Scene:get_tiles():get_tile_height(),
        obe.transform.Units.ScenePixels
    );
    scene_size = scene_pixels_size:to(obe.transform.Units.SceneUnits);
end);

local function check_out_of_map()
    local position = Character:get_position();
    if position.x < 0 or position.x > scene_size.x or position.y < -0.1 or position.y > scene_size.y then
        Character:hop_on_bus();
    end
end


-- Local Update Function
function Event.Game.Update(event)
    -- print("Framerate", 1/event.dt);
    if not Character.is_spawing then
        Character.trajectories:update(event.dt);
    end

    if not Character.is_spawing and check_out_of_map() then
        Engine.Scene:get_game_object("bus"):onboard(Character);
    end

    local current_color = Character.components.Sprite:get_color();
    if current_color.r < 255 then
        current_color.r = current_color.r + 1;
    end
    if current_color.g < 255 then
        current_color.g = current_color.g + 1;
    end
    if current_color.b < 255 then
        current_color.b = current_color.b + 1;
    end
    Character.components.Sprite:set_color(current_color);

    Character.is_going_down = false;

    local current_animation_frame = Character.components.Animator:get_current_animation():get_current_frame_index();
    if last_animation_frame ~= current_animation_frame then
        Character:_sync_hat_position();
        last_animation_frame = current_animation_frame;
    end

    -- Moving Character
    if Character.is_falling and not Character.is_attacking then
        Character.components.Animator:set_animation("fall");
    end

    if Character.components.Animator:get_current_animation_name() == "attack" and Character.components.Animator:get_current_animation():is_over() then
        Character.is_attacking = false;
    end
    Character:move();

    Engine.Scene:get_camera():set_position(Character.components.SceneNode:get_position(), obe.transform.Referential.Center);
end

function Character:get_position()
    return self.components.SceneNode:get_position();
end

function Character:set_position(x, y)
    self.components.SceneNode:set_position(obe.transform.UnitVector(x, y));
end

local old_direction = DIRECTIONS.Right;
function Character:move()
    local move_trajectory = self.trajectories:get_trajectory("Move");
    if not self.is_moving or self.is_attacking then
        if not self.is_falling and not self.is_jumping then
            self.trajectories:get_trajectory("Move"):set_speed(0);
        end
        if not self.is_jumping and not self.is_falling and not self.is_attacking then
            Character:set_animation("idle");
        end

        return;
    end

    if (self.is_jumping or self.is_falling) and self.is_moving and self.direction ~= old_direction then
        move_trajectory:set_speed(SPEEDS.walk / 3);
        return;
    end

    local direction_angle = 0;
    local direction_speed = 0;
    if not self.is_jumping and not self.is_falling and not self.is_attacking then
        Character:set_animation("run");
    end

    if self.is_running then
        direction_speed = SPEEDS.run;
    elseif self.is_moving then
        direction_speed = SPEEDS.walk;
    else
        direction_speed = 0;
    end
    if self.direction == DIRECTIONS.Left then
        direction_angle = 180;
    elseif self.direction == DIRECTIONS.Right then
        direction_angle = 0;
    end

    move_trajectory
        :set_angle(direction_angle)
        :set_speed(direction_speed);

    self.is_moving = false;
    old_direction = self.direction;
end

function Character:spawn()
    self.is_spawing = false;
    Engine.Scene:get_camera():set_size(0.25);
    self.is_falling = true;
end

---Fetch Character by id
---@param id string# id of the Character
---@return Character?
local function fetch_character_by_id(target_id)
    ---@type Character
    local character_to_fetch = Engine.Scene:get_game_object(target_id);
    if character_to_fetch.type ~= "Character" then
        return;
    end
    return character_to_fetch;
end

function NetworkEvent.Character.Hit(evt)
    local character_to_update = fetch_character_by_id(evt.target);
    if character_to_update then
        character_to_update.components.Sprite:set_color(obe.graphics.Color.Red);
        character_to_update.hp = character_to_update.hp - 1;
        Character.damage_sound_handle = Character.damage_sound:make_handle();
        Character.damage_sound_handle:play();
        if character_to_update.hp == 0 then
            Character.death_sound_handle = Character.death_sound:make_handle();
            Character.death_sound_handle:play();
            character_to_update.hp = MAX_HP;
            Character:hop_on_bus();
        end
    end
end