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

% ===== normgeo =====
% Normalizes a geodesic matrix by |sum_ij L(i,j)^2 m(i) m(j)|^(1/2), with
% m the node measure. Every expected value below is worked out by hand
% from that definition rather than recorded from a run.
G2 = [0 1; 1 0];

% uniform measure over 2 nodes: m = [.5 .5], so the weighted sum is
% 2 * (0.25 * 1^2) = 0.5 and the factor is sqrt(0.5).
[gn2, nm2] = normgeo(G2, [1;1]);
assert(max(abs(nm2 - [0.5;0.5])) < 1e-12, 'node measure should be uniform and sum to 1.');
assert(max(abs(gn2 - G2/sqrt(0.5)), [], 'all') < 1e-12, ...
    'normgeo should divide the geodesics by sqrt(0.5) here.');
assert(abs(sum(nm2) - 1) < 1e-12, 'the node measure is a probability measure.');

% omitting nsize is documented as "a vector of ones", so it must agree
[gn_omit, nm_omit] = normgeo(G2);
assert(isequal(gn_omit, gn2) && isequal(nm_omit, nm2), ...
    'omitting nsize should match passing ones(N,1) exactly.');

% node size genuinely reweights: m = [.75 .25] gives a weighted sum of
% 2 * (0.1875 * 1^2) = 0.375.
[gn_w, nm_w] = normgeo(G2, [3;1]);
assert(max(abs(nm_w - [0.75;0.25])) < 1e-12, 'node measure should follow node size.');
assert(max(abs(gn_w - G2/sqrt(0.375)), [], 'all') < 1e-12, ...
    'a non-uniform node measure should change the normalizing factor.');
assert(~isequal(gn_w, gn2), 'weighting by node size must actually change the result.');

% excludeDiag drops the diagonal from the normalizing factor only. With a
% nonzero diagonal: all-entries sum = 0.25*(4+1+1+4) = 2.5; off-diagonal
% only = 0.25*(1+1) = 0.5.
Gd = [2 1; 1 2];
gn_all  = normgeo(Gd, [1;1], 'excludeDiag', false);
gn_excl = normgeo(Gd, [1;1], 'excludeDiag', true);
assert(max(abs(gn_all  - Gd/sqrt(2.5)), [], 'all') < 1e-12, ...
    'including the diagonal should divide by sqrt(2.5).');
assert(max(abs(gn_excl - Gd/sqrt(0.5)), [], 'all') < 1e-12, ...
    'excluding the diagonal should divide by sqrt(0.5).');
assert(~isequal(gn_all, gn_excl), 'excludeDiag must change the answer when the diagonal is nonzero.');

% Inf stands in as the network diameter -- the realistic case, since a
% disconnected transition network has unreachable pairs
Ginf = [0 1 Inf; 1 0 Inf; Inf Inf 0];
gn_inf = normgeo(Ginf, [1;1;1]);
assert(all(isfinite(gn_inf(:))), 'unreachable pairs should be finite after normalization.');

% ...but with nothing finite there is no diameter to borrow, and the old
% code failed with a shape error that named nothing
threw_ng = false;
try
    normgeo(Inf(3), [1;1;1]);
catch err_ng
    threw_ng = strcmp(err_ng.identifier, 'normgeo:allInfinite');
end
assert(threw_ng, 'an all-Inf geodesic matrix should raise normgeo:allInfinite.');

% ===== normtcm =====
T = [0 2; 4 0];
assert(max(abs(normtcm(T) - T/4), [], 'all') < 1e-12, ...
    'the default should divide by the maximum finite value (4).');
assert(isequal(normtcm(T), normtcm(T,'normtype','max')), ...
    '''max'' should be the default normtype.');
assert(max(abs(normtcm(T,'normtype','norm') - T/sqrt(20)), [], 'all') < 1e-12, ...
    '''norm'' should divide by norm(tcm(:)) = sqrt(20).');
assert(~isequal(normtcm(T,'normtype','max'), normtcm(T,'normtype','norm')), ...
    'the two normtypes must genuinely differ.');

% Inf handling: 'max' substitutes the largest finite value, 'nan' blanks it
Tinf = [0 Inf; 2 0];
assert(isequal(normtcm(Tinf,'infreplace','max'), [0 1; 1 0]), ...
    '''max'' should replace Inf with the largest finite value before normalizing.');
Tn = normtcm(Tinf,'infreplace','nan');
assert(isnan(Tn(1,2)) && abs(Tn(2,1) - 1) < 1e-12, ...
    '''nan'' should blank Inf entries and normalize the rest by the finite max.');

% an all-zero matrix has nothing to divide by and must come back unchanged
% rather than as NaN
assert(isequal(normtcm(zeros(3)), zeros(3)), ...
    'an all-zero tcm should be returned unchanged, not divided by zero.');

% invalid options used to fail confusingly (MATLAB:UndefinedFunction) or,
% for infreplace, not at all -- silently leaving Inf to be divided away
threw_nt = false;
try
    normtcm(T,'normtype','bogus');
catch err_nt
    threw_nt = strcmp(err_nt.identifier,'normtcm:invalidNormType');
end
assert(threw_nt, 'an unknown normtype should raise normtcm:invalidNormType.');

threw_ir = false;
try
    normtcm(Tinf,'infreplace','bogus');
catch err_ir
    threw_ir = strcmp(err_ir.identifier,'normtcm:invalidInfReplace');
end
assert(threw_ir, 'an unknown infreplace should raise normtcm:invalidInfReplace.');

threw_ai = false;
try
    normtcm(Inf(3));
catch err_ai
    threw_ai = strcmp(err_ai.identifier,'normtcm:allInfinite');
end
assert(threw_ai, 'an all-Inf tcm should raise normtcm:allInfinite.');

disp('All tests passed.');
