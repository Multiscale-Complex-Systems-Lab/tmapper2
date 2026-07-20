%TEST_SYMDYN tests for symDyn2digraph: the core safe-input case, the
%   previously-buggy multi-digit num2str-padding case (now fixed), the
%   nargout<=2 path, and degenerate inputs (constant symDyn, length-1
%   symDyn -- also previously buggy, now fixed). Run this script
%   directly in MATLAB; it prints "All tests passed." on success and
%   errors out on the first failing check.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));

symDyn = [1;1;1;2;2;3;3;3;1;1;4;4;2;2];
N = length(symDyn);

[dg,dwelltime,nodemembers] = symDyn2digraph(symDyn);

uniqueStates = unique(symDyn);
assert(dg.numnodes == length(uniqueStates), ...
    'digraph should have one node per unique state.');
assert(sum(dwelltime) == N, 'dwelltime should sum to the length of symDyn.');
assert(length(nodemembers) == dg.numnodes, ...
    'nodemembers should have one cell per node.');

% -- reconstruct symDyn from nodemembers and check it matches
reconstructed = zeros(N,1);
for n = 1:dg.numnodes
    reconstructed(nodemembers{n}) = uniqueStates(n);
end
assert(isequal(reconstructed, symDyn), ...
    'nodemembers should map back exactly to the original symDyn sequence.');

% -- edge count should match the number of unique consecutive-state transitions
changepoints = find(diff(symDyn) ~= 0);
transitions = unique([symDyn(changepoints), symDyn(changepoints+1)], 'rows');
assert(dg.numedges == size(transitions,1), ...
    'digraph edge count should match the number of unique transitions.');

% -- previously-buggy multi-digit case: state 10 only ever appears as a
% sink (never a transition source), so trans(:,1)'s max (3) used to
% differ from trans(:,2)'s/state_names' max (10), causing num2str to pad
% them inconsistently ('2' vs ' 2') and digraph() to error ("Edge list
% contains a name not present in the node names argument"). Now fixed by
% converting each value independently.
symDyn_multidigit = [1;1;2;2;3;3;10;10];
[dg_md, dwelltime_md, nodemembers_md] = symDyn2digraph(symDyn_multidigit);
assert(dg_md.numnodes == 4, 'expected 4 nodes (states 1,2,3,10).');
assert(dg_md.numedges == 3, 'expected 3 edges (1->2, 2->3, 3->10).');
assert(isequal(sort(dwelltime_md), [2;2;2;2]), 'each state appears exactly twice.');
assert(isequal(sort(dg_md.Nodes.Name), sort({'1';'2';'3';'10'})), ...
    'node names should be clean, unpadded strings.');
idx1 = find(strcmp(dg_md.Nodes.Name,'1'));
idx10 = find(strcmp(dg_md.Nodes.Name,'10'));
assert(isequal(sort(nodemembers_md{idx1}), [1;2]), 'state 1 should cover time points 1,2.');
assert(isequal(sort(nodemembers_md{idx10}), [7;8]), 'state 10 should cover time points 7,8.');

% -- nargout<=2: dg and dwelltime should be identical regardless of
% whether nodemembers is requested (computed before the nargout check).
[dg_2out, dwelltime_2out] = symDyn2digraph(symDyn);
assert(isequal(dg_2out.Nodes, dg.Nodes) && isequal(dg_2out.Edges, dg.Edges), ...
    'dg should be identical whether or not nodemembers is requested.');
assert(isequal(dwelltime_2out, dwelltime), ...
    'dwelltime should be identical whether or not nodemembers is requested.');
dg_1out = symDyn2digraph(symDyn); % single-output call should also just work
assert(isequal(dg_1out.Nodes, dg.Nodes), 'single-output call should give the same dg.');

% -- degenerate input: constant symDyn (no transitions at all). Should
% give a single node with no edges, not error.
symDyn_const = [5;5;5;5];
[dg_const, dwelltime_const, nodemembers_const] = symDyn2digraph(symDyn_const);
assert(dg_const.numnodes == 1 && dg_const.numedges == 0, ...
    'constant symDyn should give a single node with no edges.');
assert(dwelltime_const == 4, 'dwelltime should be 4 for a constant length-4 symDyn.');
assert(isequal(nodemembers_const{1}, (1:4)'), 'the single node should cover all 4 time points.');

% -- degenerate input: length-1 symDyn. Previously crashed ("Index in
% position 2 exceeds array bounds") because diff() of a scalar returns a
% 1x0 (not 0x1) empty, propagating to a 0x0 (not 0x2) trans matrix. Now
% fixed by normalizing shapes with (:).
symDyn_one = 7;
[dg_one, dwelltime_one, nodemembers_one] = symDyn2digraph(symDyn_one);
assert(dg_one.numnodes == 1 && dg_one.numedges == 0, ...
    'a length-1 symDyn should give a single node with no edges.');
assert(dwelltime_one == 1, 'dwelltime should be 1 for a length-1 symDyn.');
assert(isequal(nodemembers_one{1}, 1), 'the single node should cover the single time point.');

disp('All tests passed.');
