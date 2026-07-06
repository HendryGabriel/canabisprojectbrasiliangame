const dom = {
  assetFiles: document.getElementById("assetFiles"),
  projectFile: document.getElementById("projectFile"),
  importAssetsBtn: document.getElementById("importAssetsBtn"),
  importProjectBtn: document.getElementById("importProjectBtn"),
  exportProjectBtn: document.getElementById("exportProjectBtn"),
  exportMapBtn: document.getElementById("exportMapBtn"),
  exportImporterBtn: document.getElementById("exportImporterBtn"),
  statusText: document.getElementById("statusText"),
  mapName: document.getElementById("mapName"),
  tileSize: document.getElementById("tileSize"),
  mapWidth: document.getElementById("mapWidth"),
  mapHeight: document.getElementById("mapHeight"),
  resizeMapBtn: document.getElementById("resizeMapBtn"),
  zoomRange: document.getElementById("zoomRange"),
  showGrid: document.getElementById("showGrid"),
  showCollisions: document.getElementById("showCollisions"),
  snapDecor: document.getElementById("snapDecor"),
  canvasInfo: document.getElementById("canvasInfo"),
  selectionInfo: document.getElementById("selectionInfo"),
  mapCanvas: document.getElementById("mapCanvas"),
  canvasWrap: document.getElementById("canvasWrap"),
  layersList: document.getElementById("layersList"),
  addLayerBtn: document.getElementById("addLayerBtn"),
  layerTemplate: document.getElementById("layerTemplate"),
  assetSearch: document.getElementById("assetSearch"),
  hideEmptyTiles: document.getElementById("hideEmptyTiles"),
  assetList: document.getElementById("assetList"),
  previewCanvas: document.getElementById("previewCanvas"),
  assetName: document.getElementById("assetName"),
  assetMeta: document.getElementById("assetMeta"),
  assetKind: document.getElementById("assetKind"),
  assetZ: document.getElementById("assetZ"),
  pivotX: document.getElementById("pivotX"),
  pivotY: document.getElementById("pivotY"),
  collisionEnabled: document.getElementById("collisionEnabled"),
  collisionX: document.getElementById("collisionX"),
  collisionY: document.getElementById("collisionY"),
  collisionW: document.getElementById("collisionW"),
  collisionH: document.getElementById("collisionH"),
  collisionFullBtn: document.getElementById("collisionFullBtn"),
  collisionBottomBtn: document.getElementById("collisionBottomBtn"),
  collisionClearBtn: document.getElementById("collisionClearBtn"),
  atlasList: document.getElementById("atlasList")
};

const ctx = dom.mapCanvas.getContext("2d");
const previewCtx = dom.previewCanvas.getContext("2d");

const state = {
  tool: "brush",
  filter: "all",
  zoom: 3,
  isPointerDown: false,
  selectedAssetId: "",
  selectedLayerId: "",
  atlases: [],
  assets: [],
  map: {
    name: "weed_factory_map",
    tileSize: 16,
    width: 40,
    height: 28,
    layers: []
  }
};

function makeId(prefix) {
  return `${prefix}_${Math.random().toString(36).slice(2, 8)}_${Date.now().toString(36)}`;
}

function setStatus(text) {
  dom.statusText.textContent = text;
}

function getLayer(id = state.selectedLayerId) {
  return state.map.layers.find(layer => layer.id === id) || null;
}

function getAsset(id = state.selectedAssetId) {
  return state.assets.find(asset => asset.id === id) || null;
}

function getAtlas(id) {
  return state.atlases.find(atlas => atlas.id === id) || null;
}

function cellKey(x, y) {
  return `${x},${y}`;
}

function clampNumber(value, min, max, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function createLayer(name, type = "tile") {
  const layer = {
    id: makeId("layer"),
    name,
    type,
    visible: true,
    opacity: 1,
    cells: {}
  };
  state.map.layers.push(layer);
  state.selectedLayerId = layer.id;
  renderLayers();
  drawMap();
  return layer;
}

function initDefaultLayers() {
  if (state.map.layers.length > 0) return;
  createLayer("Chao", "tile");
  createLayer("Decoracao", "decor");
  state.selectedLayerId = state.map.layers[0].id;
}

function readFileAsText(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = reject;
    reader.readAsText(file);
  });
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = src;
  });
}

function basename(name) {
  return name.replace(/\.[^/.]+$/, "").toLowerCase();
}

function guessKind(sprite, tileSize) {
  const type = String(sprite.suggested_type || "").toLowerCase();
  if (type.includes("decor") || type.includes("bush") || type.includes("plant") || type.includes("tree")) return "decor";
  const w = Number(sprite.w || sprite.region?.[2] || tileSize);
  const h = Number(sprite.h || sprite.region?.[3] || tileSize);
  return w === tileSize && h === tileSize ? "tile" : "decor";
}

function spriteRegion(sprite, tileSize) {
  if (Array.isArray(sprite.region)) return sprite.region.map(value => Number(value) || 0);
  return [
    Number(sprite.x) || 0,
    Number(sprite.y) || 0,
    Number(sprite.w) || tileSize,
    Number(sprite.h) || tileSize
  ];
}

function manifestSprites(manifest, image, tileSize) {
  if (Array.isArray(manifest?.sprites) && manifest.sprites.length > 0) return manifest.sprites;

  const sprites = [];
  const cols = Math.floor(image.naturalWidth / tileSize);
  const rows = Math.floor(image.naturalHeight / tileSize);
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      sprites.push({
        id: `tile_${String(y * cols + x + 1).padStart(3, "0")}`,
        name: `tile_${x}_${y}`,
        x: x * tileSize,
        y: y * tileSize,
        w: tileSize,
        h: tileSize,
        pivot: [tileSize / 2, tileSize],
        suggested_type: "tile"
      });
    }
  }
  return sprites;
}

function isRegionFullyTransparent(image, region) {
  const [sx, sy, sw, sh] = region.map(value => Math.max(0, Math.floor(Number(value) || 0)));
  if (sw <= 0 || sh <= 0) return true;

  const canvas = document.createElement("canvas");
  canvas.width = sw;
  canvas.height = sh;
  const alphaCtx = canvas.getContext("2d", { willReadFrequently: true });
  alphaCtx.drawImage(image, sx, sy, sw, sh, 0, 0, sw, sh);
  const pixels = alphaCtx.getImageData(0, 0, sw, sh).data;
  for (let i = 3; i < pixels.length; i += 4) {
    if (pixels[i] > 0) return false;
  }
  return true;
}

async function importAssetFiles(fileList) {
  const files = Array.from(fileList || []);
  if (files.length === 0) return;

  const pngFiles = files.filter(file => file.type === "image/png" || file.name.toLowerCase().endsWith(".png"));
  const jsonFiles = files.filter(file => file.name.toLowerCase().endsWith(".json"));
  const jsonByBase = new Map();
  const jsonBySource = new Map();

  for (const file of jsonFiles) {
    try {
      const text = await readFileAsText(file);
      const json = JSON.parse(text);
      jsonByBase.set(basename(file.name).replace(/_sprites$/, ""), json);
      if (json.source) jsonBySource.set(String(json.source).toLowerCase(), json);
    } catch (error) {
      console.warn(error);
      setStatus(`JSON ignorado: ${file.name}`);
    }
  }

  for (const file of pngFiles) {
    const dataUrl = await readFileAsDataUrl(file);
    const image = await loadImage(dataUrl);
    const tileSize = Number(dom.tileSize.value) || state.map.tileSize;
    const manifest = jsonBySource.get(file.name.toLowerCase()) || jsonByBase.get(basename(file.name)) || {};
    addAtlasFromManifest(file.name, dataUrl, image, manifest, tileSize);
  }

  if (pngFiles.length === 0 && jsonFiles.length > 0) {
    setStatus("JSON carregado. Selecione o PNG correspondente para visualizar.");
  } else {
    setStatus(`${pngFiles.length} atlas importado(s)`);
  }

  renderAtlasList();
  renderAssetList();
  syncInspector();
  drawMap();
}

function addAtlasFromManifest(fileName, dataUrl, image, manifest, tileSize) {
  const atlasId = makeId("atlas");
  const atlas = {
    id: atlasId,
    name: fileName,
    source: manifest.source || fileName,
    width: image.naturalWidth,
    height: image.naturalHeight,
    godotPath: `res://src/ASSETS/${fileName}`,
    dataUrl,
    image
  };
  state.atlases.push(atlas);

  const sprites = manifestSprites(manifest, image, tileSize);
  for (let index = 0; index < sprites.length; index++) {
    const sprite = sprites[index];
    const region = spriteRegion(sprite, tileSize);
    const pivot = Array.isArray(sprite.pivot) ? sprite.pivot : [Math.round(region[2] / 2), region[3]];
    const blocks = Boolean(sprite.blocks_walk || sprite.blocks_build);
    const spriteId = String(sprite.id || sprite.name || `sprite_${index + 1}`);
    state.assets.push({
      id: `${atlasId}:${spriteId}`,
      atlasId,
      spriteId,
      name: String(sprite.name || spriteId),
      region,
      kind: guessKind(sprite, tileSize),
      empty: isRegionFullyTransparent(image, region),
      z: 0,
      pivot: [Number(pivot[0]) || 0, Number(pivot[1]) || 0],
      tags: [sprite.suggested_type || "", atlas.name].filter(Boolean),
      collision: {
        enabled: blocks,
        rect: [0, 0, region[2], region[3]]
      }
    });
  }

  if (!state.selectedAssetId && state.assets.length > 0) {
    state.selectedAssetId = state.assets[0].id;
  }
}

function renderAtlasList() {
  dom.atlasList.innerHTML = "";
  if (state.atlases.length === 0) {
    dom.atlasList.innerHTML = `<div class="empty">Nenhum atlas importado.</div>`;
    return;
  }

  for (const atlas of state.atlases) {
    const count = state.assets.filter(asset => asset.atlasId === atlas.id).length;
    const item = document.createElement("div");
    item.className = "atlas-item";
    item.innerHTML = `
      <strong>${escapeHtml(atlas.name)}</strong>
      <span>${atlas.width} x ${atlas.height} px - ${count} sprites</span>
      <label>Caminho Godot<input type="text" value="${escapeHtml(atlas.godotPath)}"></label>
    `;
    item.querySelector("input").addEventListener("change", event => {
      atlas.godotPath = event.target.value.trim();
    });
    dom.atlasList.appendChild(item);
  }
}

function assetMatchesFilter(asset) {
  if (state.filter !== "all" && asset.kind !== state.filter) return false;
  if (dom.hideEmptyTiles.checked && asset.kind === "tile" && asset.empty) return false;
  const query = dom.assetSearch.value.trim().toLowerCase();
  if (!query) return true;
  const atlas = getAtlas(asset.atlasId);
  return [asset.name, asset.spriteId, asset.kind, atlas?.name || "", ...asset.tags]
    .join(" ")
    .toLowerCase()
    .includes(query);
}

function renderAssetList() {
  dom.assetList.innerHTML = "";
  const assets = state.assets.filter(assetMatchesFilter);

  if (assets.length === 0) {
    dom.assetList.innerHTML = `<div class="empty">Importe PNG + JSON ou ajuste a busca.</div>`;
    return;
  }

  for (const asset of assets) {
    const card = document.createElement("button");
    card.type = "button";
    card.className = `asset-card${asset.id === state.selectedAssetId ? " selected" : ""}`;
    card.innerHTML = `<div class="thumb"></div><span>${escapeHtml(asset.name)}</span>`;
    card.addEventListener("click", () => {
      state.selectedAssetId = asset.id;
      renderAssetList();
      syncInspector();
      drawMap();
    });
    dom.assetList.appendChild(card);
    drawAssetThumb(card.querySelector(".thumb"), asset, 58);
  }
}

function drawAssetThumb(container, asset, size) {
  const atlas = getAtlas(asset.atlasId);
  if (!atlas?.image) return;
  const [sx, sy, sw, sh] = asset.region;
  const canvas = document.createElement("canvas");
  const scale = Math.min(size / sw, size / sh, 4);
  canvas.width = Math.max(1, Math.ceil(sw * scale));
  canvas.height = Math.max(1, Math.ceil(sh * scale));
  const thumbCtx = canvas.getContext("2d");
  thumbCtx.imageSmoothingEnabled = false;
  thumbCtx.drawImage(atlas.image, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
  container.appendChild(canvas);
}

function renderLayers() {
  dom.layersList.innerHTML = "";
  for (const layer of state.map.layers) {
    const node = dom.layerTemplate.content.firstElementChild.cloneNode(true);
    node.classList.toggle("active", layer.id === state.selectedLayerId);
    const select = node.querySelector(".layer-select");
    const name = node.querySelector(".layer-name");
    const type = node.querySelector(".layer-type");
    const visible = node.querySelector(".layer-visible");
    const remove = node.querySelector(".layer-delete");

    select.textContent = layer.id === state.selectedLayerId ? "✓" : "";
    name.value = layer.name;
    type.value = layer.type;
    visible.checked = layer.visible;

    select.addEventListener("click", () => {
      state.selectedLayerId = layer.id;
      renderLayers();
      drawMap();
    });
    name.addEventListener("change", event => {
      layer.name = event.target.value.trim() || layer.name;
    });
    type.addEventListener("change", event => {
      layer.type = event.target.value;
      drawMap();
    });
    visible.addEventListener("change", event => {
      layer.visible = event.target.checked;
      drawMap();
    });
    remove.addEventListener("click", () => {
      if (state.map.layers.length <= 1) return;
      state.map.layers = state.map.layers.filter(item => item.id !== layer.id);
      if (state.selectedLayerId === layer.id) state.selectedLayerId = state.map.layers[0].id;
      renderLayers();
      drawMap();
    });

    dom.layersList.appendChild(node);
  }
}

function applyMapInputs() {
  state.map.name = dom.mapName.value.trim() || "weed_factory_map";
  state.map.tileSize = clampNumber(dom.tileSize.value, 4, 128, 16);
  state.map.width = clampNumber(dom.mapWidth.value, 1, 512, 40);
  state.map.height = clampNumber(dom.mapHeight.value, 1, 512, 28);

  for (const layer of state.map.layers) {
    for (const key of Object.keys(layer.cells)) {
      const cell = layer.cells[key];
      if (cell.x >= state.map.width || cell.y >= state.map.height) delete layer.cells[key];
    }
  }

  drawMap();
}

function mapPointFromEvent(event) {
  const rect = dom.mapCanvas.getBoundingClientRect();
  const scaleX = dom.mapCanvas.width / rect.width;
  const scaleY = dom.mapCanvas.height / rect.height;
  const px = (event.clientX - rect.left) * scaleX / state.zoom;
  const py = (event.clientY - rect.top) * scaleY / state.zoom;
  return {
    x: Math.floor(px / state.map.tileSize),
    y: Math.floor(py / state.map.tileSize)
  };
}

function inBounds(x, y) {
  return x >= 0 && y >= 0 && x < state.map.width && y < state.map.height;
}

function handleCanvasAction(event) {
  const point = mapPointFromEvent(event);
  if (!inBounds(point.x, point.y)) return;

  const layer = getLayer();
  if (!layer) return;

  if (state.tool === "brush") {
    paintCell(layer, point.x, point.y);
  } else if (state.tool === "erase") {
    delete layer.cells[cellKey(point.x, point.y)];
  } else if (state.tool === "pick") {
    pickCell(point.x, point.y);
  } else if (state.tool === "fill") {
    fillLayer(layer, point.x, point.y);
  }

  drawMap();
}

function paintCell(layer, x, y) {
  const asset = getAsset();
  if (!asset) return;
  layer.cells[cellKey(x, y)] = {
    x,
    y,
    assetId: asset.id
  };
}

function pickCell(x, y) {
  for (let i = state.map.layers.length - 1; i >= 0; i--) {
    const layer = state.map.layers[i];
    const cell = layer.cells[cellKey(x, y)];
    if (cell) {
      state.selectedLayerId = layer.id;
      state.selectedAssetId = cell.assetId;
      renderLayers();
      renderAssetList();
      syncInspector();
      return;
    }
  }
}

function fillLayer(layer, x, y) {
  const asset = getAsset();
  if (!asset) return;
  const startKey = cellKey(x, y);
  const targetAssetId = layer.cells[startKey]?.assetId || "";
  if (targetAssetId === asset.id) return;

  const queue = [[x, y]];
  const seen = new Set();
  while (queue.length > 0) {
    const [cx, cy] = queue.shift();
    const key = cellKey(cx, cy);
    if (seen.has(key) || !inBounds(cx, cy)) continue;
    seen.add(key);
    const currentAssetId = layer.cells[key]?.assetId || "";
    if (currentAssetId !== targetAssetId) continue;
    layer.cells[key] = { x: cx, y: cy, assetId: asset.id };
    queue.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
  }
}

function drawMap() {
  const tileSize = state.map.tileSize;
  const width = state.map.width * tileSize;
  const height = state.map.height * tileSize;
  state.zoom = Number(dom.zoomRange.value) || 3;
  dom.mapCanvas.width = width * state.zoom;
  dom.mapCanvas.height = height * state.zoom;
  dom.mapCanvas.style.width = `${width * state.zoom}px`;
  dom.mapCanvas.style.height = `${height * state.zoom}px`;

  ctx.imageSmoothingEnabled = false;
  ctx.setTransform(state.zoom, 0, 0, state.zoom, 0, 0);
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#10131a";
  ctx.fillRect(0, 0, width, height);

  for (const layer of state.map.layers) {
    if (!layer.visible) continue;
    const cells = Object.values(layer.cells);
    if (layer.type === "decor") {
      cells.sort((a, b) => a.y - b.y || a.x - b.x || ((getAsset(a.assetId)?.z || 0) - (getAsset(b.assetId)?.z || 0)));
    }
    ctx.globalAlpha = Number(layer.opacity) || 1;
    for (const placement of cells) drawPlacement(layer, placement);
    ctx.globalAlpha = 1;
  }

  if (dom.showGrid.checked) drawGrid(width, height, tileSize);

  ctx.setTransform(1, 0, 0, 1, 0, 0);
  dom.canvasInfo.textContent = `${state.map.width} x ${state.map.height} celulas - tile ${tileSize}px - zoom ${state.zoom}x`;
  const asset = getAsset();
  dom.selectionInfo.textContent = asset ? `${asset.name} em ${getLayer()?.name || "sem camada"}` : "Nenhum sprite selecionado";
}

function drawPlacement(layer, placement) {
  const asset = getAsset(placement.assetId);
  const atlas = asset ? getAtlas(asset.atlasId) : null;
  if (!asset || !atlas?.image) return;

  const tileSize = state.map.tileSize;
  const [sx, sy, sw, sh] = asset.region;
  const isDecor = layer.type === "decor" || asset.kind === "decor";
  let dx = placement.x * tileSize;
  let dy = placement.y * tileSize;
  if (isDecor && dom.snapDecor.checked) {
    dx += tileSize / 2 - asset.pivot[0];
    dy += tileSize - asset.pivot[1];
  }

  ctx.drawImage(atlas.image, sx, sy, sw, sh, dx, dy, sw, sh);

  if (dom.showCollisions.checked && asset.collision?.enabled) {
    const rect = asset.collision.rect || [0, 0, sw, sh];
    ctx.save();
    ctx.strokeStyle = "rgba(239, 100, 97, .95)";
    ctx.fillStyle = "rgba(239, 100, 97, .18)";
    ctx.lineWidth = 1 / state.zoom;
    ctx.fillRect(dx + rect[0], dy + rect[1], rect[2], rect[3]);
    ctx.strokeRect(dx + rect[0], dy + rect[1], rect[2], rect[3]);
    ctx.restore();
  }
}

function drawGrid(width, height, tileSize) {
  ctx.save();
  ctx.strokeStyle = "rgba(255, 255, 255, .12)";
  ctx.lineWidth = 1 / state.zoom;
  ctx.beginPath();
  for (let x = 0; x <= width; x += tileSize) {
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
  }
  for (let y = 0; y <= height; y += tileSize) {
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
  }
  ctx.stroke();
  ctx.restore();
}

function syncInspector() {
  const asset = getAsset();
  previewCtx.clearRect(0, 0, dom.previewCanvas.width, dom.previewCanvas.height);
  previewCtx.imageSmoothingEnabled = false;

  if (!asset) {
    dom.assetName.textContent = "Nenhum sprite";
    dom.assetMeta.textContent = "Importe uma spritesheet para iniciar.";
    return;
  }

  const atlas = getAtlas(asset.atlasId);
  const [sx, sy, sw, sh] = asset.region;
  dom.assetName.textContent = asset.name;
  dom.assetMeta.textContent = `${atlas?.name || "atlas"} - ${sw}x${sh} - ${asset.kind}`;
  dom.assetKind.value = asset.kind;
  dom.assetZ.value = asset.z;
  dom.pivotX.value = asset.pivot[0];
  dom.pivotY.value = asset.pivot[1];
  dom.collisionEnabled.checked = Boolean(asset.collision?.enabled);
  dom.collisionX.value = asset.collision?.rect?.[0] ?? 0;
  dom.collisionY.value = asset.collision?.rect?.[1] ?? 0;
  dom.collisionW.value = asset.collision?.rect?.[2] ?? sw;
  dom.collisionH.value = asset.collision?.rect?.[3] ?? sh;

  if (atlas?.image) {
    const scale = Math.min(82 / sw, 82 / sh, 6);
    const dw = sw * scale;
    const dh = sh * scale;
    const dx = (96 - dw) / 2;
    const dy = (96 - dh) / 2;
    previewCtx.drawImage(atlas.image, sx, sy, sw, sh, dx, dy, dw, dh);
    if (asset.collision?.enabled) {
      const rect = asset.collision.rect;
      previewCtx.fillStyle = "rgba(239, 100, 97, .18)";
      previewCtx.strokeStyle = "rgba(239, 100, 97, .95)";
      previewCtx.fillRect(dx + rect[0] * scale, dy + rect[1] * scale, rect[2] * scale, rect[3] * scale);
      previewCtx.strokeRect(dx + rect[0] * scale, dy + rect[1] * scale, rect[2] * scale, rect[3] * scale);
    }
  }
}

function updateSelectedAssetFromInputs() {
  const asset = getAsset();
  if (!asset) return;
  const [, , sw, sh] = asset.region;
  asset.kind = dom.assetKind.value;
  asset.z = clampNumber(dom.assetZ.value, -100, 100, 0);
  asset.pivot = [
    clampNumber(dom.pivotX.value, -1024, 1024, Math.round(sw / 2)),
    clampNumber(dom.pivotY.value, -1024, 1024, sh)
  ];
  asset.collision = {
    enabled: dom.collisionEnabled.checked,
    rect: [
      clampNumber(dom.collisionX.value, -1024, 1024, 0),
      clampNumber(dom.collisionY.value, -1024, 1024, 0),
      clampNumber(dom.collisionW.value, 1, 2048, sw),
      clampNumber(dom.collisionH.value, 1, 2048, sh)
    ]
  };
  renderAssetList();
  syncInspector();
  drawMap();
}

function setCollisionPreset(kind) {
  const asset = getAsset();
  if (!asset) return;
  const [, , sw, sh] = asset.region;
  if (kind === "full") {
    asset.collision = { enabled: true, rect: [0, 0, sw, sh] };
  } else if (kind === "bottom") {
    asset.collision = { enabled: true, rect: [0, Math.floor(sh * 0.55), sw, Math.ceil(sh * 0.45)] };
  } else {
    asset.collision = { enabled: false, rect: [0, 0, sw, sh] };
  }
  syncInspector();
  drawMap();
}

function exportEditorProject() {
  return {
    format: "weed_factory_map_editor_project",
    version: 1,
    map: state.map,
    selectedAssetId: state.selectedAssetId,
    selectedLayerId: state.selectedLayerId,
    atlases: state.atlases.map(atlas => ({
      id: atlas.id,
      name: atlas.name,
      source: atlas.source,
      width: atlas.width,
      height: atlas.height,
      godotPath: atlas.godotPath,
      dataUrl: atlas.dataUrl
    })),
    assets: state.assets
  };
}

function exportGodotMap() {
  return {
    format: "weed_factory_godot_map",
    version: 1,
    generated_by: "tools/godot_map_editor",
    map: {
      name: state.map.name,
      tile_size: state.map.tileSize,
      width: state.map.width,
      height: state.map.height
    },
    atlases: state.atlases.map(atlas => ({
      id: atlas.id,
      name: atlas.name,
      image: atlas.godotPath,
      width: atlas.width,
      height: atlas.height
    })),
    sprites: state.assets.map(asset => ({
      id: asset.id,
      atlas_id: asset.atlasId,
      sprite_id: asset.spriteId,
      name: asset.name,
      region: asset.region,
      kind: asset.kind,
      pivot: asset.pivot,
      z: asset.z,
      collision: asset.collision
    })),
    layers: state.map.layers.map((layer, index) => ({
      id: layer.id,
      name: layer.name,
      type: layer.type,
      visible: layer.visible,
      opacity: layer.opacity,
      z_index: index,
      cells: Object.values(layer.cells)
    }))
  };
}

async function importEditorProject(file) {
  const data = JSON.parse(await readFileAsText(file));
  if (data.format !== "weed_factory_map_editor_project") {
    throw new Error("Arquivo nao e um projeto do editor de mapas.");
  }

  state.map = data.map;
  state.selectedAssetId = data.selectedAssetId || "";
  state.selectedLayerId = data.selectedLayerId || state.map.layers[0]?.id || "";
  state.assets = data.assets || [];
  state.atlases = [];

  for (const atlasData of data.atlases || []) {
    const image = atlasData.dataUrl ? await loadImage(atlasData.dataUrl) : null;
    state.atlases.push({ ...atlasData, image });
  }

  for (const asset of state.assets) {
    if (typeof asset.empty === "boolean") continue;
    const atlas = state.atlases.find(item => item.id === asset.atlasId);
    asset.empty = atlas?.image ? isRegionFullyTransparent(atlas.image, asset.region) : false;
  }

  dom.mapName.value = state.map.name;
  dom.tileSize.value = state.map.tileSize;
  dom.mapWidth.value = state.map.width;
  dom.mapHeight.value = state.map.height;
  renderAtlasList();
  renderAssetList();
  renderLayers();
  syncInspector();
  drawMap();
  setStatus(`Projeto aberto: ${file.name}`);
}

function downloadJson(filename, data) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  downloadBlob(filename, blob);
}

function downloadBlob(filename, blob) {
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  URL.revokeObjectURL(link.href);
  link.remove();
}

function exportImporterScript() {
  const blob = new Blob([GODOT_IMPORTER_SOURCE], { type: "text/plain" });
  downloadBlob("godot_map_importer.gd", blob);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function wireEvents() {
  dom.importAssetsBtn.addEventListener("click", () => dom.assetFiles.click());
  dom.assetFiles.addEventListener("change", event => {
    importAssetFiles(event.target.files).catch(error => {
      console.error(error);
      setStatus("Falha ao importar assets.");
    });
    event.target.value = "";
  });

  dom.importProjectBtn.addEventListener("click", () => dom.projectFile.click());
  dom.projectFile.addEventListener("change", event => {
    const file = event.target.files?.[0];
    if (!file) return;
    importEditorProject(file).catch(error => {
      console.error(error);
      alert(error.message || "Nao foi possivel abrir o projeto.");
    });
    event.target.value = "";
  });

  dom.exportProjectBtn.addEventListener("click", () => downloadJson(`${state.map.name}_editor_project.json`, exportEditorProject()));
  dom.exportMapBtn.addEventListener("click", () => downloadJson(`${state.map.name}_godot_map.json`, exportGodotMap()));
  dom.exportImporterBtn.addEventListener("click", exportImporterScript);
  dom.resizeMapBtn.addEventListener("click", applyMapInputs);

  [dom.mapName, dom.tileSize, dom.mapWidth, dom.mapHeight].forEach(input => {
    input.addEventListener("change", applyMapInputs);
  });

  dom.zoomRange.addEventListener("input", drawMap);
  dom.showGrid.addEventListener("change", drawMap);
  dom.showCollisions.addEventListener("change", drawMap);
  dom.snapDecor.addEventListener("change", drawMap);

  document.querySelectorAll(".tool").forEach(button => {
    button.addEventListener("click", () => {
      state.tool = button.dataset.tool;
      document.querySelectorAll(".tool").forEach(item => item.classList.toggle("active", item === button));
    });
  });

  document.querySelectorAll(".filter").forEach(button => {
    button.addEventListener("click", () => {
      state.filter = button.dataset.kind;
      document.querySelectorAll(".filter").forEach(item => item.classList.toggle("active", item === button));
      renderAssetList();
    });
  });

  dom.assetSearch.addEventListener("input", renderAssetList);
  dom.hideEmptyTiles.addEventListener("change", renderAssetList);
  dom.addLayerBtn.addEventListener("click", () => createLayer(`Camada ${state.map.layers.length + 1}`, "tile"));

  dom.mapCanvas.addEventListener("pointerdown", event => {
    state.isPointerDown = true;
    dom.mapCanvas.setPointerCapture(event.pointerId);
    handleCanvasAction(event);
  });
  dom.mapCanvas.addEventListener("pointermove", event => {
    if (!state.isPointerDown) return;
    if (state.tool === "brush" || state.tool === "erase") handleCanvasAction(event);
  });
  dom.mapCanvas.addEventListener("pointerup", event => {
    state.isPointerDown = false;
    dom.mapCanvas.releasePointerCapture(event.pointerId);
  });
  dom.mapCanvas.addEventListener("pointerleave", () => {
    state.isPointerDown = false;
  });

  [dom.assetKind, dom.assetZ, dom.pivotX, dom.pivotY, dom.collisionEnabled, dom.collisionX, dom.collisionY, dom.collisionW, dom.collisionH].forEach(input => {
    input.addEventListener("change", updateSelectedAssetFromInputs);
  });

  dom.collisionFullBtn.addEventListener("click", () => setCollisionPreset("full"));
  dom.collisionBottomBtn.addEventListener("click", () => setCollisionPreset("bottom"));
  dom.collisionClearBtn.addEventListener("click", () => setCollisionPreset("clear"));
}

const GODOT_IMPORTER_SOURCE = `@tool
extends Node

@export_file("*.json") var map_json_path := ""
@export var target_parent_path: NodePath
@export var clear_previous := true
@export var rebuild_in_editor := false:
	set(value):
		if value:
			import_map()
	get:
		return false

func import_map() -> Node2D:
	if map_json_path.is_empty():
		push_error("Defina map_json_path com o JSON exportado pelo Godot Map Editor.")
		return null

	var text := FileAccess.get_file_as_string(map_json_path)
	if text.is_empty():
		push_error("Nao foi possivel ler o mapa: " + map_json_path)
		return null

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON de mapa invalido.")
		return null

	var parent := get_node_or_null(target_parent_path)
	if parent == null:
		parent = self

	if clear_previous:
		for child in parent.get_children():
			if child.is_in_group("imported_map_editor_map"):
				child.queue_free()

	var root := _build_map(parsed)
	parent.add_child(root)
	if Engine.is_editor_hint():
		root.owner = get_tree().edited_scene_root
		_set_owner_recursive(root, root.owner)
	return root

func _build_map(data: Dictionary) -> Node2D:
	var map_info: Dictionary = data.get("map", {})
	var root := Node2D.new()
	root.name = str(map_info.get("name", "ImportedMap"))
	root.add_to_group("imported_map_editor_map")

	var textures := {}
	for atlas in data.get("atlases", []):
		var atlas_id := str(atlas.get("id", ""))
		var image_path := str(atlas.get("image", ""))
		if atlas_id.is_empty() or image_path.is_empty():
			continue
		var texture := load(image_path)
		if texture == null:
			push_warning("Atlas nao encontrado: " + image_path)
			continue
		textures[atlas_id] = texture

	var sprites := {}
	for sprite in data.get("sprites", []):
		sprites[str(sprite.get("id", ""))] = sprite

	var tile_size := int(map_info.get("tile_size", 16))
	for layer_data in data.get("layers", []):
		if not bool(layer_data.get("visible", true)):
			continue
		var layer := Node2D.new()
		layer.name = str(layer_data.get("name", "Layer"))
		layer.z_index = int(layer_data.get("z_index", 0))
		root.add_child(layer)

		var layer_type := str(layer_data.get("type", "tile"))
		for cell in layer_data.get("cells", []):
			var asset_id := str(cell.get("assetId", cell.get("asset_id", "")))
			if not sprites.has(asset_id):
				continue
			var sprite_data: Dictionary = sprites[asset_id]
			var atlas_id := str(sprite_data.get("atlas_id", ""))
			if not textures.has(atlas_id):
				continue
			var node := _create_sprite_node(textures[atlas_id], sprite_data, cell, layer_type, tile_size)
			layer.add_child(node)
	return root

func _create_sprite_node(atlas: Texture2D, sprite_data: Dictionary, cell: Dictionary, layer_type: String, tile_size: int) -> Sprite2D:
	var region: Array = sprite_data.get("region", [0, 0, tile_size, tile_size])
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))

	var sprite := Sprite2D.new()
	sprite.name = str(sprite_data.get("name", "Sprite"))
	sprite.texture = atlas_texture
	sprite.centered = false
	sprite.z_index = int(sprite_data.get("z", 0))

	var x := int(cell.get("x", 0))
	var y := int(cell.get("y", 0))
	var pos := Vector2(x * tile_size, y * tile_size)
	var kind := str(sprite_data.get("kind", layer_type))
	if kind == "decor" or layer_type == "decor":
		var pivot: Array = sprite_data.get("pivot", [tile_size / 2.0, tile_size])
		pos += Vector2(tile_size / 2.0 - float(pivot[0]), tile_size - float(pivot[1]))
	sprite.position = pos

	var collision: Dictionary = sprite_data.get("collision", {})
	if bool(collision.get("enabled", false)):
		var rect: Array = collision.get("rect", [0, 0, float(region[2]), float(region[3])])
		var body := StaticBody2D.new()
		body.name = "Collision"
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(float(rect[2]), float(rect[3]))
		shape.shape = rectangle
		shape.position = Vector2(float(rect[0]) + float(rect[2]) / 2.0, float(rect[1]) + float(rect[3]) / 2.0)
		body.add_child(shape)
		sprite.add_child(body)
	return sprite

func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
`;

wireEvents();
initDefaultLayers();
renderAtlasList();
renderAssetList();
renderLayers();
syncInspector();
drawMap();
