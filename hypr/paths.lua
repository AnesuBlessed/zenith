-- =============================================================================
--  ZENITH — PATH RESOLUTION (LUA)
-- =============================================================================
local M = {}

function M.quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function env(name, fallback)
    local value = os.getenv(name)
    if value == nil or value == "" then return fallback end
    return value
end

local home = env("HOME", "")

-- Primary: read the root path written by install.sh (always correct)
local root_file = home .. "/.config/zenith/root"
local rf = io.open(root_file, "r")
if rf then
    M.root = rf:read("*l"):gsub("%s+$", "")
    rf:close()
else
    -- Fallback: derive from this file's resolved path
    local file = debug.getinfo(1, "S").source:sub(2)
    local p = io.popen("readlink -f -- " .. M.quote(file))
    local resolved = p and p:read("*l")
    if p then p:close() end
    M.root = resolved and resolved:match("^(.*)/hypr/[^/]+$") or (home .. "/zenith")
end

M.cache   = env("XDG_CACHE_HOME", home .. "/.cache") .. "/zenith"
M.state   = env("XDG_STATE_HOME", home .. "/.local/state") .. "/zenith"
M.runtime = env("XDG_RUNTIME_DIR", M.cache .. "/runtime") .. "/zenith"

function M.bin(name)
    return M.quote(M.root .. "/build/" .. name)
end

function M.script(name)
    return M.quote(M.root .. "/scripts/" .. name)
end

hl.env("ZENITH_ROOT", M.root)
hl.env("ZENITH_CACHE", M.cache)
hl.env("ZENITH_STATE", M.state)
hl.env("ZENITH_RUNTIME", M.runtime)

return M
