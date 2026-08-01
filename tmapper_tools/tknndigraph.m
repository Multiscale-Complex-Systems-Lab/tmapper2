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
%   lowMemory: build the graph from X a block of rows at a time, never
%   holding an N-by-N matrix. Peak memory becomes O(blockSize*N) rather
%   than O(N^2), which is what makes large N feasible at all: the bundled
%   57709-row sample needs ~88 GB the usual way and ~0.6 GB this way. Needs
%   the coordinates X, not a precomputed D. Default false.
%   blockSize: rows per block in lowMemory mode. Larger is slightly faster,
%   smaller uses less memory (peak is roughly blockSize*N*8 bytes). Default
%   picks ~400 MB.
%   distance: the metric used to turn X into distances, passed straight to
%   pdist2. Any pdist2 metric name ('euclidean' (default), 'cityblock',
%   'cosine', 'correlation', ...), a function handle, or a cell array when
%   the metric takes an extra argument, e.g. {'minkowski',3}. Only applies
%   when X is passed -- with a precomputed D the metric is already baked in,
%   so supplying one is an error rather than a silent no-op.
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
p.addParameter('lowMemory',false); % build from X a block of rows at a time, never holding an N-by-N matrix
p.addParameter('blockSize',[]); % rows per block in lowMemory mode; [] picks ~400 MB
p.addParameter('distance','euclidean'); % metric used when X (not D) is passed; see pdist2
p.parse(varargin{:})
par = p.Results;
par.k = k;

% -- normalise the metric into a pdist2 argument list. A cell lets metrics
% that take an extra parameter through, e.g. {'minkowski',3}.
if iscell(par.distance)
    distArgs = par.distance;
else
    distArgs = {par.distance};
end
customDistance = ~(numel(distArgs)==1 && (ischar(distArgs{1}) || isstring(distArgs{1})) ...
    && strcmpi(distArgs{1},'euclidean'));

% -- low-memory path: never form the N-by-N distance matrix at all. Must
% branch before D is built, since building it is the thing being avoided.
if par.lowMemory
    [nr,nc] = size(XorD);
    if nr == nc && nr > 1 && isequal(XorD, XorD')
        error('tknndigraph:lowMemoryNeedsX', ...
            ['lowMemory builds distances block by block, so it needs the coordinates X ' ...
             '(N-by-d), not a precomputed N-by-N distance matrix -- passing D means the ' ...
             'full matrix already exists and there is nothing left to save.']);
    end
    [g, par] = blockedBuild(XorD, k, tidx, par, distArgs);
    return
end

% -- check input and obtain distance matrix D
% Symmetry decides whether this is a distance matrix or coordinates, and it
% has to be tested with a tolerance rather than exactly: pdist2's 'cosine'
% and 'correlation' return matrices that differ from their own transpose by
% an ULP (~2.2e-16). Under an exact test such a matrix was silently
% classified as COORDINATES, and the function went on to compute euclidean
% distances between the rows of a distance matrix -- a meaningless graph,
% produced without any error.
[nr,nc]=size(XorD);
isDistanceMatrix = false;
if nr==nc && nr>1
    scale = max(abs(XorD),[],'all');
    if scale == 0 || isinf(scale)
        isDistanceMatrix = isequal(XorD, XorD.');
    else
        isDistanceMatrix = max(abs(XorD - XorD.'),[],'all') <= 1e-10*scale;
    end
end
if ~isDistanceMatrix
    D = pdist2(XorD,XorD,distArgs{:});
else
    if customDistance
        error('tknndigraph:distanceNeedsX', ...
            ['A custom ''distance'' was given, but XorD is already a distance matrix -- ' ...
             'the metric is baked into it. Pass the coordinates X instead.']);
    end
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

D(1:Nn+1:end) = Inf; % exclude self-loops (linear indexing: logical(eye(Nn))
                     % built a whole Nn-by-Nn double, then a logical copy of
                     % it, just to address the diagonal -- gigabytes at scale)

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


function [g, par] = blockedBuild(X, k, tidx, par, distArgs)
%BLOCKEDBUILD tknndigraph's low-memory path: identical graph, built a
%block of rows at a time so no N-by-N array is ever allocated.
%   Every step except the percentile is row-local, so it blocks cleanly.
%   The percentile needs the global distribution, which is exactly what
%   blocking refuses to hold -- so it is accumulated as a histogram during
%   the same pass (see below).
N = size(X,1);
tidx = tidx(:);
if k >= N
    error('tknndigraph:invalidInput','k must be smaller than the number of points (%d).',N);
end
if any(isnan(X(:)))
    error('tknndigraph:missingData', ...
        ['XorD contains NaN values (or produces them once converted to a distance matrix). ' ...
        'Remove or impute missing data before calling tknndigraph, e.g. via rmmissing.']);
end

B = par.blockSize;
if isempty(B)
    B = max(1, min(N, floor(50e6 / max(N,1)))); % ~400 MB of doubles per block
end
par.blockSize = B;

% the temporal band: pairs (i, i+n) for n = 1..range, upper triangle only,
% wherever i has a temporal successor -- same construction as the dense path
t_wafter = circshift(tidx,-1,1) - 1 == tidx;
iAfter = find(t_wafter);
succ = iAfter(iAfter+1 <= N);
t_after_idx1 = sparse(succ, succ+1, true, N, N);
isAfter = false(N,1); isAfter(iAfter) = true;

% Histogram range without an extra pass: the bounding-box diagonal is a
% hard upper bound on any pairwise Euclidean distance, and costs O(N*d).
needPrct = par.maxNeighborDistPrct < 100;
nBins = 1e6;
if needPrct
    hi = norm(max(X,[],1) - min(X,[],1));
    if hi <= 0, hi = 1; end
    edges = linspace(0, hi, nBins+1);
    counts = zeros(nBins,1);
end

nBlk = ceil(N/B);
rowsAll = cell(nBlk,1); colsAll = cell(nBlk,1); distAll = cell(nBlk,1);
blk = 0;
for i0 = 1:B:N
    blk = blk + 1;
    i1 = min(i0+B-1, N);
    idx = (i0:i1)';
    Db = pdist2(X(idx,:), X, distArgs{:});          % the only large array

    Db(sub2ind(size(Db), (1:numel(idx))', idx)) = Inf;   % self-loops
    if par.timeExcludeSpace
        for n = 1:par.timeExcludeRange
            r = idx(isAfter(idx) & idx + n <= N);
            if ~isempty(r)
                Db(sub2ind(size(Db), r-i0+1, r+n)) = Inf;
            end
        end
    end

    if needPrct
        finiteVals = Db(isfinite(Db));
        counts = counts + histcounts(finiteVals, edges)';
    end

    [Dk,~] = mink(Db, k, 2);
    keep = Db <= Dk(:,k);   % the k nearest, plus any ties at the kth distance
    [rr, cc] = find(keep);
    % Shape care, all for the last block when it holds a single row:
    % find() returns ROW vectors for a 1-row input, and indexing a ROW
    % vector Db yields a row whatever shape the index is (MATLAB keeps the
    % source's orientation for vector sources). Either one breaks the
    % vertcat below, and only for particular blockSize/N combinations.
    rr = rr(:); cc = cc(:);
    rowsAll{blk} = rr + i0 - 1;
    colsAll{blk} = cc;
    dblk = Db(sub2ind(size(Db), rr, cc));
    distAll{blk} = dblk(:);
end

% -- resolve the distance threshold. The percentile comes from the
% histogram accumulated above: exact to one bin width (range/1e6), which
% for a distance cutoff is far below any scale that changes the graph.
if needPrct
    total = sum(counts);
    target = par.maxNeighborDistPrct/100 * total;
    ib = find(cumsum(counts) >= target, 1, 'first');
    if isempty(ib), ib = nBins; end
    prctThreshold = edges(ib+1);   % upper edge: inclusive, matching D<=thr
else
    prctThreshold = Inf;
end
par.maxNeighborDist = min(prctThreshold, par.maxNeighborDist);

% -- assemble, dropping candidates beyond the resolved cutoff
rows = vertcat(rowsAll{:}); cols = vertcat(colsAll{:}); dist = vertcat(distAll{:});
ok = dist <= par.maxNeighborDist;
A = sparse(rows(ok), cols(ok), true, N, N);

if par.timeExcludeSpace
    bandRows = cell(par.timeExcludeRange,1); bandCols = cell(par.timeExcludeRange,1);
    for n = 1:par.timeExcludeRange
        r = iAfter(iAfter + n <= N);
        bandRows{n} = r; bandCols{n} = r + n;
    end
    t_after_idx = triu(sparse(vertcat(bandRows{:}), vertcat(bandCols{:}), true, N, N));
    % indexed assignment, not A & ~t_after_idx: the complement of a sparse
    % matrix is DENSE and would undo the whole point of blocking.
    A_space = A;
    A_space(t_after_idx) = false;
else
    A_space = A;
end

if par.reciprocal
    A_space = A_space & A_space';
else
    A_space = A_space | A_space';
end

g = digraph(t_after_idx1 | A_space);
end
