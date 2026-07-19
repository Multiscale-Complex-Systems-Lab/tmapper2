%TEST_SYMDYN smoke test for symDyn2digraph on a safe input (single-digit
%   state labels, so this intentionally avoids the known num2str-width
%   edge case, which is left for a fix-specific test later). Run this
%   script directly in MATLAB; it prints "All tests passed." on success
%   and errors out on the first failing check.
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

disp('All tests passed.');
