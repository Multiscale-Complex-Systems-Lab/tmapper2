%TEST_VISUALIZATION smoke tests for plottmgraph, plotgraphtcm, and
%   TCMdistance on top of the core pipeline output. Run this script
%   directly in MATLAB; it prints "All tests passed." on success and
%   errors out on the first failing check.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));

rng(0);

% -- synthetic data: 20 time points, 2 well-separated spatial clusters
N1 = 10; N2 = 10;
X = [repmat([0 0],N1,1) + 0.01*randn(N1,2);
     repmat([10 10],N2,1) + 0.01*randn(N2,2)];
N = size(X,1);
tidx = (1:N)';
D = pdist2(X,X);
k = 3;

g = tknndigraph(D,k,tidx);
[g_simp, members] = filtergraph(g,5,'reciprocal',true);
colorvar = X(:,1); % arbitrary per-time-point coloring variable

% -- plottmgraph: default (no scatter overlay)
[h1,cb,hg,hs] = plottmgraph(g_simp,colorvar,members);
assert(isgraphics(h1,'axes'), 'plottmgraph should return an axes handle.');
assert(isgraphics(cb,'colorbar'), 'plottmgraph should return a colorbar handle.');
assert(isa(hg,'matlab.graphics.chart.primitive.GraphPlot'), 'plottmgraph should return a GraphPlot handle.');
assert(isempty(hs), 'hs should be empty when nodescatter is false (default).');
close all

% -- plottmgraph: with scatter overlay
[~,~,~,hs2] = plottmgraph(g_simp,colorvar,members,'nodescatter',true);
assert(isgraphics(hs2,'scatter'), 'hs should be a scatter handle when nodescatter is true.');
close all

% -- plotgraphtcm
t = tidx;
[pg_h1,pg_h2,~,~,~,D_geo,~] = plotgraphtcm(g_simp,colorvar,t,members);
assert(isgraphics(pg_h1,'axes') && isgraphics(pg_h2,'axes'), ...
    'plotgraphtcm should return two axes handles.');
assert(isequal(size(D_geo),[N N]), 'plotgraphtcm recurrence matrix should be N-by-N.');
assert(all(diag(D_geo)==0), 'plotgraphtcm recurrence matrix diagonal should be zero.');
close all

% -- TCMdistance directly
TCM = TCMdistance(g_simp, members);
assert(isequal(size(TCM),[N N]), 'TCMdistance output should be N-by-N.');
assert(all(diag(TCM)==0), 'TCMdistance diagonal should be zero.');

% -- plotgraphtcm's bsinglemember branch: with d=1 every node is
% guaranteed singleton (see test_core_pipeline.m), so plotgraphtcm should
% take the distances(g,'Method','unweighted') shortcut instead of calling
% TCMdistance. Both paths should agree mathematically when every node is
% its own singleton member, which we cross-check directly.
[g_simp1, members1] = filtergraph(g,1,'reciprocal',true);
[~,~,~,~,~,D_geo1,~] = plotgraphtcm(g_simp1,colorvar,t,members1);
TCM1 = TCMdistance(g_simp1, members1);
assert(isequal(size(D_geo1),[N N]), 'plotgraphtcm (singleton case) recurrence matrix should be N-by-N.');
assert(max(abs(D_geo1(:) - TCM1(:))) < 1e-9, ...
    'with every node singleton, the bsinglemember shortcut should agree with TCMdistance.');
close all

% -- TCMdistance with weighted=true should use real edge weights instead
% of forcing them to 1. 3 nodes: 1->2 (w=5), 2->3 (w=1), 1->3 (w=100).
% Unweighted: dist(1,3)=1 (direct edge, hop count). Weighted: dist(1,3)=6
% (5+1 via node 2, cheaper than the expensive direct edge).
dg_w = digraph([1 2 1],[2 3 3],[5 1 100]);
nodet_w = {1;2;3};
TCM_unweighted = TCMdistance(dg_w, nodet_w, false);
TCM_weighted = TCMdistance(dg_w, nodet_w, true);
assert(TCM_unweighted(1,3) == 1, 'unweighted TCMdistance should use hop count (1) between node 1 and 3.');
assert(TCM_weighted(1,3) == 6, 'weighted TCMdistance should use the cheaper weighted path (5+1=6) between node 1 and 3.');

% -- plottmgraph nodesizemode variants: use sizes [1,2,10] (not evenly
% spaced, not a geometric progression) so rank/log/original genuinely
% disagree -- evenly-spaced or geometric-progression sizes would make
% some of these modes coincidentally identical.
g3 = digraph(zeros(3)); % 3 isolated nodes, no edges (digraph(3) is NOT the same -- it's a 1x1 adjacency matrix, giving 1 node)
members_size = {1; [2;3]; (4:13)'}; % sizes 1, 2, 10
x_label3 = ones(13,1);

[~,~,hg_rank] = plottmgraph(g3,x_label3,members_size,'nodesizemode','rank');
assert(max(abs(hg_rank.MarkerSize - [1 5.5 10])) < 1e-9, ...
    'rank mode should give evenly-spaced marker sizes [1, 5.5, 10] for 3 distinct ranks.');

[~,~,hg_log] = plottmgraph(g3,x_label3,members_size,'nodesizemode','log');
assert(max(abs(hg_log.MarkerSize - [1 3.709 10])) < 1e-3, ...
    'log mode should give logarithmically-spaced marker sizes, differing from rank mode.');

[~,~,hg_orig] = plottmgraph(g3,x_label3,members_size,'nodesizemode','original');
assert(max(abs(hg_orig.MarkerSize - [1 2 10])) < 1e-9, ...
    'original mode should rescale the raw sizes [1,2,10] directly (no rank/log transform).');
close all

% -- plottmgraph labelmethod variants: 3 nodes with distinct label
% distributions to discriminate mode/mean/median/none.
members_label = {[1;2;3]; [4;5]; 6};
x_label_vals = [10;10;20;5;7;100];
% node1 -> {10,10,20}: mode=10, mean=13.333, median=10
% node2 -> {5,7}: mode=5 (smallest of an all-tied set), mean=6, median=6
% node3 -> {100}: 100 regardless of method

[~,~,hg_mode] = plottmgraph(g3,x_label_vals,members_label,'labelmethod','mode');
assert(isequal(hg_mode.NodeCData(:), [10;5;100]), 'mode labelmethod gave unexpected NodeCData.');

[~,~,hg_mean] = plottmgraph(g3,x_label_vals,members_label,'labelmethod','mean');
assert(max(abs(hg_mean.NodeCData(:) - [13+1/3;6;100])) < 1e-9, 'mean labelmethod gave unexpected NodeCData.');

[~,~,hg_median] = plottmgraph(g3,x_label_vals,members_label,'labelmethod','median');
assert(isequal(hg_median.NodeCData(:), [10;6;100]), 'median labelmethod gave unexpected NodeCData.');

[~,~,hg_none] = plottmgraph(g3,x_label_vals,members_label,'labelmethod','none');
assert(isequal(hg_none.NodeCData(:), [0;0;0]), 'none labelmethod should give all-zero NodeCData.');
close all

% -- plottmgraph default nodemembers/x_label (both omitted): should fall
% back to one singleton member per node and a constant x_label, so
% buniform=true and every node gets the same "uniform" marker size.
[~,~,hg_default] = plottmgraph(g3);
assert(isequal(hg_default.NodeCData(:), [1;1;1]), ...
    'default x_label should be constant (ones) when omitted.');
assert(max(abs(hg_default.MarkerSize - 4)) < 1e-9, ...
    'default nodemembers (all singleton) should give the uniform marker size 1+range/numnodes=4.');
close all

% -- clim edge case: a constant x_label (no variation) previously could
% crash inside plottmgraph; now it should simply skip the caxis/clim call
% and run without error.
x_label_const = 5*ones(13,1);
[h1_const, cb_const] = plottmgraph(g3,x_label_const,members_size);
assert(isgraphics(h1_const,'axes') && isgraphics(cb_const,'colorbar'), ...
    'plottmgraph should run without error when x_label has no variation (clim edge case).');
close all

disp('All tests passed.');
