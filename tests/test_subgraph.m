%TEST_SUBGRAPH smoke test for subgraphFromMembers on top of the core
%   pipeline output. Run this script directly in MATLAB; it prints "All
%   tests passed." on success and errors out on the first failing check.
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

g = tknndigraph(D,k,tidx);
[g_simp, members] = filtergraph(g,5,'reciprocal',true);

% -- restrict to the first cluster's time points only
includemembers = (1:N1)';
[g_sub, members_sub, sub_orig_nodeidx] = subgraphFromMembers(g_simp, members, includemembers);

assert(numnodes(g_sub) == length(members_sub), ...
    'g_sub node count should match members_sub length.');
assert(numnodes(g_sub) == length(sub_orig_nodeidx), ...
    'g_sub node count should match sub_orig_nodeidx length.');
assert(numnodes(g_sub) <= numnodes(g_simp), ...
    'subgraph should not have more nodes than the original graph.');

% -- every retained member must be within includemembers, and every
% original node with any overlap must be retained
for n = 1:length(members_sub)
    assert(all(ismember(members_sub{n}, includemembers)), ...
        'members_sub should only contain time points from includemembers.');
end
expected_orig_idx = find(cellfun(@(x) ~isempty(intersect(x,includemembers)), members));
assert(isequal(sort(sub_orig_nodeidx), sort(expected_orig_idx)), ...
    'sub_orig_nodeidx should match nodes of g_simp overlapping includemembers.');

% -- empty includemembers: no node overlaps anything, subgraph should be
% empty (0 nodes), not error.
[g_sub_empty, members_sub_empty, idx_empty] = subgraphFromMembers(g_simp, members, []);
assert(numnodes(g_sub_empty) == 0, 'empty includemembers should give a 0-node subgraph.');
assert(isempty(members_sub_empty), 'empty includemembers should give empty members_sub.');
assert(isempty(idx_empty), 'empty includemembers should give empty sub_orig_nodeidx.');

% -- full includemembers (every original time point): should reproduce
% g_simp exactly, a no-op restriction.
[g_sub_full, members_sub_full, idx_full] = subgraphFromMembers(g_simp, members, (1:N)');
assert(numnodes(g_sub_full) == numnodes(g_simp), ...
    'full includemembers should retain every node of g_simp.');
assert(isequal(members_sub_full, members), ...
    'full includemembers should leave members unchanged.');
assert(isequal(idx_full, (1:numnodes(g_simp))'), ...
    'full includemembers should map every node back to itself.');

% -- out-of-range includemembers (values that are not any node's member,
% e.g. beyond N): should be silently ignored, giving the identical result
% to omitting them.
[g_sub_a, members_sub_a, idx_a] = subgraphFromMembers(g_simp, members, [1;2;3]);
[g_sub_b, members_sub_b, idx_b] = subgraphFromMembers(g_simp, members, [1;2;3;999]);
assert(numnodes(g_sub_a) == numnodes(g_sub_b), ...
    'an out-of-range includemembers value should not change the node count.');
assert(isequal(members_sub_a, members_sub_b), ...
    'an out-of-range includemembers value should not change members_sub.');
assert(isequal(idx_a, idx_b), ...
    'an out-of-range includemembers value should not change sub_orig_nodeidx.');

disp('All tests passed.');
