-- extract time sections from srt file to current file

local M = {}

-- Function to read and split SRT file by blank lines
local function read_srt_file(file_path)
	-- Open the file for reading
	local file = io.open(file_path, "r")

	-- Check if file was opened successfully
	if not file then
		vim.notify("Error: Could not open file " .. file_path, vim.log.levels.ERROR)
		return nil
	end

	-- Read the entire file content
	local content = file:read("*a")
	file:close()

	-- Split the content by blank lines (two consecutive newlines)
	-- This will separate each subtitle entry
	local entries = {}
	for entry in content:gmatch("(.-)\n\n") do
		table.insert(entries, entry)
	end

	-- Handle the last entry which might not have trailing newlines
	local last_entry = content:match("\n\n(.-)$")
	if last_entry and #last_entry > 0 then
		table.insert(entries, last_entry)
	end

	return entries
end

local function to_sec(hms)
	local h, m, s, ms = hms:match("(%d+):(%d+):(%d+),(%d+)")
	return h * 3600 + m * 60 + s + ms / 1000
end

local function get_section(entry)
	local time = entry[2]
	-- 00:00:00,000 --> 00:00:06,240
	local time1, time2 = time:match("(%d+:%d+:%d+,%d*) %--> (%d+:%d+:%d+,%d+)")
	local sec1, sec2 = to_sec(time1), to_sec(time2)
	return sec1, sec2
end

-- entry needs to be a table
local function bulid_element(path, entry)
	local time1, time2 = get_section(entry)
	local sentence = entry[3]

	return '["' .. path .. '" ; (' .. time1 .. ":" .. time2 .. ")]" .. "\n" .. sentence
end

function M.find_srt_path(video_path)
	local dir, base = video_path:match("^(.*)[/\\]([^/\\]+)%.%w+$")
	if not dir then
		return nil
	end

	-- scan dir
	local handle = vim.loop.fs_scandir(dir)
	if not handle then
		return nil
	end

	while true do
		local name, t = vim.loop.fs_scandir_next(handle)
		if not name then
			break
		end
		if t == "file" and name:lower():sub(-4) == ".srt" then
			-- 3. 主干名相同就命中
			local name_base = name:match("^([^/\\]+)%.srt$")
			if name_base == base then
				return dir .. "/" .. name
			end
		end
	end
	return nil
end

function M.extract(video_path)
	local srt_file_path = M.find_srt_path(video_path)
	local srt_entries = read_srt_file(srt_file_path)

	local result = {}

	-- check srt entries
	if not srt_entries then
		vim.notify("Failed to read srt file", vim.log.levels.ERROR)
		return
	end

	for i = 1, #srt_entries do
		local lines = {}
		for entry in srt_entries[i]:gmatch("[^\r\n]+") do
			table.insert(lines, entry)
		end

		local element = bulid_element(video_path, lines)
		table.insert(result, element)
	end

	vim.notify("extract done", vim.log.levels.INFO)

	-- write to file
	local current_buf_path = vim.api.nvim_buf_get_name(0)
	local current_buf = io.open(current_buf_path, "a+")
	if not current_buf then
		return
	end
	current_buf:write(table.concat(result, "\n\n"))
	current_buf:close()
end

return M
