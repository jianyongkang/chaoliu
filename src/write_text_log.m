function write_text_log(file_path, lines)
%WRITE_TEXT_LOG Write a plain-text log file from a cell array of lines.

if ischar(lines)
    lines = {lines};
elseif isstring(lines)
    lines = cellstr(lines(:));
end

fid = fopen(file_path, 'w');
if fid == -1
    error('write_text_log:OpenFailed', ...
        'Unable to open log file for writing: %s', file_path);
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

for k = 1:numel(lines)
    fprintf(fid, '%s\n', lines{k});
end
end
