# Temporal Mapper 2

**Temporal Mapper 2** (`tmapper`) is a MATLAB toolbox that turns time-series data
into an **attractor transition network** — a compact graph that captures the
stable states of a dynamical system and the transitions between them, using
nothing but the time series itself.

It generalizes the original, fMRI-specific
[Temporal Mapper](https://github.com/Multiscale-Complex-Systems-Lab/tmapper/)
into a general-purpose tool for characterizing complex dynamics across
disciplines and data types.

![An attractor transition network built from East Lansing weather data.](assets/ELtemp_graph.png){ width="480" }
/// caption
An attractor transition network built by Temporal Mapper from historical East
Lansing weather data. You will reproduce this figure in the [Quickstart](quickstart.md).
///

## What it produces

Given a time series, Temporal Mapper returns a directed graph in which:

- each **node** is an attractor (a stable state the system settles into),
- the **size** of a node reflects the local stability of that attractor (how many time points collapse into it), and
- each **edge** is an observed transition from one attractor to another.

## How it works

Under the hood the computation is a two-step pipeline. You can read the full
rationale in the [paper](#citation); the short version is:

!!! note "Step 1 — spatiotemporal neighborhood graph"
    Starting from a pairwise **distance matrix** `D` between all time points,
    [`tknndigraph`](quickstart.md#step-4-build-the-spatiotemporal-graph) builds
    a directed *k*-nearest-neighbor graph with one node per time point, adding
    back the temporal (t → t+1) links so the flow of time is preserved.

!!! note "Step 2 — simplified transition network"
    [`filtergraph`](quickstart.md#step-5-simplify-into-the-transition-network)
    contracts time points that sit within a distance `d` of each other into a
    single node. The connected components become the nodes of the final
    attractor transition network.

Two parameters do most of the work: **`k`** (how many spatial neighbors each
time point may have) and **`d`** (the compression threshold — loops shorter than
this are absorbed into a node). The [Quickstart](quickstart.md) walks through
both on real data.

## Where to go next

- **[Installation](installation.md)** — add the toolbox to your MATLAB path and check dependencies.
- **[Quickstart](quickstart.md)** — build your first transition network end to end, reproducing the figure above.

## Citation

If you use this toolbox in your work, please cite:

> Zhang, M., Chowdhury, S., & Saggar, M. (2023).
> [Temporal Mapper: transition networks in simulated and real neural dynamics](https://doi.org/10.1162/netn_a_00301).
> *Network Neuroscience*, 7(2): 431–460.
