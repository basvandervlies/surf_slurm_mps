-- ===========================================================================
-- @SURF spank plugin to enable MPS for all graphic cards
-- ===========================================================================

--
-- includes
--
local posix = require("posix")

--
-- constants
--
myname = "SURF"

--
-- functions
--
--
function isdir(fn)
        return (posix.stat(fn, "type") == 'directory')
end

function isfile(fn)
        return (posix.stat(fn, "type") == 'regular')
end

function gethostname()
    local f = io.popen ("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    hostname = string.gsub(hostname, "\n$", "")
    return hostname
end

function getuid(spank)
    local f = io.popen ("/usr/bin/id -un")
    local uid = f:read("*a") or ""
    f:close()
    uid = string.gsub(uid, "\n$", "")
    return uid
end

function getgid()
    local f = io.popen ("/usr/bin/id -gn")
    local gid = f:read("*a") or ""
    f:close()
    gid = string.gsub(gid, "\n$", "")
    return gid
end

function display_msg(spank, caller)
    local context = spank.context
    local hostname = gethostname()
    local uid = getuid(spank)
    local gid = getgid()

    SPANK.log_info("%s: ctx:%s host:%s caller:%s uid:%s gid:%s" , myname, spank.context, hostname, caller, uid, gid)
    return 0
end

function slurm_spank_task_init_privileged (spank)
    fn = "slurm_spank_task_init_privileged"
    display_msg(spank, fn)

    key = "S_JOB_ID"
    job_id = spank:get_item (key)
    job_id = math.floor(job_id)

    key = "S_JOB_UID"
    job_uid = spank:get_item (key)
    job_uid = math.floor(job_uid)

    key = "S_JOB_STEPID"
    job_stepid = spank:get_item (key)
    job_stepid = math.floor(job_stepid)

    gpu_selected_file = surf_mps_cache_dir .. job_uid .. '_' .. job_id
    if isfile(gpu_selected_file) then
        SPANK.log_info("%s:GPU sharing activated uid:job_id:job_stepid (%d:%d:%d)", fn, job_uid, job_id, job_stepid)
    else
        SPANK.log_info("%s:GPU sharing not needed", fn)
        return 0
    end

    cgroups_uid_dir = slurm_cgroups_devices_uid_dir .. job_uid
    cgroups_job_dir = cgroups_uid_dir .. '/job_' .. job_id

    if isdir(cgroups_uid_dir) then
        local job_deny = cgroups_job_dir .. '/devices.deny'
        local job_allow = cgroups_job_dir .. '/devices.allow'
        local uid_allow = cgroups_uid_dir .. '/devices.allow'

        local prog_allow = ""
        local gpu_selected = ""

        if (job_stepid >= 0) then
            prog_allow = cgroups_job_dir .. '/step_' .. job_stepid .. '/devices.allow'
        else
            prog_allow = cgroups_job_dir .. '/step_batch/devices.allow'
        end


        --[[
        -- Remove the devices that SLURM has set always device zero
        ]]--
        SPANK.log_info("%s: removing gpu0 for: %s", fn, job_deny)
        local f = io.open(job_deny, "w")
        f:write("c 195:0 rw")
        f:close()

        --[[
        -- Read the file where the slurmd prolog has saved the selected GPU
        -- for this uid and jobid. Then we must hierarchically add the device to
        -- the allow list:
        --  1.  user uid --> jobid --> stepid (srun)
        --  2.  user uid --> step_batch (sbatch/salloc)
        ]]--
        local f = io.open(gpu_selected_file, "r")
        local gpu  = f:read("*a") or ""
        f:close()
        gpu = string.gsub(gpu, "\n$", "")

        SPANK.log_info("%s: adding '%s' to '%s'", fn, gpu, uid_allow)
        local f = io.open(uid_allow, "w")
        f:write(gpu)
        f:close()

        SPANK.log_info("%s: adding '%s' to '%s'", fn, gpu, job_allow)
        local f = io.open(job_allow, "w")
        f:write(gpu)
        f:close()

        SPANK.log_info("%s: adding '%s' to '%s'", fn, gpu, prog_allow)
        local f = io.open(prog_allow, "w")
        f:write(gpu)
        f:close()

    else
        SPANK.log_info("%s: NOT cgroups_dir = %s", fn, cgroups_dir)
    end
    return 0
end
