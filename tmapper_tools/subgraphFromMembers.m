function [g_sub,members_sub,sub_orig_nodeidx] =...
    subgraphFromMembers(g_simp,members,includemembers)
%SUBGRAPHFROMMEMBERS extract subgraph of a transition network based on
%members. This function is used to process temporal mapper outputs. 
%   
% Input:
%   g_simp: simplified transition network, a graph or digraph object. 
% 
%   members: a numnodes-by-1 cell array. Each cell contains a vector of
%   integer indices, indicating which time points belong to this node.
% 
%   includemembers: a interger array, containing a subset of time points
%   (in original indices used in input variable `members`).
% 
% Output:
%   g_sub: a subgraph of g_simp, which is a graph or digraph object. This
%   graph contains only nodes in the original g_simp that contains specific
%   members provided in `includemembers`. The graph should have fewer or an
%   equal number of nodes compared to g_simp.
% 
%   members_sub: a numnodes_sub-by-1 cell array. Each cell contains a
%   vector of integer indices, indicating which time points belong to this
%   node, which must be included in `includemembers`.
% 
%   sub_orig_nodeidx: a numnodes_sub-by-1 interger vector. 

%{
~ created by Mengsen Zhang (7/15/2024) ~
modifications:

%}
members_sub = cellfun(@(x) intersect(x,includemembers),members,'UniformOutput',false);
% -- extract the indices of the subgraph nodes in the original full graph. 
sub_orig_nodeidx = find(cellfun(@(x) ~isempty(x),members_sub));
% -- create subgraph
g_sub = subgraph(g_simp, sub_orig_nodeidx);
% -- clean up members
members_sub = members_sub(sub_orig_nodeidx);

end

