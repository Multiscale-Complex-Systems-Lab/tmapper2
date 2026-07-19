%TEST_CORE_PIPELINE smoke tests for the core two-step pipeline
%   (tknndigraph -> filtergraph) and their input validation.
%   Run this script directly in MATLAB; it prints "All tests passed."
%   on success and errors out on the first failing check.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));

rng(0);

% -- synthetic data: 20 time points, 2 well-separated spatial clusters
N1 = 10; N2 = 10;
X = [repmat([0 0],N1,1) + 0.01*randn(N1,2);
     repmat([10 10],N2,1) + 0.01*randn(N2,2)];
N = size(X,1);
tidx = (1:N)';
D = pdist2(X,X);
k = 3;

% -- Step 1: tknndigraph produces a digraph with one node per time point
[g,par] = tknndigraph(D,k,tidx);
assert(isa(g,'digraph'), 'tknndigraph should return a digraph object.');
assert(numnodes(g) == N, 'tknndigraph should preserve the number of points as nodes.');
assert(par.k == k, 'returned parameters should record k.');

% -- Step 2: filtergraph preserves total membership and produces consistent sizes
% d=1 requires strictly-zero geodesic distance to collapse nodes, i.e. no
% collapsing should occur, so every original point should remain its own node.
[g_simp1, members1, nodesize1] = filtergraph(g,1,'reciprocal',true);
assert(sum(nodesize1) == N, 'nodesize should sum to the total number of original points.');
assert(numnodes(g_simp1) == length(members1), 'g_simp node count should match members length.');
assert(numnodes(g_simp1) == N, 'with d=1 no nodes should be collapsed.');

% -- a larger threshold should collapse to no more nodes than points, and still
% preserve total membership
[g_simp2, members2, nodesize2] = filtergraph(g,5,'reciprocal',true);
assert(sum(nodesize2) == N, 'nodesize should sum to the total number of original points.');
assert(numnodes(g_simp2) <= N, 'filtergraph should not increase the number of nodes.');
assert(numnodes(g_simp2) == length(members2), 'g_simp node count should match members length.');

% -- deterministic dataset for exact node/edge/size checks at non-extreme
% parameter settings: 6 points on a line, two well-separated triples.
% Expected numbers below were hand-derived by tracing the algorithms; see
% the "compressed-baking-llama" plan notes for the full derivation.
Xd = [0;1;2;10;11;12];
Nd = length(Xd);
tidxd = (1:Nd)';
Dd = pdist2(Xd,Xd);
kd = 2;

gd = tknndigraph(Dd,kd,tidxd);
assert(numnodes(gd) == 6, 'expected 6 nodes for the deterministic 6-point dataset.');
assert(numedges(gd) == 9, 'expected exactly 9 edges (4 reciprocal spatial + 5 temporal).');

% -- specific edges expected to survive reciprocal spatial filtering
for e = [1 3; 3 1; 4 6; 6 4]'
    assert(findedge(gd,e(1),e(2)) ~= 0, ...
        sprintf('expected reciprocal spatial edge %d->%d to exist.', e(1), e(2)));
end
% -- temporal edges are always present
for i = 1:5
    assert(findedge(gd,i,i+1) ~= 0, sprintf('expected temporal edge %d->%d to exist.', i, i+1));
end
% -- non-reciprocal spatial candidates should have been filtered out
assert(findedge(gd,1,4) == 0, 'edge 1->4 should not survive reciprocal filtering.');
assert(findedge(gd,4,1) == 0, 'edge 4->1 should not survive reciprocal filtering.');

% -- filtergraph at d=2: partial merge -> 4 nodes, sizes {1,1,2,2}, 5 edges
[gs_d2, mem_d2, size_d2, Dsimp_d2] = filtergraph(gd,2,'reciprocal',true);
assert(numnodes(gs_d2) == 4, 'expected 4 nodes at d=2.');
assert(isequal(sort(size_d2), [1;1;2;2]), 'expected node sizes {1,1,2,2} at d=2.');
assert(numedges(gs_d2) == 5, 'expected 5 edges in g_simp at d=2.');
idx13 = find(cellfun(@(m) any(m==1), mem_d2));
idx2  = find(cellfun(@(m) any(m==2), mem_d2));
idx46 = find(cellfun(@(m) any(m==4), mem_d2));
idx5  = find(cellfun(@(m) any(m==5), mem_d2));
assert(isequal(sort(mem_d2{idx13}), [1;3]), 'expected points 1 and 3 to merge at d=2.');
assert(isequal(mem_d2{idx2}, 2), 'expected point 2 to remain a singleton at d=2.');
assert(isequal(sort(mem_d2{idx46}), [4;6]), 'expected points 4 and 6 to merge at d=2.');
assert(isequal(mem_d2{idx5}, 5), 'expected point 5 to remain a singleton at d=2.');

% -- D_simp (4th output): hand-derived shortest cross-block distances on the
% original directed geodesics. Diagonal is 0 (self-block); off-diagonal is
% asymmetric since {4,6} cannot reach back to {1,3}/{2} in the digraph.
assert(Dsimp_d2(idx13,idx13) == 0 && Dsimp_d2(idx46,idx46) == 0, ...
    'self-block D_simp should be 0.');
assert(Dsimp_d2(idx13,idx2) == 1 && Dsimp_d2(idx2,idx13) == 1, ...
    'D_simp between {1,3} and {2} should be 1 in both directions.');
assert(Dsimp_d2(idx13,idx46) == 1, 'D_simp from {1,3} to {4,6} should be 1.');
assert(Dsimp_d2(idx46,idx13) == Inf, 'D_simp from {4,6} back to {1,3} should be Inf (unreachable).');
assert(Dsimp_d2(idx13,idx5) == 2, 'D_simp from {1,3} to {5} should be 2.');
assert(Dsimp_d2(idx5,idx13) == Inf, 'D_simp from {5} back to {1,3} should be Inf (unreachable).');
assert(Dsimp_d2(idx2,idx46) == 2, 'D_simp from {2} to {4,6} should be 2.');
assert(Dsimp_d2(idx46,idx2) == Inf, 'D_simp from {4,6} back to {2} should be Inf (unreachable).');
assert(Dsimp_d2(idx2,idx5) == 3, 'D_simp from {2} to {5} should be 3.');
assert(Dsimp_d2(idx5,idx2) == Inf, 'D_simp from {5} back to {2} should be Inf (unreachable).');
assert(Dsimp_d2(idx46,idx5) == 1, 'D_simp from {4,6} to {5} should be 1.');
assert(Dsimp_d2(idx5,idx46) == 1, 'D_simp from {5} to {4,6} should be 1.');

% -- filtergraph at d=3: fuller merge -> 2 nodes, sizes {3,3}, 1 edge
[gs_d3, mem_d3, size_d3] = filtergraph(gd,3,'reciprocal',true);
assert(numnodes(gs_d3) == 2, 'expected 2 nodes at d=3.');
assert(isequal(sort(size_d3), [3;3]), 'expected node sizes {3,3} at d=3.');
assert(numedges(gs_d3) == 1, 'expected exactly 1 edge in g_simp at d=3.');
idx123 = find(cellfun(@(m) any(m==1), mem_d3));
idx456 = find(cellfun(@(m) any(m==4), mem_d3));
assert(isequal(sort(mem_d3{idx123}), [1;2;3]), 'expected points 1,2,3 to merge at d=3.');
assert(isequal(sort(mem_d3{idx456}), [4;5;6]), 'expected points 4,5,6 to merge at d=3.');
assert(findedge(gs_d3,idx123,idx456) ~= 0, 'expected an edge from the {1,2,3} block to the {4,5,6} block.');
assert(findedge(gs_d3,idx456,idx123) == 0, 'expected no edge back from the {4,5,6} block to the {1,2,3} block.');

% -- raw coordinate input X should give the identical graph to precomputed D
g_fromX = tknndigraph(Xd,kd,tidxd);
assert(isequal(adjacency(g_fromX), adjacency(gd)), ...
    'tknndigraph should give the same graph whether given raw coordinates or a precomputed distance matrix.');

% -- tknndigraph, 'reciprocal',false: OR instead of AND on the two directions.
% Every pair with at least one direction among the k=2 NN choices becomes
% fully bidirectional (10 such pairs); the 5 "far" pairs (1-5,1-6,2-5,2-6,3-6)
% get none. Total = 20 directed edges.
g_norecip = tknndigraph(Dd,kd,tidxd,'reciprocal',false);
assert(numedges(g_norecip) == 20, 'expected 20 edges with reciprocal=false.');
for e = [1 2; 1 3; 1 4; 2 3; 2 4; 3 4; 3 5; 4 5; 4 6; 5 6]'
    assert(findedge(g_norecip,e(1),e(2)) ~= 0 && findedge(g_norecip,e(2),e(1)) ~= 0, ...
        sprintf('expected pair %d-%d to be bidirectional with reciprocal=false.', e(1), e(2)));
end
for e = [1 5; 1 6; 2 5; 2 6; 3 6]'
    assert(findedge(g_norecip,e(1),e(2)) == 0 && findedge(g_norecip,e(2),e(1)) == 0, ...
        sprintf('expected pair %d-%d to have no edge with reciprocal=false.', e(1), e(2)));
end

% -- tknndigraph, 'timeExcludeSpace',false: temporal successors may also
% compete as spatial neighbors, giving each triple a fully bidirectional
% internal clique, plus the single one-way temporal bridge 3->4 (the only
% cross-triple link, since 4,5,6 never pick 1,2,3 as spatial neighbors).
g_notimeexcl = tknndigraph(Dd,kd,tidxd,'timeExcludeSpace',false);
assert(numedges(g_notimeexcl) == 13, 'expected 13 edges with timeExcludeSpace=false.');
for e = [1 2; 2 1; 1 3; 3 1; 2 3; 3 2; 4 5; 5 4; 4 6; 6 4; 5 6; 6 5]'
    assert(findedge(g_notimeexcl,e(1),e(2)) ~= 0, ...
        sprintf('expected edge %d->%d within a triple with timeExcludeSpace=false.', e(1), e(2)));
end
assert(findedge(g_notimeexcl,3,4) ~= 0, 'expected the one-way bridge 3->4.');
assert(findedge(g_notimeexcl,4,3) == 0, 'the bridge should not exist in the reverse direction.');

% -- tknndigraph, 'timeExcludeRange',2: excluding both the 1st and 2nd
% temporal successors from spatial-NN search leaves no mutual nearest-
% neighbor pairs at all on this dataset, so only the 5 temporal edges remain.
g_range2 = tknndigraph(Dd,kd,tidxd,'timeExcludeRange',2);
assert(numedges(g_range2) == 5, 'expected only the 5 temporal edges with timeExcludeRange=2.');
for i = 1:5
    assert(findedge(g_range2,i,i+1) ~= 0, sprintf('expected temporal edge %d->%d.', i, i+1));
end
assert(findedge(g_range2,1,3) == 0, 'expected no spatial shortcut 1->3 with timeExcludeRange=2.');
assert(findedge(g_range2,4,6) == 0, 'expected no spatial shortcut 4->6 with timeExcludeRange=2.');

% -- tknndigraph, 'maxNeighborDist',1.5: cuts the two spatial shortcuts
% (1<->3 and 4<->6, both at distance 2), leaving only the 5 temporal edges.
g_maxdist = tknndigraph(Dd,kd,tidxd,'maxNeighborDist',1.5);
assert(numedges(g_maxdist) == 5, 'expected only the 5 temporal edges with maxNeighborDist=1.5.');
assert(findedge(g_maxdist,1,3) == 0, 'expected spatial shortcut 1->3 to be cut by maxNeighborDist.');
assert(findedge(g_maxdist,4,6) == 0, 'expected spatial shortcut 4->6 to be cut by maxNeighborDist.');

% -- maxNeighborDistPrct should behave identically to passing the equivalent
% percentile-derived distance directly as maxNeighborDist (cross-checks the
% wiring rather than re-deriving MATLAB's percentile interpolation by hand).
% The percentile is computed internally on the *masked* D (self-loops and
% the default timeExcludeRange=1 temporal-successor entries set to Inf), so
% replicate that masking here rather than using the raw Dd.
prct = 30;
Dd_masked = Dd;
Dd_masked(logical(eye(Nd))) = Inf;
for i = 1:Nd-1
    Dd_masked(i,i+1) = Inf;
end
equivalent_threshold = prctile(Dd_masked(:), prct);
g_prct = tknndigraph(Dd,kd,tidxd,'maxNeighborDistPrct',prct);
g_equivdist = tknndigraph(Dd,kd,tidxd,'maxNeighborDist',equivalent_threshold);
assert(isequal(adjacency(g_prct), adjacency(g_equivdist)), ...
    'maxNeighborDistPrct should give the same result as the equivalent maxNeighborDist value.');
assert(numedges(g_prct) <= numedges(gd), ...
    'a finite percentile cutoff should not add edges relative to the unfiltered graph.');

% -- duplicate-point tie handling: with an exact tie for nearest neighbor,
% ALL tied candidates should be included, not just k of them. 4 points with
% two exact-duplicate pairs: positions [0,0,5,5]. Point 1's only two
% candidates (points 3 and 4) are tied at distance 5; with reciprocal=false
% (so the tie's effect isn't masked by reciprocal filtering) this should
% connect point 1 to BOTH 3 and 4, even though k=1. Point 2 and point 4 are
% never mutual candidates and should have no edge between them.
Xdup = [0;0;5;5];
tidxdup = (1:4)';
gdup = tknndigraph(Xdup,1,tidxdup,'reciprocal',false);
assert(numedges(gdup) == 10, 'expected 10 edges in the duplicate-point tie case.');
assert(findedge(gdup,1,4) ~= 0 || findedge(gdup,4,1) ~= 0, ...
    'duplicate-tie handling should connect point 1 to point 4 despite k=1.');
assert(findedge(gdup,2,4) == 0 && findedge(gdup,4,2) == 0, ...
    'points 2 and 4 were never mutual nearest-neighbor candidates and should have no edge.');

% -- filtergraph, 'reciprocal',false at the same d=2 threshold: the OR
% condition is much more permissive and merges all 6 points into one
% component here (1-2, 1-3, 2-3, and critically 3-4 bridge the two triples,
% then 4-5, 4-6, 5-6 pull in the rest).
[gs_norec, ~, size_norec] = filtergraph(gd,2,'reciprocal',false);
assert(numnodes(gs_norec) == 1, 'expected all 6 points to merge into 1 node with reciprocal=false at d=2.');
assert(size_norec == 6, 'expected the single merged node to have size 6.');
assert(numedges(gs_norec) == 0, 'a single-node graph should have no (self-loop) edges.');

% -- filtergraph on a NAMED graph/digraph: this previously crashed
% (undefined variable 'oldenodenames' in the local index2cell helper,
% now fixed). Reuses the same 9-edge structure as gd (hand-derived above)
% but with explicit node names, so members should contain the identical
% groupings as the unnamed d=2 case, just as name strings.
nodenames = {'n1','n2','n3','n4','n5','n6'};
gd_named = digraph(full(adjacency(gd)), nodenames);
[gs_named, mem_named, size_named] = filtergraph(gd_named,2,'reciprocal',true);
assert(numnodes(gs_named) == 4, 'expected 4 nodes for the named-graph d=2 case.');
assert(isequal(sort(size_named), [1;1;2;2]), 'expected node sizes {1,1,2,2} for the named-graph case.');
nidx13 = find(cellfun(@(m) any(strcmp(m,'n1')), mem_named));
nidx2  = find(cellfun(@(m) any(strcmp(m,'n2')), mem_named));
nidx46 = find(cellfun(@(m) any(strcmp(m,'n4')), mem_named));
nidx5  = find(cellfun(@(m) any(strcmp(m,'n5')), mem_named));
assert(isequal(sort(mem_named{nidx13}(:)), sort({'n1';'n3'})), 'expected n1,n3 to merge (named graph).');
assert(isequal(mem_named{nidx2}(:), {'n2'}), 'expected n2 to remain singleton (named graph).');
assert(isequal(sort(mem_named{nidx46}(:)), sort({'n4';'n6'})), 'expected n4,n6 to merge (named graph).');
assert(isequal(mem_named{nidx5}(:), {'n5'}), 'expected n5 to remain singleton (named graph).');

% -- input validation: tknndigraph
assertThrows(@() tknndigraph(D,k,tidx(1:end-1)), 'tknndigraph:invalidInput', ...
    'tknndigraph should reject mismatched tidx length.');
assertThrows(@() tknndigraph(D,N,tidx), 'tknndigraph:invalidInput', ...
    'tknndigraph should reject k >= number of points.');
assertThrows(@() tknndigraph(D,1.5,tidx), 'tknndigraph:invalidInput', ...
    'tknndigraph should reject non-integer k.');

% -- input validation: filtergraph
assertThrows(@() filtergraph(D,1), 'filtergraph:invalidInput', ...
    'filtergraph should reject a non-graph/digraph first argument.');
assertThrows(@() filtergraph(g,-1), 'filtergraph:invalidInput', ...
    'filtergraph should reject a non-positive distance threshold.');

disp('All tests passed.');

function assertThrows(fcn, expectedID, msg)
    try
        fcn();
    catch err
        assert(strcmp(err.identifier, expectedID), ...
            '%s (expected error id "%s", got "%s")', msg, expectedID, err.identifier);
        return
    end
    error('%s (expected an error but none was thrown)', msg);
end
