local M = {}
local command = vim.api.nvim_create_user_command

M.config = {
	-- When set, use an externally managed mpv socket. When nil, MpvNote creates
	-- a temporary socket whenever it launches mpv itself.
	socket = nil,
	clipboard_cmd = "wl-copy",
	width = nil,
	height = nil,
}

M.state = {
	socket = nil,
	job_id = nil,
	path = nil,
}

local function get_socket()
	return M.state.socket or M.config.socket
end

local function socket_exists(socket)
	if not socket then
		return false
	end

	local stat = vim.loop.fs_stat(socket)
	return stat and stat.type == "socket"
end

local function cleanup_session(job_id, socket)
	-- Always clean up the socket belonging to this process, even if another
	-- managed mpv instance has become the active instance since then.
	if socket then
		vim.loop.fs_unlink(socket)
	end

	if job_id and M.state.job_id ~= job_id then
		return
	end

	M.state.job_id = nil
	M.state.socket = nil
	M.state.path = nil
end

-- Execute a command in the active mpv instance via JSON IPC.
function M.mpv_command(cmd_data)
	local socket = get_socket()
	if not socket then
		vim.notify("MpvNote: no mpv IPC socket configured or running", vim.log.levels.WARN)
		return ""
	end

	local json_cmd = vim.fn.json_encode(cmd_data)
	local cmd = string.format("printf '%%s\\n' %q | socat - %q", json_cmd, socket)
	return vim.fn.system(cmd)
end

local function wait_for_mpv_socket(socket, timeout)
	local wait_time = 0
	local interval = 0.1
	local max_time = timeout or 3

	while wait_time < max_time do
		if socket_exists(socket) then
			local result = M.mpv_command({ command = { "get_property", "time-pos" } })
			if result and result ~= "" and not result:match("Connection refused") then
				return true
			end
		end

	vim.wait(interval * 1000)
		wait_time = wait_time + interval
	end

	return false
end

local function resolve_mpv()
	local mpv = vim.fn.exepath("mpv")
	if mpv == "" then
		vim.notify("MpvNote: mpv executable not found in PATH", vim.log.levels.ERROR)
		return nil
	end
	return mpv
end

-- Start an mpv instance owned by MpvNote.
local function start_mpv(path, args)
	local mpv = resolve_mpv()
	if not mpv then
		return false
	end

	local socket = vim.fn.tempname() .. ".sock"
	local argv = { mpv, "--input-ipc-server=" .. socket }

	for _, arg in ipairs(args or {}) do
		table.insert(argv, arg)
	end

	table.insert(argv, "--")
	table.insert(argv, path)

	M.state.socket = socket
	M.state.path = path

	local job_id = vim.fn.jobstart(argv, {
		detach = false,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				cleanup_session(job_id, socket)
				if exit_code ~= 0 then
					vim.notify(string.format("MpvNote: mpv exited with code %d", exit_code), vim.log.levels.WARN)
				end
			end)
		end,
	})

	if job_id <= 0 then
		cleanup_session(nil, socket)
		vim.notify("MpvNote: failed to start mpv", vim.log.levels.ERROR)
		return false
	end

	M.state.job_id = job_id

	if not wait_for_mpv_socket(socket, 3) then
		vim.fn.jobstop(job_id)
		cleanup_session(job_id, socket)
		vim.notify("MpvNote: mpv IPC socket did not become available", vim.log.levels.ERROR)
		return false
	end

	return true
end

-- Open media in a plugin-managed mpv instance.
function M.open(path, opts)
	if not path or path == "" then
		vim.notify("MpvNote: media path is required", vim.log.levels.ERROR)
		return false
	end

	path = vim.fn.expand(path)
	opts = opts or {}

	if M.config.socket then
		M.state.socket = M.config.socket
		M.state.path = path
		local socket = M.config.socket
		if not socket_exists(socket) then
			vim.notify("MpvNote: configured IPC socket does not exist", vim.log.levels.ERROR)
			return false
		end
		M.mpv_command({ command = { "loadfile", path, "replace" } })
		return true
	end

	-- Each managed launch gets its own socket. Do not reuse a previous one.
	return start_mpv(path, opts.args)
end

local function ensure_mpv(path)
	local socket = get_socket()
	if socket_exists(socket) then
		return true
	end

	if path then
		return start_mpv(path)
	end

	vim.notify("MpvNote: mpv server not running", vim.log.levels.WARN)
	return false
end

local function extract_data(response)
	local ok, parsed = pcall(vim.fn.json_decode, response)
	if not ok then
		vim.notify("JSON extract failed: " .. response, vim.log.levels.ERROR)
		return nil
	end

	return parsed.data
end

local function get_timestamp(mode)
	local socket = get_socket()
	if not socket or not socket_exists(socket) then
		vim.notify("mpv server not running", vim.log.levels.WARN)
		return nil
	end

	local time_result = M.mpv_command({ command = { "get_property", "time-pos" }, log = false })
	local path_result = M.mpv_command({ command = { "get_property", "path" }, log = false })

	if time_result:match("Connection refused") or path_result:match("Connection refused") then
		vim.notify("mpv server not running", vim.log.levels.WARN)
		return nil
	end

	local time = extract_data(time_result)
	local path = extract_data(path_result)

	if not mode and path then
		local home_dir = os.getenv("HOME")
		if home_dir and path:sub(1, #home_dir) == home_dir then
			path = "~" .. path:sub(#home_dir + 1)
		end
	end

	return {
		time = time,
		path = path,
	}
end

local function parse_stamp_line(line)
	local mode = "stamp"
	local path, time = line:match('%["(.-)"%s*;%s*(%d+%.?%d*)%]')

	if not time then
		mode = "section"
		path, time = line:match('%["(.-)"%s*;%s*%((%d+%.?%d*:%d+%.?%d*)%)%]')
	end

	if not path or not time then
		vim.notify('format not matched: ["path" ; time] or ["path" ; (time:time)]', vim.log.levels.WARN)
		return nil, nil
	end

	if path:sub(1, 1) == "~" then
		local home = os.getenv("HOME")
		if home then
			path = home .. path:sub(2)
		end
	end

	local stat = vim.loop.fs_stat(path)
	if not (stat and stat.type == "file") then
		vim.notify("file not found: " .. path, vim.log.levels.ERROR)
		return nil, nil
	end

	return path, time, mode
end

local function open_temp()
	local path, time, mode = parse_stamp_line(vim.api.nvim_get_current_line())
	if not path or not time then
		return
	end

	if not ensure_mpv(path) then
		return
	end

	-- If the current mpv instance is alive, load the referenced media into it.
	-- A newly started instance already has the requested media loaded.
	if M.state.path ~= path then
		M.mpv_command({ command = { "loadfile", path, "replace" } })
		M.state.path = path
	end

	if mode == "stamp" then
		time = tonumber(time)
		M.mpv_command({ command = { "set_property", "pause", true } })
		M.mpv_command({ command = { "seek", time, "absolute" } })
		M.mpv_command({ command = { "set_property", "pause", false } })
	elseif mode == "section" then
		local time1, time2 = time:match("(%d+%.?%d*):(%d+%.?%d*)")
		time1, time2 = tonumber(time1), tonumber(time2)
		M.mpv_command({ command = { "set_property", "pause", true } })
		M.mpv_command({ command = { "seek", time1, "absolute" } })
		M.mpv_command({ command = { "set_property", "ab-loop-a", time1 } })
		M.mpv_command({ command = { "set_property", "ab-loop-b", time2 } })
		M.mpv_command({ command = { "set_property", "pause", false } })
	end

	vim.notify(string.format("Playing: %s @ %s", path, time), vim.log.levels.INFO)
end

local function get_image_size(path)
	local cmd =
		string.format("ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 %q", path)
	local output = vim.fn.system(cmd)
	local width, height = output:match("(%d+)x(%d+)")
	if width and height then
		return tonumber(width), tonumber(height)
	end
	return nil, nil
end

local function MpvHover()
	local path, time, mode = parse_stamp_line(vim.api.nvim_get_current_line())
	if not path then
		return
	end

	if mode == "stamp" then
		time = tonumber(time)
	else
		time = tonumber(time:match("(%d+%.?%d*):%d+%.?%d*"))
	end

	local seacks_ok, snacks = pcall(require, "snacks")
	if not seacks_ok then
		vim.notify("Snacks.nvim not found", vim.log.levels.ERROR)
		return
	end

	local cache_dir = vim.fn.stdpath("cache") .. "/mpvhover"
	local filename = "mpvhover_" .. tostring(os.time()) .. ".png"
	local image_path = cache_dir .. "/" .. filename

	if vim.fn.isdirectory(cache_dir) == 0 then
		vim.fn.mkdir(cache_dir, "p")
	end

	local ffmpeg_cmd =
		string.format('ffmpeg -y -ss %s -i "%s" -vframes 1 -q:v 2 "%s" 2>/dev/null', time, path, image_path)
	os.execute(ffmpeg_cmd)

	local img_stat = vim.loop.fs_stat(image_path)
	if not (img_stat and img_stat.type == "file") then
		vim.notify("Failed to generate png image", vim.log.levels.ERROR)
		return
	end

	local float_buf = vim.api.nvim_create_buf(false, true)
	local opts = {
		relative = "cursor",
		row = 1,
		col = 1,
		width = 1,
		height = 1,
		focusable = false,
		style = "minimal",
		border = "rounded",
	}
	local image_width, image_height = get_image_size(image_path)
	opts.width = M.width or math.floor(image_width / 30)
	opts.height = M.height or math.floor(image_height / 60)

	local float_win = vim.api.nvim_open_win(float_buf, false, opts)
	snacks.image.placement.new(float_buf, image_path, { inline = true, ops = { 1, 0 } })
	vim.api.nvim_buf_set_option(float_buf, "modifiable", true)

	vim.api.nvim_create_autocmd({ "CursorMoved", "BufUnload" }, {
		group = vim.api.nvim_create_augroup("MpvNoteHover", { clear = true }),
		once = true,
		callback = function()
			if float_win and vim.api.nvim_win_is_valid(float_win) then
				vim.api.nvim_win_close(float_win, { force = true })
				float_win = nil
			end
			if float_buf and vim.api.nvim_buf_is_valid(float_buf) then
				vim.api.nvim_buf_delete(float_buf, { force = true })
				float_buf = nil
			end
			if image_path then
				os.remove(image_path)
				image_path = nil
			end
		end,
	})
end

function M.pasteImage()
	local path, time, mode = parse_stamp_line(vim.api.nvim_get_current_line())
	if not path then
		return
	end

	local time_num = mode == "stamp" and tonumber(time) or tonumber(time:match("(%d+%.?%d*):%d+%.?%d*"))
	local cache_dir = vim.fn.stdpath("cache") .. "/mpvhover/pasted"
	local filename = "mpvhover_" .. tostring(os.time()) .. ".png"
	local image_path = cache_dir .. "/" .. filename

	if vim.fn.isdirectory(cache_dir) == 0 then
		vim.fn.mkdir(cache_dir, "p")
	end

	local ffmpeg_cmd =
		string.format('ffmpeg -y -ss %s -i "%s" -vframes 1 -q:v 2 "%s" 2>/dev/null', time_num, path, image_path)
	os.execute(ffmpeg_cmd)

	local img_stat = vim.loop.fs_stat(image_path)
	if not (img_stat and img_stat.type == "file") then
		vim.notify("Failed to generate png image", vim.log.levels.ERROR)
		return
	end

	local output
	if mode == "stamp" then
		output = string.format('!["%s" ; %s](%s)', path, time, image_path)
	else
		output = string.format('!["%s" ; (%s)](%s)', path, time, image_path)
	end

	local row = vim.api.nvim_win_get_cursor(0)[1]
	vim.api.nvim_buf_set_lines(0, row - 1, row, false, { output })
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	command("MpvNoteOpen", function(opts_cmd)
		M.open(opts_cmd.args)
	end, { nargs = 1, complete = "file", desc = "open media in a managed mpv instance" })

	command("MpvCopyStamp", function()
		local stamp = get_timestamp()
		if not (stamp and stamp.path and stamp.time) then
			return
		end

		local output = string.format('["%s" ; %.3f]', stamp.path, stamp.time)
		local copy_cmd = string.format("echo %q | %s", output, M.config.clipboard_cmd)
		vim.fn.system(copy_cmd)
		vim.notify("MpvNote: stamp copied", vim.log.levels.INFO)
	end, { desc = "copy mpv timestamp" })

	command("MpvPasteStamp", function()
		local stamp = get_timestamp()
		if not (stamp and stamp.path and stamp.time) then
			vim.notify("MpvNote: failed to get timestamp", vim.log.levels.WARN)
			return
		end

		local output = string.format('["%s" ; %.3f]', stamp.path, stamp.time)
		local row = vim.api.nvim_win_get_cursor(0)[1]
		vim.api.nvim_buf_set_lines(0, row, row, false, { output })
	end, { desc = "paste stamp at this position" })

	command("MpvOpenStamp", open_temp, { desc = "open stamped path in mpv" })
	command("MpvHover", MpvHover, { desc = "hover snapshot from stamp" })

	command("MpvTogglePause", function()
		M.mpv_command({ command = { "cycle", "pause" } })
	end, { desc = "toggle pause/play" })

	command("MpvPasteImage", function()
		M.pasteImage()
	end, { desc = "paste detected image" })

	command("MpvGetSrt", function()
		local stamp = get_timestamp(1)
		if not stamp then
			return
		end
		local srt = require("MpvNote.srt").find_srt_path(stamp.path)
		vim.notify(srt, vim.log.levels.INFO)
	end, { desc = "get srt path" })

	command("MpvExtractSrt", function()
		local stamp = get_timestamp(1)
		if not stamp then
			return
		end
		require("MpvNote.srt").extract(stamp.path)
	end, { desc = "Extract srt to current buf" })
end

return M
