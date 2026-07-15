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
