%TEST_KNNGRAPH tests for knngraph and cknngraph: hand-derived correctness
%   cases plus input validation. These are standalone graph builders (not
%   part of the core tknndigraph/filtergraph pipeline). Run this script
%   directly in MATLAB; it prints "All tests passed." on success and
%   errors out on the first failing check.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));

% -- knngraph on the deterministic 6-point, two-triple dataset (k=2, no
% temporal component at all, so ties fill both k=2 slots exactly and every
% pair ends up mutual): should give two disjoint triangles, 6 edges total.
Xd = [0;1;2;10;11;12];
g = knngraph(Xd,2);
assert(numnodes(g) == 6, 'expected 6 nodes.');
assert(numedges(g) == 6, 'expected 6 edges (two disjoint triangles).');
for e = [1 2; 1 3; 2 3; 4 5; 4 6; 5 6]'
    assert(findedge(g,e(1),e(2)) ~= 0, ...
        sprintf('expected edge %d-%d within a triple.', e(1), e(2)));
end
assert(findedge(g,3,4) == 0, 'expected no edge across the two triples.');

% -- knngraph 'reciprocal' effect: Xd2=[0,1,3], k=1. Point1's nearest is
% point2; point2's nearest is point1; point3's nearest is point2, but
% point2's nearest is point1, not point3 -- so 2-3 is one-directional.
% reciprocal=true should drop it; reciprocal=false should keep it.
Xd2 = [0;1;3];
g_rec = knngraph(Xd2,1,'reciprocal',true);
g_norec = knngraph(Xd2,1,'reciprocal',false);
assert(numedges(g_rec) == 1 && findedge(g_rec,1,2) ~= 0, ...
    'reciprocal=true should give only the mutual edge 1-2.');
assert(numedges(g_norec) == 2 && findedge(g_norec,1,2) ~= 0 && findedge(g_norec,2,3) ~= 0, ...
    'reciprocal=false should also keep the one-directional edge 2-3.');

% -- cknngraph on the same 6-point dataset, k=1, delta=1.5. Every point's
% nearest-neighbor distance (Dk) is exactly 1 here, so D_norm equals the
% raw distance matrix unchanged. Within each triple, adjacent-point pairs
% (distance 1) connect but the end-to-end pair (distance 2) does not (2
% is not < 1.5) -- giving two disjoint 3-point PATHS, not triangles.
g_ck = cknngraph(Xd,1,1.5);
assert(numnodes(g_ck) == 6, 'expected 6 nodes.');
assert(numedges(g_ck) == 4, 'expected 4 edges (two disjoint paths, not triangles).');
assert(findedge(g_ck,1,2) ~= 0 && findedge(g_ck,2,3) ~= 0, 'expected the path edges within {1,2,3}.');
assert(findedge(g_ck,1,3) == 0, 'expected no direct 1-3 edge (distance 2 exceeds delta=1.5).');
assert(findedge(g_ck,4,5) ~= 0 && findedge(g_ck,5,6) ~= 0, 'expected the path edges within {4,5,6}.');
assert(findedge(g_ck,4,6) == 0, 'expected no direct 4-6 edge (distance 2 exceeds delta=1.5).');

% -- input validation: knngraph
assertThrows(@() knngraph(Xd,1.5), 'knngraph:invalidInput', ...
    'knngraph should reject non-integer k.');
assertThrows(@() knngraph(Xd,6), 'knngraph:invalidInput', ...
    'knngraph should reject k >= number of points.');

% -- input validation: cknngraph
assertThrows(@() cknngraph(Xd,1.5,1), 'cknngraph:invalidInput', ...
    'cknngraph should reject non-integer k.');
assertThrows(@() cknngraph(Xd,6,1), 'cknngraph:invalidInput', ...
    'cknngraph should reject k >= number of points.');
assertThrows(@() cknngraph(Xd,1,-1), 'cknngraph:invalidInput', ...
    'cknngraph should reject a non-positive delta.');

disp('All tests passed.');

function assertThrows(fcn, expectedID, msg)
    try
        fcn();
    catch err
        assert(strcmp(err.identifier, expectedID), ...
            '%s (expected error id "%s", got "%s")', msg, expectedID, err.identifier);
        return
    end
    error('%s (expected an error but none was thrown)', msg);
end
