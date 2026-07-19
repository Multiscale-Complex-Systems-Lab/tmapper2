%TEST_GRAPH_UTILS smoke/regression tests for weightedAdj and digraph2graph.
%   Both previously used isfield(T,'name') on a table, which always
%   returns false, so they unconditionally clobbered real edge weights
%   to 1 and always dropped node names. Now fixed to check
%   T.Properties.VariableNames instead. Run this script directly in
%   MATLAB; it prints "All tests passed." on success and errors out on
%   the first failing check.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));

% -- weightedAdj: a genuinely weighted digraph should keep its real weights
s = [1 2 3];
t = [2 3 1];
w = [2.5 4 1.5];
dg_w = digraph(s,t,w);
A_w = weightedAdj(dg_w);
assert(full(A_w(1,2)) == 2.5, 'weightedAdj should preserve the real edge weight 1->2.');
assert(full(A_w(2,3)) == 4,   'weightedAdj should preserve the real edge weight 2->3.');
assert(full(A_w(3,1)) == 1.5, 'weightedAdj should preserve the real edge weight 3->1.');
assert(full(A_w(2,1)) == 0, 'weightedAdj should have 0 where there is no edge.');

% -- weightedAdj: a genuinely unweighted digraph (no Weight column at all)
% should still fall back to unit weights on existing edges
dg_noweight = digraph([1 2 3],[2 3 1]);
assert(~ismember('Weight', dg_noweight.Edges.Properties.VariableNames), ...
    'test setup: this digraph should have no Weight column.');
A_nw = weightedAdj(dg_noweight);
assert(isequal(full(A_nw ~= 0), logical([0 1 0; 0 0 1; 1 0 0])), ...
    'weightedAdj should default existing edges to weight 1 when there is no Weight column.');

% -- digraph2graph: asymmetric weights should be averaged, not clobbered to 1
dg_asym = digraph([1 2],[2 1],[2 4],{'A','B'});
g_avg = digraph2graph(dg_asym);
assert(isa(g_avg,'graph'), 'digraph2graph should return an undirected graph object.');
Ag = weightedAdj(g_avg);
assert(full(Ag(1,2)) == 3, 'digraph2graph should average asymmetric weights 2 and 4 to 3.');

% -- digraph2graph: node names should be preserved when present
assert(isequal(g_avg.Nodes.Name, {'A';'B'}), 'digraph2graph should preserve node names.');

% -- digraph2graph: falls back gracefully when there are no node names
dg_unnamed = digraph([1 2],[2 1],[2 4]);
g_unnamed = digraph2graph(dg_unnamed);
assert(~ismember('Name', g_unnamed.Nodes.Properties.VariableNames) || isempty(g_unnamed.Nodes.Name{1}), ...
    'digraph2graph should not fabricate node names when the input digraph has none.');
A_unnamed = weightedAdj(g_unnamed);
assert(full(A_unnamed(1,2)) == 3, ...
    'digraph2graph should still average weights correctly without node names.');

disp('All tests passed.');
