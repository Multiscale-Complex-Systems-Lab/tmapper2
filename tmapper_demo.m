% tmapper_demo.m
% ---------------
% This script demonstrates how to use Temporal Mapper to construct network
% representations of time series data.
% For technical details, see the published paper: https://doi.org/10.1162/netn_a_00301
% 
% Citation:
%   Mengsen Zhang, Samir Chowdhury, Manish Saggar (2023). Temporal Mapper:
%   Transition networks in simulated and real neural dynamics. Network
%   Neuroscience, 7(2): 431–460. doi: https://doi.org/10.1162/netn_a_00301  
% 
% Sample data: historic East Lansing weather. 
% Source: https://kilthub.cmu.edu/articles/dataset/Compiled_daily_temperature_and_precipitation_data_for_the_U_S_cities/7890488?file=32874086

%{
~ created by Mengsen Zhang (2024) ~
%}
%% ===== add temporal mapper toolbox to path =====
addpath("tmapper_tools/")

%% ===== read the sample data
clear all
close all
clc

dat = readtable('EL_temp.csv');
dat = rmmissing(dat);% remove missing data
dat = dat(53884:end,:);% just take some recent data for demo
%% ===== quick look at data =====
% --- pick a couple of variable to define the state
varidx = 3:5;
X = zscore(dat{:,varidx}); % z-score to keep different dimensions more comparable, not always necessary

% --- define time
t = dat.Date;

% --- names of the variables
varnames = string(dat.Properties.VariableNames(varidx));

% --- plot the time series
figure
plot(dat.Date,X)
xlabel('Date')
ylabel('Normalized temperature/precipitation')
legend(varnames)

%% ===== a quick and dirty delay embedding =====
%  when the data is too low dimensional, the states may not separate. Here
%  we embed the data in the higher dimensions by included delayed state (90
%  days before).
X = [X(1:end-89,:) X(90:end,:)];
t = t(90:end);
%% ===== construct distance matrix =====
% --- select the type of distance
p=2; % 2 is the Euclidean distance

% --- compute the distance matrix (i.e. classical recurrence plot)
D = pdist2(X,X,'minkowski',p);

% --- plot the recurrence matrix
figure
imagesc(t,t,D)
axis square
xlabel("Date")
ylabel("Date")
title("classical recurrence plot",'Interpreter','none')
cb = colorbar;
colormap hot
cb.Label.String = "L-" + p + " distance";
%% ===== construct temporal mapper network =====

% --- tmapper construction parameters
k = 3;
d = 3; % compression rate. loops below this parameter is absorbed into nodes
texclude = 30; % a temporal neighborhood where you consider things are not recurring. usually 1 is good. (in unit of time points)
maxdistprct = 95; % maximal distance between neighbors by percentile.
maxdist = 0.5; % maximal distance between neighbors by absolute value;

% --- define a variable for coloring the graph
% this could be any variable that assign a value to each time point
colorvarname = 'tmax';
colorvar = dat{:,colorvarname};

% --- step 1: construct knn graph
disp("computing knn graph")
tidx = (1:length(t))';% these indices will be used to define temporal neighborhoods
tic
[g, par] = tknndigraph (D,k,tidx,...
                'timeExcludeRange',texclude,...
                'maxNeighborDistPrct',maxdistprct,...
                'maxNeighborDist',maxdist);
toc

% --- step 2: construct simplified graph
% g_simp is the graph that we want
% members tell you each node is mapped to which time points
disp("simplifying knn graph")
tic
[g_simp, members, nodesize, D_simp] = filtergraph(g,d,'reciprocal',true);
toc


% --- show transition networks and recurrence plot
[a1,a2,~,~,hg,D_geo] = plotgraphtcm(g_simp,colorvar,t,members,'nodesizerange',[1,10],...
    'colorlabel',colorvarname,'labelmethod','median','nodesizemode','log');
title(a1,["sample data","k=" + k + ", d=" + d, "tx=" + texclude + ", maxdist=" + par.maxNeighborDist])
%% ===== P.S. =====
% CycleCount2p can be used to calculate the cycles in the graph, which can
% be quite fun to explore. 