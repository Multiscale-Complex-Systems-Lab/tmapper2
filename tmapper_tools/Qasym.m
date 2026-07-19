function Q = Qasym(A,C)
%QASYM modularity measure of asymmetric network with weighted edges.
%   Q = Qasym(A,C)
% input:
%   A: adjacency matrix, which may or may not be symmetric. A N-by-N matrix
%   where N is number of nodes.
%   C: community assignment of each nodes, a vector of N integer indices.
% output:
%   Q: modularity, a scalar. 
% -------------------------------------------------------------------------
% NOTE: 
%   The definition of Q here is adapted for asymmetric network with
%   weighted nodes from the cannonical definition of Fortunato (2010,
%   Physics Reports).
%
%{
Author: Mengsen Zhang <mengsenzhang@gmail.com> 2-25-2020
modifications:
(2-26-2020) remove adjustment for non-uniform node measure.
(7-19-2026) guard against a zero-edge network (previously NaN via 0/0);
now returns 0, matching calMod.m's convention of treating a network
with no edges as neither modular nor non-modular.

%}

N_edges = sum(A(:));% "2m" in other notations

if N_edges == 0
    Q = 0; % no edges: neither modular nor non-modular (matches calMod.m)
    return
end

k_source = sum(A,2); % source degree
k_sink = sum(A,1); % sink degree
P_ij = k_source*k_sink/N_edges; % null model

Q = sum(sum((A - P_ij).*(C(:)==C(:)')))/N_edges; % modularity

end

