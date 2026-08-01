classdef TemporalMapperApp < handle
    %TEMPORALMAPPERAPP interactive GUI for the Temporal Mapper pipeline.
    %   Load a data file, pick which numeric columns to build the
    %   attractor transition network from, set the tknndigraph/filtergraph
    %   parameters, and view the resulting network + recurrence plot --
    %   without writing any code.
    %
    %   Launch with:
    %       addpath("tmapper_tools/")
    %       app = TemporalMapperApp;
    %
    %   The data can also be loaded programmatically (bypassing the file
    %   picker), which is handy for scripting or testing:
    %       app.loadData(readtable("sampledata/EL_temp.csv"));
    %       app.VariableListBox.Value = 1:3; % select first 3 variables
    %       app.buildNetwork();
    %
    %{
    created by MZ (with Claude Code), 7-23-2026
    modifications: see git history for the many rounds of layout work
    that happened here.
    (7-24-2026) rewritten from an App Designer-style uifigure/
    uigridlayout app to a traditional figure/uicontrol app. The
    uigridlayout version had a confirmed, reproducible uifigure
    rendering bug on a mixed-DPI dual-monitor Windows setup (content
    beyond ~600-650px in a single grid, or the first row of a panel,
    would silently fail to paint -- independent of DPI override
    settings, GPU software/hardware rendering, or window/monitor
    placement, and reproducible in minimal test scripts unrelated to
    this app). Classic figure/uicontrol uses a completely different
    (non-web-based) rendering path and doesn't exhibit this bug.
    Layout is now done via a small helper (cellPosition) that computes
    normalized Position rectangles for a conceptual 10-row x 6-column
    grid within the Setup panel, matching the same control groupings
    the uigridlayout version used.
    %}

    properties (Access = public)
        UIFigure            matlab.ui.Figure
        DataPanel           matlab.ui.container.Panel
        PreprocessPanel     matlab.ui.container.Panel
        NetworkParamsPanel  matlab.ui.container.Panel
        PlotOptionsPanel    matlab.ui.container.Panel
        PlotPanel           matlab.ui.container.Panel

        LoadDataButton          matlab.ui.control.UIControl
        LoadWorkspaceButton     matlab.ui.control.UIControl
        FileLabel               matlab.ui.control.UIControl
        VariablesLabel          matlab.ui.control.UIControl
        SelectAllButton         matlab.ui.control.UIControl
        VariableListBox         matlab.ui.control.UIControl
        ZscoreCheckBox          matlab.ui.control.UIControl
        RangeStartLabel         matlab.ui.control.UIControl
        RangeStartEditField     matlab.ui.control.UIControl
        RangeEndLabel           matlab.ui.control.UIControl
        RangeEndEditField       matlab.ui.control.UIControl
        TimeIndexLabel          matlab.ui.control.UIControl
        TimeIndexDropDown       matlab.ui.control.UIControl
        DownsampleLabel         matlab.ui.control.UIControl
        DownsampleEditField     matlab.ui.control.UIControl
        EmbedLagLabel           matlab.ui.control.UIControl
        EmbedLagEditField       matlab.ui.control.UIControl
        EmbedOrderLabel         matlab.ui.control.UIControl
        EmbedOrderEditField     matlab.ui.control.UIControl
        ColorVarLabel           matlab.ui.control.UIControl
        ColorVarDropDown        matlab.ui.control.UIControl
        ColorVarWorkspaceButton matlab.ui.control.UIControl
        TimeVarLabel            matlab.ui.control.UIControl
        TimeVarDropDown         matlab.ui.control.UIControl
        KLabel                  matlab.ui.control.UIControl
        KEditField              matlab.ui.control.UIControl
        DLabel                  matlab.ui.control.UIControl
        DEditField              matlab.ui.control.UIControl
        TExcludeLabel           matlab.ui.control.UIControl
        TExcludeEditField       matlab.ui.control.UIControl
        MaxDistPrctLabel        matlab.ui.control.UIControl
        MaxDistPrctEditField    matlab.ui.control.UIControl
        MaxDistLabel            matlab.ui.control.UIControl
        MaxDistEditField        matlab.ui.control.UIControl
        ReciprocalCheckBox      matlab.ui.control.UIControl
        NodeSizeModeLabel       matlab.ui.control.UIControl
        NodeSizeModeDropDown    matlab.ui.control.UIControl
        ColormapLabel           matlab.ui.control.UIControl
        ColormapDropDown        matlab.ui.control.UIControl
        LabelMethodLabel        matlab.ui.control.UIControl
        LabelMethodDropDown     matlab.ui.control.UIControl
        ShowRecurrenceCheckBox  matlab.ui.control.UIControl
        ShowNodeBorderCheckBox  matlab.ui.control.UIControl
        BuildButton             matlab.ui.control.UIControl
        StopButton              matlab.ui.control.UIControl
        ResetButton             matlab.ui.control.UIControl
        CopyCodeButton          matlab.ui.control.UIControl
        ExportButton            matlab.ui.control.UIControl
        StatusLabel             matlab.ui.control.UIControl
        StatusTextArea          matlab.ui.control.UIControl

        NetworkAxes         matlab.graphics.axis.Axes
        RecurrenceAxes      matlab.graphics.axis.Axes
    end

    properties (Access = private)
        DataTable = table()   % the loaded data
        NumericVarNames = {}  % candidate columns (numeric only)
        DatetimeVarNames = {} % datetime columns: colour/time axis only, never build variables
        CategoricalVarNames = {} % text/categorical columns: colouring only -- nominal, so no time axis
        DroppedIndexCol = false % whether loadData stripped a leading row-index column
        ExtraColorVarNames = {}  % display names of workspace-sourced color vectors
        ExtraColorVarValues = {} % their values, parallel to ExtraColorVarNames
        DataSourceCode = '% dat = <load your data here as a table, e.g. dat = readtable(''your_file.csv'');>' % how "dat" was obtained, for generateCode

        % cache of the most recently BUILT network (tknndigraph +
        % filtergraph output), so plot-only option changes can re-render
        % via renderPlot() without recomputing the expensive part.
        % LastMembers is the "has a network been built yet" sentinel.
        LastGSimp = digraph()
        LastMembers = {}
        LastRows = []
        LastTidx = []
        LastPar = struct()
        LastK = []
        LastD = []
        LastTExclude = []
        LastOrder = []
        LastLag = []
        LastDownsample = []
        % the remaining build inputs, cached for the same reason: an
        % export must describe the network that was actually built, not
        % whatever the controls happen to read after the fact.
        LastSelectedVars = {}
        LastZscore = []
        LastStartRow = []
        LastEndRow = []
        LastMaxDistPrct = []
        LastMaxDistRequested = []
        LastReciprocal = []
        LastTidxSource = 'row order'

        CancelRequested = false % set by StopButtonPushed, checked between build stages
    end

    methods (Access = public)

        function loadData(app, T)
            %LOADDATA load a table into the app -- populates the variable
            %list and color/time dropdowns. Used both by the "Load
            %Data..." button (after reading the picked file) and directly
            %by scripts/tests that want to bypass the file picker.
            % -- drop a leading row-index column before anything else. A
            % CSV written without suppressing the index gets an unnamed
            % first column, which readtable names "Var1"; it is just a
            % monotonic ramp, so leaving it selectable (and selected by
            % default) would silently dominate the distance computation.
            %   "Var1" alone is a weaker signal than pandas' "Unnamed: 0",
            % since MATLAB also auto-names the columns of a genuinely
            % header-less file, so this additionally requires that some
            % other column IS named, and that the column actually looks
            % like a row index. Better to keep a stray column than to
            % silently delete someone's data.
            droppedIndexCol = false;
            allNames = T.Properties.VariableNames;
            if numel(allNames) > 1 && strcmp(allNames{1}, 'Var1') && ...
                    ~all(startsWith(allNames, 'Var')) && ...
                    isnumeric(T{:,1}) && all(diff(T{:,1}) > 0)
                T(:,1) = [];
                droppedIndexCol = true;
            end

            isnum = varfun(@isnumeric, T, 'OutputFormat','uniform');
            varNames = T.Properties.VariableNames(isnum);
            if isempty(varNames)
                error('TemporalMapperApp:noNumericVars', ...
                    'That data has no numeric columns to build a network from.');
            end
            % -- datetime columns are usable for colouring and as the time
            % axis, but NOT as build variables: distances need real
            % numbers. readtable produces these automatically from a date
            % column, so filtering the dropdowns by isnumeric alone would
            % hide the very column tmapper_demo.m uses as its time axis.
            isdt = varfun(@isdatetime, T, 'OutputFormat','uniform');
            dateNames = T.Properties.VariableNames(isdt);
            % -- text/categorical columns (condition, trial, behavioural
            % state) can colour the network, but they are purely nominal:
            % no time axis, and no build variables either.
            iscat = varfun(@(c) iscellstr(c) || isstring(c) || iscategorical(c), ...
                T, 'OutputFormat','uniform');
            catNames = T.Properties.VariableNames(iscat);

            app.DataTable = T;
            app.NumericVarNames = varNames;
            app.DatetimeVarNames = dateNames;
            app.CategoricalVarNames = catNames;
            app.DroppedIndexCol = droppedIndexCol;
            % any workspace-sourced color vectors were aligned to the
            % previous data's row count, so they no longer apply
            app.ExtraColorVarNames = {};
            app.ExtraColorVarValues = {};
            % a cached network from the previous data no longer applies either
            app.LastGSimp = digraph();
            app.LastMembers = {};
            app.LastRows = [];
            app.LastTidx = [];
            app.VariableListBox.String = varNames;
            app.VariableListBox.Value = 1:numel(varNames); % select all by default
            app.ColorVarDropDown.String = [{'(row index)'}, varNames, dateNames, catNames];
            app.ColorVarDropDown.Value = 1;
            app.TimeVarDropDown.String = [{'(row index)'}, varNames, dateNames];
            app.TimeVarDropDown.Value = 1;
            app.TimeIndexDropDown.String = [{'(from row order)'}, varNames, dateNames];
            app.TimeIndexDropDown.Value = 1;
            app.FileLabel.String = sprintf('Loaded: %d rows, %d numeric vars', height(T), numel(varNames));
            loadedMsg = {sprintf('Loaded data: %d rows, %d numeric variables.', height(T), numel(varNames))};
            if droppedIndexCol
                loadedMsg{end+1} = ['Dropped a leading unnamed row-index column ("Var1") -- ' ...
                    'it is a monotonic ramp that would dominate the distance computation.'];
            end
            app.StatusTextArea.String = loadedMsg;
        end

        function addColorVarFromWorkspace(app, name, v)
            %ADDCOLORVARFROMWORKSPACE register a numeric vector as a
            %selectable "Color by" option, displayed as "name
            %(workspace)". Must have one element per row of the loaded
            %data, since it's indexed positionally like any other color
            %source in buildNetwork. Used both by
            %ColorVarWorkspaceButtonPushed (after picking a workspace
            %variable via listdlg) and directly by scripts/tests that
            %want to bypass that picker dialog.
            if isempty(app.DataTable)
                error('TemporalMapperApp:noData','Load a data file first.');
            end
            v = v(:);
            if numel(v) ~= height(app.DataTable)
                error('TemporalMapperApp:colorVarLengthMismatch', ...
                    '%s has %d elements, but the loaded data has %d rows -- they must match.', ...
                    name, numel(v), height(app.DataTable));
            end
            displayName = sprintf('%s (workspace)', name);
            existing = strcmp(app.ExtraColorVarNames, displayName);
            if any(existing)
                app.ExtraColorVarValues{existing} = v;
            else
                app.ExtraColorVarNames{end+1} = displayName;
                app.ExtraColorVarValues{end+1} = v;
            end
            app.ColorVarDropDown.String = [{'(row index)'}, app.NumericVarNames, app.DatetimeVarNames, app.CategoricalVarNames, app.ExtraColorVarNames];
            app.ColorVarDropDown.Value = numel(app.ColorVarDropDown.String); % select the one just added
        end

        function buildNetwork(app)
            %BUILDNETWORK run tknndigraph -> filtergraph on the currently
            %selected variables/parameters, cache the result, and render
            %it into NetworkAxes/RecurrenceAxes. Used both by the "Build
            %Network" button and directly by scripts/tests.
            %   Plot-only changes (color/time axis, node size, label
            %   method, show recurrence/node border) don't need to call
            %   this again -- they re-render via renderPlot(), which
            %   reuses the cached network instead of recomputing it.
            %   Checks CancelRequested between stages so the "Stop"
            %   button can abort a slow build; this only takes effect
            %   between stages, not mid-computation within one.
            if isempty(app.DataTable)
                error('TemporalMapperApp:noData','Load a data file first.');
            end
            selectedVars = app.VariableListBox.String(app.VariableListBox.Value);
            if isempty(selectedVars)
                error('TemporalMapperApp:noVars','Select at least one variable to build the network from.');
            end

            app.CancelRequested = false;
            app.BuildButton.Enable = 'off';
            app.StopButton.Enable = 'on';
            enableCleanup = onCleanup(@() app.resetBuildControls()); %#ok<NASGU>

            % -- restrict to a row range and/or downsample BEFORE
            % z-scoring/embedding, so those steps see only the rows the
            % user actually wants included. 'end row' uses Inf as a
            % sentinel for "the last row" (same convention as the max
            % dist fields below), clamped to the data's actual height.
            N_full = height(app.DataTable);
            startRow = app.parseNumericField(app.RangeStartEditField, 'start row', 1, N_full, true, false);
            endRow = min(app.parseNumericField(app.RangeEndEditField, 'end row', 1, Inf, true, false), N_full);
            if endRow < startRow
                error('TemporalMapperApp:invalidRange', 'End row must be greater than or equal to start row.');
            end
            downsample = app.parseNumericField(app.DownsampleEditField, 'downsample factor', 1, Inf, true, false);

            % -- anti-aliasing lowpass filter, then decimate ON THE
            % ORIGINAL ROW GRID. A plain strided pick (every Nth row) can
            % alias high-frequency content in the raw variables into
            % spurious low-frequency structure, so smoothing over a window
            % the size of the downsample factor first (movmean -- base
            % MATLAB, no toolbox needed) attenuates it. No-op when
            % downsample==1.
            %   Decimating the ORIGINAL grid rather than the list of rows
            % left after missing-data removal matters: striding the
            % survivors slides every later sample off the true time grid,
            % so samples that were in fact evenly spaced start showing
            % fabricated gaps.
            %   'omitnan' lets the average simply skip a missing input, so
            % an isolated NaN costs no sample at all; only a grid point
            % whose whole window is missing survives as NaN and gets
            % dropped below. Missing data must not reach the pipeline
            % either way -- zscore and pdist2 both propagate NaN across an
            % entire column/matrix, so a network built from unremoved NaNs
            % degenerates silently.
            windowRows = (startRow:endRow)';
            windowVals = app.DataTable{windowRows,selectedVars};
            if downsample > 1
                smoothVals = movmean(windowVals, downsample, 1, 'omitnan');
            else
                smoothVals = windowVals;
            end
            gridIdx = (1:downsample:numel(windowRows))';
            gridRows = windowRows(gridIdx);
            gridVals = smoothVals(gridIdx,:);

            keepMask = ~any(isnan(gridVals), 2);
            baseRows = gridRows(keepMask);
            filteredVals = gridVals(keepMask,:);
            nDropped = numel(gridRows) - numel(baseRows);

            if numel(baseRows) < 2
                error('TemporalMapperApp:invalidRange', ...
                    'Row range/downsampling/missing-data removal leaves only %d row(s) -- need at least 2.', numel(baseRows));
            end

            % -- refuse an oversized range BEFORE pdist2 allocates it
            oversized = TemporalMapperApp.oversizedWindowMessage(numel(baseRows));
            if ~isempty(oversized)
                error('TemporalMapperApp:windowTooLarge', '%s', oversized);
            end

            if app.ZscoreCheckBox.Value
                X_raw = zscore(filteredVals);
            else
                X_raw = filteredVals;
            end
            N_raw = size(X_raw,1);

            % -- delay embedding: concatenate 'order' copies of the state,
            % each 'lag' time points apart, e.g. [x(t-lag), x(t)] for
            % order=2. This is what reveals cyclic/recurrent structure
            % that isn't visible in the raw variables alone (see
            % tmapper_demo.m's "quick and dirty delay embedding"). The
            % default order=1 skips this and passes X_raw through as-is.
            lag = app.parseNumericField(app.EmbedLagEditField, 'embed lag', 0, Inf, true, false);
            order = app.parseNumericField(app.EmbedOrderEditField, 'embed order', 1, Inf, true, false);
            if order > 1
                if lag < 1
                    error('TemporalMapperApp:invalidEmbed', ...
                        'Embed lag must be at least 1 when embed order > 1.');
                end
                N = N_raw - (order-1)*lag;
                if N < 2
                    error('TemporalMapperApp:invalidEmbed', ...
                        'Embed lag/order too large: only %d rows of data available.', N_raw);
                end
                nvars = size(X_raw,2);
                X = zeros(N, nvars*order);
                for j = 1:order
                    X(:, (j-1)*nvars + (1:nvars)) = X_raw((j-1)*lag + (1:N), :);
                end
            else
                N = N_raw;
                X = X_raw;
            end
            % original DataTable rows aligned with each embedded state
            % (the most recent slice, since embedding above stacks
            % past->present), mapped back through baseRows since X_raw
            % may already be a range-restricted/downsampled subset.
            rows = baseRows((N_raw-N+1):N_raw);

            % -- tidx counts elapsed SAMPLING INTERVALS from the first
            % kept row, not position in the array. tknndigraph treats two
            % points as temporally adjacent only when their tidx differs
            % by exactly 1, so numbering the survivors 1:N would renumber
            % the neighbours of a dropped row as adjacent and fabricate a
            % temporal edge straight across a real gap in the data.
            % Dividing by downsample puts it in decimated units, so
            % consecutive kept samples still differ by 1.
            tidxChoice = app.TimeIndexDropDown.String{app.TimeIndexDropDown.Value};
            if strcmp(tidxChoice, '(from row order)')
                tidx = (rows - rows(1))/downsample + 1;
            else
                tidx = app.tidxFromColumn(tidxChoice, rows);
            end

            k = app.parseNumericField(app.KEditField, 'k (neighbors)', 1, Inf, true, false);
            d = app.parseNumericField(app.DEditField, 'd (compression)', 0, Inf, false, true);
            texclude = app.parseNumericField(app.TExcludeEditField, 'texclude', 1, Inf, true, false);
            maxdistprct = app.parseNumericField(app.MaxDistPrctEditField, 'max dist percentile', 0, 100, false, false);
            maxdist = app.parseNumericField(app.MaxDistEditField, 'max dist', 0, Inf, false, true);
            recip = app.ReciprocalCheckBox.Value;

            totalTimer = tic;

            % -- distances and the k-NN graph in one step. X is handed over
            % rather than a precomputed pdist2 matrix so tknndigraph can use
            % its lowMemory path, which computes distances a block of rows
            % at a time and never allocates an N-by-N array. That is what
            % lets the app handle long recordings at all: peak goes from
            % O(N^2) to O(blockSize*N), so the full bundled sample (56835
            % rows, ~85 GB the dense way) builds in about 2 GB.
            app.StatusTextArea.String = {'Computing distances and k-NN graph...'};
            drawnow
            if app.CancelRequested, app.reportCancelled(); return; end
            stepTimer = tic;
            [g, par] = tknndigraph(X, k, tidx, ...
                'timeExcludeRange', texclude, ...
                'maxNeighborDistPrct', maxdistprct, ...
                'maxNeighborDist', maxdist, ...
                'lowMemory', true);
            tKnn = toc(stepTimer);

            app.StatusTextArea.String = {sprintf('k-NN graph: %.2fs. Simplifying graph...', tKnn)};
            drawnow
            if app.CancelRequested, app.reportCancelled(); return; end
            stepTimer = tic;
            [g_simp, members, ~, ~] = filtergraph(g, d, 'reciprocal', recip);
            tSimplify = toc(stepTimer);

            if app.CancelRequested, app.reportCancelled(); return; end

            % cache for cheap plot-only re-renders (see renderPlot)
            app.LastGSimp = g_simp;
            app.LastMembers = members;
            app.LastRows = rows;
            app.LastTidx = tidx;
            app.LastPar = par;
            app.LastK = k;
            app.LastD = d;
            app.LastTExclude = texclude;
            app.LastOrder = order;
            app.LastLag = lag;
            app.LastDownsample = downsample;
            app.LastSelectedVars = selectedVars;
            app.LastZscore = app.ZscoreCheckBox.Value;
            app.LastStartRow = startRow;
            app.LastEndRow = endRow;
            app.LastMaxDistPrct = maxdistprct;
            app.LastMaxDistRequested = maxdist;
            app.LastReciprocal = recip;
            app.LastTidxSource = tidxChoice;

            [tPlotNetwork, tPlotRecurrence, showRecurrence] = app.renderPlot();

            tTotal = toc(totalTimer);
            if showRecurrence
                timingLine = sprintf(['Timing (s): distances+k-NN %.2f, simplify %.2f, ' ...
                    'network plot %.2f, recurrence plot %.2f, total %.2f.'], ...
                    tKnn, tSimplify, tPlotNetwork, tPlotRecurrence, tTotal);
            else
                timingLine = sprintf(['Timing (s): distances+k-NN %.2f, simplify %.2f, ' ...
                    'network plot %.2f, total %.2f.'], ...
                    tKnn, tSimplify, tPlotNetwork, tTotal);
            end
            statusLines = { ...
                sprintf('Built network: %d nodes, %d edges. Resolved max distance = %.4g.', ...
                    numnodes(g_simp), numedges(g_simp), par.maxNeighborDist), ...
                timingLine};
            if nDropped > 0
                statusLines{end+1} = sprintf(['Dropped %d of %d row(s) in the selected range due to ' ...
                    'missing values in the selected variables.'], nDropped, numel(gridRows));
            end
            app.StatusTextArea.String = statusLines;
        end

        function [tPlotNetwork, tPlotRecurrence, showRecurrence] = renderPlot(app)
            %RENDERPLOT re-render the network/recurrence plots from the
            %most recently BUILT network (see buildNetwork), using
            %whatever the CURRENT Plot Options controls say -- does not
            %recompute tknndigraph/filtergraph, so it's cheap and safe
            %to call every time a plot-only control changes (color/time
            %axis, node size, label method, show recurrence/node
            %border). Errors if no network has been built yet.
            if isempty(app.LastMembers)
                error('TemporalMapperApp:noNetwork','Build a network first.');
            end
            g_simp = app.LastGSimp;
            members = app.LastMembers;
            rows = app.LastRows;
            tidx = app.LastTidx;
            par = app.LastPar;
            k = app.LastK; d = app.LastD; texclude = app.LastTExclude;
            order = app.LastOrder; lag = app.LastLag; downsample = app.LastDownsample;

            % -- color variable (a DataTable column, a workspace-sourced
            % vector picked via ColorVarWorkspaceButton, or row index)
            selectedColor = app.ColorVarDropDown.String{app.ColorVarDropDown.Value};
            nCats = 0; % >0 only for a categorical colour variable
            if strcmp(selectedColor, '(row index)')
                colorvar = tidx;
                colorlabel = 'row index';
            elseif ismember(selectedColor, app.NumericVarNames)
                colorvar = app.DataTable.(selectedColor)(rows);
                colorlabel = selectedColor;
            elseif ismember(selectedColor, app.DatetimeVarNames)
                % plottmgraph calls isnan on colorvar, which errors on
                % datetime, and a colormap needs numbers regardless --
                % datenum keeps the ordering and spacing intact.
                colorvar = datenum(app.DataTable.(selectedColor)(rows)); %#ok<DATNM>
                colorlabel = selectedColor;
            elseif ismember(selectedColor, app.CategoricalVarNames)
                % nominal labels -> 1..nCategories. The codes are
                % arbitrary identifiers, not quantities.
                [colorvar, catNames] = findgroups(app.DataTable.(selectedColor)(rows));
                colorvar = double(colorvar);
                nCats = numel(catNames);
                colorlabel = selectedColor;
            else
                extraIdx = strcmp(app.ExtraColorVarNames, selectedColor);
                fullvec = app.ExtraColorVarValues{extraIdx};
                colorvar = fullvec(rows);
                colorlabel = selectedColor;
            end

            % -- time axis variable (for the recurrence plot)
            selectedTime = app.TimeVarDropDown.String{app.TimeVarDropDown.Value};
            if strcmp(selectedTime, '(row index)')
                t = tidx;
            else
                t = app.DataTable.(selectedTime)(rows);
            end

            cla(app.NetworkAxes)
            cla(app.RecurrenceAxes)
            colorbar(app.RecurrenceAxes,'off') % remove any colorbar from a previous render
            % cla() doesn't reset axes Color, but re-assert white here anyway
            % in case a theme change restyled it since createComponents.
            app.NetworkAxes.Color = [1 1 1];
            app.RecurrenceAxes.Color = [1 1 1];

            showRecurrence = app.ShowRecurrenceCheckBox.Value;
            if showRecurrence
                % leave enough of a gap between the two axes for the
                % network's colorbar + its (possibly long, e.g. a
                % workspace variable name) rotated label to clear the
                % recurrence plot's own y-axis label -- a narrower gap
                % let them visually collide.
                app.NetworkAxes.Position = [0.05 0.12 0.38 0.78];
                app.RecurrenceAxes.Position = [0.58 0.12 0.38 0.78];
                app.RecurrenceAxes.Visible = 'on';
            else
                % network plot alone gets the full plot panel width
                app.NetworkAxes.Position = [0.08 0.12 0.85 0.78];
                app.RecurrenceAxes.Visible = 'off';
            end

            stepTimer = tic;
            nodeSizeMode = app.NodeSizeModeDropDown.String{app.NodeSizeModeDropDown.Value};
            app.syncLabelMethodOptions(nCats > 0);
            labelMethod = app.LabelMethodDropDown.String{app.LabelMethodDropDown.Value};
            cmapName = app.ColormapDropDown.String{app.ColormapDropDown.Value};
            % pin the colour axis so each category owns an equal band --
            % otherwise the scale stretches to whichever codes happen to
            % be present and the same category changes colour between
            % builds.
            if nCats > 0
                nodeclim = [0.5, nCats + 0.5];
            else
                nodeclim = []; % plottmgraph's default: the data's own range
            end
            plottmgraph(g_simp, colorvar, members, 'ax', app.NetworkAxes, ...
                'nodeclim', nodeclim, ...
                'nodesizemode', nodeSizeMode, ...
                'labelmethod', labelMethod, ...
                'colorlabel', colorlabel, ...
                'cmap', cmapName, ...
                'nodescatter', app.ShowNodeBorderCheckBox.Value);
            % axis('equal') alone lets MATLAB stretch the axis LIMITS
            % (not just the rendered box) to match the axes' own w:h
            % ratio when it isn't perfectly square, leaving wide blank
            % margins on whichever side that stretch fell on. 'tight'
            % afterward re-hugs the limits to the actual plotted data,
            % while 'equal' (already set inside plottmgraph) keeps the
            % 1:1 aspect so the network isn't visually distorted.
            axis(app.NetworkAxes,'tight')
            titleStr = sprintf('k=%g, d=%g, texclude=%g, maxdist=%.4g', k, d, texclude, par.maxNeighborDist);
            if order > 1
                titleStr = [titleStr sprintf(', lag=%g, order=%g', lag, order)];
            end
            if downsample > 1
                titleStr = [titleStr sprintf(', downsample=%g', downsample)];
            end
            title(app.NetworkAxes, titleStr);
            tPlotNetwork = toc(stepTimer);

            tPlotRecurrence = 0;
            if showRecurrence
                stepTimer = tic;
                nodesizevec = cellfun(@length, members);
                bsingle = all(nodesizevec==1);
                if bsingle
                    D_geo = distances(g_simp,'Method','unweighted');
                else
                    D_geo = TCMdistance(g_simp, members);
                end
                imagesc(app.RecurrenceAxes, t, t, D_geo);
                axis(app.RecurrenceAxes,'square')
                colormap(app.RecurrenceAxes, 'hot')
                cb = colorbar(app.RecurrenceAxes);
                cb.Label.String = 'path length';
                xlabel(app.RecurrenceAxes,'time')
                ylabel(app.RecurrenceAxes,'time')
                title(app.RecurrenceAxes,'geodesic recurrence plot')
                tPlotRecurrence = toc(stepTimer);
            end

            app.StatusTextArea.String = {sprintf( ...
                'Re-rendered plot (network unchanged): %d nodes, %d edges.', ...
                numnodes(g_simp), numedges(g_simp))};
        end

        function exportResults(app, outDir)
            %EXPORTRESULTS write the built network's analysis-ready
            %artifacts into outDir: both figures, a per-time-point
            %timeline, a provenance record, and the reproduction script.
            %Used by the "Export..." button (after picking a folder) and
            %directly by scripts/tests.
            %   The timeline is the point of this: it is the join-back
            %   table saying WHICH ATTRACTOR the system was in at each
            %   time point, which is what dwell-time, transition-rate and
            %   occupancy analyses actually need, and the one thing that
            %   cannot be recovered from the figures.
            if isempty(app.LastMembers)
                error('TemporalMapperApp:noNetwork','Build a network first.');
            end
            if ~exist(outDir,'dir')
                mkdir(outDir);
            end

            g_simp = app.LastGSimp;
            members = app.LastMembers;
            rows = app.LastRows(:);
            tidx = app.LastTidx(:);

            % -- figures. exportgraphics on the axes rather than the
            % figure: the app's axes live inside a panel alongside all the
            % controls, so saving the figure would capture the whole GUI.
            exportgraphics(app.NetworkAxes, fullfile(outDir,'network.png'), 'Resolution',200);
            if app.ShowRecurrenceCheckBox.Value
                exportgraphics(app.RecurrenceAxes, fullfile(outDir,'recurrence.png'), 'Resolution',200);
            end

            % -- timeline: one row per retained time point. members holds
            % positional indices into the original graph's nodes (i.e.
            % into tidx/rows), since g came straight from tknndigraph.
            node = zeros(numel(tidx),1);
            for i = 1:numel(members)
                node(members{i}) = i;
            end
            TL = table(tidx, rows, node, 'VariableNames', {'tidx','source_row','node'});
            % carry the chosen colour/time columns through too, so the
            % table can be plotted or grouped without re-reading the source
            selectedColor = app.ColorVarDropDown.String{app.ColorVarDropDown.Value};
            if ~strcmp(selectedColor,'(row index)')
                TL.(matlab.lang.makeValidName(selectedColor)) = app.columnValues(selectedColor, rows);
            end
            selectedTime = app.TimeVarDropDown.String{app.TimeVarDropDown.Value};
            if ~strcmp(selectedTime,'(row index)') && ~strcmp(selectedTime, selectedColor)
                TL.(matlab.lang.makeValidName(selectedTime)) = app.columnValues(selectedTime, rows);
            end
            writetable(TL, fullfile(outDir,'timeline.csv'));

            % -- provenance. Everything here comes from the cached BUILD
            % inputs, not from the live controls, so the record describes
            % the network that actually produced these figures.
            P = struct();
            P.tool = 'Temporal Mapper 2 (MATLAB GUI)';
            P.exported = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));

            src = struct();
            src.data_source_code = app.DataSourceCode;
            src.dropped_index_column = app.DroppedIndexCol;
            src.n_rows_loaded = height(app.DataTable);
            P.source = src;

            pre = struct();
            pre.variables = app.LastSelectedVars;
            pre.zscore = logical(app.LastZscore);
            pre.start_row = app.LastStartRow;
            pre.end_row = app.LastEndRow;
            pre.downsample = app.LastDownsample;
            pre.time_index_source = app.LastTidxSource;
            pre.embed_lag = app.LastLag;
            pre.embed_order = app.LastOrder;
            P.preprocessing = pre;

            np = struct();
            np.k = app.LastK;
            np.d = app.LastD;
            np.texclude = app.LastTExclude;
            np.max_neighbor_dist_prct = app.LastMaxDistPrct;
            np.max_neighbor_dist_requested = app.LastMaxDistRequested;
            % the percentile and absolute cutoffs are combined internally
            % (the stricter wins), so record what was actually applied
            np.max_neighbor_dist_resolved = app.LastPar.maxNeighborDist;
            np.reciprocal = logical(app.LastReciprocal);
            P.network_parameters = np;

            po = struct();
            po.color_by = selectedColor;
            po.time_axis = selectedTime;
            po.node_size_mode = app.NodeSizeModeDropDown.String{app.NodeSizeModeDropDown.Value};
            po.label_method = app.LabelMethodDropDown.String{app.LabelMethodDropDown.Value};
            po.colormap = app.ColormapDropDown.String{app.ColormapDropDown.Value};
            po.show_recurrence = logical(app.ShowRecurrenceCheckBox.Value);
            po.show_node_border = logical(app.ShowNodeBorderCheckBox.Value);
            P.plot_options = po;

            res = struct();
            res.n_nodes = numnodes(g_simp);
            res.n_edges = numedges(g_simp);
            res.n_time_points = numel(tidx);
            P.result = res;

            app.writeTextFile(fullfile(outDir,'params.json'), jsonencode(P,'PrettyPrint',true));
            app.writeTextFile(fullfile(outDir,'reproduce.m'), app.generateCode());

            app.StatusTextArea.String = { ...
                sprintf('Exported to %s', outDir), ...
                'network.png, timeline.csv (time point -> node), params.json, reproduce.m'};
        end

        function code = generateCode(app)
            %GENERATECODE build a self-contained MATLAB script that
            %reproduces the network/plot currently configured in the
            %GUI, using the same validated parameters buildNetwork
            %would use. Used by the "Copy Code" button (copied to the
            %clipboard) and directly by scripts/tests.
            if isempty(app.DataTable)
                error('TemporalMapperApp:noData','Load a data file first.');
            end
            selectedVars = app.VariableListBox.String(app.VariableListBox.Value);
            if isempty(selectedVars)
                error('TemporalMapperApp:noVars','Select at least one variable to build the network from.');
            end
            varListStr = strjoin(cellfun(@(v) ['''' v ''''], selectedVars, 'UniformOutput',false), ', ');

            N_full = height(app.DataTable);
            startRow = app.parseNumericField(app.RangeStartEditField, 'start row', 1, N_full, true, false);
            endRow = min(app.parseNumericField(app.RangeEndEditField, 'end row', 1, Inf, true, false), N_full);
            if endRow < startRow
                error('TemporalMapperApp:invalidRange', 'End row must be greater than or equal to start row.');
            end
            downsample = app.parseNumericField(app.DownsampleEditField, 'downsample factor', 1, Inf, true, false);
            lag = app.parseNumericField(app.EmbedLagEditField, 'embed lag', 0, Inf, true, false);
            order = app.parseNumericField(app.EmbedOrderEditField, 'embed order', 1, Inf, true, false);
            k = app.parseNumericField(app.KEditField, 'k (neighbors)', 1, Inf, true, false);
            d = app.parseNumericField(app.DEditField, 'd (compression)', 0, Inf, false, true);
            texclude = app.parseNumericField(app.TExcludeEditField, 'texclude', 1, Inf, true, false);
            maxdistprct = app.parseNumericField(app.MaxDistPrctEditField, 'max dist percentile', 0, 100, false, false);
            maxdist = app.parseNumericField(app.MaxDistEditField, 'max dist', 0, Inf, false, true);
            recip = app.ReciprocalCheckBox.Value;
            nodeSizeMode = app.NodeSizeModeDropDown.String{app.NodeSizeModeDropDown.Value};
            labelMethod = app.LabelMethodDropDown.String{app.LabelMethodDropDown.Value};
            cmapName = app.ColormapDropDown.String{app.ColormapDropDown.Value};

            L = {};
            L{end+1} = '%% Temporal Mapper -- generated by TemporalMapperApp''s "Copy Code" button';
            L{end+1} = 'addpath("tmapper_tools/")';
            L{end+1} = '';
            L{end+1} = app.DataSourceCode;
            if app.DroppedIndexCol
                L{end+1} = '%% drop the leading unnamed row-index column (readtable names it';
                L{end+1} = '%% "Var1") -- a monotonic ramp left over from writing a CSV without';
                L{end+1} = '%% suppressing the index, which would dominate the distances.';
                L{end+1} = 'dat(:,1) = [];';
            end
            L{end+1} = '';
            L{end+1} = sprintf('selectedVars = {%s};', varListStr);
            L{end+1} = sprintf('startRow = %g; endRow = %g; downsample = %g;', startRow, endRow, downsample);
            L{end+1} = 'windowRows = (startRow:endRow)'';';
            L{end+1} = 'windowVals = dat{windowRows,selectedVars};';
            if downsample > 1
                L{end+1} = '%% anti-aliasing lowpass filter before decimating (moving average over';
                L{end+1} = '%% the downsample window, so striding below doesn''t alias high-frequency';
                L{end+1} = '%% content into spurious low-frequency structure). ''omitnan'' lets the';
                L{end+1} = '%% average skip a missing input, so an isolated NaN costs no sample.';
                L{end+1} = sprintf('smoothVals = movmean(windowVals, %g, 1, ''omitnan'');', downsample);
            else
                L{end+1} = 'smoothVals = windowVals;';
            end
            L{end+1} = '%% decimate on the ORIGINAL row grid, not on the rows left after';
            L{end+1} = '%% missing-data removal -- striding the survivors would slide every later';
            L{end+1} = '%% sample off the true time grid, inventing gaps between samples that';
            L{end+1} = '%% were in fact evenly spaced.';
            L{end+1} = sprintf('gridIdx = (1:%g:numel(windowRows))'';', downsample);
            L{end+1} = 'gridRows = windowRows(gridIdx);';
            L{end+1} = 'gridVals = smoothVals(gridIdx,:);';
            L{end+1} = '%% zscore and pdist2 both propagate NaN across a whole column/matrix, so';
            L{end+1} = '%% any grid point still missing has to go.';
            L{end+1} = 'keepMask = any(isnan(gridVals), 2) == 0;';
            L{end+1} = 'baseRows = gridRows(keepMask);';
            L{end+1} = 'filteredVals = gridVals(keepMask,:);';
            L{end+1} = 'nDropped = numel(gridRows) - numel(baseRows);';
            L{end+1} = 'if nDropped > 0';
            L{end+1} = ['    warning(''TemporalMapper:missingData'', ''Dropped %d of %d row(s) due ' ...
                'to missing values in the selected variables.'', nDropped, numel(gridRows));'];
            L{end+1} = 'end';
            if app.ZscoreCheckBox.Value
                L{end+1} = 'X = zscore(filteredVals);';
            else
                L{end+1} = 'X = filteredVals;';
            end
            L{end+1} = '';
            if order > 1
                L{end+1} = '%% delay embedding: [x(t-lag), ..., x(t)]';
                L{end+1} = sprintf('lag = %g; order = %g;', lag, order);
                L{end+1} = 'N_raw = size(X,1);';
                L{end+1} = 'N = N_raw - (order-1)*lag;';
                L{end+1} = 'nvars = size(X,2);';
                L{end+1} = 'X_embed = zeros(N, nvars*order);';
                L{end+1} = 'for j = 1:order';
                L{end+1} = '    X_embed(:, (j-1)*nvars + (1:nvars)) = X((j-1)*lag + (1:N), :);';
                L{end+1} = 'end';
                L{end+1} = 'rows = baseRows((N_raw-N+1):N_raw);';
                L{end+1} = 'X = X_embed;';
                L{end+1} = '';
            else
                L{end+1} = 'rows = baseRows;';
            end
            L{end+1} = '%% tidx counts elapsed sampling intervals from the first kept row, not';
            L{end+1} = '%% array position: tknndigraph links two points in time only when their';
            L{end+1} = '%% tidx differs by exactly 1, so numbering the surviving rows 1:N would';
            L{end+1} = '%% close up any gap left by a dropped row and fabricate a temporal edge';
            L{end+1} = '%% across it.';
            tidxChoice = app.TimeIndexDropDown.String{app.TimeIndexDropDown.Value};
            if strcmp(tidxChoice, '(from row order)')
                L{end+1} = sprintf('tidx = (rows - rows(1))/%g + 1;', downsample);
            else
                L{end+1} = sprintf('%%%% time index taken from "%s": the unit is the smallest step', tidxChoice);
                L{end+1} = '%% between kept samples, so a larger step stays a real break in time.';
                if ismember(tidxChoice, app.DatetimeVarNames)
                    L{end+1} = sprintf('tvals = seconds(dat.%s(rows) - dat.%s(rows(1)));', tidxChoice, tidxChoice);
                else
                    L{end+1} = sprintf('tvals = double(dat.%s(rows));', tidxChoice);
                end
                L{end+1} = 'tsteps = diff(tvals);';
                L{end+1} = 'tidx = round((tvals - tvals(1)) / min(tsteps)) + 1;';
            end
            L{end+1} = '%% X is passed straight to tknndigraph rather than a precomputed';
            L{end+1} = '%% pdist2 matrix, so its lowMemory path can compute distances a block';
            L{end+1} = '%% of rows at a time and never allocate an N-by-N array.';
            L{end+1} = '';
            L{end+1} = sprintf(['[g, par] = tknndigraph(X, %g, tidx, ''timeExcludeRange'', %g, ' ...
                '''maxNeighborDistPrct'', %g, ''maxNeighborDist'', %g, ''lowMemory'', true);'], ...
                k, texclude, maxdistprct, maxdist);
            L{end+1} = sprintf('[g_simp, members] = filtergraph(g, %g, ''reciprocal'', %d);', d, recip);
            L{end+1} = '';

            selectedColor = app.ColorVarDropDown.String{app.ColorVarDropDown.Value};
            if strcmp(selectedColor, '(row index)')
                L{end+1} = 'colorvar = tidx;';
                colorlabelExpr = '''row index''';
            elseif ismember(selectedColor, app.NumericVarNames)
                L{end+1} = sprintf('colorvar = dat.%s(rows);', selectedColor);
                colorlabelExpr = ['''' selectedColor ''''];
            elseif ismember(selectedColor, app.CategoricalVarNames)
                L{end+1} = '%% nominal category labels -> integer codes 1..nCategories. The codes are';
                L{end+1} = '%% arbitrary identifiers, not quantities, so the colour axis is pinned so';
                L{end+1} = '%% each category owns an equal band, and only ''mode''/''none'' make sense';
                L{end+1} = '%% as label methods (averaging codes would name a different category).';
                L{end+1} = sprintf('[colorvar, catNames] = findgroups(dat.%s(rows));', selectedColor);
                L{end+1} = 'colorvar = double(colorvar);';
                L{end+1} = 'nodeclim = [0.5, numel(catNames) + 0.5];';
                colorlabelExpr = ['''' selectedColor ''''];
            elseif ismember(selectedColor, app.DatetimeVarNames)
                L{end+1} = '%% plottmgraph calls isnan on colorvar, which errors on datetime, and';
                L{end+1} = '%% a colormap needs numbers regardless -- datenum keeps the ordering';
                L{end+1} = '%% and spacing intact. (The time axis below stays datetime: imagesc';
                L{end+1} = '%% takes it natively and labels the axis with real dates.)';
                L{end+1} = sprintf('colorvar = datenum(dat.%s(rows));', selectedColor);
                colorlabelExpr = ['''' selectedColor ''''];
            else
                L{end+1} = sprintf(['%% "%s" was a workspace variable added via the "Color by Workspace ' ...
                    'Variable..." button -- substitute your own vector here, indexed by rows:'], selectedColor);
                L{end+1} = sprintf('colorvar = %s(rows); %% <-- replace %s with your workspace variable', ...
                    matlab.lang.makeValidName(selectedColor), matlab.lang.makeValidName(selectedColor));
                colorlabelExpr = ['''' selectedColor ''''];
            end

            if ~ismember(selectedColor, app.CategoricalVarNames)
                L{end+1} = 'nodeclim = []; %% plottmgraph default: the data''s own range';
            end

            selectedTime = app.TimeVarDropDown.String{app.TimeVarDropDown.Value};
            if strcmp(selectedTime, '(row index)')
                L{end+1} = 't = tidx;';
            else
                L{end+1} = sprintf('t = dat.%s(rows);', selectedTime);
            end
            L{end+1} = '';

            nodescatter = app.ShowNodeBorderCheckBox.Value;
            if app.ShowRecurrenceCheckBox.Value
                % plotgraphtcm opens its own figure internally (network
                % + recurrence plot side by side), so no explicit
                % figure() call here. All outputs are named (rather than
                % suppressed with ~) so they're available for downstream
                % custom analysis: h1/h2 are the network/recurrence axes,
                % cb/cb_ their colorbars, hg the graph plot handle,
                % D_geo the recurrence/TCM distance matrix, hs the node
                % scatter overlay handle (empty unless nodescatter=1).
                L{end+1} = sprintf(['[h1, h2, cb, cb_, hg, D_geo, hs] = plotgraphtcm(g_simp, colorvar, t, members, ' ...
                    '''nodesizemode'', ''%s'', ''labelmethod'', ''%s'', ''colorlabel'', %s, ' ...
                    '''cmap'', ''%s'', ''nodeclim'', nodeclim, ''nodescatter'', %d);'], nodeSizeMode, labelMethod, colorlabelExpr, cmapName, nodescatter);
            else
                % plottmgraph plots into gca by default, reusing an
                % existing figure if one is open -- open a new one first
                % so this doesn't overwrite whatever's already on screen.
                % Outputs named for the same reason as above: h1 the
                % network axes, cb its colorbar, hg the graph plot
                % handle, hs the node scatter overlay handle.
                L{end+1} = 'figure;';
                L{end+1} = sprintf(['[h1, cb, hg, hs] = plottmgraph(g_simp, colorvar, members, ' ...
                    '''nodesizemode'', ''%s'', ''labelmethod'', ''%s'', ''colorlabel'', %s, ' ...
                    '''cmap'', ''%s'', ''nodeclim'', nodeclim, ''nodescatter'', %d);'], nodeSizeMode, labelMethod, colorlabelExpr, cmapName, nodescatter);
            end
            % axis('equal') alone (set inside plottmgraph) can leave wide
            % blank margins when the axes box isn't perfectly square;
            % 'tight' re-hugs the limits to the actual plotted data,
            % giving the network more of the figure to fill -- same fix
            % applied to the app's own NetworkAxes.
            L{end+1} = 'axis(h1,''tight'')';
            % titleFmt is inserted below via %s (not processed as a format
            % string itself), so it holds single, not doubled, percents --
            % it IS the literal text that should appear in the generated code.
            titleFmt = 'k=%g, d=%g, texclude=%g, maxdist=%.4g';
            titleArgs = sprintf('%g, %g, %g, par.maxNeighborDist', k, d, texclude);
            if order > 1
                titleFmt = [titleFmt ', lag=%g, order=%g'];
                titleArgs = [titleArgs sprintf(', %g, %g', lag, order)];
            end
            if downsample > 1
                titleFmt = [titleFmt ', downsample=%g'];
                titleArgs = [titleArgs sprintf(', %g', downsample)];
            end
            L{end+1} = sprintf('title(h1, sprintf(''%s'', %s));', titleFmt, titleArgs);

            code = strjoin(L, newline);
        end
    end

    methods (Access = private)

        function tidx = tidxFromColumn(app, name, rows)
            %TIDXFROMCOLUMN integer time indices from a user-chosen column,
            %sampled at the kept rows.
            %   tknndigraph treats points as temporally adjacent only when
            %   their tidx differs by exactly 1, so the column has to be
            %   expressible on a regular integer grid. The unit is the
            %   SMALLEST step present between kept samples -- which already
            %   includes the downsample factor, since rows is the decimated
            %   set -- and every other step must be a whole multiple of it.
            %   A larger step is a real break and stays a real break.
            vals = app.DataTable.(name)(rows);
            if isdatetime(vals)
                vals = seconds(vals - vals(1));
            else
                vals = double(vals);
            end
            if any(isnan(vals))
                error('TemporalMapperApp:invalidTimeIndex', ...
                    'Time index column "%s" has missing values in the selected range.', name);
            end
            steps = diff(vals);
            if isempty(steps) || any(steps <= 0)
                error('TemporalMapperApp:invalidTimeIndex', ...
                    'Time index column "%s" must be strictly increasing over the selected range.', name);
            end
            interval = min(steps);
            ratios = steps / interval;
            % tolerance rather than exact equality: a datetime column
            % becomes seconds, and sub-second sampling need not divide
            % exactly in floating point.
            if any(abs(ratios - round(ratios)) > 1e-6)
                error('TemporalMapperApp:invalidTimeIndex', ...
                    ['Time index column "%s" is irregular: it has steps that are not whole ' ...
                     'multiples of its smallest step (%g). There is no regular grid to place ' ...
                     'it on, so use row order instead.'], name, interval);
            end
            tidx = round((vals - vals(1)) / interval) + 1;
        end

        function syncLabelMethodOptions(app, isCategorical)
            %SYNCLABELMETHODOPTIONS offer only the label methods that mean
            %something for the current colour variable.
            %   Category codes are arbitrary identifiers, so averaging
            %   them is nonsense -- the mean of codes 1 and 3 is code 2,
            %   a different category entirely. mean/median are therefore
            %   withdrawn while a category is selected, and restored
            %   afterwards. The current choice is matched by NAME, since
            %   the same index means a different method in a shorter list.
            if isCategorical
                allowed = {'mode','none'};
            else
                allowed = {'mode','mean','median','none'};
            end
            if isequal(app.LabelMethodDropDown.String(:)', allowed)
                return
            end
            current = app.LabelMethodDropDown.String{app.LabelMethodDropDown.Value};
            idx = find(strcmp(allowed, current), 1);
            if isempty(idx)
                idx = 1; % a withdrawn method falls back to mode
            end
            app.LabelMethodDropDown.String = allowed;
            app.LabelMethodDropDown.Value = idx;
        end

        function v = columnValues(app, name, rows)
            %COLUMNVALUES the values of a selectable colour/time source at
            %the given rows, whether it is a table column or one of the
            %workspace-sourced vectors. Kept in its own method because
            %exportResults and renderPlot must agree on what a given
            %dropdown entry means.
            if ismember(name, app.ExtraColorVarNames)
                fullvec = app.ExtraColorVarValues{strcmp(app.ExtraColorVarNames, name)};
                v = fullvec(rows);
            else
                v = app.DataTable.(name)(rows);
            end
        end

        function writeTextFile(~, path, text)
            fid = fopen(path, 'w');
            if fid < 0
                error('TemporalMapperApp:exportFailed','Could not write %s.', path);
            end
            closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, text);
        end

        function ExportButtonPushed(app, ~, ~)
            if isempty(app.LastMembers)
                errordlg('Build a network first.', 'Export error');
                return
            end
            outDir = uigetdir(pwd, 'Choose a folder to export into');
            if isequal(outDir, 0)
                return
            end
            try
                app.exportResults(outDir);
            catch ME
                errordlg(ME.message, 'Export error');
            end
        end

        function val = parseNumericField(~, ctrl, label, minVal, maxVal, mustBeInt, minExclusive)
            %PARSENUMERICFIELD parse+validate a classic edit field's
            %String as a number, replicating the Limits/
            %RoundFractionalValues/LowerLimitInclusive constraints the
            %uieditfield version of this app used to enforce live.
            val = str2double(ctrl.String);
            if isnan(val)
                error('TemporalMapperApp:invalidNumericField', '%s must be a number.', label);
            end
            if mustBeInt && val ~= round(val)
                error('TemporalMapperApp:invalidNumericField', '%s must be an integer.', label);
            end
            if minExclusive
                if val <= minVal
                    error('TemporalMapperApp:invalidNumericField', '%s must be greater than %g.', label, minVal);
                end
            elseif val < minVal
                error('TemporalMapperApp:invalidNumericField', '%s must be at least %g.', label, minVal);
            end
            if val > maxVal
                error('TemporalMapperApp:invalidNumericField', '%s must be at most %g.', label, maxVal);
            end
        end

        function LoadDataButtonPushed(app, ~, ~)
            [file, filepath] = uigetfile({'*.csv;*.txt','Data files (*.csv, *.txt)'; '*.*','All files'}, ...
                'Select a data file');
            if isequal(file,0)
                return
            end
            try
                T = readtable(fullfile(filepath,file));
            catch ME
                errordlg(sprintf('Could not read file: %s', ME.message), 'Load error');
                return
            end
            try
                app.loadData(T);
                app.DataSourceCode = sprintf('dat = readtable(''%s'');', fullfile(filepath,file));
            catch ME
                errordlg(ME.message, 'Load error');
            end
        end

        function LoadWorkspaceButtonPushed(app, ~, ~)
            % -- offer only base-workspace variables that loadData can
            % actually use: tables, or 2D numeric matrices (which get
            % wrapped into a table via array2table so the rest of the
            % app can treat both sources identically).
            varNames = evalin('base','who');
            isCandidate = false(size(varNames));
            for i = 1:numel(varNames)
                v = evalin('base', varNames{i});
                isCandidate(i) = istable(v) || (isnumeric(v) && ismatrix(v));
            end
            varNames = varNames(isCandidate);
            if isempty(varNames)
                errordlg('No table or numeric matrix variables found in the base workspace.', 'Load error');
                return
            end
            [idx, tf] = listdlg('ListString', varNames, 'SelectionMode','single', ...
                'Name','Select workspace variable', 'PromptString','Select a variable to load:');
            if ~tf
                return
            end
            v = evalin('base', varNames{idx});
            if isnumeric(v)
                % explicit VariableNames avoids array2table naming
                % columns after this method's local variable ("v1,
                % v2,...") instead of a generic, CSV-like "Var1, Var2,..."
                v = array2table(v, 'VariableNames', compose('Var%d', 1:size(v,2)));
                sourceCode = sprintf(['dat = array2table(%s, ''VariableNames'', ' ...
                    'compose(''Var%%d'', 1:size(%s,2))); %% loaded from base workspace matrix'], ...
                    varNames{idx}, varNames{idx});
            else
                sourceCode = sprintf('dat = %s; %% loaded from base workspace', varNames{idx});
            end
            try
                app.loadData(v);
                app.DataSourceCode = sourceCode;
                app.FileLabel.String = sprintf('Loaded from workspace: %s', varNames{idx});
            catch ME
                errordlg(ME.message, 'Load error');
            end
        end

        function ColorVarWorkspaceButtonPushed(app, ~, ~)
            % -- let users color the network by a workspace vector that
            % isn't a column of the loaded data (e.g. a label vector
            % computed separately).
            if isempty(app.DataTable)
                errordlg('Load a data file first.', 'Load error');
                return
            end
            varNames = evalin('base','who');
            isCandidate = false(size(varNames));
            for i = 1:numel(varNames)
                v = evalin('base', varNames{i});
                isCandidate(i) = isnumeric(v) && isvector(v);
            end
            varNames = varNames(isCandidate);
            if isempty(varNames)
                errordlg('No numeric vector variables found in the base workspace.', 'Load error');
                return
            end
            [idx, tf] = listdlg('ListString', varNames, 'SelectionMode','single', ...
                'Name','Select workspace variable', 'PromptString','Select a vector to color by:');
            if ~tf
                return
            end
            v = evalin('base', varNames{idx});
            try
                app.addColorVarFromWorkspace(varNames{idx}, v);
                % re-render immediately using the newly-added color
                % option, same as any other Plot Options change
                if ~isempty(app.LastMembers)
                    app.renderPlot();
                end
            catch ME
                errordlg(ME.message, 'Load error');
            end
        end

        function BuildButtonPushed(app, ~, ~)
            try
                app.buildNetwork();
            catch ME
                errordlg(ME.message, 'Build error');
                app.StatusTextArea.String = {['Error: ' ME.message]};
            end
        end

        function StopButtonPushed(app, ~, ~)
            %STOPBUTTONPUSHED request cancellation of an in-progress
            %build. Checked between stages in buildNetwork (after
            %distances, after the k-NN graph, after simplification), so
            %it can't interrupt a single slow stage mid-computation, but
            %it will stop the build from continuing into the next one.
            app.CancelRequested = true;
            app.StatusTextArea.String = {'Cancelling...'};
            drawnow
        end

        function ResetButtonPushed(app, ~, ~)
            %RESETBUTTONPUSHED restore all parameter/plot-option
            %controls to their defaults (does not clear loaded data or
            %the variable selection, since reloading data is usually
            %the expensive/annoying part to redo).
            app.ZscoreCheckBox.Value = 1;
            app.RangeStartEditField.String = '1';
            app.RangeEndEditField.String = 'Inf';
            app.DownsampleEditField.String = '1';
            app.EmbedLagEditField.String = '0';
            app.EmbedOrderEditField.String = '1';
            app.KEditField.String = '3';
            app.DEditField.String = '3';
            app.TExcludeEditField.String = '1';
            app.MaxDistPrctEditField.String = '100';
            app.MaxDistEditField.String = 'Inf';
            app.ReciprocalCheckBox.Value = 1;
            app.ColorVarDropDown.Value = 1;
            app.TimeVarDropDown.Value = 1;
            app.NodeSizeModeDropDown.Value = 1;
            app.LabelMethodDropDown.Value = 1;
            app.ColormapDropDown.Value = 1;
            app.ShowRecurrenceCheckBox.Value = 1;
            app.ShowNodeBorderCheckBox.Value = 0;
            app.StatusTextArea.String = {'Parameters reset to defaults.'};
        end

        function SelectAllButtonPushed(app, ~, ~)
            app.VariableListBox.Value = 1:numel(app.VariableListBox.String);
        end

        function CopyCodeButtonPushed(app, ~, ~)
            try
                code = app.generateCode();
                clipboard('copy', code);
                app.StatusTextArea.String = {'Code copied to clipboard.'};
            catch ME
                errordlg(ME.message, 'Copy code error');
            end
        end

        function PlotOptionChanged(app, ~, ~)
            %PLOTOPTIONCHANGED callback shared by every Plot Options
            %control (color/time axis, node size, label method, show
            %recurrence/node border): re-renders the cached network's
            %plot cheaply via renderPlot() instead of rebuilding. A
            %no-op if nothing has been built yet.
            if isempty(app.LastMembers)
                return
            end
            try
                app.renderPlot();
            catch ME
                errordlg(ME.message, 'Render error');
            end
        end

        function resetBuildControls(app)
            %RESETBUILDCONTROLS re-enable Build/disable Stop once
            %buildNetwork finishes, however it exits (success, error, or
            %cancellation) -- registered via onCleanup in buildNetwork.
            if isvalid(app.UIFigure)
                app.BuildButton.Enable = 'on';
                app.StopButton.Enable = 'off';
            end
        end

        function reportCancelled(app)
            app.StatusTextArea.String = {'Build cancelled.'};
        end
    end

    methods (Access = private)

        function pos = rowPosition(~, row, nRows, col, nCols, rowSpan)
            %ROWPOSITION normalized [x y w h] (bottom-left origin, as
            %classic uicontrol Position expects) for a cell (or
            %vertically-spanned block of cells) in an nRows x nCols grid
            %within whatever panel this is called for, row/col counted
            %from the top-left. Each of the 4 Setup panels defines its
            %own nRows/nCols since they hold different amounts of
            %content -- this is deliberately per-panel rather than one
            %shared grid across the whole Setup area.
            if nargin < 6, rowSpan = 1; end
            rowH = 1/nRows;
            colW = 1/nCols;
            x = (col-1)*colW;
            yTop = (row-1)*rowH;
            h = rowSpan*rowH;
            y = 1 - yTop - h;
            % vertical padding is smaller than horizontal: rows are
            % generally much shorter than columns are wide, so the same
            % pad value ate a much bigger fraction of a control's height
            % than its width, leaving buttons/dropdowns looking
            % vertically squeezed (reported on a collaborator's screen).
            hPad = 0.03;
            vPad = 0.01;
            pos = [x+hPad, y+vPad, max(colW-2*hPad,0.001), max(h-2*vPad,0.001)];
        end

        function createComponents(app)
            screenSize = get(0,'ScreenSize');
            figW = min(1150, 0.85*screenSize(3));
            figH = min(800, 0.85*screenSize(4));
            app.UIFigure = figure('Name','Temporal Mapper', 'NumberTitle','off', ...
                'MenuBar','none', 'ToolBar','none', 'Units','pixels', ...
                'Position',[100 100 figW figH]);

            % top: 4 setup panels side by side (data/variables,
            % preprocessing, network parameters, plot+build); bottom:
            % network plots, which get the bulk of the window since they
            % benefit from space far more than the mostly-text/
            % short-field setup controls do.
            setupH = 0.24;
            panelW = 1/4;
            app.DataPanel = uipanel(app.UIFigure, 'Title','Data', ...
                'Units','normalized', 'Position',[0*panelW 1-setupH panelW setupH]);
            app.PreprocessPanel = uipanel(app.UIFigure, 'Title','Variables & Preprocessing', ...
                'Units','normalized', 'Position',[1*panelW 1-setupH panelW setupH]);
            app.NetworkParamsPanel = uipanel(app.UIFigure, 'Title','Network Parameters', ...
                'Units','normalized', 'Position',[2*panelW 1-setupH panelW setupH]);
            app.PlotOptionsPanel = uipanel(app.UIFigure, 'Title','Plot Options', ...
                'Units','normalized', 'Position',[3*panelW 1-setupH panelW setupH]);
            % BackgroundColor forced to white (not left to inherit from
            % the figure/theme) so the plotting region doesn't turn dark
            % under MATLAB dark mode -- plottmgraph draws graph edges in
            % black, which would become invisible against a dark
            % background otherwise.
            app.PlotPanel = uipanel(app.UIFigure, 'Title','Network', ...
                'BackgroundColor',[1 1 1], ...
                'Units','normalized', 'Position',[0 0 1 1-setupH]);

            % ================= panel 1: data, build & status =================
            nRows = 8;
            app.LoadDataButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Load Data...', 'TooltipString','Read a .csv or .txt file with readtable. The first row is treated as column names.', ...
                'Units','normalized', ...
                'Position', app.rowPosition(1,nRows,1,2), ...
                'Callback', @(src,evt) app.LoadDataButtonPushed(src,evt));

            app.LoadWorkspaceButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Load from Workspace...', 'TooltipString','Use a table or numeric matrix already in your base workspace instead of a file.', ...
                'Units','normalized', ...
                'Position', app.rowPosition(1,nRows,2,2), ...
                'Callback', @(src,evt) app.LoadWorkspaceButtonPushed(src,evt));

            app.FileLabel = uicontrol(app.DataPanel, 'Style','text', ...
                'String','No file loaded.', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(2,nRows,1,1));

            app.BuildButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Build Network', 'BackgroundColor',[0.31 0.60 0.95], ...
                'ForegroundColor','white', 'FontWeight','bold', ...
                'TooltipString','Run the pipeline: distances, k-NN graph, then simplification. Plot Options re-render without rebuilding.', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,1,2), ...
                'Callback', @(src,evt) app.BuildButtonPushed(src,evt));

            app.StopButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Stop', 'Enable','off', ...
                'BackgroundColor',[0.80 0.20 0.20], 'ForegroundColor','white', 'FontWeight','bold', ...
                'TooltipString','Cancel an in-progress build. Takes effect between stages (distances/k-NN graph/simplify), not mid-stage.', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,2,2), ...
                'Callback', @(src,evt) app.StopButtonPushed(src,evt));

            app.ResetButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Reset', ...
                'BackgroundColor',[0.30 0.65 0.35], 'ForegroundColor','white', 'FontWeight','bold', ...
                'TooltipString','Restore all parameters and plot options to their defaults (keeps loaded data).', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,1,2), ...
                'Callback', @(src,evt) app.ResetButtonPushed(src,evt));

            app.CopyCodeButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Copy Code', ...
                'TooltipString','Copy MATLAB code that reproduces this build to the clipboard.', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,2,2), ...
                'Callback', @(src,evt) app.CopyCodeButtonPushed(src,evt));

            app.ExportButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Export...', ...
                'TooltipString','Save both figures, timeline.csv (which node the system was in at each time point), params.json and reproduce.m into a folder.', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,1), ...
                'Callback', @(src,evt) app.ExportButtonPushed(src,evt));

            app.StatusLabel = uicontrol(app.DataPanel, 'Style','text', ...
                'String','Status:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,1,1));

            app.StatusTextArea = uicontrol(app.DataPanel, 'Style','edit', ...
                'String',{'Load a data file to get started.'}, 'Max',2, 'Min',0, ...
                'Enable','inactive', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(7,nRows,1,1,2));

            % ================= panel 2: variables & preprocessing =================
            nRows = 11;
            app.VariablesLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','Variables:', 'HorizontalAlignment','left', ...
                'TooltipString','Ctrl/shift-click to select multiple.', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,1,2));
            app.SelectAllButton = uicontrol(app.PreprocessPanel, 'Style','pushbutton', ...
                'String','Select All', 'TooltipString','Select every numeric variable in the list.', ...
                'Units','normalized', ...
                'Position', app.rowPosition(1,nRows,2,2), ...
                'Callback', @(src,evt) app.SelectAllButtonPushed(src,evt));

            app.VariableListBox = uicontrol(app.PreprocessPanel, 'Style','listbox', ...
                'String',{}, 'Max',2, 'Min',0, 'Value',[], ...
                'TooltipString','The numeric columns defining the system''s state -- distances are measured between these. Ctrl/shift-click for multiple.', ...
                'Units','normalized', 'Position', app.rowPosition(2,nRows,1,1,3));

            app.ZscoreCheckBox = uicontrol(app.PreprocessPanel, 'Style','checkbox', ...
                'String','z-score variables', 'Value',1, ...
                'TooltipString','Z-score variables before building network.', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,1));

            app.RangeStartLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','start row:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,1,2));
            app.RangeStartEditField = uicontrol(app.PreprocessPanel, 'Style','edit', ...
                'String','1', 'TooltipString','First row to include. Use with ''end row'' to analyse a sub-range, or to cut a long recording down to a workable size.', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,2,2));

            app.RangeEndLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','end row:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(7,nRows,1,2));
            app.RangeEndEditField = uicontrol(app.PreprocessPanel, 'Style','edit', ...
                'String','Inf', 'TooltipString','Inf means the last row of the loaded data.', ...
                'Units','normalized', 'Position', app.rowPosition(7,nRows,2,2));

            app.TimeIndexLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','time index:', 'HorizontalAlignment','left', ...
                'TooltipString','Which column says who is temporally adjacent. Default derives it from row order; pick a column for data with real breaks (separate sessions/trials).', ...
                'Units','normalized', 'Position', app.rowPosition(8,nRows,1,2));
            app.TimeIndexDropDown = uicontrol(app.PreprocessPanel, 'Style','popupmenu', ...
                'String',{'(from row order)'}, 'Value',1, ...
                'TooltipString','Which column says who is temporally adjacent. Points are linked in time only when their index differs by exactly 1, so gaps break the chain -- use it for data with real breaks (separate sessions/trials). Default derives it from row order.', ...
                'Units','normalized', 'Position', app.rowPosition(8,nRows,2,2));

            app.DownsampleLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','downsample (N):', 'HorizontalAlignment','left', ...
                'TooltipString','Keep every Nth row within the selected range (1 = no downsampling); a moving-average lowpass is applied first to avoid aliasing.', ...
                'Units','normalized', 'Position', app.rowPosition(11,nRows,1,2));
            app.DownsampleEditField = uicontrol(app.PreprocessPanel, 'Style','edit', ...
                'String','1', 'TooltipString','Keep every Nth row within the selected range (1 = no downsampling); a moving-average lowpass is applied first to avoid aliasing.', ...
                'Units','normalized', 'Position', app.rowPosition(11,nRows,2,2));

            app.EmbedLagLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','embed lag:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(9,nRows,1,2));
            app.EmbedLagEditField = uicontrol(app.PreprocessPanel, 'Style','edit', ...
                'String','0', 'TooltipString','Delay embedding: how many samples back each extra copy of the state is taken from. Ignored when embed order is 1.', ...
                'Units','normalized', 'Position', app.rowPosition(9,nRows,2,2));

            app.EmbedOrderLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','embed order:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(10,nRows,1,2));
            app.EmbedOrderEditField = uicontrol(app.PreprocessPanel, 'Style','edit', ...
                'String','1', 'TooltipString','How many lagged copies of the state to stack. 1 (default) means no embedding. Use it when the raw variables are too few to separate distinct states. Costs (order-1)*lag samples.', ...
                'Units','normalized', 'Position', app.rowPosition(10,nRows,2,2));

            % ================= panel 3: network parameters =================
            nRows = 6;
            app.KLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','k (neighbors):', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,1,2));
            app.KEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','3', 'TooltipString','Max spatial neighbours each time point may link to. The main knob: it largely determines the network''s topology, so explore it first. Larger k gives a denser graph.', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,2,2));

            app.DLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','d (compression):', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(2,nRows,1,2));
            app.DEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','3', 'TooltipString','Compression threshold. Time points within this geodesic distance collapse into one node, so loops shorter than d are absorbed. Larger d gives a coarser network.', ...
                'Units','normalized', 'Position', app.rowPosition(2,nRows,2,2));

            app.TExcludeLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','texclude:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,1,2));
            app.TExcludeEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','1', 'TooltipString','How many following time points count as temporal neighbours and are therefore barred from also counting as spatial neighbours -- this stops adjacent moments being read as recurrence. Set it from your sampling density.', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,2,2));

            app.MaxDistPrctLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','max dist %ile:', 'HorizontalAlignment','left', ...
                'TooltipString','max dist percentile', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,1,2));
            app.MaxDistPrctEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','100', 'TooltipString','Neighbour cutoff as a percentile of all pairwise distances (100 = no cutoff). The stricter of this and ''max dist'' wins.', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,2,2));

            app.MaxDistLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','max dist:', 'HorizontalAlignment','left', ...
                'TooltipString','max dist (absolute)', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,2));
            app.MaxDistEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','Inf', 'TooltipString','Neighbour cutoff as an absolute distance (Inf = no cutoff). The stricter of this and ''max dist %ile'' wins.', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,2,2));

            app.ReciprocalCheckBox = uicontrol(app.NetworkParamsPanel, 'Style','checkbox', ...
                'String','reciprocal', 'Value',1, ...
                'TooltipString','Merge two time points only when the short path holds in BOTH directions. The stricter, recommended setting for directed graphs.', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,1,1));

            % ================= panel 4: plot options =================
            nRows = 8;
            app.ColorVarLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Color by:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,1,2));
            app.ColorVarDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'(row index)'}, 'Value',1, ...
                'TooltipString','What the node colours mean. Numbers, dates, or text categories -- categories are treated as nominal labels and aggregated per node by majority vote.', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,2,2), ...
                'Callback', @(src,evt) app.PlotOptionChanged(src,evt));

            app.ColorVarWorkspaceButton = uicontrol(app.PlotOptionsPanel, 'Style','pushbutton', ...
                'String','Color by Workspace Variable...', 'TooltipString','Colour by a numeric vector from your base workspace (e.g. a label vector computed elsewhere). It must have one element per row of the loaded data.', ...
                'Units','normalized', ...
                'Position', app.rowPosition(2,nRows,1,1), ...
                'Callback', @(src,evt) app.ColorVarWorkspaceButtonPushed(src,evt));

            app.TimeVarLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Time axis:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,1,2));
            app.TimeVarDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'(row index)'}, 'Value',1, ...
                'TooltipString','Which column labels the recurrence plot''s time axes. A datetime column gives real dates rather than row numbers.', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,2,2), ...
                'Callback', @(src,evt) app.PlotOptionChanged(src,evt));

            app.NodeSizeModeLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Node size:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,1,2));
            app.NodeSizeModeDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'log','rank','original'}, 'Value',1, ...
                'TooltipString','How node sizes map to member counts. ''log'' keeps large nodes from swamping the plot; ''rank'' ignores magnitude entirely.', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,2,2), ...
                'Callback', @(src,evt) app.PlotOptionChanged(src,evt));

            app.ColormapLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Colormap:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,2));
            app.ColormapDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',TemporalMapperApp.colormapNames(), 'Value',1, ...
                'TooltipString','Colormap for the node colors. "lines"/"prism"/"colorcube" are qualitative -- adjacent colors are unrelated, which suits categorical labels.', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,2,2), ...
                'Callback', @(src,evt) app.PlotOptionChanged(src,evt));

            app.LabelMethodLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Label method:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,1,2));
            app.LabelMethodDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'mode','mean','median','none'}, 'Value',1, ...
                'TooltipString','How each node''s colour is aggregated from its member time points. mean/median are withdrawn for categorical colours, where averaging codes is meaningless.', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,2,2), ...
                'Callback', @(src,evt) app.PlotOptionChanged(src,evt));

            app.ShowRecurrenceCheckBox = uicontrol(app.PlotOptionsPanel, 'Style','checkbox', ...
                'String','Show recurrence plot', 'Value',1, ...
                'TooltipString','Uncheck to show only the network plot, widened to fill the panel.', ...
                'Units','normalized', 'Position', app.rowPosition(8,nRows,1,2), ...
                'Callback', @(src,evt) app.PlotOptionChanged(src,evt));

            app.ShowNodeBorderCheckBox = uicontrol(app.PlotOptionsPanel, 'Style','checkbox', ...
                'String','Show node border', 'Value',0, ...
                'TooltipString','Overlay a black-outlined scatter marker on each node (plottmgraph''s "nodescatter" option) -- can look cleaner for dense graphs.', ...
                'Units','normalized', 'Position', app.rowPosition(7,nRows,1,2), ...
                'Callback', @(src,evt) app.PlotOptionChanged(src,evt));

            % ================= bottom: plot panel =================
            % Color forced to white for the same dark-mode reason as
            % PlotPanel's BackgroundColor above; re-asserted in
            % renderPlot() too since cla() doesn't reset it, but a
            % theme change could still restyle it between builds.
            app.NetworkAxes = axes('Parent', app.PlotPanel, 'Units','normalized', ...
                'Color',[1 1 1], 'Position',[0.05 0.12 0.38 0.78]);
            title(app.NetworkAxes,'attractor transition network')

            app.RecurrenceAxes = axes('Parent', app.PlotPanel, 'Units','normalized', ...
                'Color',[1 1 1], 'Position',[0.58 0.12 0.38 0.78]);
            title(app.RecurrenceAxes,'geodesic recurrence plot')
        end
    end

    methods (Static)

        function names = colormapNames()
            %COLORMAPNAMES colormaps offered in Plot Options. jet first to
            %preserve plottmgraph's own default. The last three are
            %qualitative -- adjacent entries are unrelated rather than a
            %ramp -- which is what categorical node labels need.
            names = {'jet','parula','turbo','hot','cool','winter','autumn', ...
                'gray','hsv','lines','prism','colorcube'};
        end

        function msg = oversizedWindowMessage(nPoints)
            %OVERSIZEDWINDOWMESSAGE the error text for a row range whose
            %full pairwise distance matrix would be unreasonably large,
            %or '' if it is fine.
            %   The numbers here are measured (process peak working set,
            %   one fresh MATLAB per size), not assumed.
            %   tknndigraph now runs on its lowMemory path, which never
            %   forms an nPoints-by-nPoints array, so its cost is roughly
            %   FLAT in nPoints -- hence the constant term.
            %   filtergraph is what still scales quadratically: distances()
            %   returns a full nPoints-by-nPoints geodesic matrix. That is
            %   the binding constraint now, and the quadratic term below is
            %   it. (Fixing that would raise this ceiling much further --
            %   for an unweighted graph, thresholding geodesics at d is
            %   reachability within d hops, which sparse boolean products
            %   give without ever going dense.)
            %   Counted AFTER decimation, so raising downsample is a
            %   genuine fix rather than a way to sidestep the check.
            %   Fitted to measured whole-GUI peaks (1.75 GB at 8000
            %   points, 6.15 GB at 17320), which is what a user actually
            %   pays: filtergraph's geodesic matrix AND, when the
            %   recurrence plot is shown, TCMdistance's per-time-point
            %   matrix, which is a second nPoints-by-nPoints array.
            overheadGB = 0.6;      % roughly flat: the blocked distance pass
            bytesPerSquare = 18.6; % the quadratic consumers above
            budgetGB = 4;          % the limit is a memory budget, not a magic count
            maxPoints = floor(sqrt(max(budgetGB-overheadGB,0)*1e9/bytesPerSquare));
            if nPoints > maxPoints
                msg = sprintf(['The selected range leaves %d time points -- building a ' ...
                    'network that size needs ~%.1f GB of memory (the limit here is %.0f GB, ' ...
                    'about %d points). Restrict the row range (start row/end row) or ' ...
                    'increase downsample (N).'], ...
                    nPoints, overheadGB + bytesPerSquare*nPoints^2/1e9, budgetGB, maxPoints);
            else
                msg = '';
            end
        end
    end

    methods (Access = public)

        function app = TemporalMapperApp
            createComponents(app)
        end

        function delete(app)
            if isvalid(app.UIFigure)
                delete(app.UIFigure)
            end
        end
    end
end
