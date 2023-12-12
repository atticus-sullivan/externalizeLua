------------------------------------------
------- Real externalization stuff -------
------------------------------------------
-- Directory structure: (Filename: <tex-basename>.tex)
--   <prefix><tex-basename>-ext_<hash>.pdf: output corresponding to the code with the hash/diff (created by pgf)
--   <prefix><tex-basename>-ext_<hash>.dpth: baseline stuff (created by pgf)

local dbg = false
local emit_tex = false

-- local tprint = tex.sprint
-- function tex.sprint(...)
-- 	tprint(...)
-- 	print(...)
-- end

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
local config = {
	prefix      = "",
	realjobname = "",
	basename    = "",
	-- only things returning string can be used since the returned value is used in the filename
	mode        = "md5",
	pre = "",
	post = "",
	allow = {""},
}

-- function is supposed to set the config struct with values provided by the user
-- TODO no tex bindings for this up to now
local function configure(args)
	args = args or {}
	config.pre      = args.pre   or config.pre
	config.post     = args.post  or config.post
	config.allow    = args.allow or config.allow

	config.prefix      = args.prefix  or "figures/"
	config.realjobname = args.jobname or "main"

	-- split the prefix in a directory-path and a name part
	config.dir         = config.prefix:gsub("(.*/)(.*)", "%1")
	config.name        = config.prefix:gsub("(.*/)(.*)", "%2")

	config.basename    = config.dir..config.name..config.realjobname.."-ext_%s"

	tex.sprint(string.format([[\pgfrealjobname{%s}]], config.realjobname))
end

-- just a small utility function for readability
local function is_internal_run()
	return tex.jobname ~= config.realjobname
end

local map  = {} -- hash to set (lookup of already compiled stuff)
local clup = {} -- hash to basename (keeps track of unused files)
local ini = false
local current_hash = nil

-- INIT:
-- search for .md5 files with corresponding .pdf files => build up two maps,
-- one for clean-up purposes (remove unused files in the end) and one for
-- finding IDs of the hashes fast
local function init(o)
	if is_internal_run() then
		if dbg then print("being in internal run mode =======================================================") end
		current_hash = tex.jobname:match(escape_pattern(config.dir..config.name..config.realjobname.."-ext_").."(%x+)")
		if dbg then print("current hash", current_hash) end
		return
	end
	for x in lfs.dir(config.dir) do
		local h = x:match(escape_pattern(config.name..config.realjobname.."-ext_").."(%x+).pdf")
		if h
			and lfs.attributes(config.dir..x, "mode") == "file"
		then
			print("found", h)
			map[h]  = true
			clup[h] = config.dir..x:gsub("%.pdf$", "")
		end
	end
end

local processed = false -- switch so that on duplicates only tie first one is compiled in the pgf run

local function handle_string(data)
	local hash = nil

	if config.mode == "md5" then
		hash = md5.sumhexa(data)
		if dbg then print("hash:", hash) end
	else
		tex.error("No mode specified")
	end
	if is_internal_run() then
		-- internal
		if not processed and hash == current_hash then
			-- remember that the to be processed env has been found
			-- => all envs to come should be ignored
			processed = true
		else
			-- ignore env by using "invalid" hash (is necessary since there
			-- might be duplicates) (digest too short)
			hash = "0"
		end
	else
		if emit_tex then
			local f = assert(io.open(config.basename:format(hash)..".tex", "w"))
			if f ~= nil then
				f:write(data)
				assert(f:close())
			end
		end
		-- outer run
		if map[hash] then
			clup[hash] = nil -- mark hash as used by removing from clean_up-set
			print(string.format("====================== '%s' is up to date ==============================", config.basename:format(hash)))
		else
			-- for k,v in pairs(map) do
			-- 	print(k,v)
			-- end
			-- print(hash)
			-- extract the how the main run included the tex-code from the commandline arguments
			local fn
			for _,v in ipairs(arg) do
				fn = v
			end
			print(string.format("====================== lualatex --jobname='%s' '%s' ==============================", config.basename:format(hash), fn))
			-- TODO same args as on call via ipairs(arg) table, but would need some escaping/quoting (lualatex + arg[:-1] + set_jobname + arg[-1])
			-- TODO other option than using popen and &>/dev/null to avoid stdout?
			os.execute(string.format("lualatex -halt-on-error -interaction=batchmode --jobname='%s' '%s'", config.basename:format(hash), fn))
			-- TODO check returncode!!
			map[hash] = true -- mark hash as build for duplicated images
		end
	end
	tex.print(string.format("\\beginpgfgraphicnamed{%s}", config.basename:format(hash)))

	-- print(config.pre)
	tex.print(config.pre)

	for l in data:gmatch("[^\r\n]+") do
		tex.print(l)
	end

	-- print(config.post)
	tex.print(config.post)

	tex.print(string.format("\\endpgfgraphicnamed"))
end
local function handle(fn)
	local f = assert(io.open(fn))
	local data = f:read("*all")
	assert(f:close())
	assert(os.remove(fn))
	return handle_string(data)
end

-- CLEAN UP:
-- remove all unused files from potential previous runs
local function clean_up()
	for _,x in pairs(clup) do
		if dbg then print("remove", x) end
		-- this removing might error, but this should be no problem
		os.remove(x..".pdf")
		os.remove(x..".dpth")
	end
end

return {
	handle            = handle,
	handle_string            = handle_string,
	clean_up          = clean_up,
	configure         = configure,
	init              = init,
}
