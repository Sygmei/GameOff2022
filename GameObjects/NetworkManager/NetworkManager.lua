---@class NetworkManager : GameObjectCls
local NetworkManager = GameObject();

local network = require("obe://Lib/Internal/Network");

function NetworkManager:init(offline)
    local full_network_config = vili.from_file("game://network.vili");
    local selected_network_config = full_network_config.configs[full_network_config.use];
    self.config = network.make_config_defaults(selected_network_config);
    local event_namespace = Engine.Events:create_namespace(self.config.namespace);
    local vili_spec = vili.from_file_as_vili(self.config.spec);
    self.components.NetworkManager = obe.network.NetworkEventManager(event_namespace, vili_spec);
    network.make_event_handler(self, self.components.NetworkManager);
    self.events = network.make_network_event_namespace_hook(self, self.components.NetworkManager, self.config);
    if offline then
        return;
    end
    if self.config.mode == "client" then
        self.components.NetworkManager:connect(self.config.host, self.config.port);
    elseif self.config.mode == "server" then
        self.components.NetworkManager:host(self.config.port);
    end

    -- TODO: move that elsewhere
    self.soundtrack = Engine.Audio:load(obe.system.Path("game://Music/soundtrack.ogg"), obe.audio.LoadPolicy.Stream);
    self.soundtrack_handle = self.soundtrack:make_handle();
    self.soundtrack_handle:set_looping(true);
    self.soundtrack_handle:play();
end

function NetworkManager:get_client_name()
    ---@type obe.network.NetworkEventManager
    local network_manager = self.components.NetworkManager;
    return network_manager:get_client_name();
end