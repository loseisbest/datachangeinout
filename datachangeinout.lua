obs = obslua

-- 定义默认参数
source_names = {"t1", "t2", "t3", "t4"}  -- 默认源名称数组
container_source_names = {"C_t1", "C_t2", "C_t3", "C_t4"}  -- 默认中间变量的源名称数组
check_interval = 100  -- 检查间隔，毫秒

current_texts = {"", "", "", ""}  -- 全局变量，存储当前文本内容
new_texts = {"", "", "", ""}  -- 全局变量，存储新文本内容
is_hiding = {false, false, false, false}
is_showing = {false, false, false, false}
timers = {nil, nil, nil, nil} -- 定时器句柄

-- 获取源的文本内容
function get_source_text(source)
    if not source then return "" end
    local settings = obs.obs_source_get_settings(source)
    local text = obs.obs_data_get_string(settings, "text")
    obs.obs_data_release(settings)
    return text
end

-- 设置源的文本内容
function set_source_text(source, text)
    if not source then return end
    local settings = obs.obs_source_get_settings(source)
    obs.obs_data_set_string(settings, "text", text)
    obs.obs_source_update(source, settings)
    obs.obs_data_release(settings)
end

-- 获取源的可见性状态
function is_source_visible(scene_item)
    if not scene_item then return false end
    return obs.obs_sceneitem_visible(scene_item)
end

-- 设置源的可见性
function set_source_visibility(scene_item, visible)
    if not scene_item then return end
    obs.obs_sceneitem_set_visible(scene_item, visible)
end

-- 检查中间变量内容变化的函数
function check_container_content()
    for i = 1, #container_source_names do
        if is_hiding[i] or is_showing[i] then
            return
        end

        local container_source_name = container_source_names[i]
        local source_name = source_names[i]
        
        if container_source_name == "" or source_name == "" then
            return
        end

        local container_source = obs.obs_get_source_by_name(container_source_name)
        if container_source then
            local detected_text = get_source_text(container_source)
            if detected_text ~= current_texts[i] then
                new_texts[i] = detected_text  -- 保存新文本内容
                local t_source = obs.obs_get_source_by_name(source_name)
                if t_source then
                    local scene_item = get_sceneitem_from_source(t_source)
                    if scene_item then
                        is_hiding[i] = true
                        if is_source_visible(scene_item) then
                            set_source_visibility(scene_item, false)
                            timers[i] = function() apply_new_text(i) end
                            obs.timer_add(timers[i], 300)  -- 300毫秒后应用新的文本内容
                        else
                            apply_new_text_direct(i)
                        end
                    end
                    obs.obs_source_release(t_source)
                end
            end
            obs.obs_source_release(container_source)
        end
    end
end

-- 在隐藏动画后应用新的文本内容并播放入场动画
function apply_new_text(index)
    obs.timer_remove(timers[index])
    timers[index] = nil

    current_texts[index] = new_texts[index]  -- 更新全局变量
    local source = obs.obs_get_source_by_name(source_names[index])
    if source then
        set_source_text(source, current_texts[index])  -- 更新源的文本内容
        local scene_item = get_sceneitem_from_source(source)
        if scene_item then
            is_hiding[index] = false
            is_showing[index] = true
            set_source_visibility(scene_item, true)
            timers[index] = function() finish_show_animation(index) end
            obs.timer_add(timers[index], 300)  -- 等待 300 毫秒以完成显示动画
        end
        obs.obs_source_release(source)
    end
end

-- 直接应用新的文本内容而不显示
function apply_new_text_direct(index)
    current_texts[index] = new_texts[index]  -- 更新全局变量
    local source = obs.obs_get_source_by_name(source_names[index])
    if source then
        set_source_text(source, current_texts[index])  -- 更新源的文本内容
        is_hiding[index] = false
        is_showing[index] = false
        obs.obs_source_release(source)
    end
end

-- 完成显示动画
function finish_show_animation(index)
    obs.timer_remove(timers[index])
    timers[index] = nil
    is_showing[index] = false
end

-- 获取源对应的场景项
function get_sceneitem_from_source(source)
    if not source then return nil end
    local source_name = obs.obs_source_get_name(source)
    
    local scenes = obs.obs_frontend_get_scenes()
    if not scenes then return nil end

    for _, scene in ipairs(scenes) do
        local scene_source = obs.obs_scene_from_source(scene)
        if scene_source then
            local scene_item = obs.obs_scene_find_source_recursive(scene_source, source_name)
            if scene_item then
                obs.source_list_release(scenes)
                return scene_item
            end
            obs.obs_scene_release(scene_source)
        end
    end
    obs.source_list_release(scenes)
    return nil
end

-- 脚本加载时调用
function script_load(settings)
    for i = 1, 4 do
        source_names[i] = obs.obs_data_get_string(settings, "source_name" .. i)
        container_source_names[i] = obs.obs_data_get_string(settings, "container_source_name" .. i)
        
        local container_source = obs.obs_get_source_by_name(container_source_names[i])
        if container_source then
            current_texts[i] = get_source_text(container_source)  -- 初始化current_texts为当前的文本内容
            obs.obs_source_release(container_source)
        end
    end
    obs.timer_add(check_container_content, check_interval)
end

-- 脚本卸载时调用
function script_unload()
    obs.timer_remove(check_container_content)
    for i = 1, #timers do
        if timers[i] then
            obs.timer_remove(timers[i])
            timers[i] = nil
        end
    end
end

-- 定义脚本的默认参数
function script_defaults(settings)
    for i = 1, 4 do
        obs.obs_data_set_default_string(settings, "source_name" .. i, "t" .. i)
        obs.obs_data_set_default_string(settings, "container_source_name" .. i, "C_t" .. i)
    end
end

-- 定义脚本的描述
function script_description()
    return "检测并隐藏转场后的文本变化脚本.\n\n作者: B站直播说"
end

-- 定义脚本的属性
function script_properties()
    local props = obs.obs_properties_create()
    for i = 1, 4 do
        obs.obs_properties_add_text(props, "source_name" .. i, "源名称 " .. i, obs.OBS_TEXT_DEFAULT)
        obs.obs_properties_add_text(props, "container_source_name" .. i, "中间变量的源名称 " .. i, obs.OBS_TEXT_DEFAULT)
    end
    
    return props
end

-- 当脚本参数更新时调用
function script_update(settings)
    for i = 1, 4 do
        source_names[i] = obs.obs_data_get_string(settings, "source_name" .. i)
        container_source_names[i] = obs.obs_data_get_string(settings, "container_source_name" .. i)
    end
end
