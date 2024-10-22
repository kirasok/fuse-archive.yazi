local shell = os.getenv("SHELL") or ""
---@enum FUSE_ARCHIVE_RETURN_CODE
local FUSE_ARCHIVE_RETURN_CODE = {
	SUCCESS = 0, -- Success.
	ERROR_GENERIC = 1, -- Generic error code for: missing command line argument, \
	-- too many command line arguments, unknown option, mount point is not empty, etc.
	CREATE_MOUNT_POINT_FAILED = 10, -- Cannot create the mount point.
	OPEN_THE_ACHIVE_FILE_FAILED = 11, -- Cannot open the archive file.
	CREATE_CACHE_FILE_FAILED = 12, -- Cannot create the cache file.
	NOT_ENOUGH_TEMP_SPACE = 13, -- Cannot write to the cache file. This is most likely the indication that there is not enough temp space.
	ENCRYPTED_FILE_BUT_NOT_PASSWORD = 20, -- The archive contains an encrypted file, but no password was provided.
	ENCRYPTED_FILE_BUT_WRONG_PASSWORD = 21, -- The archive contains an encrypted file, and the provided password does not decrypt it.
	ENCRYPTED_METHOD_UNSUPPORTED = 22, -- The archive contains an encrypted file, and the encryption method is not supported.
	ARCHIVE_FORMAT_UNSUPPORTED = 30, -- Cannot recognize the archive format.
	ARCHIVE_HEADER_INVALID = 31, -- Invalid archive header.
	ARCHIVE_READ_PERMISSION_INVALID = 32, -- Cannot read and extract the archive.
}

---@enum FUSE_ARCHIVE_MOUNT_ERROR_MSG
local FUSE_ARCHIVE_MOUNT_ERROR_MSG = {
	[FUSE_ARCHIVE_RETURN_CODE.ERROR_GENERIC] = "Fuse-archive exited with error: %s", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.CREATE_MOUNT_POINT_FAILED] = "Can't create mount point %s, maybe you don't have permission", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.OPEN_THE_ACHIVE_FILE_FAILED] = "Can't open archive file, maybe you don't have permission", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.CREATE_CACHE_FILE_FAILED] = "Can't not create cache point or not enough space for cache, trying to disable cache opt, this would make thing much slower", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.NOT_ENOUGH_TEMP_SPACE] = "Can't not create cache point or not enough space for cache, trying to disable cache opt, this would make thing much slower", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_METHOD_UNSUPPORTED] = "Encrypted method is unsupported", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_WRONG_PASSWORD] = "Incorrect password, %s attempts remaining.", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_NOT_PASSWORD] = "Please enter password to unlock file,%s attempts remaining.", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_FORMAT_UNSUPPORTED] = "Unsupported this format file", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_HEADER_INVALID] = "Archive file is corrupted", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_READ_PERMISSION_INVALID] = "Can't open archive file, maybe you don't have permission",
}
---@enum YA_INPUT_EVENT
local YA_INPUT_EVENT = {
	ERROR = 0,
	CONFIRMED = 1,
	CANCELLED = 2,
	VALUE_CHANGED = 3,
}

---@enum Command.PIPED
---@enum Command.NULL
---@enum Command.INHERIT

---@type Command
local Command = _G.Command

---@class (exact) Command
---@overload fun(cmd: string): self
---@field PIPED Command.PIPED
---@field NULL Command.NULL
---@field INHERIT Command.INHERIT
---@field arg fun(self: Command, arg: string): self
---@field args fun(self: Command, args: string[]): self
---@field cwd fun(self: Command, dir: string): self
---@field env fun(self: Command, key: string, value: string): self
---@field stdin fun(self: Command, cfg: Command.PIPED | Command.NULL | Command.INHERIT| STD_STREAM): self
---@field stdout fun(self: Command, cfg: Command.PIPED | Command.NULL | Command.INHERIT| STD_STREAM): self
---@field stderr fun(self: Command, cfg: Command.PIPED | Command.NULL | Command.INHERIT| STD_STREAM): self
---@field spawn fun(self: Command): Child|nil, integer
---@field output fun(self: Command): Output|nil, integer
---@field status fun(self: Command): Status|nil, integer

---@alias STD_STREAM unknown

---@class (exact) Child
---@field read fun(self: Child, len: string): string, 1|0
---@field read_line fun(self: Child): string, 1|0
---@field read_line_with fun(self: Child, opts: {timeout: integer}): string, 1|2|3
---@field wait fun(self: Child): Status|nil, integer
---@field wait_with_output fun(self: Child): Output|nil, integer
---@field start_kill fun(self: Child): boolean, integer
--- stdin(Command.PIPED) is set
---@field take_stdin fun(self: Child): STD_STREAM|nil, integer
--- stdin(Command.PIPED) is set
---@field take_stdout fun(self: Child): STD_STREAM|nil, integer
--- stdin(Command.PIPED) is set
---@field take_stderr fun(self: Child): STD_STREAM|nil, integer
--- stdin(Command.PIPED) is set
--- take_stdin() has never been called
---@field write_all fun(self: Child, src: string): STD_STREAM|nil, integer
---@field flush fun(self: Child): STD_STREAM|nil, integer

---@class (exact) Output The Output of the command if successful; otherwise, nil
---@field status Status The Status of the child process
---@field stdout string The stdout of the child process, which is a string
---@field stderr string The stderr of the child process, which is a string

---@class (exact) Status The Status of the child process
---@field success boolean whether the child process exited successfully, which is a boolean.
---@field code integer the exit code of the child process, which is an integer if any

local function error(s, ...)
	ya.notify({ title = "fuse-archive", content = string.format(s, ...), timeout = 3, level = "error" })
end

local function info(s, ...)
	ya.notify({ title = "fuse-archive", content = string.format(s, ...), timeout = 3, level = "info" })
end

local set_state = ya.sync(function(state, archive, key, value)
	if state[archive] then
		state[archive][key] = value
	else
		state[archive] = {}
		state[archive][key] = value
	end
end)

local get_state = ya.sync(function(state, archive, key)
	if state[archive] then
		return state[archive][key]
	else
		return nil
	end
end)

local function path_quote(path)
	local result = "'" .. string.gsub(path, "'", "'\\''") .. "'"
	return result
end

local is_mount_point = ya.sync(function(state)
	local dir = cx.active.current.cwd:name()
	for archive, _ in pairs(state) do
		if archive == dir then
			return true
		end
	end
	return false
end)

local current_file = ya.sync(function()
	local h = cx.active.current.hovered
	if h then
		return h.name
	else
		return nil
	end
end)

local current_dir = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local current_dir_name = ya.sync(function()
	return cx.active.current.cwd:name()
end)

local enter = ya.sync(function()
	local h = cx.active.current.hovered
	if h then
		if h.cha.is_dir then
			ya.manager_emit("enter", {})
		else
			if get_state("global", "smart_enter") then
				ya.manager_emit("open", { hovered = true })
			else
				ya.manager_emit("enter", {})
			end
		end
	end
end)

---run any command
---@param cmd string
---@param args string[]
---@param _stdin? STD_STREAM|nil
---@return integer|nil, Output|nil
local function run_command(cmd, args, _stdin)
	local cwd = current_dir()
	local stdin = _stdin or Command.INHERIT
	local child, cmd_err =
		Command(cmd):args(args):cwd(cwd):stdin(stdin):stdout(Command.PIPED):stderr(Command.INHERIT):spawn()

	if not child then
		error("Spawn " .. cmd .. " failed with error code %s", cmd_err)
		return cmd_err, nil
	end

	local output, out_err = child:wait_with_output()
	if not output then
		error("Cannot read " .. cmd .. " output, error code %s", out_err)
		return out_err, nil
	else
		return nil, output
	end
end

local is_mounted = function(dir_path)
	local cmd_err_code, res = run_command(shell, { "-c", "mountpoint -q " .. path_quote(dir_path) })
	if cmd_err_code or res == nil or res.status.code ~= 0 then
		-- case error, or mountpoint command not found
		return false
	end
	return res and res.status.success
end

local valid_extension = ya.sync(function()
	local h = cx.active.current.hovered
	if h then
		if h.cha.is_dir then
			return false
		end
		local valid_extensions = {
			"zip",
			"gz",
			"bz2",
			"tar",
			"tgz",
			"tbz2",
			"txz",
			"xz",
			"tzs",
			"zst",
			"iso",
			"rar",
			"7z",
			"cpio",
			"lz",
			"lzma",
			"shar",
			"a",
			"ar",
			"apk",
			"jar",
			"xpi",
			"cab",
		}
		local file_extention = h.url.ext(h.url)
		for _, ext in ipairs(valid_extensions) do
			if ext == file_extention then
				return true
			end
		end
		return false
	else
		return false
	end
end)

---Get the fuse mount point
---@return string|nil
local fuse_dir = function()
	local fuse_mount_point = "/tmp" .. "/yazi/fuse-archive"
	local _, _, exit_code = os.execute("mkdir -p " .. ya.quote(fuse_mount_point))
	if exit_code ~= 0 then
		error("Cannot create mount point %s", fuse_mount_point)
		return
	end
	return fuse_mount_point
end

--- return a string array with unique value
---@param tbl string[]
---@return string[] table with only unique strings
function tbl_unique_strings(tbl)
	local unique_table = {}
	local seen = {}

	for _, str in ipairs(tbl) do
		if not seen[str] then
			seen[str] = true
			table.insert(unique_table, str)
		end
	end

	return unique_table
end

---
---@param file string file path
---@return string|nil
local function get_mount_path(file)
	local fuse_mount_point = get_state("global", "fuse_dir")
	if not fuse_mount_point then
		return
	end
	local tmp_path = fuse_mount_point .. "/" .. file
	return tmp_path
end

---Show password input dialog
---@return boolean cancelled, string password
local function show_ask_pw_dialog()
	---TODO: update this with input password (*******)
	local passphrase = ""
	local cancelled = false
	-- Asking user to input the password
	local input_pw = ya.input({
		title = "Enter password to unlock:",
		position = { "center", x = 0, y = 0, w = 50, h = 3 },
		realtime = true,
	})

	while true do
		---@type string, YA_INPUT_EVENT
		local value, ev = input_pw:recv()
		if ev == YA_INPUT_EVENT.CONFIRMED then
			passphrase = value or ""
			break
		elseif ev == YA_INPUT_EVENT.CANCELLED then
			passphrase = ""
			cancelled = true
			break
		end
	end
	return cancelled, passphrase
end

---mount fuse
---@param opts {archive_path: string, fuse_mount_point: string, mount_opts: string[], passphrase?: string, max_retry?: integer, retries?: integer}
---@return boolean
local function mount_fuse(opts)
	local archive_path = opts.archive_path
	local fuse_mount_point = opts.fuse_mount_point
	local mount_opts = opts.mount_opts
	local passphrase = opts.passphrase
	local max_retry = opts.max_retry or 3
	local retries = opts.retries or 0
	local ignore_global_error_notify = false
	local payload_error_notify = {}

	if is_mounted(opts.fuse_mount_point) then
		return true
	end
	local passpharase_stdin = Command.PIPED
	mount_opts = tbl_unique_strings({ "auto_unmount", "use_ino", "readdir_ino", table.unpack(mount_opts or {}) })

	-- show notify + exit after too many attempts to mount

	if passphrase then
		passpharase_stdin = Command("echo")
			:arg(path_quote(passphrase))
			:stderr(Command.PIPED)
			:stdout(Command.PIPED)
			:spawn()
			:take_stdout()
	end
	local res, _ = Command(shell)
		:args({
			"-c",
			"fuse-archive -o "
				.. table.concat(mount_opts, ",")
				.. " "
				.. path_quote(archive_path)
				.. " "
				.. path_quote(fuse_mount_point),
		})
		:stderr(Command.PIPED)
		:stdin(passpharase_stdin)
		:stdout(Command.NULL)
		:output()

	local fuse_mount_res_code

	-- already mounted, so stop re-mount
	if res then
		if res.stderr and res.stderr:find("mountpoint is not empty") then
			return true
		end
		fuse_mount_res_code = res.status.code
	end

	if fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.SUCCESS then
		return true
	elseif fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ERROR_GENERIC then
		payload_error_notify = { fuse_mount_res_code }
	elseif fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.CREATE_MOUNT_POINT_FAILED then
		payload_error_notify = { fuse_mount_point }
	elseif
		fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.NOT_ENOUGH_TEMP_SPACE
		or fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.CREATE_CACHE_FILE_FAILED
	then
		-- disable cache
		table.insert(mount_opts, "nocache")
	elseif
		fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_NOT_PASSWORD
		or fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_WRONG_PASSWORD
	then
		ignore_global_error_notify = true
		-- Too many attempts
		if retries == max_retry then
			return false
		end
		if retries == 0 then
			-- First time ask for password dialog shown up
			info(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], max_retry - retries)
		else
			error(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], max_retry - retries)
		end
		local cancelled, pw = show_ask_pw_dialog()
		if not cancelled then
			passphrase = pw
		else
			return false
		end
	end

	--show retry notification
	if retries >= max_retry or not ignore_global_error_notify then
		if FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code] then
			error(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], table.unpack(payload_error_notify))
		end
		return false
	end
	-- Increase retries every run
	retries = retries + 1
	return mount_fuse({
		archive_path = archive_path,
		fuse_mount_point = fuse_mount_point,
		mount_opts = mount_opts,
		passphrase = passphrase,
		retries = retries,
		max_retry = max_retry,
	})
end

---Mount path using inode (unique for each files)
---e.g. /tmp/yazi/fuse-archive/test.zip.tmp.11675995
---@param path string
---@return string|nil
local function tmp_file_name(path)
	local cmd_err_code, res = run_command(shell, { "-c", "xxh128sum -q " .. path_quote("./" .. path) })
	if cmd_err_code or res == nil or res.status.code ~= 0 then
		error("Cannot create unique path of file %s", path)
		return nil
	end
	local hashed_name = res.stdout:match("^(%S+)")
	return path .. ".tmp." .. hashed_name
end

local function setup(_, opts)
	local fuse = fuse_dir()
	set_state("global", "fuse_dir", fuse)
	if opts and opts.smart_enter then
		set_state("global", "smart_enter", true)
	else
		set_state("global", "smart_enter", false)
	end
end

return {
	entry = function(_, args)
		local action = args[1]
		if not action then
			return
		end

		if action == "mount" then
			local file = current_file()
			if file == nil then
				return
			end
			if not valid_extension() then
				enter()
				return
			end
			local tmp_file_name = tmp_file_name(file)
			local tmp_file_path = get_mount_path(tmp_file_name)

			if tmp_file_path then
				local success = mount_fuse({
					archive_path = "./" .. file,
					fuse_mount_point = tmp_file_path,
				})
				if success then
					set_state(tmp_file_name, "cwd", current_dir())
					set_state(tmp_file_name, "tmp", tmp_file_path)
					ya.manager_emit("cd", { tmp_file_path })
					ya.manager_emit("enter", {})
				end
			end
			-- leave without unmount
		elseif action == "leave" then
			if not is_mount_point() then
				ya.manager_emit("leave", {})
				return
			end
			local file = current_dir_name()
			-- local tmp_file = get_state(file, "tmp")
			ya.manager_emit("cd", { get_state(file, "cwd") })
			return
		elseif action == "unmount" then
			if not is_mount_point() then
				ya.manager_emit("leave", {})
				return
			end
			local file = current_dir_name()
			local tmp_file = get_state(file, "tmp")
			ya.manager_emit("cd", { get_state(file, "cwd") })

			local cmd_err_code, res = run_command(shell, { "-c", "umount " .. path_quote(tmp_file) })
			if cmd_err_code or res and not res.status.success then
				error("Unable to unmount %s", tmp_file)
			end
			return
		end
	end,
	setup = setup,
}
