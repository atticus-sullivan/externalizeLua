module = "externalize"
typesetexe = "lualatex"
unpackexe = "luatex"

installfiles = {"*.lua", "*.sty"}
sourcefiles = {"*.dtx", "*.ins", "externalize.lua"}
excludefiles = {".link.md", "*~","build.lua","config-*.lua"}
