function [g_simp, members, nodesize, D_simp] = filtergraph(g,d,varargin)
%FILTERGRAPH filter a graph g to produce a simpler one where nodes under
%"distance" d will be collapsed to a single node. Here we use "distance" in
%a loose sense, since "g" can be a directed graph, thus the "distance" or
%path length is not necessarily symmetric. 
%   [g_simp, members, nodesize, D_simp] = filtergraph(g,d,'reciprocal',1)
% input:
%   g: a graph or digraph (MATLAB object), to be simplified
%   d: a threshold under which orginal nodes will be collapsed to a new
%   node. 
% parameters:
%   reciprocal: whether we require both the path length from x to y and
%   from y to x to be under d in the filtering step. Default, true.
% output:
%   g_simp: the simplified graph (analogous to a Mapper shape graph)
%   members: members of the old graph (old nodes) in each new node. If g
%   has no Nodes.Name (e.g. straight from tknndigraph), members contains
%   the positional indices of g's nodes (1..numnodes(g)) -- NOT tidx
%   values, even if tidx was non-contiguous or offset when g was built.
%   Use members2tidx to translate positional-index members back to real
%   tidx values if needed. If g does have Nodes.Name, members contains
%   those names instead.
%   nodesize: # members in each new node
%   D_simp: simplified "distance" matrix. This gives the shortest distance
%   between any two group of "members" in the original graph.
% --------------------------- what is this ------------------------------
% Complimenting the philosophy behind a Mapper shape graph, this function
% simplify a larger graph (directed or undirected) to a more compact one by
% contracting some nodes in the old graph into a single node of the new,
% compact graph, together with a map "f" from a set of the old nodes to
% each new node.
% This simplification takes three steps:
% 1. construct a filtered graph, whose connected components will be mapped
% to the nodes of the new graph. Specifically, this graph only retains
% connectivity between old node x and y, iff the shortest path length (pl)
% between x and y is less than a threshold "d" (we can either require
% pl(x,y) and pl(y,x) to be both less than d or either).
% 2. construct a new, simplified graph whose nodes (new nodes) are
% associated with the connected components of the filtered graph from step
% 3. There is a link from new node x to new node y, iff there is at least
% one link from f^-1(x) to f^-1(y) in the old graph "g", and the average
% weight of links from f^-1(x) to f^-1(y) in the old graph "g" is the
% weight of the link in the simplified graph. 
% -----------------------------------------------------------------------
%{
created by MZ, 9/12/2019
modifications:

%}

% -- validate required inputs
if ~isa(g,'graph') && ~isa(g,'digraph')
    error('filtergraph:invalidInput','g must be a MATLAB graph or digraph object.');
end
if ~isscalar(d) || ~isreal(d) || d <= 0
    error('filtergraph:invalidInput','d must be a positive real scalar.');
end

p=inputParser();
p.addParameter('reciprocal',1);% if require pl(x,y)<d and pl(y,x)<d (pl = path length)
p.parse(varargin{:});
par = p.Results;

A = weightedAdj(g);% adjacency matrix
D = distances(g);% geodesic distance

% -- connectivity within a distance threshold
if par.reciprocal
    A_ = (D < d) & (D' < d);
else
    A_ = (D < d) | (D' < d);
end
A_ = zerodiag(A_); % remove self-loop

% -- create graph out of nodes within said threshold
if ismember('Name', g.Nodes.Properties.VariableNames)
    g_ = graph(A_,g.Nodes.Name);
else 
    g_ = graph(A_);
end

% -- find connected components (define the new nodes)
idx_newnodes = conncomp(g_);
if ismember('Name', g.Nodes.Properties.VariableNames)
    [members, nodesize] = index2cell(idx_newnodes,g_.Nodes.Name);
else
    [members, nodesize] = index2cell(idx_newnodes);
end

% -- define distance between new nodes
D_simp = simplifyDistance(D,idx_newnodes); % shortest path between new nodes. 

% -- construct simplified graph
g_simp = digraph(simplifyAdj(A,idx_newnodes),'OmitSelfLoops');
end

function A_simp = simplifyAdj(A, idx_newnodes)
% SIMPLIFYADJ simplifiy adjacency matrix A, such that A_simp(i,j) reflects
% the average connectivity between blocks of A.
%{
(7-23-2026) vectorized: sort nodes into contiguous per-group blocks,
then reduce via two passes of N_newnodes vectorized sum operations over
whole row/column slices, replacing an O(N_newnodes^2 * N) nested loop
that recomputed idx_newnodes==n/==m masks on every (n,m) pair --
profiling showed this was the dominant cost of filtergraph at realistic
graph sizes (~12.5s of an ~18.8s total on a 2863-node graph;
distances() itself took 0.08s). An accumarray-with-function-handle
version was tried first but gave only a ~2.5x speedup: accumarray falls
back to a per-bin loop internally for any function other than the
default @sum, so it isn't actually vectorized the way a bare @sum call
is. Assumes idx_newnodes uses contiguous labels 1..N_newnodes, matching
its sole caller conncomp() (same assumption the original loop made via
idx_newnodes==n for n=1:N_newnodes).
%}
    N_newnodes = length(unique(idx_newnodes));
    N = size(A,1);

    [~, order] = sort(idx_newnodes);
    A_sorted = A(order, order);
    g_sorted = idx_newnodes(order);
    group_start = [1; find(diff(g_sorted(:)) ~= 0) + 1];
    group_end = [group_start(2:end) - 1; N];
    group_size = group_end - group_start + 1;

    A_row_sum = zeros(N_newnodes, N);
    for n = 1:N_newnodes
        A_row_sum(n,:) = sum(A_sorted(group_start(n):group_end(n), :), 1);
    end

    A_col_sum = zeros(N_newnodes, N_newnodes);
    for m = 1:N_newnodes
        A_col_sum(:,m) = sum(A_row_sum(:, group_start(m):group_end(m)), 2);
    end

    A_simp = A_col_sum ./ (group_size * group_size');
end

function D_simp = simplifyDistance(D, idx_newnodes)
% SIMPLIFYDISTANCE given a distance matrix D, and a node-assignment vector
% idx_newnodes.
%{
(7-23-2026) vectorized, see simplifyAdj -- same two-pass slice
reduction, block-min instead of block-mean/sum.
%}
    N_newnodes = length(unique(idx_newnodes));
    N = size(D,1);

    [~, order] = sort(idx_newnodes);
    D_sorted = D(order, order);
    g_sorted = idx_newnodes(order);
    group_start = [1; find(diff(g_sorted(:)) ~= 0) + 1];
    group_end = [group_start(2:end) - 1; N];

    D_row = zeros(N_newnodes, N);
    for n = 1:N_newnodes
        D_row(n,:) = min(D_sorted(group_start(n):group_end(n), :), [], 1);
    end

    D_simp = zeros(N_newnodes, N_newnodes);
    for m = 1:N_newnodes
        D_simp(:,m) = min(D_row(:, group_start(m):group_end(m)), [], 2);
    end
end

function [members, nodesize] = index2cell(idx_newnodes,oldnodenames)
% INDEX2CELL convert a vector of labels of new nodes for each old nodes
% (idx_newnodes) to a cell array where each cell contains the names of the
% members of each new node. "nodesize" gives the size of the new nodes.
    if nargin<2 || isempty(oldnodenames)
        oldnodenames = (1:length(idx_newnodes))';
    end
    
    uidx = unique(idx_newnodes);% unique indices of new nodes
    Nidx = length(uidx);% number of new nodes
    
    members = cell(Nidx,1);% 1 cell = old nodes included in a new node
    nodesize = zeros(Nidx,1);% size of new node
    
    for n = 1:Nidx
        members{n} = oldnodenames(idx_newnodes == uidx(n));
        nodesize(n) = length(members{n});
    end
end

