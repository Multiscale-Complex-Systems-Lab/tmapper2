function tidx_members = members2tidx(members, tidx)
%MEMBERS2TIDX translate positional-index members to real tidx values.
%   tidx_members = members2tidx(members, tidx)
% Use this when tidx is non-contiguous or offset (e.g. real timestamps
% with gaps): filtergraph's `members` output gives positional indices into
% your original data (1..N), not tidx values, so index into tidx yourself
% to recover the real time labels for each node's members.
% input:
%   members: a numnodes-by-1 cell array (e.g. from filtergraph), where each
%   cell contains a vector of positional indices into the original data
%   (rows of X/D, or elements of tidx) belonging to that node. This only
%   makes sense if `members` holds positional indices, i.e. the graph
%   passed to filtergraph had no Nodes.Name (see filtergraph.m).
%   tidx: the same tidx vector originally passed to tknndigraph.
% output:
%   tidx_members: a numnodes-by-1 cell array with the same shape as
%   members, but with each positional index replaced by its real tidx
%   value.
tidx_members = cellfun(@(m) tidx(m), members, 'UniformOutput', false);
end
