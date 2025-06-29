function [traf_mean,traf_med, traf_min,traf_max,traf_std] = pathtraffic(allpath,nodesize)
%PATHTRAFFIC compute the traffic on each path given. 
% Usage:
%   [traf_mean,traf_med, traf_min,traf_max,traf_std] = pathtraffic(allpath,nodesize)
% Input:
%   allpath: cell array of N_path elements. each cell contains a vector of node names
%   indicating a path through the relevant nodes. 
%   nodesize: size of each node. a vector of N_node elements. 
% Output:
%   traf_mean: average traffic (average node size along path), N_path-by-1
%   vector.
%   traf_med: median traffic, N_path-by-1 vector.
%   traf_min: min traffic (bottleneck) on path, N_path-by-1 vector.
%   traf_max: max traffic (bottleneck) on path, N_path-by-1 vector.
%   traf_std: standard deviation of node size, N_path-by-1 vector.

%{
~ created by Mengsen Zhang (MZ, 4/24/2024) ~

%}
pathnodesize = cellfun(@(p) toVec(nodesize(p)),allpath, 'UniformOutput',false);
traf_mean = cellfun(@mean, pathnodesize);
traf_med = cellfun(@median, pathnodesize);
traf_min = cellfun(@min, pathnodesize);
traf_max = cellfun(@max,pathnodesize);
traf_std = cellfun(@std, pathnodesize);

end

