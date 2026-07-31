function [g, par] = tknndigraph(XorD,k,tidx,varargin)
%TKNNDIGRAPH construct a directed graph based on k-nearest neighbors which
%much include its temporal neighbors. Here we do so by simply set the
%distance between consecutive time points to zero before running knn.
%   g = tknndigraph(XorD,k,tidx)
% input:
%   XorD: a N-by-d matrix (X) of the coordinates of N points in d-sim
%       space, or a N-by-N distance matrix (D). If the input is X, D is
%       computed from X based on Euclidean distances. 
%   k: # nearest neighbors
%   tidx: a vector of N integers, two points x, y are considered temporal
%   neighbors iff tidx[x]+1 = tidx[y] or tidx[x]-1 = tidx[y].
% output:
%   g: matlab graph object (unweighted, directed). Node i of g corresponds
%   to row i of XorD / element i of tidx (i.e. node identity is the
%   position in your input arrays, not the value of tidx(i)).
%   par: parameters used
% parameters:
%   reciprocal: whether to enforce spatial-knn neighbors to be reciprocal.
%   default is true
%   timeExcludeSpace: enforce temporal neighbors cannot be spatial
%   neighbors. default is true.
%   timeExcludeRange: how many time points following each time points is
%   considered the temporal neighborhood (in the range samples cannot be
%   spatial neighbors). default is 1.
%   maxNeighborDist: maximal distance between two points for them to be
%   considered as spatial neighbors. Default, Inf (so no max). If
%   maxNeighborDistPrct is also given, actual threshold will be the min of
%   the two.
%   maxNeighborDistPrct: maximal percentile distance between two points for
%   them to be considered as spatial neighbors. Taken over the FINITE
%   distances only -- pairs already excluded from being spatial neighbors
%   (the diagonal, and temporal pairs within timeExcludeRange) are held as
%   Inf internally, and counting them would drag the cutoff upward.
%   Default 100 (so no max). If
%   maxNeighborDist is also given, actual threshold will be the min of the
%   two. 
%{
created by MZ, 8-16-2019
modifcations:
(8-20-2019) add option to not enforce reciprocity.
(2-5-2020) add option to determine whether temporal link can be a spatial
link. parameter: timeExcludeSpace
(3-26-2024) add option to define time range to exclude for spatial knn
calculation. enforced spatial knn to not include temporal neighbors. Reduce
k by 1 relative to previous versions will yield same result.
(6-29-2025) handle edge case of duplicate points. add max distances.
(7-25-2026) error on NaN in the (computed) distance matrix instead of
silently propagating it into a degenerate graph -- callers must remove
or impute missing data themselves (e.g. via rmmissing).

%}

% -- validate required inputs
if ndims(XorD) ~= 2
    error('tknndigraph:invalidInput','XorD must be a 2D matrix.');
end
if ~isscalar(k) || k < 1 || k ~= round(k)
    error('tknndigraph:invalidInput','k must be a positive integer scalar.');
end
tidx = tidx(:);
if length(tidx) ~= size(XorD,1)
    error('tknndigraph:invalidInput','tidx must have the same number of elements as rows of XorD.');
end

p = inputParser;
p.addParameter('reciprocal',true)% spatially reciprocal
p.addParameter('timeExcludeSpace',true)% whether temporal links are allow to be spatial links
p.addParameter('timeExcludeRange',1); % how many time links to exclude
p.addParameter('maxNeighborDist',Inf); % maximal distance between two points for them to be considered as spatial neighbors
p.addParameter('maxNeighborDistPrct',100); % maximal percentile distance between two points for them to be considered as spatial neighbors
p.parse(varargin{:})
par = p.Results;
par.k = k;

% -- check input and obtain distance matrix D
[nr,nc]=size(XorD);
if nr~=nc || any(any(XorD~=XorD'))
    D = pdist2(XorD,XorD);
else
    D = XorD;
end

% -- reject missing data outright rather than silently degrading: NaN
% propagates through pdist2/zscore-style computations (a NaN coordinate
% poisons every distance touching it), which would otherwise produce a
% network with no real spatial edges without any indication why.
if any(isnan(D(:)))
    error('tknndigraph:missingData', ...
        ['XorD contains NaN values (or produces them once converted to a distance matrix). ' ...
        'Remove or impute missing data before calling tknndigraph, e.g. via rmmissing.']);
end

Nn = length(D); % number of nodes

if k >= Nn
    error('tknndigraph:invalidInput','k must be smaller than the number of points (%d).',Nn);
end

D(logical(eye(Nn))) = Inf; % exclude self-loops

% -- find indices for temporal links D_{i(t),i(t+1)}
% Built as sparse bands rather than by OR-ing shifted full Nn-by-Nn
% diagonals: circshift(diag(...),n,2) allocated a whole Nn-by-Nn matrix on
% every one of timeExcludeRange iterations, which dominated this function
% for realistic texclude. Each band is just the pairs (i, i+n) for the i
% that have a temporal successor, so build the indices directly.
t_wafter = circshift(tidx,-1,1) - 1 == tidx; % for which time points there exist a time point after
iAfter = find(t_wafter);
t_after_idx1 = sparse(iAfter(iAfter+1 <= Nn), iAfter(iAfter+1 <= Nn)+1, true, Nn, Nn); % immediate successors
rowsBand = cell(par.timeExcludeRange,1);
colsBand = cell(par.timeExcludeRange,1);
for n = 1:par.timeExcludeRange
    r = iAfter(iAfter + n <= Nn);
    rowsBand{n} = r;
    colsBand{n} = r + n;
end
t_after_idx = sparse(vertcat(rowsBand{:}), vertcat(colsBand{:}), true, Nn, Nn);
t_after_idx = triu(t_after_idx);% ensure time doesn't flow backward
if par.timeExcludeSpace
    D(t_after_idx) = Inf;
end

% -- compute adjacency matrix
% mink rather than a full sort(D,2): only the k nearest are ever used, and
% sort's two Nn-by-Nn outputs cost hundreds of MB at realistic sizes while
% k is typically single digits. Logical rather than double for the same
% reason -- 1 byte per entry instead of 8.
A = false(Nn,Nn);
[Dk,Ik] = mink(D,k,2);
I = sub2ind([Nn Nn], repmat((1:Nn)',1,k), Ik);
A(I(:))=true;

% -- check for duplicate points
dmax = Dk(:,k); % maximal distance in each point's spatial neighborhood
A(D<=dmax) = true; % other points with the same distance are also included
                   % (implicit expansion; repmat here built a whole Nn-by-Nn copy)

% -- get distance threshold: the smaller of the percentile-derived and the
% absolute cutoff. At the default 100th percentile there is nothing to
% compute -- D's masked entries are Inf, so the answer is always Inf and
% the absolute cutoff wins -- and skipping it avoids sorting all Nn^2
% distances just to learn that.
% The percentile is taken over FINITE distances only. By this point D has
% Inf wherever a pair is excluded from being spatial neighbours -- the
% diagonal, and every temporal pair within timeExcludeRange -- and those
% Infs sit at the top of the distribution, so including them dragged the
% cutoff upward and made it more permissive than asked for. With
% texclude=30 on 1500 points the 99th percentile came out as Inf outright:
% a request to drop the most distant 1% of neighbours silently applied no
% cutoff at all.
if par.maxNeighborDistPrct >= 100
    prctThreshold = Inf;
else
    finiteD = D(isfinite(D));
    if isempty(finiteD)
        prctThreshold = Inf; % nothing finite to take a percentile of
    else
        prctThreshold = prctile(finiteD,par.maxNeighborDistPrct);
    end
end
par.maxNeighborDist = min(prctThreshold,par.maxNeighborDist);

% -- remove neighbors that exceed max distance
A(D>par.maxNeighborDist) = false;

% -- exclude or retain temporal links as spatial links 
if par.timeExcludeSpace
    A_space = A & ~t_after_idx; % remove temporal links (logical, not double .*)
else
    A_space = A;
end

% -- enforce symmetry of spatial links
if par.reciprocal
    A_space = A_space & A_space';
else
    A_space = A_space | A_space';
end

% -- (re-)incoporate temporal links
A = t_after_idx1 | A_space; 

% -- convert to graph
g = digraph(A);
end

