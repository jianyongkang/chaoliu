function ctx = init_env()
%INIT_ENV Prepare repository paths and verify MATPOWER/MOST availability.

src_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(src_dir);

ctx = struct();
ctx.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
ctx.root_dir = root_dir;
ctx.data_dir = fullfile(root_dir, 'data');
ctx.src_dir = src_dir;
ctx.results_dir = fullfile(root_dir, 'results');
ctx.logs_dir = fullfile(ctx.results_dir, 'logs');
ctx.mats_dir = fullfile(ctx.results_dir, 'mats');
ctx.tables_dir = fullfile(ctx.results_dir, 'tables');
ctx.figures_dir = fullfile(ctx.results_dir, 'figures');
ctx.temp_dir = fullfile(root_dir, 'temp');
ctx.case_name = 'case24_ieee_rts';

addpath(ctx.data_dir);
addpath(ctx.src_dir);

ensure_dir(ctx.results_dir);
ensure_dir(ctx.logs_dir);
ensure_dir(ctx.mats_dir);
ensure_dir(ctx.tables_dir);
ensure_dir(ctx.figures_dir);
ensure_dir(ctx.temp_dir);

ctx.matpower_added_from_env = false;
if ~has_matpower_core()
    matpower_dir = getenv('MATPOWER_DIR');
    if ~isempty(matpower_dir) && isfolder(matpower_dir)
        addpath(genpath(matpower_dir));
        ctx.matpower_added_from_env = true;
    end
end

ctx.has_matpower = has_matpower_core();
if ~ctx.has_matpower
    error('init_env:MissingMATPOWER', ...
        ['MATPOWER core functions were not found on the MATLAB path. ', ...
         'Start MATLAB/Octave with MATPOWER enabled or set MATPOWER_DIR ', ...
         'before calling init_env().']);
end

ctx.has_most = exist('most', 'file') == 2 && exist('loadmd', 'file') == 2;
ctx.matpower_root = infer_matpower_root();
ctx.matpower_version = query_version('mpver');
ctx.most_version = 'not available';
if ctx.has_most
    ctx.most_version = query_version('mostver');
end

try
    case_data = loadcase(ctx.case_name);
    ctx.case_ready = isstruct(case_data);
catch me
    error('init_env:MissingCase', ...
        'Unable to load %s from MATPOWER: %s', ctx.case_name, me.message);
end

ctx.base_total_load_mw = safe_sum(case_data.bus(:, 3));
ctx.num_buses = size(case_data.bus, 1);
ctx.num_gens = size(case_data.gen, 1);
ctx.num_branches = size(case_data.branch, 1);

ctx.mpopt = mpoption('verbose', 1, 'out.all', 0);
ctx.mpopt_pf = ctx.mpopt;
ctx.mpopt_opf = ctx.mpopt;
if ctx.has_most
    ctx.mpopt_most = mpoption(ctx.mpopt, ...
        'model', 'DC', ...
        'most.solver', 'DEFAULT', ...
        'most.uc.run', 0);
else
    ctx.mpopt_most = mpoption(ctx.mpopt, 'model', 'DC');
end

log_lines = {
    'MATPOWER/MOST environment initialized'
    ['timestamp: ', ctx.timestamp]
    ['root_dir: ', ctx.root_dir]
    ['case_name: ', ctx.case_name]
    ['matpower_root: ', ctx.matpower_root]
    ['matpower_version: ', ctx.matpower_version]
    ['most_available: ', logical_to_text(ctx.has_most)]
    ['most_version: ', ctx.most_version]
    ['matpower_added_from_env: ', logical_to_text(ctx.matpower_added_from_env)]
    ['num_buses: ', num2str(ctx.num_buses)]
    ['num_gens: ', num2str(ctx.num_gens)]
    ['num_branches: ', num2str(ctx.num_branches)]
    ['base_total_load_mw: ', sprintf('%.2f', ctx.base_total_load_mw)]
    ['logs_dir: ', ctx.logs_dir]
    ['mats_dir: ', ctx.mats_dir]
    ['tables_dir: ', ctx.tables_dir]
    ['figures_dir: ', ctx.figures_dir]
};

write_text_log(fullfile(ctx.logs_dir, 'init_env_log.txt'), log_lines);
save(fullfile(ctx.mats_dir, 'init_env_context.mat'), 'ctx', '-v7');

if ~ctx.has_most
    warning('init_env:MissingMOST', ...
        ['MATPOWER was found, but MOST was not detected on the path. ', ...
         'PF/OPF scripts will work, but multi-period scenarios will fail until ', ...
         'MOST is available.']);
end
end

function tf = has_matpower_core()
tf = exist('loadcase', 'file') == 2 && ...
     exist('runpf', 'file') == 2 && ...
     exist('runopf', 'file') == 2 && ...
     exist('mpoption', 'file') == 2;
end

function ensure_dir(target_dir)
if ~exist(target_dir, 'dir')
    mkdir(target_dir);
end
end

function value = query_version(func_name)
value = 'unknown';
if exist(func_name, 'file') ~= 2
    return;
end
try
    out = feval(func_name);
    if isstruct(out)
        if isfield(out, 'Version')
            value = out.Version;
        elseif isfield(out, 'version')
            value = out.version;
        else
            value = 'available';
        end
    elseif ischar(out)
        value = out;
    end
catch
    value = 'available';
end
end

function root = infer_matpower_root()
root = '';
loadcase_path = which('loadcase');
if isempty(loadcase_path)
    return;
end
root = fileparts(fileparts(loadcase_path));
end

function txt = logical_to_text(tf)
if tf
    txt = 'true';
else
    txt = 'false';
end
end

function total = safe_sum(x)
if isempty(x)
    total = 0;
else
    total = sum(x(:));
end
end
