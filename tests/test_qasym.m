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

% -- asymmetric, weighted, directed network: this is Qasym's actual
% differentiator (the symmetric case above doesn't exercise it). 2
% communities {1,2},{3,4}, with directed, unevenly-weighted edges:
% 1->2 (w=2), 2->1 (w=1), 3->4 (w=3), 4->3 (w=1), and one cross-community
% edge 2->3 (w=1, one direction only). Hand-derived expected Q=0.375.
A_dir = zeros(4);
A_dir(1,2)=2; A_dir(2,1)=1; A_dir(3,4)=3; A_dir(4,3)=1; A_dir(2,3)=1;
C_dir = [1;1;2;2];
Q_dir = Qasym(A_dir, C_dir);
assert(abs(Q_dir - 0.375) < tol, 'Qasym should give Q=0.375 for the asymmetric weighted case.');

% -- confirm edge weights are actually used (not silently ignored): the
% binarized version of the same directed structure (all weights -> 1)
% has hand-derived Q=0.32, genuinely different from the weighted result.
A_bin = double(A_dir ~= 0);
Q_bin = Qasym(A_bin, C_dir);
assert(abs(Q_bin - 0.32) < tol, 'Qasym on the binarized structure should give Q=0.32.');
assert(abs(Q_dir - Q_bin) > tol, 'weighted and binarized Q should genuinely differ -- weights must matter.');

% -- zero-edge guard: an all-zero adjacency matrix previously gave Q=NaN
% (unguarded 0/0 division); now matches calMod.m's convention and
% returns 0 (neither modular nor non-modular).
Q_zero = Qasym(zeros(4), C_dir);
assert(Q_zero == 0, 'Qasym should return 0 (not NaN) for an all-zero adjacency matrix.');

disp('All tests passed.');
