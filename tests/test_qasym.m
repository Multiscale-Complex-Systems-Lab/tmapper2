%TEST_QASYM hand-checkable correctness test for Qasym (modularity of an
%   asymmetric, weighted network). Run this script directly in MATLAB;
%   it prints "All tests passed." on success and errors out on the first
%   failing check.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));

% -- two disjoint fully-connected 3-node blocks (block-diagonal adjacency,
% no self-loops, no edges across blocks)
block = ones(3) - eye(3);
A = blkdiag(block, block);

% -- correct partition: one community per block
C_correct = [1;1;1;2;2;2];
Q_correct = Qasym(A, C_correct);

% -- trivial partition: everything in one community
C_merged = ones(6,1);
Q_merged = Qasym(A, C_merged);

% hand-derived expected values: N_edges=12, uniform P_ij=1/3
% Q_correct = 0.5, Q_merged = 0 (see derivation in code review notes)
tol = 1e-10;
assert(abs(Q_correct - 0.5) < tol, ...
    'Qasym should give Q=0.5 for the correct two-block partition.');
assert(abs(Q_merged - 0) < tol, ...
    'Qasym should give Q=0 for the trivial single-community partition.');
assert(Q_correct > Q_merged, ...
    'the correct partition should have higher modularity than the trivial one.');

disp('All tests passed.');
