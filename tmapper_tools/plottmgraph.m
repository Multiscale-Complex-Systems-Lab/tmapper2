function [h1, cb, hg, hs] = plottmgraph(g,x_label,nodemembers, varargin)
%PLOTTMGRAPH plot a temporal mapper graph without recurrence plot. 
%   [h1,cb,hg] = plottmgraph(g,x_label,t,nodemembers, ...)
% input:
%   g: a graph or digraph (MATLAB object). 
%   x_label: a label for each member of each node of the graph, assumed to
%   be a N-by-1 vector of integer indices, where N is the number of unique
%   members of all nodes.
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
%   h1: axis handle of the plot.
%   cb: handle of the colorbar of graph
%   hg: handle of the graph
%   hs: handle of the scatter plot overlay of the graph

%{
~ created by MZ, 7/5/2024, adapted from PLOTGRAPHTCM ~
modifications:
(6/29/2025) add option to not use scatterplot

%}

p = inputParser;
p.addParameter('nodesizerange',[1 20]);
p.addParameter('nodesizemode','rank')% whether of not use ranked node size
p.addParameter('colorlabel','attractor index')
p.addParameter('cmap','jet') % colormap
% p.addParameter('normalize',false) % whether or not 
p.addParameter('labelmethod','mode')% methods for labeling nodes
p.addParameter('nodeclim',[])% [min max] of the color axis for the node colors
p.addParameter('nodescatter',false)% plot scatterplot overlay of nodes (to look better)
p.parse(varargin{:});

par = p.Results;

% -- check nodes
if nargin<4 || isempty(nodemembers)
    nodemembers = num2cell((1:g.numnodes)');
end

% -- check labels for members
if nargin<2 || isempty(x_label)
    x_label = ones(length(unique(cell2mat(nodemembers(:)))),1);
end

% -- check other parameters
if isempty(par.nodeclim)
    par.nodeclim = double([min(x_label) max(x_label)]);
end
% -- define node size
nodesize = cell2mat(cellfun(@(x) length(x), nodemembers, 'UniformOutput',0));
bsinglemember = all(nodesize==1);% there is only one member associated with each node.
buniform = length(unique(nodesize))==1; % if all nodes are of the same size
if ~buniform%adjust nodesize with rank
    switch par.nodesizemode
        case 'rank'
            nodesize = rankval(nodesize);% the marker size reflects the rank of the node size
        case 'log'
            nodesize = log10(nodesize);% on log scale.
    end
    nodesize = rescale(nodesize, min(par.nodesizerange), max(par.nodesizerange));
else%adjust nodesize with number of nodes
    nodesize = ones(g.numnodes,1)*(par.nodesizerange(1)+range(par.nodesizerange)/g.numnodes);
end

% -- define node labels
nodelabel = findnodelabel(nodemembers,x_label,'labelmethod',par.labelmethod);

% -- plotting
% plot graph
hg=plot(g,'EdgeAlpha',0.3,'EdgeColor','k','NodeCData',nodelabel,'NodeLabel','',...
    'Layout','force','UseGravity',true,'ArrowSize',5,'MarkerSize',nodesize); 
axis equal
axis off
cb=colorbar;
cb.Label.String = par.colorlabel;
caxis(par.nodeclim)
colormap(gca, par.cmap)
h1 = gca;
% -- overlay with scatter plot for better visualization
if par.nodescatter
    hold on
    [~,idx] = sort(hg.MarkerSize,'ascend'); % --- determine scatter order
    hs=scatter(hg.XData(idx),hg.YData(idx),hg.MarkerSize(idx).^2,hg.NodeCData(idx),...
        'filled','MarkerEdgeColor','k','LineWidth',0.2);
else
    hs = [];
end
end

