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

disp('All tests passed.');
