import raylib, msgpack4nim
import std/sequtils, std/tables

type
  TileId = uint8

  Chunk = object
    pos: (int, int)
    bgTiles: seq[TileId]
    fgTiles: seq[TileId]
    
  TileMap = object
    chunks: Table[(int, int), Chunk]
    tileSize: int
    chunkSize: int # e.g., 16 for 16x16 tiles p/ chunk
    tilesetPath: string
    tilesetColumns: int
    tilesetTexture: Texture2D # not serialized

  SerializableTileMap = object
    chunks: seq[Chunk]
    tileSize: int
    chunkSize: int
    tilesetPath: string
    tilesetColumns: int

  MouseStatus = object
    pos: Vector2
    lastPos: Vector2
    dragging: bool
    scroll: float32
  
  Game = object
    camera: Camera2D
    level: TileMap
    mouseStatus: MouseStatus
    selectedTile: uint8
    selectedLayer: string # "fg" or "bg"

proc serializeTileMap(m: TileMap): string =
  let serializableMap = SerializableTileMap(
    chunks: toSeq(m.chunks.values),
    tileSize: m.tileSize,
    chunkSize: m.chunkSize,
    tilesetPath: m.tilesetPath,
    tilesetColumns: m.tilesetColumns,
  )

  var stream = MsgStream.init()
  stream.pack(serializableMap)
  return stream.data

proc deserializeTileMap(data: string): TileMap =
  var stream = MsgStream.init(data)
  var sMap: SerializableTileMap
  stream.unpack(sMap)

  result.tileSize = sMap.tileSize
  result.chunkSize = sMap.chunkSize
  result.tilesetPath = sMap.tilesetPath
  result.tilesetColumns = sMap.tilesetColumns
  result.tilesetTexture = loadTexture(sMap.tilesetPath)

  for chunk in sMap.chunks:
    result.chunks[chunk.pos] = chunk

proc saveToFile(filename: string, data: string) =
  let f = open(filename, fmWrite)
  defer: f.close()
  f.write(data)

proc loadFromFile(filename: string): string =
  let f = open(filename, fmRead)
  defer: f.close()
  return f.readAll()

proc saveTileMap(filename: string, map: TileMap) =
  saveToFile(filename, serializeTileMap(map))

proc loadTileMap(filename: string): TileMap =
  return deserializeTileMap(loadFromFile(filename))

proc getVisibleWorldRect(camera: Camera2D): Rectangle =
  let screenTL = getScreenToWorld2D(Vector2(x: 0, y: 0), camera)
  let screenBR = getScreenToWorld2D(
    Vector2(
      x: float(getScreenWidth()),
      y: float(getscreenHeight()),
    ),
    camera
  )

  result = Rectangle(
    x: screenTL.x,
    y: screenTL.y,
    width: screenBR.x - screenTL.x,
    height: screenBR.y - screenTL.y
  )

proc drawChunk(chunk: Chunk, map: TileMap, layer: string) =
  for y in 0 ..< map.chunkSize:
    for x in 0 ..< map.chunkSize:
      let idx = y * map.chunkSize + x
      let tileId =
        if layer == "bg": chunk.bgTiles[idx]
        else: chunk.fgTiles[idx]

      if tileId == 0: continue

      let tileIdx = int(tileId) - 1
      let src = Rectangle(
        x: float((tileIdx mod map.tilesetColumns) * map.tileSize),
        y: float((tileIdx div map.tilesetColumns) * map.tileSize),
        width: float(map.tileSize),
        height: float(map.tileSize),
      )
      let dest = Vector2(
        x: float((chunk.pos[0] * map.chunkSize + x) * map.tileSize),
        y: float((chunk.pos[1] * map.chunkSize + y) * map.tileSize),
      )

      drawTexture(map.tilesetTexture, src, dest, WHITE)

proc buildTestTileMap(): TileMap =
  var map: TileMap
  map.tileSize = 16
  map.chunkSize = 4
  map.tilesetPath = "assets/tileset.png"
  map.tilesetColumns = 2
  map.tilesetTexture = loadTexture(map.tilesetPath)

  var chunk: Chunk = Chunk(
    pos: (0, 0),
    bgTiles: @[1, 2, 1, 2,
               2, 1, 2, 1,
               1, 2, 1, 2,
               2, 1, 2, 1],
    fgTiles: repeat(0'u8, 16) # fill with zeros
  )

  for x in 0..10:
    for y in 0..10:
      chunk.pos = (x, y)
      map.chunks[(x, y)] = chunk
      
  return map

proc drawTileMap(map: TileMap, camera: Camera2D) =
  let visibleRect = getVisibleWorldRect(camera)

  for chunk in map.chunks.values:
    let chunkX = chunk.pos[0] * map.chunkSize * map.tileSize
    let chunkY = chunk.pos[1] * map.chunkSize * map.tileSize
    let chunkRect = Rectangle(
      x: float(chunkX),
      y: float(chunkY),
      width: float(map.chunkSize * map.tileSize),
      height: float(map.chunkSize * map.tileSize)
    )

    if checkCollisionRecs(chunkRect, visibleRect):
      drawChunk(chunk, map, "bg")
  
  for chunk in map.chunks.values:
    let chunkX = chunk.pos[0] * map.chunkSize * map.tileSize
    let chunkY = chunk.pos[1] * map.chunkSize * map.tileSize
    let chunkRect = Rectangle(
      x: float(chunkX),
      y: float(chunkY),
      width: float(map.chunkSize * map.tileSize),
      height: float(map.chunkSize * map.tileSize)
    )

    if checkCollisionRecs(chunkRect, visibleRect):
      drawChunk(chunk, map, "fg")

proc initGame(): Game =
  result.camera.offset = Vector2(x: 320, y: 240) # centered
  result.camera.target = Vector2(x: 0, y: 0)
  result.camera.rotation = 0.0
  result.camera.zoom = 1.0

  result.level = loadTileMap("levels/tilemap.dat")

  result.mouseStatus.lastPos = Vector2(x: 0, y: 0)
  result.mouseStatus.dragging = false

  result.selectedTile = 1
  result.selectedLayer = "bg"

proc handleTilePlacement(g: var Game) =
  if isMouseButtonDown(MouseButton.Right): return
  if isMouseButtonDown(MouseButton.Left):
    let mouseWorld = getScreenToWorld2D(getMousePosition(), g.camera)
    let tileSize = g.level.tileSize
    let chunkSize = g.level.chunkSize

    let tileX = int(mouseWorld.x) div tileSize
    let tileY = int(mouseWorld.y) div tileSize

    # Negative tile coords are invalid
    if tileX < 0 or tileY < 0:
      return

    let chunkPos = (tileX div chunkSize, tileY div chunkSize)
    let localX = tileX mod chunkSize
    let localY = tileY mod chunkSize

    # Handle modulo with negatives correctly
    if localX < 0 or localY < 0:
      return

    let idx = localY * chunkSize + localX
    if idx < 0 or idx >= chunkSize * chunkSize:
      return

    var chunk = g.level.chunks.getOrDefault(chunkPos)
    if chunk.bgTiles.len == 0:
      chunk.pos = chunkPos
      chunk.bgTiles = repeat(0'u8, chunkSize * chunkSize)
      chunk.fgTiles = repeat(0'u8, chunkSize * chunkSize)

    if g.selectedLayer == "fg":
      chunk.fgTiles[idx] = g.selectedTile
    else:
      chunk.bgTiles[idx] = g.selectedTile

    g.level.chunks[chunkPos] = chunk

proc handleDragging(g: var Game) =
  g.mouseStatus.pos = getMousePosition()

  if isMouseButtonPressed(Right):
    g.mouseStatus.dragging = true
    g.mouseStatus.lastPos = g.mouseStatus.pos

  if isMouseButtonReleased(Right):
    g.mouseStatus.dragging = false

  if g.mouseStatus.dragging:
    let delta = Vector2(
      x: (g.mouseStatus.lastPos.x - g.mouseStatus.pos.x) / g.camera.zoom,
      y: (g.mouseStatus.lastPos.y - g.mouseStatus.pos.y) / g.camera.zoom,
    )
    g.camera.target.x += delta.x
    g.camera.target.y += delta.y

  g.mouseStatus.lastPos = g.mouseStatus.pos

proc handleScrolling(g: var Game) =
  g.mouseStatus.scroll = getMouseWheelMove()
  if g.mouseStatus.scroll == 0: return

  g.mouseStatus.pos = getMousePosition()
  let beforeZoom = getScreenToWorld2D(g.mouseStatus.pos, g.camera)

  if g.mouseStatus.scroll > 0:
    g.camera.zoom *= 1.1
  elif g.mouseStatus.scroll < 0 :
    g.camera.zoom *= 0.9

  g.camera.zoom = clamp(g.camera.zoom, 0.5, 4.0)

  let afterZoom = getScreenToWorld2D(g.mouseStatus.pos, g.camera)

  let zoomDelta = Vector2(
    x: beforeZoom.x - afterZoom.x,
    y: beforeZoom.y - afterZoom.y,
  )
  g.camera.target.x += zoomDelta.x
  g.camera.target.y += zoomDelta.y

proc handleTileCycling(g: var Game) =
  if isKeyPressed(Minus):
    if g.selectedTile > 0:
      dec g.selectedTile
  if isKeyPressed(Equal) and g.selectedTile < 2:
    inc g.selectedTile

proc handleLayerCycling(g: var Game) =
  if isKeyPressed(LeftBracket):
    g.selectedLayer = "bg"
  if isKeyPressed(RightBracket):
    g.selectedLayer = "fg"

proc handleInput(game: var Game) =
  handleDragging(game)
  handleScrolling(game)
  handleTileCycling(game)
  handleLayerCycling(game)
  handleTilePlacement(game)

proc draw(game: var Game) =
  beginDrawing()
  
  clearBackground(RAYWHITE)

  beginMode2D(game.camera)
  drawTileMap(game.level, game.camera)
  endMode2d()

  drawText("Tile: " & $game.selectedTile, 10, 30, 20, DARKGRAY)
  drawText("Layer: " & game.selectedLayer, 10, 50, 20, DARKGRAY)
  drawFPS(10, 10)

  endDrawing()

when isMainModule:
  initWindow(640, 480, "Tilemap Test")
  setWindowState(flags(WindowResizable))

  var game: Game = initGame()
    
  while not windowShouldClose():
    handleInput(game)
    draw(game)

  saveTileMap("levels/tilemap.dat", game.level)
    
  closeWindow()
