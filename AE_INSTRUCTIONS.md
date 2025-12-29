# Instructions to reproduce the evaluations of the paper

Here are the detailed instructions to perform the same experiments in our paper.

## Artifact claims

We claim that the results might differ from those in our paper due to various factors (e.g., cluster sizes, hardware specifications, OS, software packages, etc.). 
**The hardware in the provided testbeds is not identical to that used for the original paper; for example, we replaced some broken nodes and faulty SSDs with healthy ones, and the provided cluster is heterogeneous.** These changes may cause performance to vary from the results originally published. Nevertheless, we expect HATS will continue to outperform its baselines.


## Testbed setup

**For FAST'26 AE reviewers**, please use the provided testbeds to reproduce the evaluations directly. These testbeds come equipped with **pre-loaded datasets and pre-deployed software**, which will significantly reduce setup time and help avoid potential configuration issues. **Please contact us via HotCRP website for instructions on how to log into the control node of our testbed**.
> Our provided testbed contains 1 control node, 2 client nodes, and 10 storage nodes connected via a 10Gbps switch. The testbed configuration is as follows: the client nodes match those in the original paper, while the control node has the same specifications as the client nodes. All storage nodes are equipped with quad-core Intel CPUs of different models (ranging from 5th to 7th generation); 9 nodes have 16GB RAM and 1 has 32GB RAM; 9 nodes use 128GB SATA SSDs and 1 node uses a 256GB NVMe SSD. All other settings remain the same as the original paper.

## Evaluations

This section describes how to reproduce the evaluations in our paper. To simplify the reproduction process, we provide Ansible-based scripts to run all the experiments. The script will automatically run the experiments and generate the result logs. 
> **Since running the complete set of experiments as described in the paper would take approximately 45 days, we have set the `ROUNDS` parameter to 1 for all experiments to significantly reduce the overall runtime.**

Note on the experiment scripts:
- **How to avoid interruptions?** These evaluation scripts require a long time to run. To avoid the interruption of the experiments, we suggest using `tmux` to run the scripts. You can create a new tmux session via `tmux new -s control`, run the script inside the tmux session, and then detach the session via `Ctrl+b d`. You can re-attach the session later via `tmux attach -t control`.
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
hats            workloada       38105.22             511.00          14894.00        82891.00
hats            workloadb       64511.30             454.00          4488.00         47324.00
hats            workloadc       85585.66             383.00          2740.00         25307.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
fineschedule    workloada       26467.06             505.00          40821.00        89529.00
fineschedule    workloadb       61523.92             450.00          4874.00         51305.00
fineschedule    workloadc       87352.41             378.00          2448.00         28302.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
coarseschedule  workloada       24265.55             485.00          43331.00        115625.00
coarseschedule  workloadb       57923.33             480.00          5424.00         51959.00
coarseschedule  workloadc       86480.35             377.00          2626.00         29114.00

Scheme          Workload        Throughput(ops/s)    P50(us)         P99(us)         P999(us)
--------------------------------------------------------------------------------
mlsm            workloada       21863.04             526.00          48082.00        124408.00
mlsm            workloadb       49844.68             546.00          6234.00         58124.00
mlsm            workloadc       42022.03             506.00          4277.00         242298.00
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
Scheme          Workload        Avg CoV              Latency Standard Deviation(us)
--------------------------------------------------------------------
hats            workloada       .30                  264.70
hats            workloadb       .25                  32.93
hats            workloadc       .13                  9.32

Scheme          Workload        Avg CoV              Latency Standard Deviation(us)
--------------------------------------------------------------------
depart-5.0      workloada       .28                  491.32
depart-5.0      workloadb       .25                  109.44
depart-5.0      workloadc       .33                  130.97

Scheme          Workload        Avg CoV              Latency Standard Deviation(us)
--------------------------------------------------------------------
c3              workloada       .41                  473.10
c3              workloadb       .19                  36.71
c3              workloadc       .25                  26.60

Scheme          Workload        Avg CoV              Latency Standard Deviation(us)
--------------------------------------------------------------------
mlsm            workloada       .27                  655.23
mlsm            workloadb       .40                  195.11
mlsm            workloadc       .28                  69.18

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

This experiment requires loading new datasets with different value sizes.
You can run the provided script to load the datasets directly, which will take around 12 hours.
```shell
cd scripts/ae
bash load_ycsb.sh # make sure the FIELD_LENGTH=(512 2048) in the script, since we have already loaded the datasets with value size of 1000 bytes.
```

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

## Others

### Load the datasets (Skip this for FAST'26 AE reviewers)

We already pre-loaded all the datasets. If you really want to load the datasets by yourself, you can use the following commands to load the YCSB and Facebook datasets. **Please modify the script if you want to change the dataset size or other parameters. The default settings for the YCSB benchmarks contain 100M KV pairs for YCSB workloads, 3-way replication, key size of 24 bytes, and value size of 1000 bytes. Refer to the `Parameters` section for more details.**

```shell
cd scripts/ae
bash load_ycsb.sh # for ycsb benchmark
bash load_fb.sh # for facebook workload
```
### Parameters

You can modify the experiment settings by changing the parameters in the corresponding script files. The configurable parameters include:

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