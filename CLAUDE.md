# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Temporal Mapper 2 (`tmapper`), developed by Mengsen Zhang, is a MATLAB toolbox that builds a Mapper-algorithm-style **attractor transition network** from time-series data. Each node in the resulting graph represents an attractor/stable state (node size = local stability), and each edge represents an observed transition between states. It generalizes the original fMRI-specific Temporal Mapper (https://github.com/Multiscale-Complex-Systems-Lab/tmapper/) to arbitrary time-series data.

This is a pure MATLAB codebase with **no build system, package manager, linter, test suite, or CI** — none of that tooling exists in this repo. Don't invent commands for build/lint/test; there aren't any to run.

## Running the code

- The toolbox is a flat, unpackaged folder of functions in `tmapper_tools/`. Scripts load it via `addpath("tmapper_tools/")` — there's no `startup.m` or `+namespace` packaging.
- `tmapper_demo.m` (repo root) is the canonical, living reference for correct end-to-end usage — read/run it before making changes to the core pipeline. It loads `sampledata/EL_temp.csv`, builds a transition network, and reproduces the figure at `doc/ELtemp_graph.png`.
- `tests/test_core_pipeline.m` — a lightweight, dependency-free smoke test for the core `tknndigraph`/`filtergraph` pipeline and its input validation. Run with `matlab -batch "run('tests/test_core_pipeline.m')"` (or just open and run it in the MATLAB GUI). It prints `All tests passed.` on success and errors out on the first failing check; run it after touching either of those two functions.
- `gui/TemporalMapperApp.m` — an interactive point-and-click app for the core pipeline (load data, pick variables, set parameters, view the network + recurrence plot, copy generated code reproducing the current build). Built as a classic `figure`/`uicontrol` app (not App Designer/`uifigure`) — a prior `uigridlayout` version hit a real, reproducible `uifigure` rendering bug on a mixed-DPI multi-monitor Windows setup where content would silently fail to paint; classic figures don't share that rendering path. Launch with `addpath("gui/"); app = TemporalMapperApp;`.
- `tests/test_gui_app.m` — smoke test for `gui/TemporalMapperApp.m`: `loadData`/`buildNetwork`/`addColorVarFromWorkspace`/`generateCode` and their input validation, run the same way as `test_core_pipeline.m`; run it after touching the GUI.
- Environment: tested on MATLAB 2024a. Relies on MATLAB's built-in graph/digraph functions (`digraph`, `distances`, `conncomp`, `adjacency`) and Statistics and Machine Learning Toolbox functions (`pdist2`, `tiedrank`, `rescale`, `prctile`, `zscore`, `mode`).

## Core architecture: the two-step pipeline

Data flow: raw time series/state-space data → distance matrix `D` → `tknndigraph` → `filtergraph` → `plottmgraph` / `plotgraphtcm`.

**Step 1 — `tmapper_tools/tknndigraph.m`**: `[g, par] = tknndigraph(D, k, tidx, ...)`
Builds the spatiotemporal k-nearest-neighbor directed graph: one node per time point. Takes a pairwise distance matrix `D` (e.g. `pdist2(X,X)` on raw data `X`), `k` (max spatial neighbors per time point), and `tidx` (time index per sample). Handles excluding temporal neighbors from counting as spatial neighbors (`timeExcludeSpace`/`timeExcludeRange`), optional reciprocity (`reciprocal`), and a max-distance cutoff (`maxNeighborDist`/`maxNeighborDistPrct`), then re-inserts temporal (t→t+1) edges. Related standalone variants: `knngraph.m` (undirected, no temporal component) and `cknngraph.m` (continuous k-NN, density-normalized threshold).

**Step 2 — `tmapper_tools/filtergraph.m`**: `[g_simp, members, nodesize, D_simp] = filtergraph(g, d, 'reciprocal', true)`
The Mapper-style contraction step. Thresholds geodesic distances in `g` at `d`, then takes connected components as the nodes of the simplified graph `g_simp` — this is the attractor transition network. Returns `members` (which original time points map to each new node) and `nodesize` (member counts).

**Visualization**:
- `tmapper_tools/plottmgraph.m` — the core network plot: node size from `nodesizemode` (`rank`/`log`/`original`), node color from `findnodelabel.m` (mode/mean/median aggregation of a per-time-point coloring variable), force-directed layout, optional scatter overlay (`nodescatter`).
- `tmapper_tools/plotgraphtcm.m` — composite wrapper used in the demo: `plottmgraph` (network) plus a geodesic recurrence plot / temporal connectivity matrix from `TCMdistance.m`, side by side. `plotgraphtcm` calls `plottmgraph` internally, so `plottmgraph` is the lower-level primitive.
- `tmapper_tools/subgraphFromMembers.m` — extracts a subgraph restricted to a subset of original time points, for zooming into specific epochs post-hoc.

Small numeric helpers (`normgeo.m`, `normtcm.m`, `nodesize.m`, `nodemeasure.m`, `weightedAdj.m`, `zerodiag.m`, `digraph2graph.m`, `symDyn2digraph.m`) support the above and are generally called internally rather than directly by users.

### Secondary toolkit: cycle/path analysis

An optional, more advanced extension (referenced in `tmapper_demo.m`'s closing comment) for analyzing the topology of the resulting transition network by enumerating and clustering cycles: `CycleCount.m`/`CycleCount2p.m` (enumerate simple cycles), `reorgCycles.m`, `CyclePathOverlap.m`, `CycleCluster.m`/`CycleClusterConn.m`, `CycleCutter.m`, `Cycles2Paths.m`, `CyclePathDecomp.m`, `pathtraffic.m` (traffic/flow along paths), and `Qasym.m`/`calMod.m` (modularity of community structure). This is not part of the core two-step pipeline.

## Citation

Zhang, M., Chowdhury, S., & Saggar, M. (2023). [Temporal Mapper: transition networks in simulated and real neural dynamics](https://doi.org/10.1162/netn_a_00301). *Network Neuroscience*, 7(2): 431–460.
