%% --- Environment Setup ---
matlabDir = fullfile('C:', 'Users', 'Jennifer.McWhorter', 'Documents', 'MATLAB');

% Define key directories
appsDir = fullfile(matlabDir, 'Apps');
dataDir = fullfile(matlabDir, 'ARGO', 'DATA', 'SPROF');

% Add paths cleanly to MATLAB search path
addpath(genpath(appsDir), '-end');
addpath(genpath(dataDir), '-end');
addpath(matlabDir, '-end');

%% --- Parameters ---
% Array of numeric WMO IDs
wmoList = [1902800, 2904010, 2904011, 3902693, 4903622, ...
           4903624, 4903625, 4903904, 6999992, 7901009, 7902327];

% Pre-allocate a structure array to store results
fileInfo = struct('WMO', [], 'FileName', '', 'FullPath', '', 'Status', '');

%% --- Dynamic Search Loop ---
fprintf('\n================ Scanning Argo Sprof Files ================\n');

for i = 1:length(wmoList)
    % Ensure WMO ID is formatted as a clean string (e.g., '1902800')
    wmoStr = num2str(wmoList(i));
    fileName = sprintf('%s_Sprof.nc', wmoStr);
    
    % Define candidate paths (root SPROF directory vs. WMO subfolder)
    filePathRoot = fullfile(dataDir, fileName);
    filePathSub  = fullfile(dataDir, wmoStr, fileName);
    
    % Store base info
    fileInfo(i).WMO = wmoList(i);
    fileInfo(i).FileName = fileName;
    
    % Check file existence
    if isfile(filePathRoot)
        fileInfo(i).FullPath = filePathRoot;
        fileInfo(i).Status   = 'Found in Root';
        fprintf('[FOUND] WMO %s -> %s\n', wmoStr, filePathRoot);
        
    elseif isfile(filePathSub)
        fileInfo(i).FullPath = filePathSub;
        fileInfo(i).Status   = 'Found in Subfolder';
        fprintf('[FOUND] WMO %s -> %s\n', wmoStr, filePathSub);
        
    else
        fileInfo(i).FullPath = '';
        fileInfo(i).Status   = 'Missing';
        fprintf('[MISSING] WMO %s -> File %s not found\n', wmoStr, fileName);
    end
end

fprintf('===========================================================\n\n');

%% --- Summary Table ---
% Display results cleanly in the Command Window
summaryTable = struct2table(fileInfo);
disp(summaryTable(:, {'WMO', 'Status', 'FileName'}));

% Extract only valid, existing file paths for further processing
existingFiles = {fileInfo(strcmp({fileInfo.Status}, 'Missing') == 0).FullPath}';