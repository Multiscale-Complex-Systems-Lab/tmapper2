function A = weightedAdj(g)
% WEIGHTEDAJD get the weighted adjacency matrix from a graph object "g".
% This is to accomandate for over versions of matlab. 
% A = weightedAdj(g) input a graph g and get weighted adjacency matrix A. 
%{
created by MZ, 9/11/2019
modifications:
(7-19-2026) fix: isfield() does not work on table objects like
g.Edges (always returns false), so the Weight-column check
unconditionally overwrote any real edge weights with 1s. Switched to
checking g.Edges.Properties.VariableNames instead.
%}
    % Ask adjacency() for weights and fall back if there are none, rather
    % than inspecting g.Edges first: touching the Edges property
    % materialises the whole edge TABLE, which profiling showed cost more
    % than everything else in this function put together (~26x). The
    % unweighted fallback is all-ones weights, which is exactly what
    % adjacency(g) already returns.
    try
        A = adjacency(g,'weighted');
    catch
        A = adjacency(g);
    end
end