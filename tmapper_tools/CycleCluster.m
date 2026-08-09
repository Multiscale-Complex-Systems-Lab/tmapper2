function [clusterIdx] = CycleCluster(allcycles,thres,varargin)
%CYCLECLUSTER cluster cycles based on the overlap between them. The
%fraction of overlap between two cycles is the number of shared nodes
%divided by the number of the union of nodes from two cycles. 
%   [clusterIdx] = CycleCluster(allcycles,thres,...)
% input:
%   allcycles: N-by-1 cell array, each cell contains the path of one cycle
%   thres: a number between 0 and 1, a cut-off threshold for the
%   clustering. Two cycles are candidates for the same cluster when their
%   overlap exceeds thres; whether they end up together also depends on
%   'linkage' below. 
% output: 
%   clusterIdx: N-by-1 integer array, each integer is the index of a
%   loop-cluster. Integers are from 1 to M. 
% parameters:
%   plotmat: plot the overlap matrix (N-by-N). Default true.
%   plotmds: plot the 2D mds projection. Default false.
%   plothist: plot the histogram of linkage distance. Default true.
%   reordermat: reorder rows/cols of overlap matrix according to cluster
%   assignment. Default true.
%   linkage: the agglomeration method handed to linkage(). Default
%   'complete', which is what this function has always done despite an
%   older comment here reading "single linkage".
%     'complete' requires EVERY pair in a cluster to overlap above thres,
%       so a cycle only joins a group it resembles as a whole.
%     'single' merges on ANY pair above thres, matching the simpler
%       reading "overlap>thres implies same cluster" -- but it chains:
%       cycles sharing nothing can land together via an intermediary.
%   The two genuinely differ. On three cycles where c1-c2 and c2-c3 each
%   overlap 0.333 and c1-c3 share nothing, at thres=0.2 'complete' gives
%   [1 2 2] and 'single' gives [1 1 1]. Cycle clusters drive the whole
%   path decomposition, so this choice propagates -- change it knowingly.
%{
~ Author: Mengsen Zhang <mengsenzhang@gmail.com> 9-1-2020 ~
modifications:
(7-19-2026) guard Nc<=1: linkage/cluster are not meaningful for 0 or 1
observations and previously crashed (0 cycles) or silently returned a
mismatched-length clusterIdx (1 cycle, corrupting downstream callers
like CycleClusterConn). Now returns the trivial result directly.
%}

p=inputParser;
p.addParameter('plotmat',true)
p.addParameter('plotmds',false)
p.addParameter('plothist',true)
p.addParameter('reordermat',true)
p.addParameter('linkage','complete') % see the note in the help above
p.parse(varargin{:})
par=p.Results;


% -- compute overlap between cycles
Nc=length(allcycles);

if Nc <= 1
    clusterIdx = ones(Nc,1); % 0 or 1 cycles: nothing meaningful to cluster
    return
end

prct_overlap = nan(Nc,Nc);

for ii=1:Nc
    for jj=1:Nc 
        prct_overlap(ii,jj) = length(intersect(allcycles{ii},allcycles{jj}))...
            /length(union(allcycles{ii},allcycles{jj}));
    end
end


% -- clustering
% :: visualize clusters with MDS
if par.plotmds
    Y=cmdscale(1-prct_overlap,2);
    figure
    scatter(Y(:,1),Y(:,2))
end

% :: agglomerate. 'complete' by default -- see the 'linkage' note in the
% help; an earlier comment here claimed single linkage, which this has
% never done.
validLinkage = {'single','complete','average','weighted','centroid','median','ward'};
if ~(ischar(par.linkage) || isstring(par.linkage)) || ~ismember(lower(char(par.linkage)), validLinkage)
    error('CycleCluster:invalidLinkage', ...
        'linkage must be one of: %s.', strjoin(validLinkage, ', '));
end
Z=linkage(squareform(1-prct_overlap),lower(char(par.linkage)));
% :: visualize linkage
if par.plothist
    % figure
    % dendrogram(Z)
    figure;
    histogram(1-Z(:,3),linspace(0,1,21))
    hold on
    plot(thres*[1 1],ylim)
    xlabel('overlap')
    ylabel('count')
end

clusterIdx = cluster(Z,'cutoff',1-thres,'criterion','distance');

% -- visualize overlaps between cycles
if par.plotmat
    figure
    if par.reordermat
        [~,cycorder]=sort(clusterIdx);
        imagesc(prct_overlap(cycorder,cycorder));
    else
        imagesc(prct_overlap);
    end
    set(gca,'ydir','normal')
    hcb=colorbar;
    hcb.Label.String='fraction of overlap';
    caxis([0 1])
    axis square
    if par.reordermat
        xlabel('cycle/path index (reordered)')
        ylabel('cycle/path index (reordered)')
    else
        xlabel('cycle/path index')
        ylabel('cycle/path index')
    end
end

end

