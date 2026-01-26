--- @since 25.5.31

local Log = {}
function Log.error(s, ...)
	ya.notify({ title = "fuse-archive", content = string.format(s, ...), timeout = 3, level = "error" })
end

function Log.info(s, ...)
	ya.notify({ title = "fuse-archive", content = string.format(s, ...), timeout = 3, level = "info" })
end

--- Copies a table recursively
---@generic T: table
---@param tbl T
---@return T
function table.deep_copy(tbl)
	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = table.deep_copy(v)
			setmetatable(copy[k], getmetatable(v))
		else
			copy[k] = v
		end
	end
	return copy
end

---@class fuse-archive.Set
local Set = {
	__name = "fuse-archive.Set"
}

--- Create set from table of values
--- Keys are discarded
---@param tbl any[]
---@return fuse-archive.Set
function Set.from_table(tbl)
	local set = {}
	for _, v in pairs(tbl) do
		set[v] = true
	end
	return setmetatable(set, Set)
end

--- Return a union of two sets
---@param other fuse-archive.Set
function Set:__bor(other)
	local combined = table.deep_copy(self)
	for k, _ in pairs(other) do
		combined[k] = other[k] or combined[k]
	end
	return combined
end

--- Return self \ other; a relative complement of other in respect to self
---@param other fuse-archive.Set
function Set:__shl(other)
	local combined = table.deep_copy(self)
	for k, _ in pairs(other) do
		combined[k] = other[k] and false
	end
	return combined
end

---@return any[]
function Set:__call()
	local values = {}
	for k, v in pairs(self) do
		if v then
			table.insert(values, k)
		end
	end
	return values
end

function Set:__len()
	return #self()
end

---@enum FUSE_ARCHIVE_RETURN_CODE
local FUSE_ARCHIVE_RETURN_CODE = {
	SUCCESS = 0,                           -- Success.
	ERROR_GENERIC = 1,                     -- Generic error code for: missing command line argument, \
	-- too many command line arguments, unknown option, mount point is not empty, etc.
	CREATE_MOUNT_POINT_FAILED = 10,        -- Cannot create the mount point.
	OPEN_THE_ACHIVE_FILE_FAILED = 11,      -- Cannot open the archive file.
	CREATE_CACHE_FILE_FAILED = 12,         -- Cannot create the cache file.
	NOT_ENOUGH_TEMP_SPACE = 13,            -- Cannot write to the cache file. This is most likely the indication that there is not enough temp space.
	ENCRYPTED_FILE_BUT_NOT_PASSWORD = 20,  -- The archive contains an encrypted file, but no password was provided.
	ENCRYPTED_FILE_BUT_WRONG_PASSWORD = 21, -- The archive contains an encrypted file, and the provided password does not decrypt it.
	ENCRYPTED_METHOD_UNSUPPORTED = 22,     -- The archive contains an encrypted file, and the encryption method is not supported.
	ARCHIVE_FORMAT_UNSUPPORTED = 30,       -- Cannot recognize the archive format.
	ARCHIVE_HEADER_INVALID = 31,           -- Invalid archive header.
	ARCHIVE_READ_PERMISSION_INVALID = 32,  -- Cannot read and extract the archive.
}

---@enum FUSE_ARCHIVE_MOUNT_ERROR_MSG
local FUSE_ARCHIVE_MOUNT_ERROR_MSG = {
	[FUSE_ARCHIVE_RETURN_CODE.ERROR_GENERIC] = "Fuse-archive exited with error: %s",                                             -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.CREATE_MOUNT_POINT_FAILED] = "Can't create mount point %s, maybe you don't have permission",       -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.OPEN_THE_ACHIVE_FILE_FAILED] = "Can't open archive file, maybe you don't have permission",         -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.CREATE_CACHE_FILE_FAILED] =
	"Can't not create cache point or not enough space for cache, trying to disable cache opt, this would make thing much slower", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.NOT_ENOUGH_TEMP_SPACE] =
	"Can't not create cache point or not enough space for cache, trying to disable cache opt, this would make thing much slower", -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_METHOD_UNSUPPORTED] = "Encrypted method is unsupported",                                 -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_WRONG_PASSWORD] = "Incorrect password, %s attempts remaining.",                 -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ENCRYPTED_FILE_BUT_NOT_PASSWORD] =
	"Please enter password to unlock file,%s attempts remaining.",                                                               -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_FORMAT_UNSUPPORTED] = "Unsupported this format file",                                      -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_HEADER_INVALID] = "Archive file is corrupted",                                             -- Success.
	[FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_READ_PERMISSION_INVALID] = "Can't open archive file, maybe you don't have permission",
}
---@enum YA_INPUT_EVENT
local YA_INPUT_EVENT = {
	ERROR = 0,
	CONFIRMED = 1,
	CANCELLED = 2,
	VALUE_CHANGED = 3,
}

local set_state = ya.sync(function(state, archive, key, value)
	if not state[archive] then
		state[archive] = {}
	end
	state[archive][key] = value
end)

local get_state = ya.sync(function(state, archive, key)
	if state[archive] then
		return state[archive][key]
	else
		return nil
	end
end)

---@class fuse-archive.OpenedFile
---@field cwd string
---@field tmp string

---@class fuse-archive.State
---@field mount_root_dir string
---@field smart_enter boolean
---@field valid_extensions fuse-archive.Set
---@field mount_options string[]
local State = setmetatable(
	{}, {
		_global = { "mount_root_dir", "smart_enter", "valid_extensions", "mount_options" },
		__index = function(t, k)
			for _, v in pairs(getmetatable(t)._global) do
				if k == v then
					return get_state("global", k)
				end
			end
			---@type fuse-archive.OpenedFile
			return { cwd = get_state(k, "cwd"), tmp = get_state(k, "tmp") }
		end,
		---@param v fuse-archive.OpenedFile
		__newindex = function(t, k, v)
			for _, v2 in pairs(getmetatable(t)._global) do
				if k == v2 then
					set_state("global", k, v)
					return
				end
			end
			set_state(k, "cwd", v.cwd)
			set_state(k, "tmp", v.tmp)
		end
	})

--- Escapes special characters of Lua Pattern
---@param str string
---@return string
local function is_literal_string(str)
	return str and str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- Removes trailing slash from path string
---@param path string
---@return string
local function path_remove_trailing_slash(path)
	return (path:gsub("^(.+)/$", "%1"))
end

---@type fun(): boolean
local is_mount_point = ya.sync(function(state)
	local dir = cx.active.current.cwd.name
	local cwd = tostring(cx.active.current.cwd)
	local match_pattern = "^" .. is_literal_string(State.mount_root_dir) .. "/[^/]+%.tmp%.[^/]+$"

	for archive, _ in pairs(state) do
		if archive == dir and string.match(cwd, match_pattern) then
			return true
		end
	end
	return false
end)

---@type fun(): Url|nil, boolean|nil
local current_file = ya.sync(function()
	local h = cx.active.current.hovered
	if not h then
		return
	end
	---@diagnostic disable-next-line: redundant-return-value
	return h.url, h.cha.is_dir
end)

---@type fun(): Url
local current_dir = ya.sync(function()
	return cx.active.current.cwd
end)

---@type fun(): string?
local current_dir_name = ya.sync(function()
	return cx.active.current.cwd.name
end)

--- Smart enter implementation
---@param is_dir boolean
local function enter(is_dir)
	if not State.smart_enter or is_dir then
		ya.emit("enter", {})
	else
		ya.emit("open", { hovered = true })
	end
end

--- Check if path is mounted
---@param path string
---@return boolean ok
local function is_mounted(path)
	local res, _ = Command("mountpoint"):arg { "-q ", ya.quote(path) }:output()
	return res and res.status.success or false
end

---@param input string
---@return string[]
local function split_by_space_or_comma(input)
	local result = {}
	for word in string.gmatch(input, "[^%s,]+") do
		table.insert(result, word)
	end
	return result
end

---Show password input dialog
---@return boolean ok, string password
local function show_ask_pw_dialog()
	-- Asking user to input the password
	local input_pw, event = ya.input({
		title = "Enter password to unlock:",
		obscure = true,
		pos = { "center", x = 0, y = 0, w = 50, h = 3 },
		position = { "center", x = 0, y = 0, w = 50, h = 3 },
	})
	return event == YA_INPUT_EVENT.CONFIRMED, input_pw or ""
end

---@type fun()
local redirect_mounted_tab_to_cwd = ya.sync(function(state, _)
	local match_pattern = "^" .. is_literal_string(State.mount_root_dir) .. "/[^/]+%.tmp%.[^/]+$"

	for _, tab in ipairs(cx.tabs) do
		local dir = tab.current.cwd.name
		local cwd = tostring(tab.current.cwd)

		for archive, value in pairs(state) do
			if archive == dir and string.match(cwd, match_pattern) then
				ya.emit("cd", {
					value.cwd,
					tab = (type(tab.id) == "number" or type(tab.id) == "string") and tab.id or tab.id.value,
					raw = true,
				})
				goto continue
			end
		end
		::continue::
	end
end)

---mount fuse
---@param opts {archive_path: Url, fuse_mount_point: Url, mount_options: string[], passphrase?: string, max_retry?: integer, retries?: integer}
---@return boolean
local function mount_fuse(opts)
	local archive_path = opts.archive_path
	local fuse_mount_point = opts.fuse_mount_point
	local mount_options = opts.mount_options or {}
	local passphrase = opts.passphrase
	local max_retry = opts.max_retry or 3
	local retries = opts.retries or 0
	local ignore_global_error_notify = false
	local payload_error_notify = {}

	if is_mounted(tostring(opts.fuse_mount_point)) then
		return true
	end

	local args = {
		tostring(archive_path),
		tostring(fuse_mount_point),
	}
	if opts.mount_options and #opts.mount_options > 0 then
		table.insert(args, 1, "-o")
		table.insert(args, 2,
			table.concat(opts.mount_options, ",")
		)
	end
	local res, _ = Command("fuse-archive")
			:arg(args)
			:stdin(Command.PIPED)
			:stderr(Command.PIPED)
			:stdout(Command.PIPED)
			:spawn()
	if res then
		if passphrase then
			res:write_all(passphrase)
			---@diagnostic disable-next-line: undefined-field
			res:flush() -- https://github.com/sxyazi/yazi/blob/face6aed40b37f86be4320bab934b2dcf98277fe/yazi-plugin/src/process/child.rs#L146
		end
		---@diagnostic disable-next-line: cast-local-type
		res, _ = res:wait_with_output()
	end

	local fuse_mount_res_code, fuse_mount_res_msg

	-- already mounted, so stop re-mount
	if res then
		if res.stderr and res.stderr:find("mountpoint is not empty") then
			return true
		end
		fuse_mount_res_code = res.status.code
		fuse_mount_res_msg = res.stderr
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
		table.insert(mount_options, "nocache")
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
			Log.info(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], max_retry - retries)
		else
			Log.error(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], max_retry - retries)
		end
		local ok, pw = show_ask_pw_dialog()
		if ok then
			passphrase = pw
		else
			return false
		end
	end

	--show retry notification
	if retries >= max_retry or not ignore_global_error_notify then
		if FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code] then
			if fuse_mount_res_code == FUSE_ARCHIVE_RETURN_CODE.ARCHIVE_READ_PERMISSION_INVALID then
				if
						archive_path.ext == "rar"
						and fuse_mount_res_msg
						and fuse_mount_res_msg:find("encrypted data is not currently supported", 1, true)
				then
					error("Password-protected RAR file is not supported yet!")
					return false
				elseif fuse_mount_res_msg and fuse_mount_res_msg:find("Unspecified error", 1, true) then
					error("Cannot mount archive file, error: Unspecified error")
					return false
				end
			end
			Log.error(FUSE_ARCHIVE_MOUNT_ERROR_MSG[fuse_mount_res_code], table.unpack(payload_error_notify))
		end
		return false
	end
	-- Increase retries every run
	retries = retries + 1
	return mount_fuse({
		archive_path = archive_path,
		fuse_mount_point = fuse_mount_point,
		mount_options = mount_options,
		passphrase = passphrase,
		retries = retries,
		max_retry = max_retry,
	})
end

local function unmount_on_quit()
	redirect_mounted_tab_to_cwd()
	local mount_root_dir = State.mount_root_dir
	local unmount_script = os.getenv("HOME") .. "/.config/yazi/plugins/fuse-archive.yazi/assets/unmount_on_quit.sh"
	-- FIX: doesn't unmount archive if CWD is inside it's mount point
	Command(ya.quote(unmount_script)):arg(ya.quote(mount_root_dir)):spawn()
end

local function setup(_, opts)
	opts = opts or {}
	State.mount_root_dir =
			tostring(Url(opts.mount_root_dir
				and type(opts.mount_root_dir) == "string"
				and path_remove_trailing_slash(opts.mount_root_dir)
				or "/tmp"):join(string.format("yazi.%i/fuse-archive", ya.uid())))

	local ok, err = fs.create("dir_all", Url(State.mount_root_dir))
	if not ok then
		Log.error("Cannot create mount point %s, error: %s", State.mount_root_dir, err)
		return
	end

	State.smart_enter = opts.smart_enter or false
	local mount_options = {}
	if opts and opts.mount_options then
		if type(opts.mount_options) == "string" then
			mount_options = split_by_space_or_comma(opts.mount_options)
		else
			error("mount_options option in setup() must be a string separated by space or comma")
		end
	end
	State.mount_options = mount_options

	-- stylua: ignore
	local ORIGINAL_SUPPORTED_EXTENSIONS = {
		"7z", "7zip", "a", "aia", "apk",
		"ar", "b64", "base64", "br", "brotli",
		"bz2", "bzip2", "cab", "cpio", "crx",
		"deb", "docx", "grz", "grzip", "gz",
		"gzip", "iso", "iso9660", "jar", "lha",
		"lrz", "lrzip", "lz", "lz4", "lzip",
		"lzma", "lzo", "lzop", "mtree", "odf",
		"odg", "odp", "ods", "odt", "ppsx",
		"pptx", "rar", "rpm", "tar", "tar.br",
		"tar.brotli", "tar.bz2", "tar.bzip2", "tar.grz", "tar.grzip",
		"tar.gz", "tar.gzip", "tar.lha", "tar.lrz", "tar.lrzip",
		"tar.lz", "tar.lz4", "tar.lzip", "tar.lzma", "tar.lzo",
		"tar.lzop", "tar.xz", "tar.z", "tar.zst", "tar.zstd",
		"taz", "tb2", "tbr", "tbz", "tbz2",
		"tgz", "tlz", "tlz4", "tlzip", "tlzma",
		"txz", "tz", "tz2", "tzs", "tzst",
		"tzstd", "uu", "warc", "xar", "xlsx",
		"xz", "z", "zip", "zipx", "zst",
		"zstd",
	}

	local SET_ALLOWED_EXTENSIONS = Set.from_table(ORIGINAL_SUPPORTED_EXTENSIONS)

	if opts and opts.extra_extensions then
		if type(opts.extra_extensions) == "table" then
			SET_ALLOWED_EXTENSIONS = SET_ALLOWED_EXTENSIONS | Set.from_table(opts.extra_extensions)
		else
			error("extra_extensions option in setup() must be a table of string")
		end
	end

	if opts and opts.excluded_extensions then
		if type(opts.excluded_extensions) == "table" then
			SET_ALLOWED_EXTENSIONS = SET_ALLOWED_EXTENSIONS << Set.from_table(opts.excluded_extensions)
		else
			error("excluded_extensions option in setup() must be a table of string")
		end
	end
	State.valid_extensions = SET_ALLOWED_EXTENSIONS

	-- trigger unmount on quit
	ps.sub("key-quit", function(args)
		unmount_on_quit()
		---@diagnostic disable-next-line: redundant-return-value
		return args
	end)
	ps.sub("emit-quit", function(args)
		unmount_on_quit()
		---@diagnostic disable-next-line: redundant-return-value
		return args
	end)
	ps.sub("emit-ind-quit", function(args)
		unmount_on_quit()
		---@diagnostic disable-next-line: redundant-return-value
		return args
	end)
end

return {
	entry = function(_, job)
		local action = job.args[1]
		if not action then
			return
		end

		if action == "mount" then
			local hovered_url, is_dir = current_file()
			local hovered_url_raw = tostring(hovered_url)
			if hovered_url == nil then
				return
			end
			if is_dir or is_dir == nil or (is_dir == false and not State.valid_extensions[hovered_url.ext]) then
				enter(is_dir or false)
				return
			end
			local is_virtual = hovered_url.scheme and hovered_url.scheme.is_virtual
			hovered_url = is_virtual and Url(hovered_url.scheme.cache .. tostring(hovered_url.path)) or hovered_url
			if is_virtual and not fs.cha(hovered_url) then
				ya.emit("download", { hovered_url_raw })
				return
			end

			local tmp_fname = hovered_url.name .. ".tmp." .. ya.hash(hovered_url_raw)
			local tmp_file_url = Url(State.mount_root_dir):join(tmp_fname)

			if tmp_file_url then
				local success = mount_fuse({
					archive_path = hovered_url,
					fuse_mount_point = tmp_file_url,
					mount_options = State.mount_options,
				})
				if success then
					---@type fuse-archive.OpenedFile
					local value = { cwd = tostring(current_dir()), tmp = tostring(tmp_file_url) }
					State[tmp_fname] = value
					ya.emit("cd", { tostring(tmp_file_url), raw = true })
				end
			end
			-- leave without unmount
		elseif action == "leave" then
			if not is_mount_point() then
				ya.emit("leave", {})
				return
			end
			local file = current_dir_name()
			ya.emit("cd", { State[file].cwd, raw = true })
			return
		elseif action == "unmount" then
			unmount_on_quit()
		end
	end,
	setup = setup,
}