function runall()
%RUNALL run every test in this folder, reporting pass/fail per file.
%   Usage, from the repository root:
%       matlab -batch "addpath('tests'); runall"
%   or, in the GUI, open this file and press Run. It prints one line per
%   test file and errors out if any of them failed, so it is safe to use as
%   a pre-commit or pre-push check.
%
%   This is a FUNCTION file, not a script, so it must be called by name as
%   above -- run('tests/runall.m') does not work on a function file.
%
%   Each test is executed inside RUNONE's own function workspace, which is
%   the whole point of this file. The tests are plain scripts rather than
%   matlab.unittest classes, and RUN executes a script in the CALLER's
%   workspace -- so a test that assigns a common name like i, n or files
%   silently overwrites the driver's loop state. A naive driver
%
%       files = dir('tests/test_*.m');
%       for i = 1:numel(files), run(...); end
%
%   reports a wrong count and still exits 0: test_cyclepath.m assigns one of
%   those names, which made an otherwise green suite report '6/9 passed'.
%   Calling through RUNONE contains each script's assignments to a workspace
%   the loop does not depend on.
%
%   CI runs each tests/test_*.m in its own process and is unaffected by that
%   hazard; this file exists so a local run matches CI's verdict.
%
%   Note the name: the CI workflow globs tests/test_*.m, so this driver is
%   deliberately NOT called test_runall, or it would recurse into itself.

here = fileparts(mfilename('fullpath'));
d = dir(fullfile(here, 'test_*.m'));
names = sort({d.name});
if isempty(names)
    error('runall:noTests', 'No test_*.m files found in %s.', here);
end

ok = 0;
failures = {};
for kk = 1:numel(names)
    try
        runone(fullfile(here, names{kk}));
        ok = ok + 1;
        disp(['  PASS  ' names{kk}]);
    catch err
        failures{end+1} = names{kk}; %#ok<AGROW>
        disp(['  FAIL  ' names{kk} ' -- ' err.message]);
    end
end

disp(' ');
disp(['=== ' num2str(ok) '/' num2str(numel(names)) ' test files passed ===']);
if ~isempty(failures)
    error('runall:testsFailed', '%d test file(s) failed: %s', ...
        numel(failures), strjoin(failures, ', '));
end
end

function runone(f)
% Execute one test script in a workspace of its own, so whatever it assigns
% cannot reach the caller's loop variables.
run(f);
end
