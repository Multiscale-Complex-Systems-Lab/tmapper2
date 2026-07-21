# Temporal Mapper 2
Here is **Temporal Mapper 2** developed by Mengsen Zhang. This version improves upon the original toolbox by adding a few new parameters to accommodate application across disciplines and data types. While the [original Temporal Mapper](#previous-versions) was designed for fMRI data, it turns out to be also useful to understanding dynamics in other systems and modalities. Thus, Temporal Mapper is designed to be a more general-purpose tool for characterizing complex dynamics. 

**Full documentation, tutorials, and worked examples:** https://multiscale-complex-systems-lab.github.io/tmapper2/

## How does it work
Technical details can be found in [the paper](#citation). Briefly, Temporal Mapper is designed to capture attractor (stable state) and phase transitions in high-dimensional dynamical systems as an attractor transition network from only time series data. In the transition network, each node represent an attractor. The weight of the node indicates the local stability of the attractor. Each edge reflect an transition from one attractor to another. The computation takes two steps:

## Getting started
Add the toolbox functions to your MATLAB path:
```Matlab
addpath("tmapper_tools/")
```

### Step 1: construct spatiotemporal neighborhood graph
You will first need a distance matrix `D` which gives the pairwise distance between every two time points. `k` is the maximal number of spatial neighbors each time point will have. `tidx` is integer indices of each time point. By calling the function below, you will get a directed graph `g`, where each node is a time point. This is the spatiotemporal neighborhood graph. 

```Matlab
g = tknndigraph (D,k,tidx);
```
If you just have the time series `X` (rows: time points, columns: state variables), you can get Euclidean distance matrix `D` as below.
```
D = pdist2(X,X);
```

### Step 2: simplified transition network
In a second step, time points that are closely connected to each other (within a distance `d`) in the spatiotemporal neighborhood graph `g` get contracted to a single node. 

```Matlab
[g_simp, members] = filtergraph(g,d);
```
You will get the simplied graph `g_simp` as the attractor transition networks. `members` tell you which time points is mapped to each node. 

## Visualization
Once you have the graph, you can plot it with `plottmgraph` as below. To make it more interest, you want to have a coloring variable `colorvar`, which assigns each time point a scaler value (this could be simply one of the state variables.) 

```Matlab
figure;
plottmgraph(g_simp,colorvar,members);
```
You will get some that look like this.
![ELtemp](doc/ELtemp_graph.png)

You can follow the [full tutorial code](tmapper_demo.m) to generate this picture yourself!

If you'd also like to see a recurrence plot (temporal connectivity matrix) alongside the network, use `plotgraphtcm` instead -- it plots both side by side in one figure:
```Matlab
plotgraphtcm(g_simp,colorvar,t,members);
```
where `t` is the actual time (or a time index) associated with each time point.

## Advanced: cycle and path analysis
Beyond the core two-step pipeline above, `tmapper_tools/` also includes a set of functions for analyzing the topology of the resulting transition network, by enumerating and clustering cycles (e.g. `CycleCount2p`, `CyclePathDecomp`).

## Running tests
A regression test suite lives in `tests/`. To check that your setup is working (or to verify any changes you make), run any test script directly, e.g.:
```Matlab
run('tests/test_core_pipeline.m')
```
Each script prints `All tests passed.` on success.

## Dependencies
The code has been tested on MATLAB 2024a, and requires the Statistics and Machine Learning Toolbox (for functions such as `pdist2`).

## Citation
If you have used the code for your project, please cite:

Zhang, M., Chowdhury, S., & Saggar, M. (2023). [Temporal Mapper: transition networks in simulated and real neural dynamics](https://doi.org/10.1162/netn_a_00301). *Network Neuroscience*, 7 (2): 431–460.

## License
This project is licensed under the BSD 3-Clause License -- see [LICENSE](LICENSE) for details.

## Previous versions

The original version of the Temporal Mapper can be found [here](https://github.com/Multiscale-Complex-Systems-Lab/tmapper/).
