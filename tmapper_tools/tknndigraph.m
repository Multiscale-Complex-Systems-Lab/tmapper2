function [g, par] = tknndigraph(XorD,k,tidx,varargin)
%TKNNDIGRAPH construct a directed graph based on k-nearest neighbors which
%much include its temporal neighbors. Here we do so by simply set the
%distance between consecutive time points to zero before running knn.
%   g = tknngraph(XorD,k,tidx)
% input:
%   XorD: a N-by-d matrix (X) of the coordinates of N points in d-sim
%       space, or a N-by-N distance matrix (D). If the input is X, D is
%       computed from X based on Euclidean distances. 
%   k: # nearest neighbors
%   tidx: a vector of N integers, two points x, y are considered temporal
%   neighbors iff tidx[x]+1 = tidx[y] or tidx[x]-1 = tidx[y].
% output:
%   g: matlab graph object (unweighted, undirected).
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
%   them to be considered as spatial neighbors. Default 100 (so no max). If
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

%}
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
Nn = length(D); % number of nodes

D(logical(eye(Nn))) = Inf; % exclude self-loops

% -- find indices for temporal links D_{i(t),i(t+1)}
tidx = tidx(:); % make sure tidx is a column vector
t_wafter = circshift(tidx,-1,1) - 1 == tidx; % for which time points there exist a time point after
t_after_idx1 = circshift(diag(t_wafter),1,2); % matrix indicate immediate time points that follows
t_after_idx = triu(zeros(Nn));% initialize time connectivity matrix to indicate time points that follows up to a range
for n = 1:par.timeExcludeRange
    t_after_idx = t_after_idx | circshift(diag(t_wafter),n,2);
end
t_after_idx = triu(t_after_idx);% ensure time doesn't flow backward
if par.timeExcludeSpace
    D(t_after_idx) = Inf;
end

% -- compute adjacency matrix
A = zeros(Nn,Nn);
[Ds,Ic]=sort(D,2);
I = sub2ind([Nn Nn], repmat((1:Nn)',1,k), Ic(:,1:k));
A(I(:))=1;

% -- check for duplicate points
dmax = Ds(:,k); % maximal distance in each point's spatial neighborhood
A(D<=repmat(dmax,1,Nn)) = 1; % other points with the same distance are also included

% -- get distance threshold
par.maxNeighborDist = min(prctile(D(:),par.maxNeighborDistPrct),par.maxNeighborDist);% the smaller one of the percentage vs absolute distance

% -- remove neighbors that exceed max distance
A(D>par.maxNeighborDist) = 0;

% -- exclude or retain temporal links as spatial links 
if par.timeExcludeSpace
    A_space = A.* (~t_after_idx); % remove temporal links
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

