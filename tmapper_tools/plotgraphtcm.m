function [h1, h2, cb, cb_, hg,D_geo, hs] = plotgraphtcm(g,x_label,t,nodemembers, varargin)
%PLOTGRAPHTCM plot a shape graph and its correspomding geodesic recurrence
%plot (a kind of temporal connectivity matrix). 
%   [h1,h2] = plotgraphtcm(g,x_label,t,nodemembers, ...)
% input:
%   g: a graph or digraph (MATLAB object). 
%   x_label: a label for each member of each node of the graph, assumed to
%   be a N-by-1 vector of integer indices, where N is the number of unique
%   members of all nodes.
%   t: time associated with each member of each node. a N-by-1 vector.
%   nodemembers: a numnodes-by-1 cell array. Each cell contains a vector of
%   integer indices, indicating which time points belong to this node.
% parameters:
%   nodesizerange: [s_min, s_max], where s_min is the smallest markersize
%   when plotting the nodes of the graph, and s_max is the largest
%   markersize.
%   nodesizemode: the method used to calculate node size. options: rank
%   (default, rank of node size), original (og node size), log (log of node
%   size)
%   colorlabel: label of the color axis (meaning of the color-coding of
%   nodes), default "attractor index".
%   cmap: colormap. passed on to matlab function `colormap`
%   labelmethod: how to color code each node based on members' labels.
%   Options: mode (default), mean, median.
% output:
%   h1: axis handle of the first subplot (the graph).
%   h2: axis handle of the second subplot (the geodesic recurrence plot).
%   cb: handle of the colorbar of graph
%   cb_: handle of the colorbar of recurrence plot
%   hg: handle of the graph
%   D_geo: the recurrence plot matrix.
%   hs: handle of the scatter plot overlay of the graph

%{
created by MZ, 9/13/2019
modifications:
(9/30/2019) adjust color range, node size for special cases, and
calculation of distances (change to unweighted)
(2/11/2020) add colormap options
(11/11/2020) add more handle output
(MZ 5/29/2023) allow options for labeling methods, return recurrence
matrix.allow using non-ranked node size. 
(MZ 3/12/2024) add option to change color limits for nodes
(MZ 7/4/2024) ensure time is column vector
(MZ 6/29/2025) clear up function by calling plottmgraph
%}

% -- check for unweighted graph
nodesize = cell2mat(cellfun(@(x) length(x), nodemembers, 'UniformOutput',0));% define node size
bsinglemember = all(nodesize==1);% there is only one member associated with each node.

% -- plotting
figure('position',[10,10,1000,400]);
% plot graph
subplot(1,2,1)
[h1, cb, hg, hs] = plottmgraph(g,x_label,nodemembers, varargin{:});

% plot geodesic recurrence plot (aka TCM)
if bsinglemember
    D_geo = distances(g,'Method','unweighted');
else
    D_geo = TCMdistance(g,nodemembers);
end
subplot(1,2,2)
imagesc(t,t,D_geo);
cb_ = colorbar;
colormap(gca, 'hot')
axis square
xlabel('time (s)')
ylabel('time (s)')
title('geodesic recurrence plot')
cb_.Label.String = 'path length';
h2 = gca;
end

