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


### Quick verification

We suggest the reviewers run Exp#1 and Exp#2 first for a quick verification of our main results. Please see the instructions below.



### Microbenchmarks (Exp#1 in our paper)

#### Exp#1: Effectiveness of different techniques (1 human-minute + ~4 compute-hours / per-round)

*Running:*
```shell
cd scripts/ae
bash run_exp_1.sh
```

*Example results*

```shell
cat ~/Results/exp1_summary.txt
##############################################################
#           Exp#1 (Effectiveness of each technique)          #
##############################################################
Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
hats            workloada       38207.95             501.00          15450.00        83004.00
hats            workloadb       59371.56             482.00          4963.00         53964.00
hats            workloadc       79745.57             384.00          2887.00         50954.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
fineschedule    workloada       26077.41             491.00          40894.00        91634.00
fineschedule    workloadb       47318.10             464.00          9046.00         64198.00
fineschedule    workloadc       50634.65             400.00          7043.00         68820.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
coarseschedule  workloada       25473.63             490.00          43326.00        96299.00
coarseschedule  workloadb       38294.22             485.00          8289.00         75622.00
coarseschedule  workloadc       46416.20             405.00          5355.00         76318.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
mlsm            workloada       21210.32             523.00          48098.00        127600.00
mlsm            workloadb       35036.28             611.00          9807.00         78842.00
mlsm            workloadc       35967.23             525.00          7913.00         239031.00
```

### Macrobenchmarks and system-level analysis (Exp#2-8 in our paper)
#### Exp#2,4,6,7: YCSB synthetic workloads and system-level analysis (1 human-minutes + 10 compute-hours / per-round)
**NOTE: This script is the same as Exp#0, so you don't need to run this one if you tested Exp#0.**

*Running:*
```shell
cd scripts/ae
bash run_exp_2_4_6_7.sh
```

*Example results*
```shell
cat ~/Results/exp2_summary.txt
##############################################################
#         Exp#2 (YCSB synthetic workload performance)        #
##############################################################
Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
hats            workloada       38420.87             502.00          15072.00        84288.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
depart-5.0      workloada       24756.83             588.00          45880.00        102951.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
c3              workloada       17823.78             586.00          57022.00        246852.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
mlsm            workloada       21681.89             505.00          49024.00        118999.00

#################################################################
#       Exp#4 (Latency balance degree across the cluster)       #
#################################################################
Scheme          Workload        Avg CoV
------------------------------------------------
hats            workloada       .28

Scheme          Workload        Avg CoV
------------------------------------------------
depart-5.0      workloada       .33

Scheme          Workload        Avg CoV
------------------------------------------------
c3              workloada       .19

Scheme          Workload        Avg CoV
------------------------------------------------
mlsm            workloada       .16

##############################################################
#                Exp#6 (Performance breakdown)               #
##############################################################
Scheme       Workload     WAL(us)            WriteMemTable(us)  Flushing(us)       Compaction(us)     Selection(us)      ReadMemTable(us)   Caches(us)         Disk(us)
----------------------------------------------------------------------------------------------------------------------------
hats         workloada    8                  11                 7                  38                 183                9                  18                 802
hats         workloadc    0                  0                  0                  0                  90                 1                  1                  96

Scheme       Workload     WAL(us)            WriteMemTable(us)  Flushing(us)       Compaction(us)     Selection(us)      ReadMemTable(us)   Caches(us)         Disk(us)
----------------------------------------------------------------------------------------------------------------------------
depart-5.0   workloada    8                  12                 6                  56                 1013               10                 28                 1389
depart-5.0   workloadc    0                  0                  0                  0                  113                1                  0                  321

Scheme       Workload     WAL(us)            WriteMemTable(us)  Flushing(us)       Compaction(us)     Selection(us)      ReadMemTable(us)   Caches(us)         Disk(us)
----------------------------------------------------------------------------------------------------------------------------
c3           workloada    10                 11                 6                  191                2896               8                  58                 1476
c3           workloadc    0                  0                  0                  0                  793                1                  5                  234

Scheme       Workload     WAL(us)            WriteMemTable(us)  Flushing(us)       Compaction(us)     Selection(us)      ReadMemTable(us)   Caches(us)         Disk(us)
----------------------------------------------------------------------------------------------------------------------------
mlsm         workloada    17                 11                 7                  202                245                9                  59                 2706
mlsm         workloadc    0                  0                  0                  0                  -598               1                  4                  274

##############################################################
#                    Exp#7 (Resource usage)                  #
##############################################################
Scheme       Workload     DiskIO(MiB)        NetworkIO(MiB)     CPU(s)             Memory(GiB)
------------------------------------------------------------------------------------
hats         workloada    36653              13051              1802               5.13
hats         workloadb    15741              5774               1119               5.11
hats         workloadc    12022              4848               845                5.02

Scheme       Workload     DiskIO(MiB)        NetworkIO(MiB)     CPU(s)             Memory(GiB)
------------------------------------------------------------------------------------
depart-5.0   workloada    58936              13868              2300               5.31
depart-5.0   workloadb    52715              7019               1415               5.06
depart-5.0   workloadc    56424              6306               1248               4.80

Scheme       Workload     DiskIO(MiB)        NetworkIO(MiB)     CPU(s)             Memory(GiB)
------------------------------------------------------------------------------------
c3           workloada    121785             16617              3048               5.21
c3           workloadb    37925              12329              1893               5.17
c3           workloadc    36151              12264              1684               5.05

Scheme       Workload     DiskIO(MiB)        NetworkIO(MiB)     CPU(s)             Memory(GiB)
------------------------------------------------------------------------------------
mlsm         workloada    125387             13772              2746               5.54
mlsm         workloadb    57381              5594               1406               5.42
mlsm         workloadc    53932              6294               1162               5.25
```

#### Exp#3: Facebook workload (1 human-minute + ~4 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_3.sh
```

#### Exp#5: Latency distribution at the highest-latency node (1 human-minute + ~1.5 compute-hours / per-round)
*Running:*
```shell
cd scripts/ae
bash run_exp_5.sh
``` 

*Example results:*
```shell
cat ~/Results/exp5_summary.txt
##############################################################
#  Exp#5 (Latency distribution at the highest-latency node)  #
##############################################################
Scheme          Workload        AverageReadLatency(us) Out-of-Range(%)
--------------------------------------------------------------------
hats            workloadb       174.83          5.41

Scheme          Workload        AverageReadLatency(us) Out-of-Range(%)
--------------------------------------------------------------------
depart-5.0      workloadb       280.35          6.79

Scheme          Workload        AverageReadLatency(us) Out-of-Range(%)
--------------------------------------------------------------------
c3              workloadb       2376.43         83.66

Scheme          Workload        AverageReadLatency(us) Out-of-Range(%)
--------------------------------------------------------------------
mlsm            workloadb       2485.36         97.33
```

#### Exp#8: Scalability (1 human-minute + ~4 compute-hours / per-round)
**Note: This experiment requires a larger cluster setup. Although the provided cluster only contains 10 storage nodes, it is already heterogeneous. We recommend you skip this evaluation, or you may need to setup larger cluster by yourself.**

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

*Example results*
```shell
cat ~/Results/exp9_summary.txt
##############################################################
#     Exp#9 (Different read consistency levels)              #
##############################################################
Scheme          Consistency     Throughput(ops/s)    P99(us)
--------------------------------------------------------------------------------
hats            ONE             32868.89             21658.00
hats            TWO             18590.05             43783.00
hats            ALL             14101.05             52704.00

Scheme          Consistency     Throughput(ops/s)    P99(us)
--------------------------------------------------------------------------------
depart-5.0      ONE             24067.27             40897.00
depart-5.0      TWO             16996.59             54829.00
depart-5.0      ALL             13572.68             58021.00

Scheme          Consistency     Throughput(ops/s)    P99(us)
--------------------------------------------------------------------------------
c3              ONE             18741.57             51497.00
c3              TWO             12193.53             70523.00
c3              ALL             9346.30              86431.00

Scheme          Consistency     Throughput(ops/s)    P99(us)
--------------------------------------------------------------------------------
mlsm            ONE             21918.76             49556.00
mlsm            TWO             15892.51             57044.00
mlsm            ALL             11637.40             62409.00
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