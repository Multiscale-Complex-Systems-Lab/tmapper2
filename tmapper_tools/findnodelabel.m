function m = findnodelabel(members,x_label,varargin)
%CELLMODE find the most frequent labels for members in the same node.
%   m = findnodelabel(members,x_label) 
% input:
%   members: a N-by-1 cell array, each cell contains a vector of indices
%   x_label: label for each member. 
% output:
%   m: a N-by-1 vector each element is the most frequent label for a
%   particular cell.
% parameters:
%   labelmethod: 'mode' (default), 'mean', 'median', 'none', or a function
%   handle. A function handle is applied as labelmethod(x_label(x)) for
%   each node's members x, and must return a scalar.
%{
created by MZ, 9-13-2019
(MZ 5/28/2023) add options for labeling methods
(MZ 7/19/2026) allow labelmethod to be a custom function handle
%}
p = inputParser;
p.addParameter('labelmethod','mode')

p.parse(varargin{:});
par = p.Results;

if isa(par.labelmethod,'function_handle')
    m = cell2mat(cellfun(@(x) par.labelmethod(x_label(x)), members,'uniformoutput',0));
else
    switch par.labelmethod
        case 'mode'
            m = cell2mat(cellfun(@(x) mode(x_label(x)), members,'uniformoutput',0));
        case 'mean'
            m = cell2mat(cellfun(@(x) mean(x_label(x)), members,'uniformoutput',0));
        case 'median'
            m = cell2mat(cellfun(@(x) median(x_label(x)), members,'uniformoutput',0));
        case "none"% no color
            m = cell2mat(cellfun(@(x) 0,members,'uniformoutput',0));
    end
end
end

