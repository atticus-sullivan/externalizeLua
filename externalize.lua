------------------------------------------
------- Real externalization stuff -------
------------------------------------------
-- Directory structure: (Filename: <tex-basename>.tex)
--   <prefix><tex-basename>-ext_<hash>.pdf: output corresponding to the code with the hash (created by pgf)

local _M = {}

local dbg = false
local emit_tex = false

local pr
local spr
if dbg then
	pr = function(...)
		print(...)
		tex.print(...)
	end
	spr = function(...)
		print(...)
		tex.sprint(...)
	end
else
	spr = function(...)
		tex.sprint(...)
	end
	pr = function(...)
		tex.print(...)
	end
end

-- escape string for to be used in lua-pattern
local function escape_pattern(patt)
	local tab = {
		["%"] = "%%",
		["["] = "%[",
		["]"] = "%]",
		["."] = "%.",
		["-"] = "%-",
		["*"] = "%*",
		["+"] = "%+",
		["^"] = "%^",
		["$"] = "%$",
		["?"] = "%?",
		["("] = "%(",
		[")"] = "%)",
	}
	return patt:gsub("[%% %[ %] %. %- %* %+ %^ %$ %? %( %)]", tab)
end

-- CONFIG:
-- basename=jobname has to be specified by the user (will change on "internal" runs)
_M.config = {
	-- prefix used for externalized files
	-- can be used to put files in a subdirectory (dirs must exist beforehand)
	prefix      = "./",
	-- jobname which is being used when compiling the whole thing
	-- mist likely "main"
	realjobname = "main",

	-- externalization needs the plain/uninterpreted tex code => verbatim
	-- that's usually hard to wrap in environments/macros
	-- pre/post will be emitted before/after the content passed to the handle
	-- function (might be something like "\begin{tikzpicture}" and
	-- "\end{tikzpicture}")
	pre         = nil,
	post        = nil,

	-- set in configure, not intended as parameter
	basename    = "%s",
	dir         = "./",
	name        = "",
}
_M.internal = false

-- function is supposed to set the config struct with values provided by the user
function _M.configure(args)
	args = args or {}
	_M.config.pre      = args.pre   or _M.config.pre  or nil
	_M.config.post     = args.post  or _M.config.post or nil

	_M.config.prefix      = args.prefix  or _M.config.prefix or ""
	_M.config.realjobname = args.jobname or _M.config.realjobname or "main"

	-- split the prefix in a directory-path and a name part
	_M.config.dir         = _M.config.prefix:gsub("(.*/)(.*)", "%1")
	_M.config.name        = _M.config.prefix:gsub("(.*/)(.*)", "%2")

	_M.config.basename    = _M.config.dir.._M.config.name.._M.config.realjobname.."-ext_%s"

	spr(string.format([[\pgfrealjobname{%s}]], _M.config.realjobname))
	_M.internal = tex.jobname ~= _M.config.realjobname
end

-- hash-set (lookup what's already compiled)
_M.map  = {}
-- hash to basename (keeps track of unused files)
_M.clean_up_map = {}
_M.init_run = false
_M.current_hash = nil

-- INIT:
-- search for .md5 files with corresponding .pdf files => build up two maps,
-- one for clean-up purposes (remove unused files in the end) and one for
-- finding IDs of the hashes fast
function _M.init()
	if _M.internal then
		if dbg then print("internal mode =======================================================") end
		-- extract hash from jobname
		_M.current_hash = tex.jobname:match(escape_pattern(_M.config.dir.._M.config.name.._M.config.realjobname.."-ext_").."(%x+)")
		-- current_hash might be nil if the jobname doesn't match the pattern
		-- -> keep running, maybe the user uses a custom name
		if dbg then print("current hash", _M.current_hash) end
		return
	end

	-- reset
	_M.map = {}
	_M.clean_up_map = {}

	-- collect already built hashes from existing files
	for x in lfs.dir(_M.config.dir) do
		-- extract hash from filename
		local h = x:match(escape_pattern(_M.config.name.._M.config.realjobname.."-ext_").."(%x+).pdf")
		-- skip files which don't match the pattern or are no files
		if h and lfs.attributes(_M.config.dir..x, "mode") == "file"
		then
			if dbg then print("found", h) end
			_M.map[h]  = true
			if not _M.internal then
				-- register as a candidate for removal in the end
				-- only store the basename
				-- but only clean-up if running on the complete document
				_M.clean_up_map[h] = _M.config.dir..x:gsub("%.pdf$", "")
			end
		end
	end
	_M.init_run = true
end

-- multiple pictures might have the same hashsum -> make sure all following the
-- first one aren't processed in the same run
-- => switch if already found something for processing
_M.processed = false

-- externalize "data" to pdf and include that pdf when building the complete
-- document
function _M.handle_string(data, name)
	-- ensure the library has been properly initialized
	if not _M.init_run then
		_M.init()
	end
	local hash = md5.sumhexa(data)
	if dbg then print("hash:", hash, name) end

	if _M.internal then
		-- internal
		if not _M.processed and (hash == _M.current_hash or name == tex.jobname) then
			-- found something to process, don't trigger if a second hash matches
			if name == tex.jobname then
				-- use the specified name as hash for the filename building
				hash = name
				-- don't clean up if building with a custom named jobname
				_M.clean_up_map = {}
			end
			_M.processed = true
		else
			-- ignore env by using an already by the length "invalid" hash
			-- needed so that tikzexternal only "sees" one item
			hash = "0"
		end
	else
		-- building the complete document
		if emit_tex then
			local f = assert(io.open(_M.config.basename:format(name or hash)..".tex", "w"))
			if f ~= nil then
				f:write(data)
				assert(f:close())
			end
		end
		if _M.map[name or hash] then
			-- hash is already built => can directly be included
			print(string.format("====================== '%s' is up to date ==============================", _M.config.basename:format(name or hash)))
			-- mark hash as used => won't be removed in the end
			_M.clean_up_map[name or hash] = nil
		else
			-- TODO same args as on call via ipairs(arg) table, but would need some escaping/quoting (lualatex + arg[:-1] + set_jobname + arg[-1])
			-- currently: just extract how the main run included the tex-code
			--            from the commandline arguments
			local fn
			for _,v in ipairs(arg) do
				fn = v
			end
			-- hash needs to be built
			print(string.format("====================== lualatex --jobname='%s' '%s' ==============================", _M.config.basename:format(name or hash), fn))
			local ret = os.execute(string.format(
				"lualatex -halt-on-error -interaction=batchmode --jobname='%s' '%s'",
				_M.config.basename:format(name or hash),
				fn)
			)
			if not ret then
				-- building failed
				tex.error("Built failed")
			end
			-- mark hash as built
			-- maybe there comes the same hash again
			_M.map[name or hash] = true
		end
	end
	-- go on with the code to make tikzexternal work
	pr(string.format("\\beginpgfgraphicnamed{%s}", _M.config.basename:format(name or hash)))

	if _M.config.pre then
		pr(_M.config.pre)
	end

	for l in data:gmatch("[^\r\n]+") do
		pr(l)
	end

	if _M.config.post then
		pr(_M.config.post)
	end

	pr(string.format("\\endpgfgraphicnamed"))
end

-- like handle_string, but read content from a file
function _M.handle(fn, name)
	local f = assert(io.open(fn))
	local data = ""
	if f then
		data = f:read("*all")
		assert(f:close())
	end
	assert(os.remove(fn))
	return _M.handle_string(data, name)
end

-- CLEAN UP:
-- remove all unused files from potential previous runs
function _M.clean_up()
	for _,x in pairs(_M.clean_up_map) do
		if dbg then print("remove", x) end
		os.remove(x..".pdf")
		os.remove(x..".dpth")
	end
end

return _M
