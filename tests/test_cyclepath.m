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

disp('All tests passed.');
