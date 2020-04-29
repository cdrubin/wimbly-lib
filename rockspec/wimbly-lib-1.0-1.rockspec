package = "wimbly-lib"
version = "1.0-1"

source = {
   url = "git://github.com/cdrubin/wimbly-lib",
   tag = "1.0-1"
}

description = {
  summary = "Plain static-site generator using templet.",
  detailed = "Plain static-site generator using templet.",
  homepage = "http://...", -- We don't have one yet,
  license = "MIT"
}
  
dependencies = {
  "lua >= 5.1, < 5.4",
}
  
build = {
  type = "none"
}
