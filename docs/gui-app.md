# Interactive App

`gui/TemporalMapperApp.m` is a point-and-click alternative to the scripted
pipeline in the [Quickstart](quickstart.md) — load data, pick variables, set
parameters, and view the resulting network without writing any code. It wraps
exactly the same two-step pipeline (`tknndigraph` → `filtergraph`) and the same
plotting functions (`plottmgraph`/`plotgraphtcm`) described elsewhere in these
docs, so everything in [Concepts](concepts.md) about what the parameters mean
still applies.

![The app after building a network from the East Lansing weather data, using the same parameters as the Quickstart.](assets/app-screenshot.png)
/// caption
The same East Lansing weather dataset and parameters as the
[Quickstart](quickstart.md), built through the app instead of the command
line.
///

## Launch it

```matlab
addpath("tmapper_tools/")
addpath("gui/")
app = TemporalMapperApp;
```

## Layout

The window is split into two parts: four **Setup** panels across the top, and
the **Network**/recurrence plots filling the rest of the window.

### Data

Load a data file (`.csv`/`.txt`, read with `readtable`) or a table/numeric
matrix already sitting in your base workspace. Only numeric columns are
offered as build variables. This panel also holds **Build Network**, **Stop**
(cancels an in-progress build — see [below](#stop-cancels-between-not-mid-stage)),
**Reset** (restores every parameter to its default, but leaves your loaded
data and variable selection alone), **Copy Code**, and a live **Status** box
with per-step timing once a build finishes.

### Variables & Preprocessing

- **Variables** — the numeric columns to build the network from (⌘/Ctrl/Shift-click for multiple; **Select All** as a shortcut).
- **z-score variables** — on by default; see the Quickstart's [note on why](quickstart.md#step-1-load-and-select-the-data).
- **start row / end row** — restrict the build to a sub-range of the loaded data. `end row = Inf` means "the last row."
- **downsample (N)** — keep every Nth row. A moving-average lowpass is applied first so this doesn't alias high-frequency content into spurious low-frequency structure — see [below](#missing-data-and-downsampling).
- **embed lag / embed order** — optional [delay embedding](quickstart.md#step-2-optional-delay-embedding); order `1` (default) skips it.

### Network Parameters

The four `tknndigraph`/`filtergraph` parameters explained in the
[Quickstart](quickstart.md#step-4-build-the-spatiotemporal-graph) and
[Concepts](concepts.md): **k**, **d** (labeled "compression"), **texclude**,
the two **max dist** cutoffs, and **reciprocal**.

### Plot Options

Color/time axis variable, node size mode, label method, and whether to show
the recurrence plot / a node-border scatter overlay. Changing any of these
**re-renders the existing network instead of rebuilding it** — cheap, and
safe to click through freely once a build has completed.

## Missing data and downsampling

Two things the scripted pipeline leaves to you are handled automatically here:

!!! note "Missing data is dropped, not ignored"
    Rows with a missing value in any selected variable are dropped
    automatically before building (the status area reports exactly how many),
    rather than being silently passed through the pipeline — an unremoved
    `NaN` here would poison the entire distance matrix without any visible
    error. Calling `tknndigraph`/`plottmgraph` directly on unclean data
    still raises an error, per the usual `rmmissing`-first convention.

!!! note "Downsampling anti-aliases first"
    Setting `downsample (N) > 1` applies a moving-average lowpass over a
    window of size N before striding, rather than naively picking every Nth
    raw row.

## Stop cancels between, not mid-stage

**Stop** requests cancellation, but MATLAB callbacks run synchronously, so it
only takes effect at the boundary between stages (distances → k-NN graph →
simplify) — not mid-computation within one. For a very slow single stage
(usually the distance/k-NN step on a large dataset), it may take a moment to
actually stop.

## Copy Code

**Copy Code** puts a complete, standalone script on the clipboard that
reproduces the current build — including the data-loading line if you loaded
a file — using the exact resolved parameters shown in the app. This is the
bridge back to scripting: prototype interactively here, then paste the
generated code into your own analysis once you have parameters you like.

## What's next

- [Concepts](concepts.md) — what the network's nodes, edges, and loops mean.
- [Quickstart](quickstart.md) — the same pipeline, scripted end to end.
