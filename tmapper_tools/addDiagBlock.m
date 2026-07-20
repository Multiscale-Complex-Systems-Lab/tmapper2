function ax = addDiagBlock(ax,labels,cmap)
%ADDDIAGBLOCK add blocks on the diagonal of a square matrix to label task
%structures.
%   ax = addDiagBlock(ax,labels,cmap)
% NOTE: must be called immediately after plotting a square matrix with
% imagesc into `ax` (e.g. via CycleCluster's overlap-matrix plot), with
% no other objects added to the axes afterward -- N_samples is inferred
% from ax.Children(end).CData, the imagesc image, which is assumed to be
% the axes' last (i.e. first-drawn) child. Also depends on findtaskn.m
% and remapRange.m.
% input:
%   ax: axes handle, default current axes
%   labels: N-by-1 vector of positive integers, for a N-by-N matrix to be
%   labelled.
%   cmap: M-by-3 matrix, provide a colormap. M is the number of unique
%   labels.
% output:
%   ax: axes handle
%{
created by MZ, 2-13-2020
modifications:
(9-3-2020) changed range remap: separate start point and block-size remap.
(7-19-2026) document the ax.Children(end).CData / findtaskn / remapRange
dependencies, which were previously undocumented and easy to break.
%}

if isempty(ax)
    ax = gca;
end

ulabels = unique(labels);
N_ulabels = length(ulabels);
N_samples = length(ax.Children(end).CData);


for n=1:N_ulabels
    [block_start, ~, block_size] = findtaskn(labels==ulabels(n)); % boundaries of a single task
    % -- draw blocks
    for n_ts = 1:length(block_start)
        block_pos_ind = [block_start(n_ts) block_start(n_ts) block_size(n_ts) block_size(n_ts)];
        rectangle('position', [remapRange(block_pos_ind(1:2),1,N_samples+1,ax.XLim(1), ax.XLim(2)),...
            block_pos_ind(3:4)/N_samples*(ax.XLim(2)-ax.XLim(1))],...
            'edgecolor',cmap(ulabels==ulabels(n),:),'linewidth',3)
    end
end

end



