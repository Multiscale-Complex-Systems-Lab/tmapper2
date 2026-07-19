%TEST_CYCLEPATH smoke test for CyclePathDecomp on a small, deterministic
%   digraph with two simple cycles sharing one node. Exercises both the
%   non-plotting path and the full plotting path (addDiagBlock /
%   findtaskn / remapRange chain). Run this script directly in MATLAB;
%   it prints "All tests passed." on success and errors out on the first
%   failing check.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));

% -- two simple cycles sharing node 3: 1->2->3->1 and 3->4->5->3
A = zeros(5);
A(1,2) = 1; A(2,3) = 1; A(3,1) = 1;
A(3,4) = 1; A(4,5) = 1; A(5,3) = 1;
dg = digraph(A);

% -- core decomposition logic only, no plotting
[allbd1,pclusters_nodes1,~,~,~,~,allupath1,Tp1] = CyclePathDecomp(dg,...
    'plotmat',false,'plotmds',false,'plothist',false);
close all

assert(~isempty(allbd1), 'expected at least one boundary node.');
assert(ismember(3,allbd1), 'node 3 (shared between the two cycles) should be a boundary node.');
assert(numel(pclusters_nodes1) == max(Tp1), ...
    'path-cluster count should match the number of unique cluster labels.');
assert(~isempty(allupath1), 'expected at least one decomposed path.');

% -- full plotting path: exercises addDiagBlock -> findtaskn/remapRange
[allbd2,~,~,~,~,~,~,Tp2] = CyclePathDecomp(dg,...
    'plotmat',true,'plotmds',false,'plothist',false);
close all

assert(isequal(allbd1,allbd2), ...
    'enabling plotmat should not change the boundary-node result.');
assert(isequal(Tp1,Tp2), ...
    'enabling plotmat should not change the path clustering result.');

% -- CyclePathDecomp edge case: acyclic graph (no cycles at all). Previously
% crashed inside CycleCluster's linkage() call (0 observations) and then
% again inside Cycles2Paths (vertcat of zero elements collapsing to a
% plain empty double). Now returns trivial empty results.
dg_acyclic = digraph([1 2 3],[2 3 4]); % chain, no cycles
[allbd_acyclic,pcn_acyclic,~,~,~,~,allupath_acyclic,Tp_acyclic] = CyclePathDecomp(dg_acyclic,...
    'plotmat',false,'plotmds',false,'plothist',false);
close all
assert(isempty(allbd_acyclic), 'an acyclic graph should have no boundary nodes.');
assert(isempty(pcn_acyclic), 'an acyclic graph should have no path clusters.');
assert(isempty(allupath_acyclic), 'an acyclic graph should have no decomposed paths.');
assert(isempty(Tp_acyclic), 'an acyclic graph should have no cluster labels.');

% -- CyclePathDecomp edge case: a single isolated cycle (no sharing with
% anything else). Previously crashed inside CycleClusterConn due to a
% length mismatch between allcycles (1 cycle) and clusterIdx (which came
% back with 2 elements from a degenerate 1-observation linkage/cluster
% call). Now CycleCluster short-circuits for Nc<=1 and returns cleanly.
dg_single = digraph([1 2 3],[2 3 1]); % single 3-cycle: 1->2->3->1
[allbd_single,pcn_single,~,~,~,~,allupath_single,Tp_single] = CyclePathDecomp(dg_single,...
    'plotmat',false,'plotmds',false,'plothist',false);
close all
assert(isempty(allbd_single), 'a single isolated cycle has no boundary (nothing to share with).');
assert(numel(pcn_single) == 1, 'a single isolated cycle should form exactly one path cluster.');
assert(max(Tp_single) == 1, 'a single isolated cycle should have exactly one cluster label.');

% -- CyclePathDecomp edge case: merge-threshold-exceeded. The two cycles
% in the main 5-node graph overlap by exactly 1/5=0.2 (shared node 3 only).
% The default clusterthres=0.5 keeps them separate (tested above via
% ismember(3,allbd1)); a lower threshold (0.1 < 0.2) should merge them
% into a single cluster instead. This also exercises the CycleCutter fix
% (no boundary nodes to cut at once everything is one cluster).
[allbd_merged,pcn_merged,~,~,~,~,~,Tp_merged] = CyclePathDecomp(dg,...
    'plotmat',false,'plotmds',false,'plothist',false,'clusterthres',0.1);
close all
assert(max(Tp_merged) == 1, 'a lower clusterthres should merge the two cycles into one cluster.');
assert(numel(pcn_merged) == 1, 'merging should leave exactly one path cluster.');

% -- CycleCutter directly: the no-cutting-point branch must return a cell
% array (its documented contract), not the raw cycle array -- this was
% the root cause of the Cycles2Paths crash in the merge-exceeded case
% above.
cut_result = CycleCutter([1 2 3], []);
assert(iscell(cut_result) && isequal(cut_result, {[1 2 3]}), ...
    'CycleCutter with no cutting points should return the cycle wrapped in a 1x1 cell.');

% -- CycleCount: directed triangle (1->2->3->1) should have exactly one
% 3-cycle and no shorter cycles.
A_tri = zeros(3); A_tri(1,2)=1; A_tri(2,3)=1; A_tri(3,1)=1;
Primes_tri = CycleCount(A_tri,3);
% CycleCount uses eig() internally, so results carry tiny floating-point
% residue (e.g. 1.0000000000000002) -- compare with a tolerance, not isequal.
assert(max(abs(Primes_tri - [0 0 1])) < 1e-8, 'CycleCount on a directed triangle should give Primes=[0,0,1].');

% -- CycleCount: mutual pair (1<->2) should have exactly one 2-cycle.
A_pair = zeros(2); A_pair(1,2)=1; A_pair(2,1)=1;
Primes_pair = CycleCount(A_pair,2);
assert(max(abs(Primes_pair - [0 1])) < 1e-8, 'CycleCount on a mutual pair should give Primes=[0,1].');

% -- CycleCount vs CycleCount2p cross-check on the main 5-node two-triangle
% graph: both should agree that there are exactly 2 cycles, both length 3.
% Guards against copy-paste drift between these near-duplicate functions.
Primes5 = CycleCount(full(A),3);
[cycCount5,cycLen5,cycPath5,allcycles5] = CycleCount2p(A);
assert(max(abs(Primes5 - [0 0 2])) < 1e-8, 'CycleCount on the main graph should give Primes=[0,0,2].');
assert(isequal(cycCount5,2) && isequal(cycLen5,3), ...
    'CycleCount2p should agree: 2 cycles, both length 3.');

% -- reorgCycles: should exactly reproduce CycleCount2p's own internal
% flattening of cycPath into allcycles (same logic, independently
% implemented -- another copy-paste-drift guard).
allcycles_reorg = reorgCycles(cycPath5);
assert(isequal(allcycles_reorg, allcycles5), ...
    'reorgCycles should exactly reproduce CycleCount2p''s own allcycles output.');

% -- CyclePathOverlap: node-based overlap between two paths sharing 2 of
% 4 total unique nodes.
c_overlap = {[1,2,3],[2,3,4]};
CO_node = CyclePathOverlap(c_overlap,'type','node');
assert(abs(CO_node(1,2) - 0.5) < 1e-10, 'node-type overlap should be 2/4=0.5.');

% -- CyclePathOverlap: edge-based overlap (default cycle=true, so each
% path wraps back to its first node). Cycle1 edges {1-2,2-3,3-1}, cycle2
% edges {2-3,3-4,4-2}; only edge 2-3 is shared, union has 5 unique edges.
CO_edge = CyclePathOverlap(c_overlap,'type','edge');
assert(abs(CO_edge(1,2) - 0.2) < 1e-10, 'edge-type overlap should be 1/5=0.2.');

% -- pathtraffic: hand-derived traffic stats for two paths over 5 nodes.
allpath_traf = {[1,2,3]; [4,5]};
nodesize_traf = [10,20,30,5,15];
[traf_mean,traf_med,traf_min,traf_max,traf_std] = pathtraffic(allpath_traf,nodesize_traf);
assert(isequal(traf_mean, [20;10]), 'pathtraffic mean gave unexpected result.');
assert(isequal(traf_med, [20;10]), 'pathtraffic median gave unexpected result.');
assert(isequal(traf_min, [10;5]), 'pathtraffic min gave unexpected result.');
assert(isequal(traf_max, [30;15]), 'pathtraffic max gave unexpected result.');
assert(max(abs(traf_std - [10;sqrt(50)])) < 1e-9, 'pathtraffic std gave unexpected result.');

disp('All tests passed.');
