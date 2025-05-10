# Package

version       = "0.1.0"
author        = "ricklib"
description   = "tilemap"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["tilemap_editor"]


# Dependencies

requires "nim >= 2.2.2"
requires "naylib >= 25.13.0"
requires "msgpack4nim"
requires "native_dialogs"
