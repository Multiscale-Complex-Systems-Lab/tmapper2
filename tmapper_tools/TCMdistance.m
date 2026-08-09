function [TCM_pl] = TCMdistance(g,nodet,weighted)
%TCMDISTANCE calculate a time connectivity matrix where the edge is the
%minimal path length between two sample points.
%   [TCM_pl] = TCMdistance(g,nodet,weighted)
%   input:
%       g: matlab graph
%       nodet: members of each node as indices of time points, a cell array
%       weighted: whether to use the weight of the graph, default = false,
%       use as unweighted graph.
%   output:
%       TCM_pl: temporal connectivity using shortest path length on the
%       shape graph.
%{
created by MZ, 04-27-2019
modifications:
(8-23-2019) debug weight assignment -- no longer require input graph to be
weighted. also accomandate situation where t0~=0.
%}
if nargin<3 || isempty(weighted)
    weighted = false;
end
if ~weighted && ismember('Weight', g.Edges.Properties.VariableNames)
    % only when there are weights to strip: on an unweighted graph
    % distances() already returns hop counts, and touching g.Edges
    % materialises the whole edge table for nothing.
    g.Edges.Weight=ones(height(g.Edges),1);
end
% -- extract time
t = unique(cell2mat(nodet));
t_0 = min(t);
Nt = max(t) - t_0 + 1; % size by the full covered range, not just the count of
                       % distinct points, so gaps in nodet coverage correctly
                       % stay NaN instead of silently auto-growing with 0-fill.

% -- construct TCM from graph distance
TCM_pl = NaN(Nt,Nt);

distmat = distances(g);

% When each time point belongs to exactly one node -- which is what
% filtergraph produces, since its members are connected components and so
% partition the time points -- every (i,j) block below is written exactly
% once into an all-NaN matrix, which makes the nanmin a no-op. The double
% loop then collapses into one indexed assignment: look up each time
% point's node, and read off the node-to-node distance. That is ~57x
% faster on a 900-node network (8.0s -> 0.14s).
%   The loop is kept for the general case: a caller may hand in
% overlapping membership, and there the nanmin genuinely arbitrates.
allt = cell2mat(cellfun(@(x) x(:), nodet(:), 'UniformOutput', false));
if numel(allt) == numel(unique(allt))
    node_of_t = zeros(Nt,1);
    for i=1:g.numnodes
        node_of_t(nodet{i}-t_0+1) = i;
    end
    covered = node_of_t > 0;      % time points inside no node stay NaN
    covIdx = find(covered);
    nodeIdx = node_of_t(covIdx);
    % Filled in row blocks rather than as one indexed assignment: the
    % latter materialises a second full Nt-by-Nt double for the
    % right-hand side before writing it, doubling peak memory on exactly
    % the matrix that is already the largest thing here. A block at a
    % time keeps the temporary to a few hundred MB and costs nothing
    % measurable in speed.
    rowsPerBlock = max(1, floor(2e7 / max(numel(covIdx),1)));
    for b0 = 1:rowsPerBlock:numel(covIdx)
        b1 = min(b0+rowsPerBlock-1, numel(covIdx));
        TCM_pl(covIdx(b0:b1), covIdx) = distmat(nodeIdx(b0:b1), nodeIdx);
    end
else
    % -- assign diagonal elements to 0
    for i=1:g.numnodes
            TCM_pl(nodet{i}-t_0+1,nodet{i}-t_0+1) = 0;
    end

    % -- assign off diagonal elements
    for i=1:g.numnodes
        for j=i+1:g.numnodes
            TCM_pl(nodet{i}-t_0+1,nodet{j}-t_0+1) = nanmin(TCM_pl(nodet{i}-t_0+1,nodet{j}-t_0+1),distmat(i,j));
            TCM_pl(nodet{j}-t_0+1,nodet{i}-t_0+1) = nanmin(TCM_pl(nodet{j}-t_0+1,nodet{i}-t_0+1),distmat(j,i));
        end
    end
end


end

