package = "wimbly-lib"
version = "dev-1"

source = {
   url = "git://github.com/cdrubin/wimbly-lib"
}

description = {
  summary = "Convenience code from the wimbly project.",
  detailed = "Convenience code from the wimbly project.",
  homepage = "http://github.com/cdrubin/wimbly-lib",
  license = "MIT"
}
  
dependencies = {
  "lua >= 5.1, < 5.4",
}
  
build = {
  type = "builtin",
  modules = {
    ["wimbly-lib.util"] = "util.lua",
    ["wimbly-lib.wimbly"] = "wimbly.lua"
  }
}
