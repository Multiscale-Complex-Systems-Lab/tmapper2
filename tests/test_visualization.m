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

disp('All tests passed.');
