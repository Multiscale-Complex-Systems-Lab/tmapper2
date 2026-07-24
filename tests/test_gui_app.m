%TEST_GUI_APP smoke tests for gui/TemporalMapperApp.m: loadData,
%buildNetwork, addColorVarFromWorkspace, generateCode, and their input
%validation.
%   Run this script directly in MATLAB; it prints "All tests passed."
%   on success and errors out on the first failing check. Creates and
%   closes several figure windows (the app itself, plus whatever
%   generateCode's output opens when executed) -- expect windows to
%   flash briefly if run with a visible display.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','tmapper_tools'));
addpath(fullfile(fileparts(mfilename('fullpath')),'..','gui'));

rng(0);

% -- synthetic dataset: small and fast, 3 numeric variables plus one
% non-numeric column (to exercise the numeric-only column filter)
N = 200;
T = table();
T.label = repmat({'a'}, N, 1); % non-numeric, should be excluded
T.x = sin((1:N)'/10) + 0.05*randn(N,1);
T.y = cos((1:N)'/10) + 0.05*randn(N,1);
T.z = (1:N)' + 0.05*randn(N,1);

% -- loadData
app = TemporalMapperApp;
app.loadData(T);
assert(isequal(app.VariableListBox.String(:), {'x';'y';'z'}), ...
    'loadData should populate VariableListBox with only numeric columns.');
assert(isequal(app.VariableListBox.Value, 1:3), 'loadData should select all variables by default.');
assert(isequal(app.ColorVarDropDown.String(:), {'(row index)';'x';'y';'z'}), ...
    'loadData should populate ColorVarDropDown with (row index) + numeric columns.');
assert(app.ColorVarDropDown.Value == 1, 'loadData should default ColorVarDropDown to (row index).');

Tnonnumeric = table({'a';'b'}, 'VariableNames', {'label'});
assertThrows(@() app.loadData(Tnonnumeric), 'TemporalMapperApp:noNumericVars', ...
    'loadData should reject data with no numeric columns.');

% -- buildNetwork: error paths, on a fresh app before any data/vars
app2 = TemporalMapperApp;
assertThrows(@() app2.buildNetwork(), 'TemporalMapperApp:noData', ...
    'buildNetwork should reject building before data is loaded.');
app2.loadData(T);
app2.VariableListBox.Value = [];
assertThrows(@() app2.buildNetwork(), 'TemporalMapperApp:noVars', ...
    'buildNetwork should reject building with no variables selected.');
app2.VariableListBox.Value = 1:numel(app2.VariableListBox.String);
app2.KEditField.String = 'not a number';
assertThrows(@() app2.buildNetwork(), 'TemporalMapperApp:invalidNumericField', ...
    'buildNetwork should reject a non-numeric parameter field.');
delete(app2);

% -- buildNetwork: success, with the recurrence plot shown (default)
app.KEditField.String = '3';
app.DEditField.String = '2';
app.TExcludeEditField.String = '5';
app.buildNetwork();
assert(contains(app.StatusTextArea.String{1}, 'Built network:'), ...
    'buildNetwork should report a "Built network:" status on success.');
assert(strcmp(app.RecurrenceAxes.Visible, 'on'), ...
    'RecurrenceAxes should be visible when Show recurrence plot is checked (default).');
networkPosWithRecurrence = app.NetworkAxes.Position;

% -- Show recurrence plot toggle: hides RecurrenceAxes and widens NetworkAxes
app.ShowRecurrenceCheckBox.Value = 0;
app.buildNetwork();
assert(strcmp(app.RecurrenceAxes.Visible, 'off'), ...
    'RecurrenceAxes should be hidden when Show recurrence plot is unchecked.');
assert(app.NetworkAxes.Position(3) > networkPosWithRecurrence(3), ...
    'NetworkAxes should widen to fill the panel when the recurrence plot is hidden.');
app.ShowRecurrenceCheckBox.Value = 1;
app.buildNetwork();

% -- addColorVarFromWorkspace
N_rows = height(T);
myColorVec = mod((1:N_rows)', 7);
app.addColorVarFromWorkspace('myColorVec', myColorVec);
assert(any(strcmp(app.ColorVarDropDown.String, 'myColorVec (workspace)')), ...
    'addColorVarFromWorkspace should add the vector as a selectable color option.');
assert(strcmp(app.ColorVarDropDown.String{app.ColorVarDropDown.Value}, 'myColorVec (workspace)'), ...
    'addColorVarFromWorkspace should select the newly-added color option.');
app.buildNetwork(); % should succeed using the workspace-sourced color variable

assertThrows(@() app.addColorVarFromWorkspace('badvec', ones(N_rows-1,1)), ...
    'TemporalMapperApp:colorVarLengthMismatch', ...
    'addColorVarFromWorkspace should reject a vector of the wrong length.');

app.loadData(T); % reloading should reset workspace-sourced color options
assert(isequal(app.ColorVarDropDown.String(:), {'(row index)';'x';'y';'z'}), ...
    'reloading data should clear workspace-sourced color options.');
app.VariableListBox.Value = 1:3;
app.KEditField.String = '3';
app.DEditField.String = '2';
app.TExcludeEditField.String = '5';

% -- Select All button (invoked via its own Callback, since
% SelectAllButtonPushed itself is private)
app.VariableListBox.Value = 1;
app.SelectAllButton.Callback(app.SelectAllButton, []);
assert(isequal(app.VariableListBox.Value, 1:3), 'Select All should select every variable.');

% -- generateCode: error path
app3 = TemporalMapperApp;
assertThrows(@() app3.generateCode(), 'TemporalMapperApp:noData', ...
    'generateCode should reject generating code before data is loaded.');
delete(app3);

% -- generateCode: plotgraphtcm path (Show recurrence plot checked).
% Run the generated code standalone (with the data-loading placeholder
% swapped for the actual in-memory table) and cross-check it reproduces
% the same node/edge counts the GUI itself just reported.
app.buildNetwork();
statusLine = app.StatusTextArea.String{1};
tok = regexp(statusLine, 'Built network: (\d+) nodes, (\d+) edges', 'tokens');
guiNodes = str2double(tok{1}{1});
guiEdges = str2double(tok{1}{2});

code = app.generateCode();
assert(contains(code, 'plotgraphtcm('), ...
    'generateCode should use plotgraphtcm when Show recurrence plot is checked.');
assert(~contains(code, '~'), ...
    'generateCode should name every output rather than suppressing any with ~.');
assert(contains(code, 'axis(h1'), 'generateCode should tighten the network axes.');
assert(contains(code, 'maxdist=%.4g'), ...
    'generateCode should title the network plot with the resolved parameters.');

placeholder = '% dat = <load your data here as a table, e.g. dat = readtable(''your_file.csv'');>';
assert(contains(code, placeholder), 'generateCode should include the default data-loading placeholder comment.');
% strip the embedded addpath (this script already added the path; the
% generated line is relative to the user's own working directory, not
% this test file's) and swap the placeholder for the in-memory table
runnableCode = strrep(code, placeholder, 'dat = T;');
runnableCode = strrep(runnableCode, 'addpath("tmapper_tools/")', '');

% close/reopen only figures the generated code itself creates -- app is
% a classic figure() under the hood, so a blanket close('all') would
% destroy the app window too
figsBefore = findobj('Type','figure');
eval(runnableCode);
newFigs = setdiff(findobj('Type','figure'), figsBefore);
assert(numnodes(g_simp) == guiNodes, 'generated code should reproduce the same node count as the GUI build.');
assert(numedges(g_simp) == guiEdges, 'generated code should reproduce the same edge count as the GUI build.');
assert(isa(h1,'matlab.graphics.axis.Axes') && isa(h2,'matlab.graphics.axis.Axes'), ...
    'generated plotgraphtcm code should return named axes handles h1/h2.');
assert(isa(cb,'matlab.graphics.illustration.ColorBar') && isa(cb_,'matlab.graphics.illustration.ColorBar'), ...
    'generated plotgraphtcm code should return named colorbar handles cb/cb_.');
assert(isa(hg,'matlab.graphics.chart.primitive.GraphPlot'), ...
    'generated plotgraphtcm code should return a named graph-plot handle hg.');
assert(isequal(size(D_geo), [guiNodes guiNodes]), ...
    'generated plotgraphtcm code should return a square D_geo matching the node count.');
close(newFigs)

% -- generateCode: plottmgraph path (Show recurrence plot unchecked),
% plus the Show node border (nodescatter) option
app.ShowRecurrenceCheckBox.Value = 0;
app.ShowNodeBorderCheckBox.Value = 1;
app.buildNetwork();
code2 = app.generateCode();
assert(contains(code2, 'plottmgraph('), ...
    'generateCode should use plottmgraph when Show recurrence plot is unchecked.');
assert(contains(code2, 'figure;'), ...
    'generateCode should open a new figure before plottmgraph rather than reusing an existing one.');
assert(contains(code2, '''nodescatter'', 1'), ...
    'generateCode should pass nodescatter=1 when Show node border is checked.');

runnableCode2 = strrep(code2, placeholder, 'dat = T;');
runnableCode2 = strrep(runnableCode2, 'addpath("tmapper_tools/")', '');
preexistingFig = figure('Name','pre-existing figure that should NOT be reused');
figsBefore2 = findobj('Type','figure');
eval(runnableCode2);
figsAfter2 = findobj('Type','figure');
assert(numel(figsAfter2) == numel(figsBefore2) + 1, ...
    'generateCode''s plottmgraph path should open exactly one new figure, not reuse an existing one.');
assert(isa(hs,'matlab.graphics.chart.primitive.Scatter') && numel(hs) == 1, ...
    'generated plottmgraph code should return a real scatter handle hs when nodescatter=1.');
close(setdiff(figsAfter2, figsBefore2))
close(preexistingFig)

app.ShowRecurrenceCheckBox.Value = 1;
app.ShowNodeBorderCheckBox.Value = 0;

delete(app);
close all

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
