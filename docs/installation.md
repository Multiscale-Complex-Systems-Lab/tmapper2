# Installation

Temporal Mapper 2 is a flat folder of MATLAB functions — there is no build
step, package manager, or installer. You "install" it simply by putting the
`tmapper_tools/` folder on your MATLAB path.

## Requirements

| Requirement | Notes |
| --- | --- |
| **MATLAB** | Tested on **R2024a**. Relies on built-in `digraph`, `distances`, `conncomp`, and `adjacency`. |
| **Statistics and Machine Learning Toolbox** | Provides `pdist2`, `tiedrank`, `rescale`, `prctile`, `zscore`, and `mode`, which the pipeline uses. |

!!! tip "Checking your toolboxes"
    Run `ver` at the MATLAB prompt to list installed toolboxes, or
    `license('test','Statistics_Toolbox')` to check specifically for the
    Statistics and Machine Learning Toolbox (returns `1` if available).

## Get the code

Clone the repository (or download it as a ZIP from GitHub):

```bash
git clone https://github.com/Multiscale-Complex-Systems-Lab/tmapper2.git
```

## Add it to your MATLAB path

From the repository root, add the toolbox folder to the path. This is the one
line every script needs:

```matlab
addpath("tmapper_tools/")   % (1)!
```

1.  This is exactly what `tmapper_demo.m` does at the top. The toolbox is
    unpackaged (no `+namespace`), so a plain `addpath` is all that is required.

To make the toolbox available in every MATLAB session without re-running this,
add the same line to your [`startup.m`](https://www.mathworks.com/help/matlab/ref/startup.html),
using an absolute path to wherever you cloned the repo:

```matlab
addpath("/path/to/tmapper2/tmapper_tools/")
```

## Verify the install

The quickest check is to run the bundled demo from the repository root:

```matlab
tmapper_demo   % builds a network from the sample data and plots it
```

If a figure window opens showing a network graph next to a recurrence plot,
you are ready to go. Head to the **[Quickstart](quickstart.md)** for a
step-by-step walkthrough of what that demo actually does.

!!! note "Optional: run the smoke test"
    A lightweight, dependency-free test of the core pipeline lives in
    `tests/test_core_pipeline.m`. Run it from the repository root with:

    ```bash
    matlab -batch "run('tests/test_core_pipeline.m')"
    ```

    It prints `All tests passed.` on success.
