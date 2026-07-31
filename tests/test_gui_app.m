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
assert(isequal(app.ColorVarDropDown.String(:), {'(row index)';'x';'y';'z';'label'}), ...
    'loadData should offer (row index) + numeric columns + categorical columns for colouring.');
assert(isequal(app.TimeVarDropDown.String(:), {'(row index)';'x';'y';'z'}), ...
    'a categorical column must NOT be offered as a time axis -- it has no order.');
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
assert(isequal(app.ColorVarDropDown.String(:), {'(row index)';'x';'y';'z';'label'}), ...
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

% -- Build/Stop button Enable states after a normal (non-cancelled) build
app.buildNetwork();
assert(strcmp(app.BuildButton.Enable,'on') && strcmp(app.StopButton.Enable,'off'), ...
    'Build should be enabled and Stop disabled again once a normal build completes.');

% -- Plot Options controls should re-render cheaply (not rebuild the
% network) via their own Callback -- PlotOptionChanged -- rather than
% needing Build Network clicked again. Cross-check the node/edge count
% reported by the cheap re-render matches the last real build's.
tok = regexp(app.StatusTextArea.String{1}, '(\d+) nodes, (\d+) edges', 'tokens');
builtNodes = str2double(tok{1}{1}); builtEdges = str2double(tok{1}{2});

app.NodeSizeModeDropDown.Value = 2; % 'rank'
app.NodeSizeModeDropDown.Callback(app.NodeSizeModeDropDown, []);
assert(contains(app.StatusTextArea.String{1}, 'Re-rendered plot (network unchanged)'), ...
    'Changing Node size should re-render, not rebuild.');
tok = regexp(app.StatusTextArea.String{1}, '(\d+) nodes, (\d+) edges', 'tokens');
assert(str2double(tok{1}{1}) == builtNodes && str2double(tok{1}{2}) == builtEdges, ...
    'The re-rendered network should be the same one already built (same node/edge count).');

app.LabelMethodDropDown.Value = 2; % 'mean'
app.LabelMethodDropDown.Callback(app.LabelMethodDropDown, []);
assert(contains(app.StatusTextArea.String{1}, 'Re-rendered plot (network unchanged)'), ...
    'Changing Label method should re-render, not rebuild.');

app.ColorVarDropDown.Value = find(strcmp(app.ColorVarDropDown.String, 'x'));
app.ColorVarDropDown.Callback(app.ColorVarDropDown, []);
assert(contains(app.StatusTextArea.String{1}, 'Re-rendered plot (network unchanged)'), ...
    'Changing Color by should re-render, not rebuild.');

app.TimeVarDropDown.Value = find(strcmp(app.TimeVarDropDown.String, 'y'));
app.TimeVarDropDown.Callback(app.TimeVarDropDown, []);
assert(contains(app.StatusTextArea.String{1}, 'Re-rendered plot (network unchanged)'), ...
    'Changing Time axis should re-render, not rebuild.');

app.ShowNodeBorderCheckBox.Value = 1;
app.ShowNodeBorderCheckBox.Callback(app.ShowNodeBorderCheckBox, []);
assert(contains(app.StatusTextArea.String{1}, 'Re-rendered plot (network unchanged)'), ...
    'Toggling Show node border should re-render, not rebuild.');
app.ShowNodeBorderCheckBox.Value = 0;
app.ShowNodeBorderCheckBox.Callback(app.ShowNodeBorderCheckBox, []);

app.ColormapDropDown.Value = find(strcmp(app.ColormapDropDown.String, 'parula'));
app.ColormapDropDown.Callback(app.ColormapDropDown, []);
assert(contains(app.StatusTextArea.String{1}, 'Re-rendered plot (network unchanged)'), ...
    'Changing Colormap should re-render, not rebuild.');
% the chosen map must actually reach the axes, not just the dropdown
assert(isequal(colormap(app.NetworkAxes), parula(size(colormap(app.NetworkAxes),1))), ...
    'the selected colormap should be applied to the network axes.');
app.ColormapDropDown.Value = find(strcmp(app.ColormapDropDown.String, 'jet'));
app.ColormapDropDown.Callback(app.ColormapDropDown, []);

app.ShowRecurrenceCheckBox.Value = 0;
app.ShowRecurrenceCheckBox.Callback(app.ShowRecurrenceCheckBox, []);
assert(contains(app.StatusTextArea.String{1}, 'Re-rendered plot (network unchanged)'), ...
    'Toggling Show recurrence plot should re-render, not rebuild.');
assert(strcmp(app.RecurrenceAxes.Visible, 'off'), 'the re-render should still apply the recurrence-plot toggle.');
app.ShowRecurrenceCheckBox.Value = 1;
app.ShowRecurrenceCheckBox.Callback(app.ShowRecurrenceCheckBox, []);

% -- PlotOptionChanged should be a harmless no-op when no network has
% been built yet (must not error, and must leave the status message
% from loadData alone since there's nothing to re-render)
appFresh = TemporalMapperApp;
appFresh.loadData(T);
statusBeforeNoop = appFresh.StatusTextArea.String{1};
appFresh.NodeSizeModeDropDown.Callback(appFresh.NodeSizeModeDropDown, []); % should not error
assert(strcmp(appFresh.StatusTextArea.String{1}, statusBeforeNoop), ...
    'PlotOptionChanged should be a no-op (not touch the status text) before any network is built.');
delete(appFresh);

% -- Reset button: restores parameters/plot options to defaults, but
% does NOT clear loaded data or the variable selection
app.KEditField.String = '99';
app.DEditField.String = '99';
app.TExcludeEditField.String = '99';
app.MaxDistPrctEditField.String = '50';
app.MaxDistEditField.String = '1';
app.RangeStartEditField.String = '10';
app.RangeEndEditField.String = '150';
app.DownsampleEditField.String = '3';
app.ZscoreCheckBox.Value = 0;
app.ReciprocalCheckBox.Value = 0;
app.ShowNodeBorderCheckBox.Value = 1;
app.VariableListBox.Value = 2;
app.ResetButton.Callback(app.ResetButton, []);
assert(strcmp(app.KEditField.String,'3') && strcmp(app.DEditField.String,'3') && ...
    strcmp(app.TExcludeEditField.String,'1') && strcmp(app.MaxDistPrctEditField.String,'100') && ...
    strcmp(app.MaxDistEditField.String,'Inf'), 'Reset should restore all numeric fields to their defaults.');
assert(strcmp(app.RangeStartEditField.String,'1') && strcmp(app.RangeEndEditField.String,'Inf') && ...
    strcmp(app.DownsampleEditField.String,'1'), ...
    'Reset should restore the row range/downsample fields to their defaults.');
assert(app.ZscoreCheckBox.Value == 1 && app.ReciprocalCheckBox.Value == 1 && ...
    app.ShowRecurrenceCheckBox.Value == 1 && app.ShowNodeBorderCheckBox.Value == 0, ...
    'Reset should restore all checkboxes to their defaults.');
assert(isequal(app.VariableListBox.Value, 2), 'Reset should NOT change the variable selection.');
assert(~strcmp(app.FileLabel.String, 'No file loaded.'), 'Reset should NOT clear the loaded data.');
app.VariableListBox.Value = 1:3;
app.KEditField.String = '3';
app.DEditField.String = '2';
app.TExcludeEditField.String = '5';
app.buildNetwork();

% -- Stop button: an in-progress build can be cancelled. Since
% buildNetwork runs synchronously, simulate a real user click with an
% async timer that fires the Stop button's own Callback shortly after
% the build starts, on a large-enough synthetic dataset that the build
% reliably takes longer than the timer delay.
rng(1);
Nbig = 3000;
Tbig = table();
Tbig.a = cumsum(randn(Nbig,1));
Tbig.b = cumsum(randn(Nbig,1));
Tbig.c = cumsum(randn(Nbig,1));
appBig = TemporalMapperApp;
appBig.loadData(Tbig);
appBig.VariableListBox.Value = 1:3;
appBig.KEditField.String = '5';
appBig.DEditField.String = '3';
appBig.TExcludeEditField.String = '2';

cancelTimer = timer('StartDelay', 0.05, ...
    'TimerFcn', @(~,~) appBig.StopButton.Callback(appBig.StopButton, []));
cleanupTimer = onCleanup(@() delete(cancelTimer)); %#ok<NASGU>
start(cancelTimer);
appBig.buildNetwork();
stop(cancelTimer);
assert(strcmp(appBig.StatusTextArea.String{1}, 'Build cancelled.'), ...
    'an async Stop click during a build should cancel it before it finishes.');
assert(strcmp(appBig.BuildButton.Enable,'on') && strcmp(appBig.StopButton.Enable,'off'), ...
    'Build should be re-enabled and Stop disabled again after a cancelled build.');
delete(appBig);

% -- memory guard: a full pairwise distance matrix is O(N^2), so an
% untrimmed real dataset can ask for tens of GB. Refuse with a number the
% user can act on rather than hanging or exhausting memory.
assert(isempty(TemporalMapperApp.oversizedWindowMessage(100)), ...
    'a small window should not trip the memory guard.');
bigMsg = TemporalMapperApp.oversizedWindowMessage(50000);
assert(~isempty(bigMsg) && contains(bigMsg, 'GB'), ...
    'an oversized window should be refused with a memory estimate.');
assert(contains(bigMsg, '20.0 GB'), ...
    'the estimate should be the actual size of the matrix (50000^2 float64 = 20 GB).');

% the guard counts points AFTER decimation, so downsampling is a real fix
% rather than a way to sidestep the check
appBigWin = TemporalMapperApp;
TBigWin = table();
TBigWin.x = sin((1:9000)'/50);
TBigWin.y = cos((1:9000)'/50);
appBigWin.loadData(TBigWin);
appBigWin.VariableListBox.Value = 1:2;
appBigWin.KEditField.String = '3';
appBigWin.DEditField.String = '2';
appBigWin.TExcludeEditField.String = '5';
assertThrows(@() appBigWin.buildNetwork(), 'TemporalMapperApp:windowTooLarge', ...
    'building on an oversized row range should be refused up front.');
% ...and it must refuse BEFORE doing the expensive work, not after
appBigWin.DownsampleEditField.String = '10'; % 9000 -> 900 points
appBigWin.buildNetwork();
assert(contains(appBigWin.StatusTextArea.String{1}, 'Built network:'), ...
    'downsampling below the threshold should let the same range build.');
delete(appBigWin);

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

% -- preprocessing: row range & downsampling. Trange.z equals its own
% row index, so cross-checking dat.z(baseRows) against the expected
% window verifies the right ORIGINAL rows were selected.
rng(2);
Nrange = 200;
Trange = table();
Trange.x = sin((1:Nrange)'/10);
Trange.y = cos((1:Nrange)'/10);
Trange.z = (1:Nrange)';

appRange = TemporalMapperApp;
appRange.loadData(Trange);
appRange.VariableListBox.Value = 1:3;
appRange.KEditField.String = '3';
appRange.DEditField.String = '2';
appRange.TExcludeEditField.String = '5';

assert(strcmp(appRange.RangeStartEditField.String,'1') && ...
    strcmp(appRange.RangeEndEditField.String,'Inf') && ...
    strcmp(appRange.DownsampleEditField.String,'1'), ...
    'Row range/downsample fields should default to start=1, end=Inf, downsample=1.');

appRange.RangeStartEditField.String = '150';
appRange.RangeEndEditField.String = '100';
assertThrows(@() appRange.buildNetwork(), 'TemporalMapperApp:invalidRange', ...
    'buildNetwork should reject a start row greater than the end row.');

appRange.RangeStartEditField.String = '1';
appRange.RangeEndEditField.String = '1';
appRange.DownsampleEditField.String = '1';
assertThrows(@() appRange.buildNetwork(), 'TemporalMapperApp:invalidRange', ...
    'buildNetwork should reject a range/downsample combination leaving fewer than 2 rows.');

% -- downsampling: cross-check via generateCode's resolved baseRows/X,
% since the cached network internals are private to the app
appRange.RangeStartEditField.String = '1';
appRange.RangeEndEditField.String = 'Inf';
appRange.DownsampleEditField.String = '4';
appRange.buildNetwork();
codeDownsample = appRange.generateCode();
runnableDownsample = strrep(codeDownsample, placeholder, 'dat = Trange;');
runnableDownsample = strrep(runnableDownsample, 'addpath("tmapper_tools/")', '');
figsBeforeDS = findobj('Type','figure');
eval(runnableDownsample);
newFigsDS = setdiff(findobj('Type','figure'), figsBeforeDS);
assert(numel(baseRows) == ceil(Nrange/4), ...
    sprintf('downsample=4 should keep every 4th row: expected %d rows, got %d.', ceil(Nrange/4), numel(baseRows)));
assert(size(X,1) == numel(baseRows), 'X should have one row per selected baseRow when embed order is 1.');
rawStrided = Trange{baseRows, {'x','y','z'}};
assert(~isequal(filteredVals, rawStrided), ...
    'downsample>1 should apply an anti-aliasing lowpass filter, not just pick raw strided rows.');
close(newFigsDS)

% -- row range: start/end row should restrict to exactly that window
appRange.RangeStartEditField.String = '50';
appRange.RangeEndEditField.String = '150';
appRange.DownsampleEditField.String = '1';
appRange.buildNetwork();
codeRange = appRange.generateCode();
runnableRange = strrep(codeRange, placeholder, 'dat = Trange;');
runnableRange = strrep(runnableRange, 'addpath("tmapper_tools/")', '');
figsBeforeR = findobj('Type','figure');
eval(runnableRange);
newFigsR = setdiff(findobj('Type','figure'), figsBeforeR);
assert(isequal(baseRows(:), (50:150)'), 'start row=50, end row=150, downsample=1 should select rows 50:150.');
assert(isequal(dat.z(baseRows), (50:150)'), ...
    'the selected rows should correspond to the requested window of the original table.');
close(newFigsR)

delete(appRange);

% -- missing data guard: rows with NaN in the selected variables should
% be dropped automatically (with a warning), not silently corrupt the
% whole build via zscore's NaN-propagation-across-an-entire-column
% behavior (confirmed separately: zscore([1;2;NaN]) is all-NaN).
appMissing = TemporalMapperApp;
TMissing = Trange; % reuse the 200-row x/y/z synthetic table
TMissing.x(37) = NaN;
appMissing.loadData(TMissing);
assert(isequal(appMissing.VariableListBox.String(:), {'x';'y';'z'}), ...
    'loadData should succeed and expose all numeric variables even when they contain NaN values.');
appMissing.VariableListBox.Value = 1:3;
appMissing.KEditField.String = '3';
appMissing.DEditField.String = '2';
appMissing.TExcludeEditField.String = '5';
appMissing.RangeStartEditField.String = '1';
appMissing.RangeEndEditField.String = 'Inf';
appMissing.DownsampleEditField.String = '1';
appMissing.buildNetwork(); % should NOT throw despite the NaN
assert(contains(appMissing.StatusTextArea.String{1}, 'Built network:'), ...
    'buildNetwork should still succeed (by dropping the missing row) rather than erroring.');
assert(numel(appMissing.StatusTextArea.String) >= 3 && ...
    contains(appMissing.StatusTextArea.String{3}, 'Dropped 1 of 200 row(s)'), ...
    'buildNetwork should warn about the exact number of rows dropped for missing data.');

% -- cross-check via generateCode that the dropped row is really excluded
codeMissing = appMissing.generateCode();
runnableMissing = strrep(codeMissing, placeholder, 'dat = TMissing;');
runnableMissing = strrep(runnableMissing, 'addpath("tmapper_tools/")', '');
figsBeforeM = findobj('Type','figure');
eval(runnableMissing);
newFigsM = setdiff(findobj('Type','figure'), figsBeforeM);
assert(nDropped == 1, 'generated code should also detect exactly 1 dropped row.');
assert(~ismember(37, baseRows), 'the row with the injected NaN should be excluded from baseRows.');
close(newFigsM)
delete(appMissing);

% -- a normal (clean) build should NOT emit a "Dropped" warning line
assert(~any(contains(app.StatusTextArea.String, 'Dropped')), ...
    'a build with no missing data should not emit a dropped-rows warning.');

% -- tidx must track ELAPSED time, not array position. tknndigraph links
% two points in time only when their tidx differs by exactly 1, so if
% tidx is just 1:N over the SURVIVING rows, dropping a row silently
% renumbers its neighbours as adjacent and a temporal edge gets
% fabricated straight across a real gap in the data.
rng(3);
Ngap = 100;
TGap = table();
TGap.x = sin((1:Ngap)'/10);
TGap.y = cos((1:Ngap)'/10);
TGap.z = (1:Ngap)';
TGap.x(50) = NaN; % punch a one-row hole, so rows 49 and 51 are NOT adjacent in time

appGap = TemporalMapperApp;
appGap.loadData(TGap);
appGap.VariableListBox.Value = 1:3;
appGap.KEditField.String = '3';
appGap.DEditField.String = '2';
appGap.TExcludeEditField.String = '5';
appGap.RangeStartEditField.String = '1';
appGap.RangeEndEditField.String = 'Inf';
appGap.DownsampleEditField.String = '1';
appGap.buildNetwork();
tokGap = regexp(appGap.StatusTextArea.String{1}, 'Built network: (\d+) nodes, (\d+) edges', 'tokens');
gapNodes = str2double(tokGap{1}{1});
gapEdges = str2double(tokGap{1}{2});

codeGap = appGap.generateCode();
runnableGap = strrep(codeGap, placeholder, 'dat = TGap;');
runnableGap = strrep(runnableGap, 'addpath("tmapper_tools/")', '');
figsBeforeG = findobj('Type','figure');
eval(runnableGap);
newFigsG = setdiff(findobj('Type','figure'), figsBeforeG);

assert(numel(tidx) == Ngap-1, ...
    sprintf('one row should have been dropped: expected %d tidx entries, got %d.', Ngap-1, numel(tidx)));
% the invariant: tidx counts sampling intervals from the first kept row,
% so it inherits the hole rather than closing it up
assert(isequal(tidx(:), baseRows(:) - baseRows(1) + 1), ...
    'tidx should count elapsed sampling intervals from the first kept row, not array position.');
assert(any(diff(tidx) == 2), ...
    'tidx should show a gap (a step of 2) where the missing row was dropped.');
% and the consequence that actually matters: the pair straddling the gap
% must not satisfy tknndigraph's temporal-adjacency predicate, so no
% temporal edge is fabricated across it. Tested via the predicate itself
% rather than findedge, because the two rows either side of a one-sample
% hole are still near-neighbours in state space and may legitimately be
% linked *spatially* -- findedge alone can't tell the two apart.
% tidx(:) first: the generated script builds its row list as a row
% vector, and circshift along dim 1 of a row vector is a silent no-op --
% tknndigraph itself normalises with tidx(:) for the same reason.
tv = tidx(:);
t_wafter = circshift(tv,-1,1) - 1 == tv; % tknndigraph's own test
assert(~t_wafter(49), ...
    'the sample before the gap must not count as temporally adjacent to the one after it.');
assert(all(t_wafter(1:48)) && all(t_wafter(50:end-1)), ...
    'every genuinely consecutive pair should still count as temporally adjacent.');
% the app's own build and the generated script must agree
assert(numnodes(g_simp) == gapNodes && numedges(g_simp) == gapEdges, ...
    'generated code should reproduce the same network the GUI built on gapped data.');
close(newFigsG)
delete(appGap);

% -- decimation must happen on the ORIGINAL row grid, not on the list of
% rows left after missing-data removal. Striding the survivors slides
% every later sample off the true time grid, so samples that were in
% fact evenly spaced start showing fabricated gaps.
rng(4);
Ndec = 200;
TDec = table();
TDec.x = sin((1:Ndec)'/10);
TDec.y = cos((1:Ndec)'/10);
TDec.z = (1:Ndec)';
TDec.x(37) = NaN; % an isolated hole, sitting ON the grid (37 = 1 + 4*9)

appDec = TemporalMapperApp;
appDec.loadData(TDec);
appDec.VariableListBox.Value = 1:3;
appDec.KEditField.String = '3';
appDec.DEditField.String = '2';
appDec.TExcludeEditField.String = '5';
appDec.RangeStartEditField.String = '1';
appDec.RangeEndEditField.String = 'Inf';
appDec.DownsampleEditField.String = '4';
appDec.buildNetwork();

codeDec = appDec.generateCode();
runnableDec = strrep(codeDec, placeholder, 'dat = TDec;');
runnableDec = strrep(runnableDec, 'addpath("tmapper_tools/")', '');
figsBeforeD = findobj('Type','figure');
eval(runnableDec);
newFigsD = setdiff(findobj('Type','figure'), figsBeforeD);

assert(all(mod(baseRows(:) - 1, 4) == 0), ...
    'every kept sample must sit on the original decimation grid (rows 1, 5, 9, ...).');
% an isolated missing value costs no sample at all: the anti-aliasing
% average simply skips it, exactly as the Python app's rolling mean does
assert(ismember(37, baseRows), ...
    'an isolated missing value should be absorbed by the anti-aliasing average, not cost a whole sample.');
assert(isequal(tidx(:), (baseRows(:) - baseRows(1))/4 + 1), ...
    'tidx should count decimated intervals from the first kept sample.');
assert(all(diff(tidx(:)) == 1), ...
    'evenly spaced samples must not show fabricated gaps after downsampling.');
close(newFigsD)
delete(appDec);

% -- datetime columns. readtable turns a date column into datetime, which
% is NOT isnumeric -- so a numeric-only filter hides it from the Color
% by/Time axis dropdowns entirely, and the GUI can't even reproduce
% tmapper_demo.m's own "t = dat.Date" time axis. Datetime is offered for
% colouring and the time axis, but still barred from the build variables
% (distances need real numbers).
rng(5);
Ndt = 150;
TDate = table();
TDate.Date = (datetime(2020,1,1) + days(0:Ndt-1))';
TDate.x = sin((1:Ndt)'/10);
TDate.y = cos((1:Ndt)'/10);

appDate = TemporalMapperApp;
appDate.loadData(TDate);
assert(isequal(appDate.VariableListBox.String(:), {'x';'y'}), ...
    'a datetime column must not be offered as a build variable.');
assert(any(strcmp(appDate.TimeVarDropDown.String, 'Date')), ...
    'a datetime column should be selectable as the Time axis.');
assert(any(strcmp(appDate.ColorVarDropDown.String, 'Date')), ...
    'a datetime column should be selectable as the Color by variable.');

appDate.VariableListBox.Value = 1:2;
appDate.KEditField.String = '3';
appDate.DEditField.String = '2';
appDate.TExcludeEditField.String = '5';

% datetime as the time axis: imagesc takes datetime natively, so this
% should render the recurrence plot against real dates
appDate.TimeVarDropDown.Value = find(strcmp(appDate.TimeVarDropDown.String, 'Date'));
appDate.buildNetwork();
assert(contains(appDate.StatusTextArea.String{1}, 'Built network:'), ...
    'building with a datetime time axis should succeed.');
assert(isa(appDate.RecurrenceAxes.XAxis, 'matlab.graphics.axis.decorator.DatetimeRuler'), ...
    'the recurrence plot should use a real datetime axis, not raw numbers.');

% datetime as the colour variable: plottmgraph calls isnan on colorvar,
% which errors on datetime, so the app must convert it to numeric
appDate.ColorVarDropDown.Value = find(strcmp(appDate.ColorVarDropDown.String, 'Date'));
appDate.ColorVarDropDown.Callback(appDate.ColorVarDropDown, []);
assert(contains(appDate.StatusTextArea.String{1}, 'Re-rendered plot'), ...
    'colouring by a datetime column should re-render without erroring.');

% and the generated script must run with both set to the datetime column
codeDate = appDate.generateCode();
runnableDate = strrep(codeDate, placeholder, 'dat = TDate;');
runnableDate = strrep(runnableDate, 'addpath("tmapper_tools/")', '');
figsBeforeDt = findobj('Type','figure');
eval(runnableDate);
newFigsDt = setdiff(findobj('Type','figure'), figsBeforeDt);
assert(isnumeric(colorvar), ...
    'generated code should convert a datetime colour variable to numeric.');
assert(isdatetime(t), ...
    'generated code should keep a datetime time axis as datetime.');
close(newFigsDt)
delete(appDate);

% -- a leading unnamed row-index column (readtable names it "Var1") is a
% stray artifact of writing a CSV with the index included. It is a
% monotonic ramp, so leaving it selectable -- and selected by default --
% silently dominates the distance computation.
TIdx = table();
TIdx.Var1 = (1:120)'; % the artifact
TIdx.Date = (datetime(2020,1,1) + days(0:119))';
TIdx.tmax = sin((1:120)'/10);
TIdx.tmin = cos((1:120)'/10);

appIdx = TemporalMapperApp;
appIdx.loadData(TIdx);
assert(~any(strcmp(appIdx.VariableListBox.String, 'Var1')), ...
    'a leading row-index column should not be offered as a build variable.');
assert(isequal(appIdx.VariableListBox.String(:), {'tmax';'tmin'}), ...
    'the remaining build variables should be the real ones.');
assert(~any(strcmp(appIdx.ColorVarDropDown.String, 'Var1')), ...
    'a leading row-index column should not be offered for colouring either.');

% it must NOT fire on a genuinely header-less file, where readtable names
% EVERY column VarN -- there is no way to tell an index from real data
TAllVar = table();
TAllVar.Var1 = (1:50)';
TAllVar.Var2 = sin((1:50)'/5);
TAllVar.Var3 = cos((1:50)'/5);
appAllVar = TemporalMapperApp;
appAllVar.loadData(TAllVar);
assert(any(strcmp(appAllVar.VariableListBox.String, 'Var1')), ...
    'Var1 must be kept when every column is auto-named -- that is a header-less file, not a stray index.');
delete(appAllVar);

% nor on a Var1 that is real data rather than a row index
TRealVar1 = table();
TRealVar1.Var1 = sin((1:50)'/5); % not monotonic -- real data
TRealVar1.tmax = cos((1:50)'/5);
appRealVar1 = TemporalMapperApp;
appRealVar1.loadData(TRealVar1);
assert(any(strcmp(appRealVar1.VariableListBox.String, 'Var1')), ...
    'a non-monotonic Var1 is real data and must be kept.');
delete(appRealVar1);

% the generated script must drop it too, so its "dat" matches the app's
appIdx.VariableListBox.Value = 1:2;
appIdx.KEditField.String = '3';
appIdx.DEditField.String = '2';
appIdx.TExcludeEditField.String = '5';
appIdx.buildNetwork();
codeIdx = appIdx.generateCode();
runnableIdx = strrep(codeIdx, placeholder, 'dat = TIdx;');
runnableIdx = strrep(runnableIdx, 'addpath("tmapper_tools/")', '');
figsBeforeI = findobj('Type','figure');
eval(runnableIdx);
newFigsI = setdiff(findobj('Type','figure'), figsBeforeI);
assert(~any(strcmp(dat.Properties.VariableNames, 'Var1')), ...
    'generated code should drop the row-index column as the app did.');
close(newFigsI)
delete(appIdx);

% -- categorical colouring: text labels (condition, trial, behavioural
% state) are a legitimate way to colour the network, but they are purely
% nominal -- averaging their codes is meaningless, and a continuous ramp
% implies an ordering between categories that does not exist.
TCat = table();
TCat.cond = repmat({'rest';'task';'recovery';'task'}, 40, 1);
TCat.x = sin((1:160)'/10);
TCat.y = cos((1:160)'/10);
TCat.z = (1:160)';

appCat = TemporalMapperApp;
appCat.loadData(TCat);
assert(any(strcmp(appCat.ColorVarDropDown.String, 'cond')), ...
    'a categorical column should be selectable for colouring.');
assert(~any(strcmp(appCat.TimeVarDropDown.String, 'cond')), ...
    'a categorical column must not be offered as a time axis -- it has no order.');
assert(~any(strcmp(appCat.VariableListBox.String, 'cond')), ...
    'a categorical column must not be offered as a build variable.');

appCat.VariableListBox.Value = 1:3;
appCat.KEditField.String = '3';
appCat.DEditField.String = '2';
appCat.TExcludeEditField.String = '5';
appCat.ColorVarDropDown.Value = find(strcmp(appCat.ColorVarDropDown.String, 'cond'));
appCat.buildNetwork();
assert(contains(appCat.StatusTextArea.String{1}, 'Built network:'), ...
    'building with a categorical colour variable should succeed.');

% the colour axis is pinned so each category owns a band, rather than
% being stretched to whatever codes happen to be present
assert(isequal(appCat.NetworkAxes.CLim, [0.5 3.5]), ...
    'the colour axis should be pinned to the 3 categories (0.5 to 3.5).');

% averaging category codes is meaningless, so those options go away
assert(isequal(appCat.LabelMethodDropDown.String(:)', {'mode','none'}), ...
    'mean/median should be withdrawn while colouring by a category.');
% ...and come back for a numeric colour variable
appCat.ColorVarDropDown.Value = find(strcmp(appCat.ColorVarDropDown.String, 'x'));
appCat.ColorVarDropDown.Callback(appCat.ColorVarDropDown, []);
assert(isequal(appCat.LabelMethodDropDown.String(:)', {'mode','mean','median','none'}), ...
    'the full set of label methods should return for a numeric colour variable.');

% a mean/median selection must survive the round trip rather than being
% silently reinterpreted as a different method
appCat.LabelMethodDropDown.Value = find(strcmp(appCat.LabelMethodDropDown.String,'median'));
appCat.ColorVarDropDown.Value = find(strcmp(appCat.ColorVarDropDown.String, 'cond'));
appCat.ColorVarDropDown.Callback(appCat.ColorVarDropDown, []);
assert(strcmp(appCat.LabelMethodDropDown.String{appCat.LabelMethodDropDown.Value}, 'mode'), ...
    'an withdrawn method should fall back to mode, not to whatever sits at the old index.');

% and the generated script must reproduce the categorical colouring
codeCat = appCat.generateCode();
assert(contains(codeCat, 'findgroups'), ...
    'generated code should convert the category labels to codes.');
runnableCat = strrep(codeCat, placeholder, 'dat = TCat;');
runnableCat = strrep(runnableCat, 'addpath("tmapper_tools/")', '');
figsBeforeC = findobj('Type','figure');
eval(runnableCat);
newFigsC = setdiff(findobj('Type','figure'), figsBeforeC);
assert(isnumeric(colorvar) && all(ismember(unique(colorvar), 1:3)), ...
    'generated code should yield integer category codes.');
close(newFigsC)
delete(appCat);

% -- export: the analysis-ready artifacts. "Copy Code" alone leaves the
% user to re-run everything just to get at the node assignments, which is
% what downstream dwell-time/transition-rate analysis actually needs.
% NOTE the ramp column: without it this data collapses to a single node,
% which silently makes every assertion about the time-point -> node
% mapping below vacuously true (caught by mutation testing).
TExp = table();
TExp.Date = (datetime(2020,1,1) + days(0:149))';
TExp.x = sin((1:150)'/10);
TExp.y = cos((1:150)'/10);
TExp.z = (1:150)';

appExp = TemporalMapperApp;
assertThrows(@() appExp.exportResults(tempdir), 'TemporalMapperApp:noNetwork', ...
    'exportResults should refuse to export before a network has been built.');
appExp.loadData(TExp); % has a Date column, to exercise the datetime paths
appExp.VariableListBox.Value = 1:3;
appExp.KEditField.String = '3';
appExp.DEditField.String = '2';
appExp.TExcludeEditField.String = '5';
appExp.TimeVarDropDown.Value = find(strcmp(appExp.TimeVarDropDown.String, 'Date'));
appExp.buildNetwork();
% read the build summary BEFORE exporting -- exportResults replaces the
% status text with its own confirmation
tokExp = regexp(appExp.StatusTextArea.String{1}, 'Built network: (\d+) nodes', 'tokens');
expNodes = str2double(tokExp{1}{1});

outDir = fullfile(tempdir, sprintf('tmapper_export_test_%d', randi(1e9)));
cleanupExport = onCleanup(@() rmdir(outDir, 's')); %#ok<NASGU>
appExp.exportResults(outDir);

for f = {'network.png','recurrence.png','timeline.csv','params.json','reproduce.m'}
    assert(isfile(fullfile(outDir, f{1})), sprintf('export should write %s.', f{1}));
end

% timeline.csv is the join-back table: which attractor the system was in
% at each retained time point
TL = readtable(fullfile(outDir,'timeline.csv'));
assert(all(ismember({'tidx','source_row','node'}, TL.Properties.VariableNames)), ...
    'timeline.csv should carry tidx, source_row and node columns.');
assert(expNodes > 1, ...
    'this fixture must produce a multi-node network, or the mapping checks below prove nothing.');
assert(all(TL.node >= 1 & TL.node <= expNodes), ...
    'every timeline node id should be a real node of the built network.');
assert(isequal(unique(TL.node(:))', 1:expNodes), ...
    'every node of the network should appear in the timeline.');
% the mapping must be the real members{} grouping, not a constant or a
% renumbering. Cross-checked against an independent rerun of the exported
% reproduce.m, so the timeline is verified against the pipeline itself
% rather than against the same code that wrote it.
runnableExp = strrep(fileread(fullfile(outDir,'reproduce.m')), placeholder, 'dat = TExp;');
runnableExp = strrep(runnableExp, 'addpath("tmapper_tools/")', '');
figsBeforeE = findobj('Type','figure');
eval(runnableExp);
newFigsE = setdiff(findobj('Type','figure'), figsBeforeE);
for i = 1:expNodes
    assert(isequal(sort(find(TL.node == i))', sort(members{i}(:))'), ...
        sprintf('timeline rows for node %d should be exactly that node''s members.', i));
end
close(newFigsE)
assert(height(TL) == numel(TL.tidx) && issorted(TL.tidx), ...
    'timeline.csv should be one row per retained time point, in time order.');

% params.json records what was actually built, including resolved values
P = jsondecode(fileread(fullfile(outDir,'params.json')));
assert(P.network_parameters.k == 3 && P.network_parameters.d == 2, ...
    'params.json should record the network parameters used.');
assert(isfield(P.network_parameters,'max_neighbor_dist_resolved'), ...
    'params.json should record the RESOLVED max neighbor distance, not just the request.');
assert(P.result.n_nodes == expNodes, 'params.json should record the resulting network size.');

% reproduce.m is the same script Copy Code produces
assert(strcmp(strtrim(fileread(fullfile(outDir,'reproduce.m'))), strtrim(appExp.generateCode())), ...
    'reproduce.m should be exactly the script generateCode produces.');

% exporting without the recurrence plot shown should skip that figure
appExp.ShowRecurrenceCheckBox.Value = 0;
appExp.buildNetwork();
outDir2 = fullfile(tempdir, sprintf('tmapper_export_test2_%d', randi(1e9)));
cleanupExport2 = onCleanup(@() rmdir(outDir2, 's')); %#ok<NASGU>
appExp.exportResults(outDir2);
assert(isfile(fullfile(outDir2,'network.png')), 'the network figure should always be exported.');
assert(~isfile(fullfile(outDir2,'recurrence.png')), ...
    'the recurrence figure should not be exported when it is not shown.');
delete(appExp);

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
