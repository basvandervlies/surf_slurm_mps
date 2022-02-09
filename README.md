# SLURM_SURF_MPS

We develop this setup at SURF to share our GPU's for (jupyterhub) courses. The courses are given on our
LISA cluster. This cluster does not have A100's and we want to share our GPUs (1080TI and TitanRTX).
NVIDIA supported multiple users per GPU, but they removed this functionality due to security reasons:
 * https://docs.nvidia.com/deploy/mps/index.html

SLURM has implemented MPS support with the restriction that it only supports 1 GPU in the node. We have
multiple GPUs per node and we want to use all the GPUs in this node for sharing.
 * https://slurm.schedmd.com/gres.html#MPS_Management

We managed to share all the GPUs in a node with the aid of the lua spank plugin:
 * https://github.com/stanford-rc/slurm-spank-lua

In short we reuse the SLURM mps feature. We let SLURM schedule jobs on the node and with the combination
of slurmd prolog/epilog and the lua plugin we wrote our own GPU scheduler:
 * It will schedule the job on the least occupied GPU
 * It will manipulate the cgroup to attach the choosen GPU to the job.
 * The state of scheduler is saved in `/run/surf_mps`
 * Each job has the same mps share.

Note: the setup can not constrain the memory used on the GPUs. The way to constrain the memory is in:
 * pytorch
```
torch.cuda.set_per_process_memory_fraction(0.25).
```
 * tensorflow
```
# TensorFlow by default allocates all CUDA memory, disable this by:
export TF_FORCE_GPU_ALLOW_GROWTH=true

gpus = tf.config.list_physical_devices('GPU')
if gpus:
  # Restrict TensorFlow to only allocate 1GB of memory on the first GPU
  try:
    tf.config.set_logical_device_configuration(
        gpus[0],
        [tf.config.LogicalDeviceConfiguration(memory_limit=1024)])
    logical_gpus = tf.config.list_logical_devices('GPU')
    print(len(gpus), "Physical GPUs,", len(logical_gpus), "Logical GPUs")
  except RuntimeError as e:
    # Virtual devices must be set before GPUs have been initialized
    print(e)
```

## Setup

The LISA cluster has 4 Titan RTX (24GB) cards per node. We have choosen a value of `320` per GPU.
In `slurm.conf` and `gres.conf` the value of `mps` for the node is `1280` (4 * 320):
 * slurm.conf
```
NodeName=example Gres=gpu:titanrtx:4,mps:1280 ....
```
 * gres.conf
```
NodeName=example Count=1280 Name=mps
```

For slurm we can only use 1 GPU and the `mps` value is `320`:
 * each job has an `--gres=mps:80` then we have 4 dedicated GPU jobs
 * each job has an `--gres=mps:40` then we have 8 GPU jobs
 * each job has an `--gres=mps:32` then we have 10 GPU jobs
 * each job has an `--gres=mps:20` then we have 16 GPU jobs
 * each job has an `--gres=mps:16` then we have 20 GPU jobs
 * ....


In the distribution 3 files are included:
 1. `slurmd/prolog/surf_mps`: Select the least loaded GPU and save the state
 1. `lua.d/surf_mps.lua`        : Manipulates the job cgroup
 1. `slurmd/epilog/surf_mps`: Cleanup the state directory


`Note:` when the [slurm-spank-lua](https://github.com/stanford-rc/slurm-spank-lua) has been compiled with lua version > 5.1. You can only
run 1 lua script. If there is already a lua script installed  then you have to merge the `surf_mps.lua` script.


### Restrict the mps option with cli_filter.lua

At our site we restrict the slurm `mps` option only for certain reservations. Here is a code snippet how we
enforce it with `cli_filter.lua`:
```
if options.gres ~= nil and string.match(options.gres, "mps") then
	if options.reservation == nil then
		slurm.log_info("GRES option:'%s' not allowed", options.gres)
		return slurm.ERROR
	else
		if not(string.match(options.reservation, "jhl_homework_gpu") or string.match(options.reservation, "jupyterhub_course_")) then
			slurm.log_info("GRES option:'%s' not allowed in this reservation:'%s'", options.gres, options.reservation)
			return slurm.ERROR
		end
	end
end
```
