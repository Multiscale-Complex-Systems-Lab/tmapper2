# Quickstart

This walkthrough builds an attractor transition network end to end and
reproduces the figure on the [home page](index.md). It mirrors the bundled
`tmapper_demo.m` script step by step, so you can either read along or open that
script and run it section by section.

The sample data is a slice of historical **East Lansing daily weather**
(temperature and precipitation), included in the repo at
`sampledata/EL_temp.csv`.

!!! tip "Just want to run it?"
    From the repository root, run `tmapper_demo` to execute every step below at
    once. This page explains what each step is doing and why.

## Step 0 — Add the toolbox to the path

Everything starts by putting the toolbox functions on the MATLAB path:

```matlab
addpath("tmapper_tools/")
```

## Step 1 — Load and select the data

Read the sample table, drop rows with missing values, and keep a recent slice
for a manageable demo:

```matlab
dat = readtable(fullfile('sampledata','EL_temp.csv'));
dat = rmmissing(dat);          % remove rows with missing data
dat = dat(53884:end,:);        % keep a recent slice for the demo
```

Next, choose which columns define the **state** of the system. Here we take
three weather variables and `zscore` them so dimensions with different units
are comparable:

```matlab
varidx = 3:5;                          % (1)!
X = zscore(dat{:,varidx});             % rows = time points, cols = state variables
t = dat.Date;                          % a time value per row
varnames = string(dat.Properties.VariableNames(varidx));
```

1.  `X` must be organized as **rows = time points, columns = state variables**.
    That convention holds throughout the toolbox.

!!! note "Why z-score?"
    Z-scoring puts each variable on a common scale so that one high-variance
    dimension does not dominate the distance computation. It is a sensible
    default, not a hard requirement — skip it if your variables are already
    comparable.

## Step 2 — (Optional) Delay embedding

When data is low-dimensional, distinct dynamical states can overlap and become
hard to separate. A quick fix is **delay embedding**: augment each time point
with a copy of the state from some time earlier (here, 90 days), lifting the
data into a higher-dimensional space where states separate more cleanly.

```matlab
X = [X(1:end-89,:) X(90:end,:)];   % concatenate current state with the 90-day-lagged state
t = t(90:end);                     % align the time vector to match
```

!!! tip "Is this always needed?"
    No. Delay embedding helps when your state space is too compressed to
    distinguish attractors. For richer, higher-dimensional data you can skip
    this step entirely.

## Step 3 — Build the distance matrix

Temporal Mapper works from a **pairwise distance matrix** `D`, where `D(i,j)`
is the distance between the state at time `i` and the state at time `j`. This
is exactly a classical recurrence plot. Here we use Euclidean distance
(Minkowski with `p = 2`):

```matlab
p = 2;                                 % 2 = Euclidean distance
D = pdist2(X,X,'minkowski',p);         % N-by-N pairwise distance matrix
```

## Step 4 — Build the spatiotemporal graph

Now the first step of the pipeline. [`tknndigraph`](#step-4-build-the-spatiotemporal-graph)
turns the distance matrix into a directed *k*-nearest-neighbor graph — one node
per time point — while preserving temporal order.

```matlab
% --- construction parameters
k = 3;              % (1)!  max number of spatial neighbors per time point
texclude = 30;      % (2)!  temporal window (in time points) excluded from being "spatial" neighbors
maxdistprct = 95;   % (3)!  neighbor cutoff by percentile of all distances
maxdist = 0.5;      % (4)!  neighbor cutoff by absolute distance (the tighter of the two wins)

tidx = (1:length(t))';   % integer index per time point, used to define temporal neighborhoods

[g, par] = tknndigraph(D, k, tidx, ...
                'timeExcludeRange', texclude, ...
                'maxNeighborDistPrct', maxdistprct, ...
                'maxNeighborDist', maxdist);
```

1.  **`k`** — the maximum number of spatial (nearest-neighbor) links each time
    point may form. Larger `k` produces a denser graph.
2.  **`texclude`** — points within this many steps in time are treated as
    temporal neighbors and are *not* allowed to also count as spatial
    neighbors. This prevents "recurrence" being trivially detected between
    adjacent moments. `1` is a common default; the demo uses `30`.
3.  **`maxNeighborDistPrct`** — a distance cutoff expressed as a percentile of
    all pairwise distances (95 = ignore the most distant 5% as neighbors).
4.  **`maxNeighborDist`** — the same cutoff as an absolute distance. When both
    are given, the **smaller** (stricter) threshold is applied.

The output `g` is a MATLAB `digraph` with one node per time point; `par`
records the parameters actually used (handy for reading back the resolved
distance cutoff).

## Step 5 — Simplify into the transition network

The second step contracts the fine-grained graph into the attractor transition
network. [`filtergraph`](#step-5-simplify-into-the-transition-network) collapses
time points that lie within distance `d` of one another into a single node.

```matlab
d = 3;   % compression threshold: loops shorter than this are absorbed into a node

[g_simp, members, nodesize, D_simp] = filtergraph(g, d, 'reciprocal', true);
```

This returns everything you need to describe and plot the network:

| Output | Meaning |
| --- | --- |
| `g_simp` | the simplified graph — **this is the attractor transition network** |
| `members` | which original time points map into each new node |
| `nodesize` | number of member time points per node (a proxy for stability) |
| `D_simp` | shortest "distances" between the groups of members |

!!! note "What `reciprocal` does"
    With `'reciprocal', true`, two time points are only merged when the short
    path holds in **both** directions (x→y *and* y→x). This is the stricter,
    recommended setting for directed graphs.

## Step 6 — Visualize

Finally, plot the network alongside its recurrence plot. First pick a variable
to color the nodes — any per-time-point quantity works; here we use the daily
maximum temperature, `tmax`:

```matlab
colorvarname = 'tmax';
colorvar = dat{:,colorvarname};

[a1, a2, ~, ~, hg, D_geo] = plotgraphtcm(g_simp, colorvar, t, members, ...
    'nodesizerange', [1,10], ...
    'colorlabel', colorvarname, ...
    'labelmethod', 'median', ...
    'nodesizemode', 'log');

title(a1, ["sample data", "k=" + k + ", d=" + d, ...
           "tx=" + texclude + ", maxdist=" + par.maxNeighborDist])
```

You should now see the attractor transition network on the left and the
geodesic recurrence plot on the right — the same figure shown on the
[home page](index.md).

## What's next

- Try changing **`k`** and **`d`** and watch how the network coarsens or
  fragments — these two parameters control the resolution of the result.
- Swap in your **own data**: organize it as rows = time points, columns = state
  variables, build `D` with `pdist2`, and run the same two-step pipeline.
- The toolbox also includes a cycle/path analysis toolkit (e.g. `CycleCount2p`)
  for probing the topology of the resulting network — a natural next
  exploration once you have a transition network you like.
