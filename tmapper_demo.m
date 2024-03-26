% tmapper_demo.m
% ---------------
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
dat = rmmissing(dat);
dat = dat(53884:end,:);% just take some recent data for demo
%% ===== quick look at data =====
% --- pick a couple of variable to define the state
varidx = 3:5;
X = zscore(dat{:,varidx}); 

% --- the time
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
texclude = 30; % a temporal neighborhood where you consider things are not recurring. (in unit of time points)
% --- define a variable for coloring the graph
colorvarname = 'tmax';
colorvar = dat{:,colorvarname};

% --- construct knn graph
disp("computing knn graph")
tidx = (1:length(t))';
tic
g = tknndigraph (D,k,tidx,'reciprocal',true,'timeExcludeSpace', true,'timeExcludeRange',texclude);
toc

% --- construct simplified graph
disp("simplifying knn graph")
tic
[g_simp, members, nodesize, D_simp] = filtergraph(g,d,'reciprocal',true);
toc


% --- show transition networks      and recurrence plot
[a1,a2,~,~,hg,D_geo] = plotgraphtcm(g_simp,colorvar,t,members,'nodesizerange',[1,10],...
    'colorlabel',colorvarname,'labelmethod','median','nodesizemode','log');
title(a1,["sample data","k=" + k + ", d=" + d])
