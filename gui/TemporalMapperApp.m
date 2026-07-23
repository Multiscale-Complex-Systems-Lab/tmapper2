classdef TemporalMapperApp < matlab.apps.AppBase
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
    %       app.VariableListBox.Value = {'tmax','tmin','prcp'};
    %       app.buildNetwork();
    %
    %{
    created by MZ (with Claude Code), 7-23-2026
    modifications:
    (7-23-2026) add z-score checkbox (was always-on) and a "Select All"
    button for the variable list.
    (7-23-2026) add delay-embedding lag/order fields, matching
    tmapper_demo.m's "quick and dirty delay embedding" -- concatenates
    'order' copies of the state, each 'lag' time points apart, to
    reveal cyclic/recurrent structure not visible in the raw variables
    alone. order=1 (default) skips embedding, matching prior behavior.
    (7-23-2026) add "Load from Workspace..." button so users whose data
    is already a table/matrix variable in the base workspace don't need
    to round-trip it through a file first.
    (7-23-2026) add "Color by Workspace Variable..." button (and the
    public addColorVarFromWorkspace method backing it) so users can
    color the network by a vector that isn't a column of the loaded
    data. Also fixes a RowHeight/row-count mismatch from the previous
    change that had silently misassigned heights to several rows below
    "Color by".
    %}

    properties (Access = public)
        UIFigure            matlab.ui.Figure
        GridLayout          matlab.ui.container.GridLayout
        ControlPanel        matlab.ui.container.Panel
        PlotPanel           matlab.ui.container.Panel
        ControlGrid         matlab.ui.container.GridLayout
        PlotGrid            matlab.ui.container.GridLayout

        LoadDataButton      matlab.ui.control.Button
        LoadWorkspaceButton matlab.ui.control.Button
        FileLabel           matlab.ui.control.Label
        VariablesLabel      matlab.ui.control.Label
        SelectAllButton     matlab.ui.control.Button
        VariableListBox     matlab.ui.control.ListBox
        ZscoreCheckBox      matlab.ui.control.CheckBox
        EmbedLagLabel       matlab.ui.control.Label
        EmbedLagEditField   matlab.ui.control.NumericEditField
        EmbedOrderLabel     matlab.ui.control.Label
        EmbedOrderEditField matlab.ui.control.NumericEditField
        ColorVarLabel       matlab.ui.control.Label
        ColorVarDropDown    matlab.ui.control.DropDown
        ColorVarWorkspaceButton matlab.ui.control.Button
        TimeVarLabel        matlab.ui.control.Label
        TimeVarDropDown     matlab.ui.control.DropDown
        KLabel              matlab.ui.control.Label
        KEditField          matlab.ui.control.NumericEditField
        DLabel              matlab.ui.control.Label
        DEditField          matlab.ui.control.NumericEditField
        TExcludeLabel       matlab.ui.control.Label
        TExcludeEditField   matlab.ui.control.NumericEditField
        MaxDistPrctLabel    matlab.ui.control.Label
        MaxDistPrctEditField matlab.ui.control.NumericEditField
        MaxDistLabel        matlab.ui.control.Label
        MaxDistEditField    matlab.ui.control.NumericEditField
        ReciprocalCheckBox  matlab.ui.control.CheckBox
        NodeSizeModeLabel   matlab.ui.control.Label
        NodeSizeModeDropDown matlab.ui.control.DropDown
        LabelMethodLabel    matlab.ui.control.Label
        LabelMethodDropDown matlab.ui.control.DropDown
        BuildButton         matlab.ui.control.Button
        StatusLabel         matlab.ui.control.Label
        StatusTextArea      matlab.ui.control.TextArea

        NetworkAxes         matlab.ui.control.UIAxes
        RecurrenceAxes      matlab.ui.control.UIAxes
    end

    properties (Access = private)
        DataTable = table()   % the loaded data
        NumericVarNames = {}  % candidate columns (numeric only)
        ExtraColorVarNames = {}  % display names of workspace-sourced color vectors
        ExtraColorVarValues = {} % their values, parallel to ExtraColorVarNames
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
            app.VariableListBox.Items = varNames;
            app.VariableListBox.Value = varNames; % select all by default
            app.ColorVarDropDown.Items = [{'(row index)'}, varNames];
            app.ColorVarDropDown.Value = '(row index)';
            app.TimeVarDropDown.Items = [{'(row index)'}, varNames];
            app.TimeVarDropDown.Value = '(row index)';
            app.FileLabel.Text = sprintf('Loaded: %d rows, %d numeric vars', height(T), numel(varNames));
            app.StatusTextArea.Value = {sprintf('Loaded data: %d rows, %d numeric variables.', height(T), numel(varNames))};
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
            app.ColorVarDropDown.Items = [{'(row index)'}, app.NumericVarNames, app.ExtraColorVarNames];
            app.ColorVarDropDown.Value = displayName;
        end

        function buildNetwork(app)
            %BUILDNETWORK run tknndigraph -> filtergraph on the currently
            %selected variables/parameters and render the result into
            %NetworkAxes/RecurrenceAxes. Used both by the "Build Network"
            %button and directly by scripts/tests.
            if isempty(app.DataTable)
                error('TemporalMapperApp:noData','Load a data file first.');
            end
            selectedVars = app.VariableListBox.Value;
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
            lag = app.EmbedLagEditField.Value;
            order = app.EmbedOrderEditField.Value;
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
            D = pdist2(X,X,'minkowski',2);

            k = app.KEditField.Value;
            d = app.DEditField.Value;
            texclude = app.TExcludeEditField.Value;
            maxdistprct = app.MaxDistPrctEditField.Value;
            maxdist = app.MaxDistEditField.Value;
            recip = app.ReciprocalCheckBox.Value;

            [g, par] = tknndigraph(D, k, tidx, ...
                'timeExcludeRange', texclude, ...
                'maxNeighborDistPrct', maxdistprct, ...
                'maxNeighborDist', maxdist);
            [g_simp, members, ~, ~] = filtergraph(g, d, 'reciprocal', recip);

            % -- color variable (a DataTable column, a workspace-sourced
            % vector picked via ColorVarWorkspaceButton, or row index)
            selectedColor = app.ColorVarDropDown.Value;
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
            if strcmp(app.TimeVarDropDown.Value, '(row index)')
                t = tidx;
            else
                t = app.DataTable.(app.TimeVarDropDown.Value)(rows);
            end

            cla(app.NetworkAxes)
            cla(app.RecurrenceAxes)

            plottmgraph(g_simp, colorvar, members, 'ax', app.NetworkAxes, ...
                'nodesizemode', app.NodeSizeModeDropDown.Value, ...
                'labelmethod', app.LabelMethodDropDown.Value, ...
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

            app.StatusTextArea.Value = {sprintf( ...
                'Built network: %d nodes, %d edges. Resolved max distance = %.4g.', ...
                numnodes(g_simp), numedges(g_simp), par.maxNeighborDist)};
        end
    end

    methods (Access = private)

        function LoadDataButtonPushed(app, ~)
            [file, filepath] = uigetfile({'*.csv;*.txt','Data files (*.csv, *.txt)'; '*.*','All files'}, ...
                'Select a data file');
            if isequal(file,0)
                return
            end
            try
                T = readtable(fullfile(filepath,file));
            catch ME
                uialert(app.UIFigure, sprintf('Could not read file: %s', ME.message), 'Load error');
                return
            end
            try
                app.loadData(T);
            catch ME
                uialert(app.UIFigure, ME.message, 'Load error');
            end
        end

        function LoadWorkspaceButtonPushed(app, ~)
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
                uialert(app.UIFigure, ...
                    'No table or numeric matrix variables found in the base workspace.', 'Load error');
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
            end
            try
                app.loadData(v);
                app.FileLabel.Text = sprintf('Loaded from workspace: %s', varNames{idx});
            catch ME
                uialert(app.UIFigure, ME.message, 'Load error');
            end
        end

        function ColorVarWorkspaceButtonPushed(app, ~)
            % -- let users color the network by a workspace vector that
            % isn't a column of the loaded data (e.g. a label vector
            % computed separately).
            if isempty(app.DataTable)
                uialert(app.UIFigure, 'Load a data file first.', 'Load error');
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
                uialert(app.UIFigure, ...
                    'No numeric vector variables found in the base workspace.', 'Load error');
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
                uialert(app.UIFigure, ME.message, 'Load error');
            end
        end

        function BuildButtonPushed(app, ~)
            try
                app.buildNetwork();
            catch ME
                uialert(app.UIFigure, ME.message, 'Build error');
                app.StatusTextArea.Value = {['Error: ' ME.message]};
            end
        end

        function SelectAllButtonPushed(app, ~)
            app.VariableListBox.Value = app.VariableListBox.Items;
        end
    end

    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Name','Temporal Mapper','Position',[100 100 1150 680]);

            app.GridLayout = uigridlayout(app.UIFigure, [1 2]);
            app.GridLayout.ColumnWidth = {330, '1x'};

            % ================= left: control panel =================
            app.ControlPanel = uipanel(app.GridLayout, 'Title','Setup');
            app.ControlPanel.Layout.Row = 1;
            app.ControlPanel.Layout.Column = 1;

            app.ControlGrid = uigridlayout(app.ControlPanel, [23 2]);
            app.ControlGrid.RowHeight = {32,32,24,20,22,150,26,26,26,26,26,26,26,26,26,26,26,26,26,26,34,18,'1x'};
            app.ControlGrid.ColumnWidth = {120,'1x'};
            app.ControlGrid.RowSpacing = 4;

            app.LoadDataButton = uibutton(app.ControlGrid, 'Text','Load Data...', ...
                'ButtonPushedFcn', @(btn,event) LoadDataButtonPushed(app));
            app.LoadDataButton.Layout.Row = 1; app.LoadDataButton.Layout.Column = [1 2];

            app.LoadWorkspaceButton = uibutton(app.ControlGrid, 'Text','Load from Workspace...', ...
                'ButtonPushedFcn', @(btn,event) LoadWorkspaceButtonPushed(app));
            app.LoadWorkspaceButton.Layout.Row = 2; app.LoadWorkspaceButton.Layout.Column = [1 2];

            app.FileLabel = uilabel(app.ControlGrid, 'Text','No file loaded.');
            app.FileLabel.Layout.Row = 3; app.FileLabel.Layout.Column = [1 2];

            app.VariablesLabel = uilabel(app.ControlGrid, 'Text','Variables (ctrl/shift-click to select multiple):');
            app.VariablesLabel.Layout.Row = 4; app.VariablesLabel.Layout.Column = [1 2];

            app.SelectAllButton = uibutton(app.ControlGrid, 'Text','Select All', ...
                'ButtonPushedFcn', @(btn,event) SelectAllButtonPushed(app));
            app.SelectAllButton.Layout.Row = 5; app.SelectAllButton.Layout.Column = 2;

            app.VariableListBox = uilistbox(app.ControlGrid, 'Items',{}, 'Multiselect','on');
            app.VariableListBox.Layout.Row = 6; app.VariableListBox.Layout.Column = [1 2];

            app.ZscoreCheckBox = uicheckbox(app.ControlGrid, 'Text','z-score variables before building network', 'Value',true);
            app.ZscoreCheckBox.Layout.Row = 7; app.ZscoreCheckBox.Layout.Column = [1 2];

            app.EmbedLagLabel = uilabel(app.ControlGrid, 'Text','embed lag:');
            app.EmbedLagLabel.Layout.Row = 8; app.EmbedLagLabel.Layout.Column = 1;
            app.EmbedLagEditField = uieditfield(app.ControlGrid,'numeric', 'Value',0, 'Limits',[0 Inf], 'RoundFractionalValues','on');
            app.EmbedLagEditField.Layout.Row = 8; app.EmbedLagEditField.Layout.Column = 2;

            app.EmbedOrderLabel = uilabel(app.ControlGrid, 'Text','embed order:');
            app.EmbedOrderLabel.Layout.Row = 9; app.EmbedOrderLabel.Layout.Column = 1;
            app.EmbedOrderEditField = uieditfield(app.ControlGrid,'numeric', 'Value',1, 'Limits',[1 Inf], 'RoundFractionalValues','on');
            app.EmbedOrderEditField.Layout.Row = 9; app.EmbedOrderEditField.Layout.Column = 2;

            app.ColorVarLabel = uilabel(app.ControlGrid, 'Text','Color by:');
            app.ColorVarLabel.Layout.Row = 10; app.ColorVarLabel.Layout.Column = 1;
            app.ColorVarDropDown = uidropdown(app.ControlGrid, 'Items',{'(row index)'});
            app.ColorVarDropDown.Layout.Row = 10; app.ColorVarDropDown.Layout.Column = 2;

            app.ColorVarWorkspaceButton = uibutton(app.ControlGrid, 'Text','Color by Workspace Variable...', ...
                'ButtonPushedFcn', @(btn,event) ColorVarWorkspaceButtonPushed(app));
            app.ColorVarWorkspaceButton.Layout.Row = 11; app.ColorVarWorkspaceButton.Layout.Column = [1 2];

            app.TimeVarLabel = uilabel(app.ControlGrid, 'Text','Time axis:');
            app.TimeVarLabel.Layout.Row = 12; app.TimeVarLabel.Layout.Column = 1;
            app.TimeVarDropDown = uidropdown(app.ControlGrid, 'Items',{'(row index)'});
            app.TimeVarDropDown.Layout.Row = 12; app.TimeVarDropDown.Layout.Column = 2;

            app.KLabel = uilabel(app.ControlGrid, 'Text','k (neighbors):');
            app.KLabel.Layout.Row = 13; app.KLabel.Layout.Column = 1;
            app.KEditField = uieditfield(app.ControlGrid,'numeric', 'Value',3, 'Limits',[1 Inf], 'RoundFractionalValues','on');
            app.KEditField.Layout.Row = 13; app.KEditField.Layout.Column = 2;

            app.DLabel = uilabel(app.ControlGrid, 'Text','d (compression):');
            app.DLabel.Layout.Row = 14; app.DLabel.Layout.Column = 1;
            app.DEditField = uieditfield(app.ControlGrid,'numeric', 'Value',3, 'Limits',[0 Inf], 'LowerLimitInclusive','off');
            app.DEditField.Layout.Row = 14; app.DEditField.Layout.Column = 2;

            app.TExcludeLabel = uilabel(app.ControlGrid, 'Text','texclude:');
            app.TExcludeLabel.Layout.Row = 15; app.TExcludeLabel.Layout.Column = 1;
            app.TExcludeEditField = uieditfield(app.ControlGrid,'numeric', 'Value',1, 'Limits',[1 Inf], 'RoundFractionalValues','on');
            app.TExcludeEditField.Layout.Row = 15; app.TExcludeEditField.Layout.Column = 2;

            app.MaxDistPrctLabel = uilabel(app.ControlGrid, 'Text','max dist percentile:');
            app.MaxDistPrctLabel.Layout.Row = 16; app.MaxDistPrctLabel.Layout.Column = 1;
            app.MaxDistPrctEditField = uieditfield(app.ControlGrid,'numeric', 'Value',100, 'Limits',[0 100]);
            app.MaxDistPrctEditField.Layout.Row = 16; app.MaxDistPrctEditField.Layout.Column = 2;

            app.MaxDistLabel = uilabel(app.ControlGrid, 'Text','max dist (absolute):');
            app.MaxDistLabel.Layout.Row = 17; app.MaxDistLabel.Layout.Column = 1;
            app.MaxDistEditField = uieditfield(app.ControlGrid,'numeric', 'Value',Inf, 'Limits',[0 Inf], 'LowerLimitInclusive','off');
            app.MaxDistEditField.Layout.Row = 17; app.MaxDistEditField.Layout.Column = 2;

            app.ReciprocalCheckBox = uicheckbox(app.ControlGrid, 'Text','reciprocal', 'Value',true);
            app.ReciprocalCheckBox.Layout.Row = 18; app.ReciprocalCheckBox.Layout.Column = [1 2];

            app.NodeSizeModeLabel = uilabel(app.ControlGrid, 'Text','Node size mode:');
            app.NodeSizeModeLabel.Layout.Row = 19; app.NodeSizeModeLabel.Layout.Column = 1;
            app.NodeSizeModeDropDown = uidropdown(app.ControlGrid, 'Items',{'log','rank','original'});
            app.NodeSizeModeDropDown.Layout.Row = 19; app.NodeSizeModeDropDown.Layout.Column = 2;

            app.LabelMethodLabel = uilabel(app.ControlGrid, 'Text','Label method:');
            app.LabelMethodLabel.Layout.Row = 20; app.LabelMethodLabel.Layout.Column = 1;
            app.LabelMethodDropDown = uidropdown(app.ControlGrid, 'Items',{'mode','mean','median','none'});
            app.LabelMethodDropDown.Layout.Row = 20; app.LabelMethodDropDown.Layout.Column = 2;

            app.BuildButton = uibutton(app.ControlGrid, 'Text','Build Network', ...
                'BackgroundColor',[0.31 0.60 0.95], 'FontColor','white', 'FontWeight','bold', ...
                'ButtonPushedFcn', @(btn,event) BuildButtonPushed(app));
            app.BuildButton.Layout.Row = 21; app.BuildButton.Layout.Column = [1 2];

            app.StatusLabel = uilabel(app.ControlGrid, 'Text','Status:');
            app.StatusLabel.Layout.Row = 22; app.StatusLabel.Layout.Column = [1 2];

            app.StatusTextArea = uitextarea(app.ControlGrid, 'Value',{'Load a data file to get started.'}, 'Editable','off');
            app.StatusTextArea.Layout.Row = 23; app.StatusTextArea.Layout.Column = [1 2];

            % ================= right: plot panel =================
            app.PlotPanel = uipanel(app.GridLayout, 'Title','Network');
            app.PlotPanel.Layout.Row = 1;
            app.PlotPanel.Layout.Column = 2;

            app.PlotGrid = uigridlayout(app.PlotPanel, [1 2]);
            app.PlotGrid.Padding = [2 2 2 2];
            app.PlotGrid.ColumnSpacing = 4;

            app.NetworkAxes = uiaxes(app.PlotGrid);
            app.NetworkAxes.Layout.Row = 1; app.NetworkAxes.Layout.Column = 1;
            title(app.NetworkAxes,'attractor transition network')

            app.RecurrenceAxes = uiaxes(app.PlotGrid);
            app.RecurrenceAxes.Layout.Row = 1; app.RecurrenceAxes.Layout.Column = 2;
            title(app.RecurrenceAxes,'geodesic recurrence plot')
        end
    end

    methods (Access = public)

        function app = TemporalMapperApp
            createComponents(app)
            registerApp(app, app.UIFigure)
        end

        function delete(app)
            delete(app.UIFigure)
        end
    end
end
