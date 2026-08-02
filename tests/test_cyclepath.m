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

% -- CycleCount on a complete digraph, where the answer is combinatorial
% rather than hand-counted: K_n has exactly nchoosek(n,L)*(L-1)! simple
% cycles of length L. This is the only check here that exercises cycles
% longer than 3, and several lengths at once.
n = 4;
A_K4 = ones(n) - eye(n);
Primes_K4 = CycleCount(A_K4, n);
expected_K4 = arrayfun(@(L) nchoosek(n,L)*factorial(L-1), 1:n);
expected_K4(1) = 0;  % no self-loops in K_n
assert(max(abs(Primes_K4 - expected_K4)) < 1e-6, ...
    'CycleCount on K4 should give [%s], got [%s].', ...
    num2str(expected_K4), num2str(Primes_K4));

% -- CycleCount with cycles of DIFFERENT lengths present at once: a 2-cycle
% (1<->2) disjoint from a 4-cycle (3->4->5->6->3).
A_mixed = zeros(6);
A_mixed(1,2)=1; A_mixed(2,1)=1;
A_mixed(3,4)=1; A_mixed(4,5)=1; A_mixed(5,6)=1; A_mixed(6,3)=1;
Primes_mixed = CycleCount(A_mixed,4);
assert(max(abs(Primes_mixed - [0 1 0 1])) < 1e-6, ...
    'a disjoint 2-cycle and 4-cycle should give Primes=[0,1,0,1], got [%s].', ...
    num2str(Primes_mixed));

% -- CycleCutter, the cutting branch (only the no-cut branch was covered).
% Cutting 1->2->3->4 at nodes 1 and 3 gives the two arcs between them.
cut_two = CycleCutter([1 2 3 4], [1 3]);
assert(iscell(cut_two) && numel(cut_two) == 2, ...
    'cutting a 4-cycle at 2 points should give 2 paths, got %d.', numel(cut_two));
cut_sorted = sort(cellfun(@(c) c(1), cut_two(:)'));
assert(isequal(cut_sorted, [1 3]), ...
    'each returned path should start at one of the cutting points.');
assert(all(cellfun(@(c) ismember(c(end), [1 3]), cut_two)), ...
    'each returned path should end at a cutting point.');
% every edge of the cycle must survive the cut exactly once
edgesFromPaths = [];
for ci = 1:numel(cut_two)
    pth = cut_two{ci};
    edgesFromPaths = [edgesFromPaths; [pth(1:end-1)' pth(2:end)']]; %#ok<AGROW>
end
cycEdges = [1 2; 2 3; 3 4; 4 1];
assert(isequal(sortrows(edgesFromPaths), sortrows(cycEdges)), ...
    'cutting must preserve every edge of the cycle exactly once.');

% -- a cutting point not present in the cycle is documented as ignored
assert(isequal(CycleCutter([1 2 3], [2 99]), CycleCutter([1 2 3], 2)), ...
    'cutting points absent from the cycle should be ignored.');

% -- Cycles2Paths over two cycles sharing node 3, cut at that shared node:
% every returned path must start and end at the cut point, and between them
% the paths must cover both cycles' edges exactly.
allcyc = {[1 2 3]; [3 4 5]};
upaths = Cycles2Paths(allcyc, 3);
assert(iscell(upaths) && numel(upaths) == 2, ...
    'cutting two cycles at their single shared node should give 2 paths.');
assert(all(cellfun(@(pth) pth(1)==3 && pth(end)==3, upaths)), ...
    'each path should leave from and return to the cutting point.');

% -- calMod: modularity of a graph split into two disconnected, equal
% halves is exactly 1 - 1/c = 0.5 for c=2 communities; assigning every node
% to ONE community gives exactly 0, straight from the definition (the
% modularity matrix sums to zero). Both are exact, not approximations.
W_two = zeros(6);
W_two(1:3,1:3) = ones(3) - eye(3);   % triangle A
W_two(4:6,4:6) = ones(3) - eye(3);   % triangle B, disconnected
Q_split = calMod(W_two, [1 1 1 2 2 2]');
Q_one   = calMod(W_two, ones(6,1));
assert(abs(Q_split - 0.5) < 1e-10, ...
    'two disconnected equal communities should give modularity 0.5, got %g.', Q_split);
assert(abs(Q_one) < 1e-10, ...
    'a single all-encompassing community should give modularity 0, got %g.', Q_one);
assert(Q_split > Q_one, 'the correct split should score above the trivial one.');

% -- calMod: a deliberately WRONG split (mixing the two triangles) must
% score below the correct one, or the measure is not discriminating.
Q_wrong = calMod(W_two, [1 1 2 1 2 2]');
assert(Q_wrong < Q_split, ...
    'a split that cuts across the true communities should score below the correct one.');

% -- calMod: no edges at all is neither modular nor not, and must not be NaN
assert(calMod(zeros(4), [1 1 2 2]') == 0, ...
    'calMod should return 0 (not NaN) for an empty adjacency matrix.');

% ===== CycleCluster: direct contract tests =====
% Previously reached only through CyclePathDecomp, so its clustering rule
% was never asserted on its own.
qcl = {'plotmat',false,'plotmds',false,'plothist',false};

% -- disjoint cycles never merge, whatever the threshold
cyc_disjoint = {[1 2 3];[4 5 6]};
for thr = [0.01 0.5 0.99]
    ci = CycleCluster(cyc_disjoint, thr, qcl{:});
    close all
    assert(isequal(size(ci),[2 1]) && numel(unique(ci))==2, ...
        'cycles sharing no nodes should stay in separate clusters at thres=%g.', thr);
end

% -- identical cycles always merge (overlap is exactly 1)
ci_same = CycleCluster({[1 2 3];[1 2 3]}, 0.99, qcl{:}); close all
assert(numel(unique(ci_same))==1, 'identical cycles should land in one cluster.');

% -- the threshold acts on |shared|/|union|, which is exactly 1/5 = 0.2 for
% these two: a threshold below it merges, one above it does not
cyc_share1 = {[1 2 3];[3 4 5]};
ci_lo = CycleCluster(cyc_share1, 0.1, qcl{:}); close all
ci_hi = CycleCluster(cyc_share1, 0.5, qcl{:}); close all
assert(numel(unique(ci_lo))==1, 'overlap 0.2 should merge at thres=0.1.');
assert(numel(unique(ci_hi))==2, 'overlap 0.2 should not merge at thres=0.5.');

% -- three cycles chained by shared pairs: c1-c2 and c2-c3 each overlap by
% 2/6 = 0.333, while c1 and c3 share nothing.
cyc_chain = {[1 2 3 4];[3 4 5 6];[5 6 7 8]};

% -- the linkage method is a real modelling choice, so it is a parameter.
% These two disagree on exactly this configuration, which is the point:
% 'complete' needs every pair in a cluster above thres, 'single' merges on
% any pair and therefore chains through c2.
ci_chain = CycleCluster(cyc_chain, 0.2, qcl{:}); close all
assert(isequal(ci_chain(:)', [1 2 2]), ...
    'the default (complete) linkage should give [1 2 2] at thres=0.2, got %s.', ...
    mat2str(ci_chain(:)'));
ci_explicit = CycleCluster(cyc_chain, 0.2, qcl{:}, 'linkage','complete'); close all
assert(isequal(ci_explicit(:)', [1 2 2]), ...
    'asking for complete explicitly should match the default.');
ci_single = CycleCluster(cyc_chain, 0.2, qcl{:}, 'linkage','single'); close all
assert(isequal(ci_single(:)', [1 1 1]), ...
    'single linkage should chain c1-c2-c3 into one cluster, got %s.', mat2str(ci_single(:)'));

% single linkage is the one that satisfies the plain reading of the
% threshold -- any pair overlapping above it ends up together. Complete
% linkage deliberately does not, which is why the default matters.
CO_chain = CyclePathOverlap(cyc_chain,'type','node');
assert(CO_chain(1,2) > 0.2, 'c1 and c2 overlap above the threshold.');
assert(ci_single(1) == ci_single(2), ...
    'under single linkage, an above-threshold pair must share a cluster.');
assert(ci_chain(1) ~= ci_chain(2), ...
    'under complete linkage it need not, since c1 and c3 share nothing.');

% an unknown method should be rejected rather than silently reinterpreted
threw = false;
try
    CycleCluster(cyc_chain, 0.2, qcl{:}, 'linkage','nonesuch');
catch err
    threw = strcmp(err.identifier,'CycleCluster:invalidLinkage');
end
close all
assert(threw, 'an unrecognised linkage method should raise CycleCluster:invalidLinkage.');

% and CyclePathDecomp must pass the choice through rather than swallow it
[~,pcn_cmp] = CyclePathDecomp(dg,'plotmat',false,'plotmds',false,'plothist',false, ...
    'linkage','complete'); close all
[~,pcn_sing] = CyclePathDecomp(dg,'plotmat',false,'plotmds',false,'plothist',false, ...
    'linkage','single','clusterthres',0.1); close all
assert(~isempty(pcn_cmp) && ~isempty(pcn_sing), ...
    'CyclePathDecomp should accept and forward the linkage option.');

ci_split = CycleCluster(cyc_chain, 0.4, qcl{:}); close all
assert(numel(unique(ci_split))==3, ...
    'above every pairwise overlap (0.333) all three cycles should stay separate.');

% -- labels are 1..M with nothing skipped, as documented
assert(isequal(sort(unique(ci_split))', 1:3), 'cluster labels should be 1..M contiguous.');

% -- degenerate input: a single cycle short-circuits to one label rather
% than tripping linkage() on one observation
ci_one = CycleCluster({[1 2 3]}, 0.5, qcl{:}); close all
assert(isequal(ci_one, 1), 'a single cycle should return exactly one label, got %s.', mat2str(ci_one));

% ===== CycleClusterConn: direct contract tests =====
% Three cycles chained by shared node-pairs, kept as three clusters so the
% connectivity matrix has genuine off-diagonal structure to check.
Ac = zeros(8);
Ac(1,2)=1; Ac(2,3)=1; Ac(3,4)=1; Ac(4,1)=1;   % cycle 1: 1-2-3-4
Ac(4,5)=1; Ac(5,6)=1; Ac(6,3)=1;              % cycle 2: 3-4-5-6
Ac(6,7)=1; Ac(7,8)=1; Ac(8,5)=1;              % cycle 3: 5-6-7-8
dgc = digraph(Ac);
[conn, conn_dir, cnodes, cbound] = CycleClusterConn(dgc, cyc_chain, (1:3)');

assert(isequal(size(conn),[3 3]) && isequal(size(conn_dir),[3 3]), ...
    'connectivity matrices should be M-by-M for M clusters.');

% documented: cell(i,j) = cell(j,i)
for i = 1:3
    for j = 1:3
        assert(isequal(sort(conn{i,j}(:)), sort(conn{j,i}(:))), ...
            'cluster_conn should be symmetric at (%d,%d).', i, j);
    end
end

% the boundary between two clusters is exactly the nodes they share
assert(isequal(sort(conn{1,2}(:))', [3 4]), 'clusters 1 and 2 share nodes 3 and 4.');
assert(isequal(sort(conn{2,3}(:))', [5 6]), 'clusters 2 and 3 share nodes 5 and 6.');
assert(isempty(conn{1,3}), 'clusters 1 and 3 share no nodes, so no boundary.');

% clusters_nodes is the union of each cluster's cycles
assert(isequal(sort(cnodes{1}(:))', 1:4), 'cluster 1 spans nodes 1-4.');
assert(isequal(sort(cnodes{2}(:))', 3:6), 'cluster 2 spans nodes 3-6.');
assert(isequal(sort(cnodes{3}(:))', 5:8), 'cluster 3 spans nodes 5-8.');

% a cluster's boundary is the part of it shared with any other cluster
assert(isequal(sort(cbound{1}(:))', [3 4]), 'cluster 1''s boundary is 3 and 4.');
assert(isequal(sort(cbound{2}(:))', [3 4 5 6]), 'cluster 2 borders both neighbours.');
assert(isequal(sort(cbound{3}(:))', [5 6]), 'cluster 3''s boundary is 5 and 6.');

% every boundary node must actually belong to the cluster it bounds
for i = 1:3
    assert(all(ismember(cbound{i}, cnodes{i})), ...
        'cluster %d has a boundary node that is not one of its own nodes.', i);
end

% the directed boundary is a subset of the undirected one
for i = 1:3
    for j = 1:3
        assert(all(ismember(conn_dir{i,j}, conn{i,j})), ...
            'cluster_conn_dir(%d,%d) should not contain nodes outside cluster_conn.', i, j);
    end
end

disp('All tests passed.');
