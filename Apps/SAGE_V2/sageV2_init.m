function d = sageV2_init(app)
% SAGEV2_INIT Initializes paths, default parameters, multi-WMO Sprof checking,
% and auto-generates a default Float QC list if missing for SAGEv2.
%
% Usage:
%   d = sageV2_init(app)   % Triggered from startupFcn(app) inside SAGEv2 App Designer
%   d = sageV2_init()      % Standalone execution mode
% ************************************************************************
%                  SET DIRECTORIES & ADD TO PATH
% ************************************************************************
data_default = 'SPROF'; % 'ODV' or 'SPROF'
user_path    = fullfile('C:', 'Users', 'Jennifer.McWhorter', 'Documents', 'MATLAB');

% Define Primary Application Directory
d.dirs.sage      = fullfile(user_path, 'Apps', 'SAGE_V2');

% Define Support & Data Directories
d.dirs.esper        = fullfile(user_path, 'ESPER');
d.dirs.caynb        = fullfile(user_path, 'CANYON_B');
d.dirs.WOA          = fullfile(user_path, 'WOA2023');
d.dirs.glodap       = fullfile(user_path, 'GLODAPv3');
d.dirs.glodap_fn    = 'GLODAPv3_Merged_Master_File.mat'; % <-- ADD THIS LINE
d.dirs.QClists      = fullfile(user_path, 'ARGO_PROCESSING', 'DATA', 'CAL', 'QC_LISTS');
d.dirs.QClog        = fullfile(user_path, 'ARGO_PROCESSING', 'DATA', 'CAL');
d.dirs.cal          = d.dirs.QClog;
d.dirs.QClog_fn     = 'FloatQCList_log.txt';
d.dirs.BadSensor_fn = 'BadSensorList.txt';
d.dirs.BadSample_fn = 'BadSampleList.txt';
d.dirs.sprof        = fullfile(user_path, 'ARGO', 'DATA', 'SPROF');

% Ensure SAGE_V2 core application code and subfolders are fully added to path
if isfolder(d.dirs.sage)
    addpath(genpath(d.dirs.sage), '-end');
end

% SET DEFAULT EDIT BOX RANGES
d.defaults.CycleMin = 1;
d.defaults.CycleMax = 500;
d.defaults.Pmin     = 1280;
d.defaults.Pmax     = 1520;
d.defaults.XOver_km = 30;
d.defaults.QCATable = [];

% SET DEFAULT FLOAT DATA PATH HERE
if strcmp(data_default, 'ODV')
    d.dirs.float = fullfile(user_path, 'ARGO_PROCESSING', 'DATA', 'FLOATVIZ');
elseif strcmp(data_default, 'SPROF')
    d.dirs.float = d.dirs.sprof;
else
    fprintf('Default data source (%s) not recognized (should be ODV or SPROF)\n', data_default);
    return;
end

% TEST FOLDER EXISTENCE & ADD PATHS
PathStr = path;
flds    = fieldnames(d.dirs);

% Remove file name entries (fields ending with 'fn')
tg      = cellfun(@isempty, regexp(flds, 'fn$', 'once'));
flds    = flds(tg);

for ct = 1:size(flds, 1)
    fd = d.dirs.(flds{ct});
    if ~isfolder(fd)
        fprintf('WARNING: folder not found: %s\n', fd); 
        answer = questdlg({'Would you like to create:', fd}, ...
            'FOLDER NOT FOUND!', 'Yes', 'No', 'No');      
        if strcmp(answer, 'Yes')
            mkdir(fd);
            addpath(fd);
            fprintf('%s was created and added to path\n', fd);
        end
    else
        tf_path = contains(PathStr, fd, 'IgnoreCase', ispc);
        if ~tf_path
            addpath(fd);
            fprintf('%s was added to the Matlab path\n', fd);
        end
    end
end

% ************************************************************************
%                DYNAMIC MULTI-WMO SPROF FILE CHECK
% ************************************************************************
% Target WMO IDs
d.wmoList = [1902800, 2904010, 2904011, 3902693, 4903622, ...
             4903624, 4903625, 4903904, 6999992, 7901009, 7902327];

d.fileInfo = struct('WMO', [], 'FileName', '', 'FullPath', '', 'Status', '');

for i = 1:length(d.wmoList)
    wmoStr   = num2str(d.wmoList(i));
    fileName = sprintf('%s_Sprof.nc', wmoStr);
    
    % Candidate paths: Root SPROF directory vs WMO subfolder
    filePathRoot = fullfile(d.dirs.sprof, fileName);
    filePathSub  = fullfile(d.dirs.sprof, wmoStr, fileName);
    
    d.fileInfo(i).WMO      = d.wmoList(i);
    d.fileInfo(i).FileName = fileName;
    
    if isfile(filePathRoot)
        d.fileInfo(i).FullPath = filePathRoot;
        d.fileInfo(i).Status   = 'Found in Root';
    elseif isfile(filePathSub)
        d.fileInfo(i).FullPath = filePathSub;
        d.fileInfo(i).Status   = 'Found in Subfolder';
    else
        d.fileInfo(i).FullPath = '';
        d.fileInfo(i).Status   = 'Missing';
        fprintf('WARNING: Argo Sprof file missing for WMO %s (%s)\n', wmoStr, fileName);
    end
end

% Extract array of valid existing paths for fast reference inside SAGEv2 GUI
d.validFilePaths = {d.fileInfo(~strcmp({d.fileInfo.Status}, 'Missing')).FullPath}';

% ************************************************************************
%               AUTO-GENERATE QC LIST FILE IF MISSING
% ************************************************************************
qcFilePath = fullfile(d.dirs.QClists, d.dirs.QClog_fn);

% Check fallback directory if main location missing
if ~isfile(qcFilePath)
    qcFilePathFallback = fullfile(d.dirs.QClog, d.dirs.QClog_fn);
    if isfile(qcFilePathFallback)
        qcFilePath = qcFilePathFallback;
    end
end

if ~isfile(qcFilePath)
    fprintf('Float QC Log file missing. Generating default QC list at:\n  %s\n', qcFilePath);
    
    % Ensure target directory exists
    if ~isfolder(d.dirs.QClists)
        mkdir(d.dirs.QClists);
    end
    
    % Open file for writing
    fid = fopen(qcFilePath, 'w');
    if fid ~= -1
        % Standard SAGE / ARGO QC Log Header
        fprintf(fid, 'WMO\tDAC\tStatus\tNotes\n');
        
        % Write entry for each WMO in the list
        for k = 1:length(d.wmoList)
            fprintf(fid, '%d\taoml\tUNREVIEWED\tAuto-generated by sageV2_init\n', d.wmoList(k));
        end
        fclose(fid);
        fprintf('Successfully created %s with %d WMO entries.\n', d.dirs.QClog_fn, length(d.wmoList));
    else
        warning('Could not create QC Log file at: %s', qcFilePath);
    end
else
    fprintf('QC Log file verified: %s\n', qcFilePath);
end

% Store actual QC log full path in struct for reference
d.dirs.QClog_fullfile = qcFilePath;

% ************************************************************************
%                      ERROR LIMITS & CONFIGURATION
% ************************************************************************
d.error_limits.Nitrate = 0.3; % SAGE limits
d.error_limits.pH      = 0.004;
d.sig_level            = 0.25;

% ************************************************************************
%                      DATA LOOKUP INITIALIZATION
% ************************************************************************
% Provide default empty structures required by startupFcn when datasets are missing
% Provide default empty mlist structure with valid cell dimensions
d.mlist = struct('hdr', {{}}, 'list', {cell(0,3)});
d.bottle_lookup = struct(); 

% ************************************************************************
%                       GUI APP OBJECT PROPS
% ************************************************************************
if nargin > 0 && ~isempty(app)
    % Initialize app.colors structure safely if it doesn't exist or isn't a struct
    if ~isprop(app, 'colors') || ~isstruct(app.colors)
        app.colors = struct();
    end
    
    % Assign required GUI color definitions
    app.colors.ora = [1.0, 0.5, 0.0]; % Orange
    app.colors.grn = [0.0, 0.8, 0.2]; % Green
    app.colors.red = [0.8, 0.1, 0.1]; % Red
end

end