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

% ===== nodesize =====
% Trivial, but it is what every node-size mode in the plots is built on.
assert(isequal(nodesize({[1 2 3];[4];[5 6]}), [3;1;2]), ...
    'nodesize should count members per node.');
assert(isequal(nodesize({[1 2 3];[];[4]}), [3;0;1]), ...
    'an empty node should count as 0, not drop out.');
ns_shape = nodesize({[1 2];[3]});
assert(size(ns_shape,2)==1 && size(ns_shape,1)==2, ...
    'nodesize should return an N-by-1 column, got %s.', mat2str(size(ns_shape)));

% ===== findnodelabel =====
% This is the aggregation behind every "Label method" choice in the GUI,
% so each branch gets a hand-computed answer rather than a smoke check.
mem = {[1 2 3];[4 5]};
lab = [10 20 30 7 9];      % node 1 sees [10 20 30], node 2 sees [7 9]

assert(isequal(findnodelabel(mem, lab, 'labelmethod','mean'), [20;8]), ...
    'mean should average each node''s member labels.');
assert(isequal(findnodelabel(mem, lab, 'labelmethod','median'), [20;8]), ...
    'median should take the middle of each node''s member labels.');
assert(isequal(findnodelabel(mem, lab, 'labelmethod','none'), [0;0]), ...
    '''none'' should flatten every node to 0.');
assert(isequal(findnodelabel(mem, lab), findnodelabel(mem, lab, 'labelmethod','mode')), ...
    'mode should be the default label method.');

% mode picks the most frequent value, not the first or the largest
mem_mode = {[1 2 3 4]};
assert(isequal(findnodelabel(mem_mode, [5 9 9 1], 'labelmethod','mode'), 9), ...
    'mode should return the most frequent member label.');

% ties matter for categorical colouring, where labels are arbitrary codes:
% MATLAB's mode resolves a tie to the SMALLEST value, so a node split
% evenly between two categories always shows the lower-numbered one.
assert(isequal(findnodelabel({[1 2]}, [7 3], 'labelmethod','mode'), 3), ...
    'a two-way tie in mode should resolve to the smaller label.');

% a function handle is applied per node and must yield a scalar
assert(isequal(findnodelabel(mem, lab, 'labelmethod',@max), [30;9]), ...
    'a function handle should be applied to each node''s member labels.');
assert(isequal(findnodelabel(mem, lab, 'labelmethod',@(v) v(1)), [10;7]), ...
    'an anonymous handle should receive the member labels in order.');

% mean and median genuinely differ on a skewed node, so these are not
% accidentally testing the same code path
mem_skew = {[1 2 3 4]};
lab_skew = [1 2 3 100];
assert(isequal(findnodelabel(mem_skew, lab_skew, 'labelmethod','mean'), 26.5) && ...
       isequal(findnodelabel(mem_skew, lab_skew, 'labelmethod','median'), 2.5), ...
    'mean and median should differ on a skewed node (26.5 vs 2.5).');

% shape and length follow the members, not the labels
lbl_shape = findnodelabel({[1];[2];[3]}, [4 5 6], 'labelmethod','mean');
assert(isequal(size(lbl_shape), [3 1]), ...
    'findnodelabel should return one row per node, got %s.', mat2str(size(lbl_shape)));

% an unrecognised method used to fall through the switch and surface as
% MATLAB:unassignedOutputs, which named the wrong problem
threw_lm = false;
try
    findnodelabel(mem, lab, 'labelmethod','bogus');
catch err_lm
    threw_lm = strcmp(err_lm.identifier, 'findnodelabel:invalidLabelMethod');
end
assert(threw_lm, 'an unknown labelmethod should raise findnodelabel:invalidLabelMethod.');

disp('All tests passed.');
