function [h1, cb, hg, hs] = plottmgraph(g,x_label,nodemembers, varargin)
%PLOTTMGRAPH plot a temporal mapper graph without recurrence plot. 
%   [h1,cb,hg,hs] = plottmgraph(g,x_label,nodemembers, ...)
% input:
%   g: a graph or digraph (MATLAB object). 
%   x_label: a label for each member of each node of the graph, assumed to
%   be a N-by-1 vector of integer indices, where N is the number of unique
%   members of all nodes.
%   nodemembers: a numnodes-by-1 cell array. Each cell contains a vector of
%   integer indices, indicating which time points belong to this node.
% parameters:
%   nodesizerange: [s_min, s_max], where s_min is the smallest markersize
%   when plotting the nodes of the graph, and s_max is the largest
%   markersize.
%   nodesizemode: the method used to calculate node size. options: log
%   (default, log of node size), rank (rank of node size), original (og
%   node size)
%   colorlabel: label of the color axis (meaning of the color-coding of
%   nodes), default "x_label".
%   cmap: colormap. passed on to matlab function `colormap`
%   labelmethod: how to color code each node based on members' x_labels.
%   Options: mode (default), mean, median, none (everything same color), or
%   a function handle applied as labelmethod(x_label(members)) per node.
%   nodeclim: [min max] of the color axis for the node colors. Default
%   [], which uses [min(x_label) max(x_label)].
%   nodescatter: whether to overlay a scatter plot on top of the graph
%   nodes (can look cleaner for dense graphs). Default false.
%   ax: target axes to plot into (e.g. a uiaxes inside an App Designer
%   app). Default [], which uses gca (creating a new figure if none
%   exists), matching prior behavior.
% output:
%   h1: axis handle of the plot.
%   cb: handle of the colorbar of graph
%   hg: handle of the graph
%   hs: handle of the scatter plot overlay of the graph

%{
~ created by MZ, 7/5/2024, adapted from PLOTGRAPHTCM ~
modifications:
(6/29/2025) add option to not use scatterplot. correct rank.
(9/23/2025) edge case clim when there is no color
(7-19-2026) fix header: nodesizemode's actual default is 'log', not
'rank' as previously documented; also document 'nodeclim' and
'nodescatter', which existed but were missing from the parameter list.
(7-23-2026) add 'ax' parameter so this can render into a caller-supplied
target axes (e.g. a uiaxes inside an App Designer app) instead of
always creating/using a new figure via gca.

%}

p = inputParser;
p.addParameter('nodesizerange',[1 10]);
p.addParameter('nodesizemode','log')% whether of not use ranked node size
p.addParameter('colorlabel',"x\_label")% what variable does x_label reflect
p.addParameter('cmap','jet') % colormap
% p.addParameter('normalize',false) % whether or not
p.addParameter('labelmethod','mode')% methods for labeling nodes
p.addParameter('nodeclim',[])% [min max] of the color axis for the node colors
p.addParameter('nodescatter',false)% plot scatterplot overlay of nodes (to look better)
p.addParameter('ax',[])% target axes; default [] uses gca
p.parse(varargin{:});

par = p.Results;

% -- check nodes
if ~exist("nodemembers","var") || isempty(nodemembers)
    nodemembers = num2cell((1:g.numnodes)');
end

% -- check labels for members
if ~exist("x_label","var") || isempty(x_label)
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
            nodesize = tiedrank(nodesize);% the marker size reflects the rank of the node size
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
if isempty(par.ax)
    ax = gca; % preserves prior behavior: current axes, or a new figure if none exists
else
    ax = par.ax;
end

% plot graph
hg=plot(ax,g,'EdgeAlpha',0.3,'EdgeColor','k','NodeCData',nodelabel,'NodeLabel','',...
    'Layout','force','UseGravity',true,'ArrowSize',5,'MarkerSize',nodesize);
axis(ax,'equal')
axis(ax,'off')
cb=colorbar(ax);
cb.Label.String = par.colorlabel;
if diff(par.nodeclim)~=0% if there is a range of values
    caxis(ax,par.nodeclim)
end
colormap(ax, par.cmap)
h1 = ax;
% -- overlay with scatter plot for better visualization
if par.nodescatter
    hold(ax,'on')
    [~,idx] = sort(hg.MarkerSize,'ascend'); % --- determine scatter order
    % reshape to a column: scatter() ambiguously treats an exactly-3-
    % element ROW color vector as a single RGB triplet rather than
    % per-point color data, which breaks (errors on redraw) for
    % exactly-3-node graphs whenever the values fall outside [0,1]. A
    % column vector is never misinterpreted this way.
    hs=scatter(ax,hg.XData(idx),hg.YData(idx),hg.MarkerSize(idx).^2,reshape(hg.NodeCData(idx),[],1),...
        'filled','MarkerEdgeColor','k','LineWidth',0.2);
else
    hs = [];
end
end

