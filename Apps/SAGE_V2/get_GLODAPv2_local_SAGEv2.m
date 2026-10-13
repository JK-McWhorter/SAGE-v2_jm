function d = get_GLODAPv2_local_SAGEv2(source, track, tol, depth_bnds)
% PURPOSE: 
%   Extract all GLODAP nutrient data within a given distance from each
%   track position if it exists. Intended use is to find cross overs for
%   BGC ARGO float profiles for data quality control purposes
%   variable and then interpolate data along the provided track. 
%
% USAGE:
%	d = get_GLODAPv2_local_SAGEv2(source, track, tol, depth_bnds)
%
% INPUTS:
%   source     = path to merged glodap mat file (v2 or v3)
%   track      = n x 4 matrix [Matlab_SDN, float cycle, Lat, Lon]
%   tol        = km distance to expand search from track position
%   depth_bnds = depth bounds [min depth  max depth]
%
% OUTPUTS:
%	d =   a structure
%       d.hdr  = column headers
%       d.data = GLODAP data near track positions

% ***********************************************************************
%   DEFAULT OUTPUT
% ***********************************************************************
d    = [];
data = [];
hdr  = {};

% ***********************************************************************
%   DYNAMIC VARIABLE DETECTION (SUPPORTS GLODAPv2 AND GLODAPv3)
% ***********************************************************************
% Inspect available variables inside the MAT file
file_info  = whos('-file', source);
avail_vars = {file_info.name};

% Determine variable prefix (G3 for GLODAPv3, G2 for GLODAPv2, or none)
if any(startsWith(avail_vars, 'G3'))
    prefix = 'G3';
elseif any(startsWith(avail_vars, 'G2'))
    prefix = 'G2';
else
    prefix = '';
end

% Base parameter names desired by SAGEv2
base_names = {'cruise', 'station', 'cast', 'year', 'month', 'day', 'hour', ...
              'minute', 'latitude', 'longitude', 'pressure', 'temperature', ...
              'salinity', 'oxygen', 'nitrate', 'silicate', 'phosphate', ...
              'talk', 'tco2', 'phts25p0'};

% Build G_INFO and load_vars list based on present variables
G_INFO    = cell(length(base_names), 1);
load_vars = {};

for i = 1:length(base_names)
    var_name = [prefix, base_names{i}];
    
    % Handle 'press' / 'pressure' naming variations across dataset releases
    if strcmp(base_names{i}, 'pressure') && ~ismember(var_name, avail_vars)
        if ismember([prefix, 'press'], avail_vars)
            var_name = [prefix, 'press'];
        elseif ismember('pressure', avail_vars)
            var_name = 'pressure';
        elseif ismember('depth', avail_vars)
            var_name = 'depth';
        end
    end
    
    G_INFO{i,1} = var_name;
    
    if ismember(var_name, avail_vars)
        load_vars = [load_vars, var_name];
    end
    
    % Include associated quality flag (.f) and QC (.qc) variables if present
    f_var  = [var_name, 'f'];
    qc_var = [var_name, 'qc'];
    if ismember(f_var, avail_vars)
        load_vars = [load_vars, f_var];
    end
    if ismember(qc_var, avail_vars)
        load_vars = [load_vars, qc_var];
    end
end

% Check pH QC variable explicitly (often formatted as G2phtsqc / G3phtsqc)
ph_qc = [prefix, 'phtsqc'];
if ismember(ph_qc, avail_vars)
    load_vars = [load_vars, ph_qc];
end

% ***********************************************************************
% CHECK TRACK INPUT
% ***********************************************************************
s2 = ['Check track input: must have 4 rows or columns ', ...
     '[SDN float_cycle Lat Lon]'];
s3 = ' Check depth range input: should be [min_depth max_depth]';
[r,c] = size(track);
if r ~= 4 && c ~= 4
    disp(s2)
    return
end
if r == 4 && c ~= 4
    track = track'; % now  n x 4
end
if length(depth_bnds) ~= 2 || depth_bnds(1) > depth_bnds(2)
    disp(s3)
    return
end
clear s2 s3 r c

% ***********************************************************************
% GET / CHECK BOUNDS OF TRACK 
% ***********************************************************************
cross180 = 0; % flag for meridian crossing

% SDN LAT LON
t1 = track(:,3) == -1e10; % SET MISSING VALUES IN LAT to NaN
track(t1,3:4) = NaN;
clear t1

% CONVERT LON TO -180 to +180 IF NECESSARY
t1 = track(:,4) > 180;
track(:,4) = track(:,4) - (t1*360);

% CONVERT TOL TO DEGREES LAT AND LON
lat_tol = tol / 110.574; % approx degrees lat
lon_tol = abs(tol / (111.320 * cos(deg2rad(mean(track(:,3),'omitnan'))))); % approx deg lon

% GET LAT BOUNDS - ADD 2X TOL FOR 1st SUBSET
lat_bnds = [min(track(:,3)) - 2*lat_tol, max(track(:,3)) + 2*lat_tol];
if lat_bnds(1) < -90
    lat_bnds(1) = -90;
elseif lat_bnds(2) > 90
    lat_bnds(2) = 90;
end

% GET LON BOUNDS - ADD 2X TOL FOR 1st SUBSET
lon_bnds = [min(track(:,4)) - 2*lon_tol, max(track(:,4)) + 2*lon_tol];
if lon_bnds(1) < -180
    disp('longitude bounds - tol crosses +180 / -180 meridian')
    cross180 = 1;
    lon_bnds(1) = lon_bnds(1) + 360;
    lon_bnds    = sort(lon_bnds);
elseif lon_bnds(2) > 180
    disp('longitude bounds + tol crosses +180 / -180 meridian')
    cross180 = 1;
    lon_bnds(2) = lon_bnds(2) - 360;
    lon_bnds    = sort(lon_bnds);
end

% CHECK TRACK CROSSES -180 / +180 MERIDIAN 
if max(abs(diff(track(:,4)))) > 340
    disp('Trackline crosses +180 / -180 meridian')
    cross180 = 1;
end

% ***********************************************************************
% LOAD GLODAP AND SUBSET DATA WITHIN TRACK BOUNDS
% ***********************************************************************
% Load only the variables present in the dataset
d = load(source, load_vars{:});

% Locate pressure/depth field dynamically from loaded structure
P_var = [];
p_fields = {[prefix, 'pressure'], [prefix, 'press'], 'pressure', 'depth'};
for k = 1:length(p_fields)
    if isfield(d, p_fields{k})
        P_var = d.(p_fields{k});
        break;
    end
end

if isempty(P_var)
    error('Could not find pressure/depth field in GLODAP dataset. Available fields: %s', ...
        strjoin(fieldnames(d), ', '));
end

lat_field = [prefix, 'latitude'];
lon_field = [prefix, 'longitude'];

tP   = P_var >= depth_bnds(1) & P_var <= depth_bnds(2);
tlat = d.(lat_field) >= lat_bnds(1) & d.(lat_field) <= lat_bnds(2);

if cross180 == 0
    tlon = d.(lon_field) >= lon_bnds(1) & d.(lon_field) <= lon_bnds(2);
else
    tlon = (d.(lon_field) >= -180 & d.(lon_field) <= lon_bnds(1)) | ...
           (d.(lon_field) >= lon_bnds(2) & d.(lon_field) <= 180);
end

tdata = tP & tlat & tlon; 
Gdata = ones(sum(tdata), size(G_INFO, 1)) * NaN;

for i = 1:size(G_INFO, 1)
    var_name = G_INFO{i,1};
    if ~isfield(d, var_name)
        continue;
    end
    
    f_name  = [var_name, 'f'];
    qc_name = [var_name, 'qc'];
    
    if regexp(var_name, 'phts')
        qc_name = [prefix, 'phtsqc'];
    end
    
    tmp = d.(var_name)(tdata);
    
    % Apply QC filtering if flag and QC fields exist in file
    if isfield(d, f_name) && isfield(d, qc_name)
        tnan = d.(f_name)(tdata) > 2 & d.(qc_name)(tdata) > 1;
        tmp(tnan) = NaN;
    end
    
    Gdata(:,i) = tmp;
end

% BUILD MATLAB SDN FROM COMPONENTS
sdn_mat = [Gdata(:,4:8), zeros(size(Gdata(:,1)))];
sdn_mat(isnan(sdn_mat)) = 0;
sdn   = datenum(sdn_mat);
Gdata = [sdn, Gdata(:,1:3), Gdata(:,9:end)];
Ghdr  = {'Date', G_INFO{1:3}, G_INFO{9:end}};
clear d tmp tnan tdata tP tlat tlon i

% ***********************************************************************
% STEP THROUGH TRACK POINTS AND LOOK FOR CROSSOVER GLODAP DATA
% ***********************************************************************
stations = size(track(:,1), 1);
rr       = size(Gdata, 1);
data     = [];

for i = 1:stations
    if isnan(track(i,3))
        continue
    end
    % Haversine distance in KM from GLODAP point to track position
    [d1, ~] = lldistkm(Gdata(:,5:6), ones(rr,1) * track(i,3:4));
    t1      = d1 <= tol;
    if sum(t1) > 0
        data = [data; ones(sum(t1),1) * track(i,2), Gdata(t1,:)];
    end
end

% ***********************************************************************
% CALCULATE IN SITU PH USING SOCCOM CONSTANTS
% ***********************************************************************
if ~isempty(data)
    hdr = ['float cycle', Ghdr];
    
    pHSCALEIN     = 1;  % TOTAL SCALE
    K1K2CONSTANTS = 10; % Lueker et al, 2000
    KSO4CONSTANTS = 3;  % KSO4 of Dickson & TB of Lee 2010
    
    % GET SHIPBOARD DATA INDICES
    iP   = find(strcmp([prefix, 'pressure'], hdr) | strcmp([prefix, 'press'], hdr) | strcmp('pressure', hdr) == 1);
    iT   = find(strcmp([prefix, 'temperature'], hdr) == 1);
    iS   = find(strcmp([prefix, 'salinity'], hdr)    == 1);
    iDIC = find(strcmp([prefix, 'tco2'], hdr)        == 1);
    iALK = find(strcmp([prefix, 'talk'], hdr)        == 1);
    iPH  = find(strcmp([prefix, 'phts25p0'], hdr)    == 1);
    iSI  = find(strcmp([prefix, 'silicate'], hdr)    == 1);
    iPO4 = find(strcmp([prefix, 'phosphate'], hdr)   == 1);
    
    % IN SITU CONDITIONS
    SAL     = data(:, iS);
    TEMPOUT = data(:, iT);
    PRESOUT = data(:, iP);
    SI      = data(:, iSI);
    PO4     = data(:, iPO4);
    
    PAR1     = data(:, iALK);
    PAR1TYPE = 1;
    PAR2     = data(:, iPH);
    PAR2TYPE = 3;
    TEMPIN   = 25;
    PRESIN   = 0;
    
    [OUT] = CO2SYSSOCCOM(PAR1, PAR2, PAR1TYPE, PAR2TYPE, SAL, ...
        TEMPIN, TEMPOUT, PRESIN, PRESOUT, SI, PO4, ...
        pHSCALEIN, K1K2CONSTANTS, KSO4CONSTANTS);
    
    data = [data, OUT(:,18)];
    hdr  = [hdr, 'ph_insitu'];
end

% CREATE OUTPUT
d.hdr  = hdr;
d.data = data;
clearvars -except d
end