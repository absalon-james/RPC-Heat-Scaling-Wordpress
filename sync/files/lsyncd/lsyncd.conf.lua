{%- from 'scaling_wordpress/sync/settings.jinja' import sync with context %}
----- 
-- Hostnames {{ sync.hostnames }}
-- Hosts {{ sync.hosts }}
-- This file is managed by salt.
-- This was originally taken from an example provided by Floren Munteanu.
-- The original spawned csync2 with the -C config.id.
-- This will not work in an environment where most hostnames include
-- non alphanumeric characters like '-'. Instead, this config will spawn
-- csync2 with all non alphas removed from the config.syncid value.
--
-- Original comments are below:
-- User configuration file for lsyncd. 
-- 
-- This example synchronizes one specific directory through multiple nodes, 
-- by combining csync2 and lsyncd as monitoring tools. 
-- It avoids any race conditions generated by lsyncd, while detecting and 
-- processing multiple inotify events in batch, on each node monitored by 
-- csync2 daemon. 
-- 
-- @author        Floren Munteanu 
-- @link        http://www.axivo.com/ 
----- 
settings = { 
        logident        = "lsyncd", 
        logfacility     = "user", 
        logfile         = "/var/log/lsyncd/lsyncd.log", 
        statusFile      = "/var/log/lsyncd/status.log", 
        statusInterval  = 1 
} 

initSync = { 
        delay = 1, 
        maxProcesses = 1, 
        action = function(inlet) 
                local config = inlet.getConfig() 
                local elist = inlet.getEvents(function(event) 
                        return event.etype ~= "Init" 
                end) 
                local directory = string.sub(config.source, 1, -2) 
                local paths = elist.getPaths(function(etype, path) 
                        return "\t" .. config.syncid .. ":" .. directory .. path 
                end) 
                local configid = string.gsub(config.syncid, '%W', '')
                log("Normal", "Processing syncing list:\n", table.concat(paths, "\n")) 
                spawn(elist, "/usr/sbin/csync2", "-C", configid, "-x") 
        end, 
        collect = function(agent, exitcode) 
                local config = agent.config 
                if not agent.isList and agent.etype == "Init" then 
                        if exitcode == 0 then 
                                log("Normal", "Startup of '", config.syncid, "' instance finished.") 
                        elseif config.exitcodes and config.exitcodes[exitcode] == "again" then 
                                log("Normal", "Retrying startup of '", config.syncid, "' instance.") 
                                return "again" 
                        else 
                                log("Error", "Failure on startup of '", config.syncid, "' instance.") 
                                terminate(-1) 
                        end 
                        return 
                end 
                local rc = config.exitcodes and config.exitcodes[exitcode] 
                if rc == "die" then 
                        return rc 
                end 
                if agent.isList then 
                        if rc == "again" then 
                                log("Normal", "Retrying events list on exitcode = ", exitcode) 
                        else 
                                log("Normal", "Finished events list = ", exitcode) 
                        end 
                else 
                        if rc == "again" then 
                                log("Normal", "Retrying ", agent.etype, " on ", agent.sourcePath, " = ", exitcode) 
                        else 
                                log("Normal", "Finished ", agent.etype, " on ", agent.sourcePath, " = ", exitcode) 
                        end 
                end 
                return rc 
        end, 
        init = function(event) 
                local inlet = event.inlet 
                local config = inlet.getConfig() 
                local event = inlet.createBlanketEvent()
                local configid = string.gsub(config.syncid, '%W', '')
                log("Normal", "Recursive startup sync: ", config.syncid, ":", config.source) 
                spawn(event, "/usr/sbin/csync2", "-C", configid, "-x") 
        end, 
        prepare = function(config) 
                if not config.syncid then 
                        error("Missing 'syncid' parameter.", 4) 
                end
                local configid = string.gsub(config.syncid, '%W', '')
                local c = "csync2_" .. configid .. ".cfg" 
                local f, err = io.open("/etc/csync2/" .. c, "r") 
                if not f then 
                        error("Invalid 'syncid' parameter: " .. err, 4) 
                end 
                f:close() 
        end 
} 

local sources = {
{% set hostname = salt['grains.get']('host', 'localhost') %}
{% for inc in sync.includes %}
        ["{{ inc }}"] = "{{ hostname }}"
{% endfor %}
} 
for key, value in pairs(sources) do 
        sync {initSync, source=key, syncid=value} 
end