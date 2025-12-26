# Instructions to reproduce the evaluations of the paper

Here are the detailed instructions to perform the same experiments in our paper.

## Artifact claims

We claim that the results might differ from those in our paper due to various factors (e.g., cluster sizes, hardware specifications, OS, software packages, etc.). 
**The hardware in the provided testbeds is not identical to that used for the original paper; for example, we replaced some broken nodes and faulty SSDs with healthy ones, so the provided cluster is heterogeneous.** These changes may cause performance to vary from the results originally published. Nevertheless, we expect HATS will continue to outperform its baselines.


## Testbed setup

> **For FAST'26 AE reviewers**, please use the provided testbeds to reproduce the evaluations directly. These testbeds come equipped with **pre-loaded datasets and pre-deployed software**, which will significantly reduce setup time and help avoid potential configuration issues. **Please contact us via HotCRP website for instructions on how to log into the testbeds**.

If you want to configure the testbed from scratch, please refer to [./README.md](./README.md).

### Load the datasets (Optional)

If you really want to load the datasets by yourself, you can use the following commands to load the YCSB and Facebook datasets.

```shell
cd scripts/ae
bash load_ycsb.sh # for ycsb benchmark
bash load_fb.sh # for facebook workload
```
Please modify the script if you want to change the dataset size or other parameters. The default settings for the YCSB benchmarks contain 100M KV pairs for YCSB workloads, 3-way replication, key size of 24 bytes, and value size of 1000 bytes. The main parameters are defined in the above scripts, which contains:
```shell
SCHEMES=("mlsm" "depart-5.0") # The schemes to be tested. Note that mLSM, HATS, and C3 share the same underlying data loading process, so we only need to load the data once for them.
CLUSTER_NAMES=("1x") # The cluster names defined in settings.sh, it contains the information of the nodes in the cluster.
REPLICAS=(3) # Number of replicas
KV_NUMBER=100000000 # number of KV pairs
FIELD_LENGTH=(512 1000 2048) # value size in bytes
KEY_LENGTH=24 # key size in bytes
REBUILD_SERVER="true" # whether to rebuild the server before loading data
WAIT_TIME=3600 # wait time (in seconds) after loading data to make sure the LSM-tree are fully compacted
```

## Evaluations

This section describes how to reproduce the evaluations in our paper. To simplify the reproduction process, we provide Ansible-based scripts to run all the experiments. The script will automatically run the experiments and generate the result logs. 
> **The scripts will take ~45 days to finish all the experiments. We suggest running the scripts of Exp#0 first, which can reproduce the main results of our paper while including most of the functionality verification.**

Note on the experiment scripts:
- **How to avoid interruptions?** These evaluation scripts require a long time to run. To avoid the interruption of the experiments, we suggest running the scripts in the background with `tmux`, `nohup`, `screen`, etc.
    - We suggest using `tmux` to run the scripts. You can create a new tmux session via `tmux new -s control`, run the script inside the tmux session, and then detach the session via `Ctrl+b d`. You can re-attach the session later via `tmux attach -t control`.
- **How to modify the experiment settings?** You can modify the experiment settings by changing the parameters in the corresponding script files. The configurable parameters include:
    - `REBUILD_SERVER`: Whether to rebuild the server before running the experiment.
    - `SCHEMES`: The schemes to be tested. You can add or remove the schemes in the list.
    - `CLUSTER_NAMES`: The cluster names defined in `settings.sh`, which contains the information of the nodes in the cluster.
    - `REPLICAS`: Number of replicas.
    - `KV_NUMBER`: Number of KV pairs.
    - `KEY_LENGTH`: Key size in bytes.
    - `OPERATION_NUMBER`: Number of operations to be issued in each workload.
    - `ROUNDS`: Number of rounds to run for each workload. The default value is 1. If the value is larger than 1, the script will run multiple rounds and report the average results.
    - `CONSISTENCY_LEVEL`: Read consistency level. (Exp#9)
    - `REQUEST_DISTRIBUTIONS`: The key distribution to be used in the experiment. (Exp#10)
    - `FIELD_LENGTH`: Value size in bytes. (Exp#11)
    - `THREAD_NUMBER`: Number of client threads in each client machine to be used in the experiment. (Exp#12)

- **Where are the experiment results stored?** The experiment results will be stored in the `~/Results/` directory on the control node. Each experiment will be logged in a separate file named `exp#_summary.txt`, where `#` is the experiment number.


### Quick verification (Exp#0: quick verification)

#### Exp#0: Quick verification (1 human-minute + ~10 compute-hours / per-round)

We provide this quick verification experiment to verify our main experimental results quickly.
Specifically, we use 100M KV pairs to run the six YCSB core workloads (A-F), issue 50M operations per workload and run 1 round for each workload.
This experiment will provide the throughput and latency results of HATS and the baselines across the six workloads (Exp#2), latency balance degree across the cluster (Exp#4), the performance breakdown of each system (Exp#6), and the resource usage of each system (Exp#7) in our paper.

Your can run this quick verification experiment via the following command:

```shell
cd scripts/ae
bash run_exp_0.sh
```

The results will be output in the order shown below:

```shell
##############################################################
#         Exp#2 (YCSB synthetic workload performance)        #
##############################################################

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
hats            workloada       35582.62             511.00          17961.00        87876.00
hats            workloadb       63414.59             462.00          4478.00         47517.00
hats            workloadc       85284.35             389.00          2524.00         34908.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
depart-5.0      workloada       23645.64             606.00          48847.00        107652.00
depart-5.0      workloadb       34774.57             685.00          7869.00         87121.00
depart-5.0      workloadc       36652.16             663.00          4829.00         226130.00
...

#################################################################
#       Exp#4 (Latency balance degree across the cluster)       #
#################################################################
Scheme          Workload        Avg CoV
------------------------------------------------
hats            workloada       .26
hats            workloadb       .28
hats            workloadc       .10

##############################################################
#                Exp#6 (Performance breakdown)               #
##############################################################
Scheme       Workload     LocalRead(us)      Selection(us)      WriteMem(us)       WriteWAL(us)       Flush(us)          Compaction(us)     ReadCache(us)      ReadMem(us)        ReadSST(us)
----------------------------------------------------------------------------------------------------------------------------
hats         workloada    934                225                11                 9                  8                  47                 21                 9                  894
hats         workloadc    88                 52                 0                  0                  0                  0                  1                  1                  69

##############################################################
#                    Exp#7 (Resource usage)                  #
##############################################################
Scheme       Workload     DiskIO(MiB)        NetworkIO(MiB)     CPU(s)             Memory(GiB)
------------------------------------------------------------------------------------
hats         workloada    38347              15130              1898               4.73
hats         workloadb    12370              6105               1073               4.67
hats         workloadc    10221              5043               790                4.62
...
```

### Microbenchmarks (Exp#1 in our paper)

#### Exp#1: Effectiveness of different techniques (1 human-minute + ~4.2 compute-hours / per-round)

*Running:*
```shell
cd scripts/ae
bash run_exp_1.sh
```

### Macrobenchmarks and system-level analysis (Exp#2-8 in our paper)
#### Exp#2,4,6,7: YCSB synthetic workloads and system-level analysis (1 human-minutes + 10 compute-hours / per-round)
**NOTE: This script is the same as Exp#0, so you don't need to run this one if you tested Exp#0.**

*Running:*
```shell
cd scripts/ae
bash run_exp_2_4_6_7.sh
```

#### Exp#3: Facebook workload (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_3.sh
```

#### Exp#5: Latency distribution at the highest-latency node (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_5.sh
``` 

#### Exp#8: Scalability (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_8.sh
``` 

### Parameter Analysis (Exp#9-12 in our paper)

#### Exp#9: Different read consistency levels (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_9.sh
```

#### Exp#10: Impact of key distribution (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_10.sh
```

#### Exp#11: Impact of value size (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_11.sh
```

#### Exp#12: Impact of system saturation levels (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_12.sh
```