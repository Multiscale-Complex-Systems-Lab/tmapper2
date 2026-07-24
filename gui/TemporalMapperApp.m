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
        LabelMethodLabel        matlab.ui.control.UIControl
        LabelMethodDropDown     matlab.ui.control.UIControl
        ShowRecurrenceCheckBox  matlab.ui.control.UIControl
        BuildButton             matlab.ui.control.UIControl
        CopyCodeButton          matlab.ui.control.UIControl
        StatusLabel             matlab.ui.control.UIControl
        StatusTextArea          matlab.ui.control.UIControl

        NetworkAxes         matlab.graphics.axis.Axes
        RecurrenceAxes      matlab.graphics.axis.Axes
    end

    properties (Access = private)
        DataTable = table()   % the loaded data
        NumericVarNames = {}  % candidate columns (numeric only)
        ExtraColorVarNames = {}  % display names of workspace-sourced color vectors
        ExtraColorVarValues = {} % their values, parallel to ExtraColorVarNames
        DataSourceCode = '% dat = <load your data here as a table, e.g. dat = readtable(''your_file.csv'');>' % how "dat" was obtained, for generateCode
    end

    methods (Access = public)

        function loadData(app, T)
            %LOADDATA load a table into the app -- populates the variable
            %list and color/time dropdowns. Used both by the "Load
            %Data..." button (after reading the picked file) and directly
            %by scripts/tests that want to bypass the file picker.
            isnum = varfun(@isnumeric, T, 'OutputFormat','uniform');
            varNames = T.Properties.VariableNames(isnum);
            if isempty(varNames)
                error('TemporalMapperApp:noNumericVars', ...
                    'That data has no numeric columns to build a network from.');
            end

            app.DataTable = T;
            app.NumericVarNames = varNames;
            % any workspace-sourced color vectors were aligned to the
            % previous data's row count, so they no longer apply
            app.ExtraColorVarNames = {};
            app.ExtraColorVarValues = {};
            app.VariableListBox.String = varNames;
            app.VariableListBox.Value = 1:numel(varNames); % select all by default
            app.ColorVarDropDown.String = [{'(row index)'}, varNames];
            app.ColorVarDropDown.Value = 1;
            app.TimeVarDropDown.String = [{'(row index)'}, varNames];
            app.TimeVarDropDown.Value = 1;
            app.FileLabel.String = sprintf('Loaded: %d rows, %d numeric vars', height(T), numel(varNames));
            app.StatusTextArea.String = {sprintf('Loaded data: %d rows, %d numeric variables.', height(T), numel(varNames))};
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
            app.ColorVarDropDown.String = [{'(row index)'}, app.NumericVarNames, app.ExtraColorVarNames];
            app.ColorVarDropDown.Value = numel(app.ColorVarDropDown.String); % select the one just added
        end

        function buildNetwork(app)
            %BUILDNETWORK run tknndigraph -> filtergraph on the currently
            %selected variables/parameters and render the result into
            %NetworkAxes/RecurrenceAxes. Used both by the "Build Network"
            %button and directly by scripts/tests.
            if isempty(app.DataTable)
                error('TemporalMapperApp:noData','Load a data file first.');
            end
            selectedVars = app.VariableListBox.String(app.VariableListBox.Value);
            if isempty(selectedVars)
                error('TemporalMapperApp:noVars','Select at least one variable to build the network from.');
            end

            if app.ZscoreCheckBox.Value
                X_raw = zscore(app.DataTable{:,selectedVars});
            else
                X_raw = app.DataTable{:,selectedVars};
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
            % original rows aligned with each embedded state (the most
            % recent slice, since embedding above stacks past->present)
            rows = (N_raw-N+1):N_raw;

            tidx = (1:N)';
            totalTimer = tic;

            app.StatusTextArea.String = {'Computing pairwise distances...'};
            drawnow
            stepTimer = tic;
            D = pdist2(X,X,'minkowski',2);
            tDistances = toc(stepTimer);

            k = app.parseNumericField(app.KEditField, 'k (neighbors)', 1, Inf, true, false);
            d = app.parseNumericField(app.DEditField, 'd (compression)', 0, Inf, false, true);
            texclude = app.parseNumericField(app.TExcludeEditField, 'texclude', 1, Inf, true, false);
            maxdistprct = app.parseNumericField(app.MaxDistPrctEditField, 'max dist percentile', 0, 100, false, false);
            maxdist = app.parseNumericField(app.MaxDistEditField, 'max dist', 0, Inf, false, true);
            recip = app.ReciprocalCheckBox.Value;

            app.StatusTextArea.String = {sprintf('Distances: %.2fs. Computing k-NN graph...', tDistances)};
            drawnow
            stepTimer = tic;
            [g, par] = tknndigraph(D, k, tidx, ...
                'timeExcludeRange', texclude, ...
                'maxNeighborDistPrct', maxdistprct, ...
                'maxNeighborDist', maxdist);
            tKnn = toc(stepTimer);

            app.StatusTextArea.String = {sprintf('k-NN graph: %.2fs. Simplifying graph...', tKnn)};
            drawnow
            stepTimer = tic;
            [g_simp, members, ~, ~] = filtergraph(g, d, 'reciprocal', recip);
            tSimplify = toc(stepTimer);

            % -- color variable (a DataTable column, a workspace-sourced
            % vector picked via ColorVarWorkspaceButton, or row index)
            selectedColor = app.ColorVarDropDown.String{app.ColorVarDropDown.Value};
            if strcmp(selectedColor, '(row index)')
                colorvar = tidx;
                colorlabel = 'row index';
            elseif ismember(selectedColor, app.NumericVarNames)
                colorvar = app.DataTable.(selectedColor)(rows);
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
            colorbar(app.RecurrenceAxes,'off') % remove any colorbar from a previous build

            showRecurrence = app.ShowRecurrenceCheckBox.Value;
            if showRecurrence
                app.NetworkAxes.Position = [0.06 0.12 0.40 0.78];
                app.RecurrenceAxes.Visible = 'on';
            else
                % network plot alone gets the full plot panel width
                app.NetworkAxes.Position = [0.08 0.12 0.85 0.78];
                app.RecurrenceAxes.Visible = 'off';
            end

            app.StatusTextArea.String = {sprintf('Simplify: %.2fs. Rendering network plot...', tSimplify)};
            drawnow
            stepTimer = tic;
            nodeSizeMode = app.NodeSizeModeDropDown.String{app.NodeSizeModeDropDown.Value};
            labelMethod = app.LabelMethodDropDown.String{app.LabelMethodDropDown.Value};
            plottmgraph(g_simp, colorvar, members, 'ax', app.NetworkAxes, ...
                'nodesizemode', nodeSizeMode, ...
                'labelmethod', labelMethod, ...
                'colorlabel', colorlabel);
            % axis('equal') alone lets MATLAB stretch the axis LIMITS
            % (not just the rendered box) to match the axes' own w:h
            % ratio when it isn't perfectly square, leaving wide blank
            % margins on whichever side that stretch fell on. 'tight'
            % afterward re-hugs the limits to the actual plotted data,
            % while 'equal' (already set inside plottmgraph) keeps the
            % 1:1 aspect so the network isn't visually distorted.
            axis(app.NetworkAxes,'tight')
            if order > 1
                title(app.NetworkAxes, sprintf('k=%g, d=%g, texclude=%g, maxdist=%.4g, lag=%g, order=%g', ...
                    k, d, texclude, par.maxNeighborDist, lag, order));
            else
                title(app.NetworkAxes, sprintf('k=%g, d=%g, texclude=%g, maxdist=%.4g', ...
                    k, d, texclude, par.maxNeighborDist));
            end
            tPlotNetwork = toc(stepTimer);

            tPlotRecurrence = 0;
            if showRecurrence
                app.StatusTextArea.String = {sprintf('Network plot: %.2fs. Rendering recurrence plot...', tPlotNetwork)};
                drawnow
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

            tTotal = toc(totalTimer);
            if showRecurrence
                timingLine = sprintf(['Timing (s): distances %.2f, k-NN %.2f, simplify %.2f, ' ...
                    'network plot %.2f, recurrence plot %.2f, total %.2f.'], ...
                    tDistances, tKnn, tSimplify, tPlotNetwork, tPlotRecurrence, tTotal);
            else
                timingLine = sprintf(['Timing (s): distances %.2f, k-NN %.2f, simplify %.2f, ' ...
                    'network plot %.2f, total %.2f.'], ...
                    tDistances, tKnn, tSimplify, tPlotNetwork, tTotal);
            end
            app.StatusTextArea.String = { ...
                sprintf('Built network: %d nodes, %d edges. Resolved max distance = %.4g.', ...
                    numnodes(g_simp), numedges(g_simp), par.maxNeighborDist), ...
                timingLine};
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

            L = {};
            L{end+1} = '%% Temporal Mapper -- generated by TemporalMapperApp''s "Copy Code" button';
            L{end+1} = 'addpath("tmapper_tools/")';
            L{end+1} = '';
            L{end+1} = app.DataSourceCode;
            L{end+1} = '';
            L{end+1} = sprintf('selectedVars = {%s};', varListStr);
            if app.ZscoreCheckBox.Value
                L{end+1} = 'X = zscore(dat{:,selectedVars});';
            else
                L{end+1} = 'X = dat{:,selectedVars};';
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
                L{end+1} = 'rows = (N_raw-N+1):N_raw;';
                L{end+1} = 'X = X_embed;';
                L{end+1} = '';
            else
                L{end+1} = 'rows = 1:size(X,1);';
            end
            L{end+1} = 'tidx = (1:size(X,1))'';';
            L{end+1} = 'D = pdist2(X,X,''minkowski'',2);';
            L{end+1} = '';
            L{end+1} = sprintf(['[g, par] = tknndigraph(D, %g, tidx, ''timeExcludeRange'', %g, ' ...
                '''maxNeighborDistPrct'', %g, ''maxNeighborDist'', %g);'], k, texclude, maxdistprct, maxdist);
            L{end+1} = sprintf('[g_simp, members] = filtergraph(g, %g, ''reciprocal'', %d);', d, recip);
            L{end+1} = '';

            selectedColor = app.ColorVarDropDown.String{app.ColorVarDropDown.Value};
            if strcmp(selectedColor, '(row index)')
                L{end+1} = 'colorvar = tidx;';
                colorlabelExpr = '''row index''';
            elseif ismember(selectedColor, app.NumericVarNames)
                L{end+1} = sprintf('colorvar = dat.%s(rows);', selectedColor);
                colorlabelExpr = ['''' selectedColor ''''];
            else
                L{end+1} = sprintf(['%% "%s" was a workspace variable added via the "Color by Workspace ' ...
                    'Variable..." button -- substitute your own vector here, indexed by rows:'], selectedColor);
                L{end+1} = sprintf('colorvar = %s(rows); %% <-- replace %s with your workspace variable', ...
                    matlab.lang.makeValidName(selectedColor), matlab.lang.makeValidName(selectedColor));
                colorlabelExpr = ['''' selectedColor ''''];
            end

            selectedTime = app.TimeVarDropDown.String{app.TimeVarDropDown.Value};
            if strcmp(selectedTime, '(row index)')
                L{end+1} = 't = tidx;';
            else
                L{end+1} = sprintf('t = dat.%s(rows);', selectedTime);
            end
            L{end+1} = '';

            if app.ShowRecurrenceCheckBox.Value
                % plotgraphtcm opens its own figure internally (network
                % + recurrence plot side by side), so no explicit
                % figure() call here.
                L{end+1} = sprintf(['plotgraphtcm(g_simp, colorvar, t, members, ''nodesizemode'', ''%s'', ' ...
                    '''labelmethod'', ''%s'', ''colorlabel'', %s);'], nodeSizeMode, labelMethod, colorlabelExpr);
            else
                % plottmgraph plots into gca by default, reusing an
                % existing figure if one is open -- open a new one first
                % so this doesn't overwrite whatever's already on screen.
                L{end+1} = 'figure;';
                L{end+1} = sprintf(['plottmgraph(g_simp, colorvar, members, ''nodesizemode'', ''%s'', ' ...
                    '''labelmethod'', ''%s'', ''colorlabel'', %s);'], nodeSizeMode, labelMethod, colorlabelExpr);
            end

            code = strjoin(L, newline);
        end
    end

    methods (Access = private)

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
            pad = 0.03;
            pos = [x+pad, y+pad, max(colW-2*pad,0.001), max(h-2*pad,0.001)];
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
            app.PlotPanel = uipanel(app.UIFigure, 'Title','Network', ...
                'Units','normalized', 'Position',[0 0 1 1-setupH]);

            % ================= panel 1: data, build & status =================
            nRows = 6;
            app.LoadDataButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Load Data...', 'Units','normalized', ...
                'Position', app.rowPosition(1,nRows,1,2), ...
                'Callback', @(src,evt) app.LoadDataButtonPushed(src,evt));

            app.LoadWorkspaceButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Load from Workspace...', 'Units','normalized', ...
                'Position', app.rowPosition(1,nRows,2,2), ...
                'Callback', @(src,evt) app.LoadWorkspaceButtonPushed(src,evt));

            app.FileLabel = uicontrol(app.DataPanel, 'Style','text', ...
                'String','No file loaded.', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(2,nRows,1,1));

            app.BuildButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Build Network', 'BackgroundColor',[0.31 0.60 0.95], ...
                'ForegroundColor','white', 'FontWeight','bold', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,1,2), ...
                'Callback', @(src,evt) app.BuildButtonPushed(src,evt));

            app.CopyCodeButton = uicontrol(app.DataPanel, 'Style','pushbutton', ...
                'String','Copy Code', ...
                'TooltipString','Copy MATLAB code that reproduces this build to the clipboard.', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,2,2), ...
                'Callback', @(src,evt) app.CopyCodeButtonPushed(src,evt));

            app.StatusLabel = uicontrol(app.DataPanel, 'Style','text', ...
                'String','Status:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,1,1));

            app.StatusTextArea = uicontrol(app.DataPanel, 'Style','edit', ...
                'String',{'Load a data file to get started.'}, 'Max',2, 'Min',0, ...
                'Enable','inactive', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,1,2));

            % ================= panel 2: variables & preprocessing =================
            nRows = 7;
            app.VariablesLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','Variables:', 'HorizontalAlignment','left', ...
                'TooltipString','Ctrl/shift-click to select multiple.', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,1,2));
            app.SelectAllButton = uicontrol(app.PreprocessPanel, 'Style','pushbutton', ...
                'String','Select All', 'Units','normalized', ...
                'Position', app.rowPosition(1,nRows,2,2), ...
                'Callback', @(src,evt) app.SelectAllButtonPushed(src,evt));

            app.VariableListBox = uicontrol(app.PreprocessPanel, 'Style','listbox', ...
                'String',{}, 'Max',2, 'Min',0, 'Value',[], ...
                'Units','normalized', 'Position', app.rowPosition(2,nRows,1,1,3));

            app.ZscoreCheckBox = uicontrol(app.PreprocessPanel, 'Style','checkbox', ...
                'String','z-score variables', 'Value',1, ...
                'TooltipString','Z-score variables before building network.', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,1));

            app.EmbedLagLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','embed lag:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,1,2));
            app.EmbedLagEditField = uicontrol(app.PreprocessPanel, 'Style','edit', ...
                'String','0', 'Units','normalized', 'Position', app.rowPosition(6,nRows,2,2));

            app.EmbedOrderLabel = uicontrol(app.PreprocessPanel, 'Style','text', ...
                'String','embed order:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(7,nRows,1,2));
            app.EmbedOrderEditField = uicontrol(app.PreprocessPanel, 'Style','edit', ...
                'String','1', 'Units','normalized', 'Position', app.rowPosition(7,nRows,2,2));

            % ================= panel 3: network parameters =================
            nRows = 6;
            app.KLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','k (neighbors):', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,1,2));
            app.KEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','3', 'Units','normalized', 'Position', app.rowPosition(1,nRows,2,2));

            app.DLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','d (compression):', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(2,nRows,1,2));
            app.DEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','3', 'Units','normalized', 'Position', app.rowPosition(2,nRows,2,2));

            app.TExcludeLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','texclude:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,1,2));
            app.TExcludeEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','1', 'Units','normalized', 'Position', app.rowPosition(3,nRows,2,2));

            app.MaxDistPrctLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','max dist %ile:', 'HorizontalAlignment','left', ...
                'TooltipString','max dist percentile', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,1,2));
            app.MaxDistPrctEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','100', 'Units','normalized', 'Position', app.rowPosition(4,nRows,2,2));

            app.MaxDistLabel = uicontrol(app.NetworkParamsPanel, 'Style','text', ...
                'String','max dist:', 'HorizontalAlignment','left', ...
                'TooltipString','max dist (absolute)', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,2));
            app.MaxDistEditField = uicontrol(app.NetworkParamsPanel, 'Style','edit', ...
                'String','Inf', 'Units','normalized', 'Position', app.rowPosition(5,nRows,2,2));

            app.ReciprocalCheckBox = uicontrol(app.NetworkParamsPanel, 'Style','checkbox', ...
                'String','reciprocal', 'Value',1, ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,1,1));

            % ================= panel 4: plot options =================
            nRows = 6;
            app.ColorVarLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Color by:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,1,2));
            app.ColorVarDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'(row index)'}, 'Value',1, ...
                'Units','normalized', 'Position', app.rowPosition(1,nRows,2,2));

            app.ColorVarWorkspaceButton = uicontrol(app.PlotOptionsPanel, 'Style','pushbutton', ...
                'String','Color by Workspace Variable...', 'Units','normalized', ...
                'Position', app.rowPosition(2,nRows,1,1), ...
                'Callback', @(src,evt) app.ColorVarWorkspaceButtonPushed(src,evt));

            app.TimeVarLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Time axis:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,1,2));
            app.TimeVarDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'(row index)'}, 'Value',1, ...
                'Units','normalized', 'Position', app.rowPosition(3,nRows,2,2));

            app.NodeSizeModeLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Node size:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,1,2));
            app.NodeSizeModeDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'log','rank','original'}, 'Value',1, ...
                'Units','normalized', 'Position', app.rowPosition(4,nRows,2,2));

            app.LabelMethodLabel = uicontrol(app.PlotOptionsPanel, 'Style','text', ...
                'String','Label method:', 'HorizontalAlignment','left', ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,1,2));
            app.LabelMethodDropDown = uicontrol(app.PlotOptionsPanel, 'Style','popupmenu', ...
                'String',{'mode','mean','median','none'}, 'Value',1, ...
                'Units','normalized', 'Position', app.rowPosition(5,nRows,2,2));

            app.ShowRecurrenceCheckBox = uicontrol(app.PlotOptionsPanel, 'Style','checkbox', ...
                'String','Show recurrence plot', 'Value',1, ...
                'TooltipString','Uncheck to show only the network plot, widened to fill the panel.', ...
                'Units','normalized', 'Position', app.rowPosition(6,nRows,1,2));

            % ================= bottom: plot panel =================
            app.NetworkAxes = axes('Parent', app.PlotPanel, 'Units','normalized', ...
                'Position',[0.06 0.12 0.40 0.78]);
            title(app.NetworkAxes,'attractor transition network')

            app.RecurrenceAxes = axes('Parent', app.PlotPanel, 'Units','normalized', ...
                'Position',[0.56 0.12 0.40 0.78]);
            title(app.RecurrenceAxes,'geodesic recurrence plot')
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
