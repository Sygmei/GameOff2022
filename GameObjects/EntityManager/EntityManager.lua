---@class EntityManager : GameObjectCls
local EntityManager = GameObject();

---@type NetworkManager
local network_manager = Engine.Scene:get_game_object("network");
local NetworkEvent = network_manager.events;

function EntityManager:init()
    self.entities_by_owner = {};
end

function EntityManager:spawn(entity_type, id, owner, args)
    local rid = ("%s_%s"):format(
        entity_type,
        obe.utils.string.get_random_key(
            obe.utils.string.Alphabet .. obe.utils.string.Numbers, 8
        )
    );
    id = ("%s.%s"):format(owner, id or rid);
    args = args or {};
    print("Spawning new", entity_type, "with id", id, "and args", inspect(args));
    if self.entities_by_owner[owner] == nil then
        self.entities_by_owner[owner] = {};
    end
    self.entities_by_owner[owner][id] = true;
    return Engine.Scene:create_game_object(entity_type, id)(args);
end

function NetworkEvent.EntityManager.Spawn(evt)
    local entity = EntityManager:spawn(evt.kind, evt.id, evt.owner, evt.args);
    entity:set_owner(evt.owner);
end

function NetworkEvent.EntityManager.Remove(evt)
    Engine.Scene:remove_game_object(evt.target);
end

function NetworkEvent.EntityManager.RemoveAll(evt)
    for game_object_id, _ in pairs(EntityManager.entities_by_owner[evt.owner]) do
        Engine.Scene:remove_game_object(game_object_id);
    end
end

function NetworkEvent.Scene.Load(evt)
    print("Received new map", evt.data);
    local vili_map = vili.from_msgpack_as_vili(evt.data);
    Engine.Scene:set_future_load(vili_map);
end

function NetworkEvent.Scene.LoadFromLocalFile(evt)
    print("Using local map", evt.scene_name);
    local scene_path = ("scenes://%s"):format(evt.scene_name);
    Engine.Scene:load_from_file(scene_path);
end