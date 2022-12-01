function Game.Start()
    --[[local render_options = obe.scene.SceneRenderOptions();
    render_options.collisions = true;
    Engine.Scene:set_render_options(render_options);]]
    Engine.Scene:load_from_file("scenes://NetworkTest.vili");
    -- Engine.Scene:load_from_file("scenes://VoiceModTest.vili");
    -- Engine.Scene:load_from_file("scenes://Level_0.vili");
    -- Engine.Scene:load_from_file("scenes://MiniLevel.vili");
    -- Engine.Scene:load_from_file("scenes://Lv_Hero_Village.vili");
    -- Engine.Scene:load_from_file("scenes://vertexopt.vili");
    -- Engine.Scene:load_from_file("scenes://Lv_Modern_City.vili");
    -- Engine.Scene:load_from_file("scenes://SpritesheetTest.vili");
    --[[local map_data = vili.from_file_as_vili("scenes://Level_1.vili");
    Engine.Scene:set_future_load(map_data);]]
end