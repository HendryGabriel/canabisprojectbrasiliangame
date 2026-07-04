/**
 * Godot 4 Autotile & Terrain Rules Editor
 * Core Application Logic
 */

// Model classes representation
class TileRule {
  constructor(name, atlasCoords, mask) {
    this.name = name; // e.g. "top_left_corner"
    this.atlas = atlasCoords; // [x, y] coordinates in terms of tiles
    this.mask = mask; // 3x3 array containing interior/exterior names or "*"
  }
}

class TerrainSet {
  constructor(id, interior, exterior, interiorTransparent = false, exteriorTransparent = false) {
    this.id = id;
    this.interior = interior;
    this.exterior = exterior;
    this.interiorTransparent = interiorTransparent;
    this.exteriorTransparent = exteriorTransparent;
    this.tiles = []; // Array of TileRule
  }

  addOrUpdateRule(name, atlasCoords, mask) {
    // Check if coordinates already mapped in this set
    const existingCoordsIndex = this.tiles.findIndex(t => t.atlas[0] === atlasCoords[0] && t.atlas[1] === atlasCoords[1]);
    if (existingCoordsIndex !== -1) {
      this.tiles.splice(existingCoordsIndex, 1);
    }

    const newRule = new TileRule(name, atlasCoords, mask);
    this.tiles.push(newRule);
    return newRule;
  }

  deleteRuleByCoords(x, y) {
    const index = this.tiles.findIndex(t => t.atlas[0] === x && t.atlas[1] === y);
    if (index !== -1) {
      this.tiles.splice(index, 1);
      return true;
    }
    return false;
  }

  getRuleByName(name) {
    return this.tiles.find(t => t.name === name) || null;
  }

  getRulesByName(name) {
    return this.tiles.filter(t => t.name === name);
  }
  
  getRuleByCoords(x, y) {
    return this.tiles.find(t => t.atlas[0] === x && t.atlas[1] === y) || null;
  }
}

class AutoTileProject {
  constructor() {
    this.version = 1;
    this.imageName = "";
    this.imageElement = new Image();
    this.tileSize = [16, 16]; // [width, height]
    this.margin = 0;
    this.spacing = 0;
    this.terrains = []; // { id, display_name, is_transparent }
    this.sets = []; // Array of TerrainSet
    this.activeSetId = "";
  }

  getActiveSet() {
    return this.sets.find(s => s.id === this.activeSetId) || null;
  }

  addTerrainSet(setId, interior, exterior, interiorTransparent = false, exteriorTransparent = false) {
    // Add terrains to general registry if not exists
    this.registerTerrain(interior, interiorTransparent);
    this.registerTerrain(exterior, exteriorTransparent);

    // Create set
    const set = new TerrainSet(setId, interior, exterior, interiorTransparent, exteriorTransparent);
    this.sets.push(set);
    this.activeSetId = setId;
    return set;
  }

  registerTerrain(id, isTransparent) {
    if (!this.terrains.some(t => t.id === id)) {
      this.terrains.push({
        id: id,
        display_name: id.charAt(0).toUpperCase() + id.slice(1),
        is_transparent: isTransparent
      });
    } else {
      // Update transparency if changed
      const t = this.terrains.find(t => t.id === id);
      t.is_transparent = isTransparent;
    }
  }

  exportJSON() {
    const exportData = {
      version: this.version,
      image: this.imageName,
      tile_size: this.tileSize,
      spacing: this.spacing,
      margin: this.margin,
      terrains: this.terrains,
      sets: this.sets.map(s => ({
        id: s.id,
        interior: s.interior,
        exterior: s.exterior,
        tiles: s.tiles.map(t => ({
          name: t.name,
          atlas: t.atlas,
          mask: t.mask
        }))
      }))
    };
    return JSON.stringify(exportData, null, 2);
  }

  importJSON(jsonString) {
    try {
      const data = JSON.parse(jsonString);
      this.version = data.version || 1;
      this.imageName = data.image || "";
      this.tileSize = data.tile_size || [16, 16];
      this.spacing = data.spacing ?? 0;
      this.margin = data.margin ?? 0;
      this.terrains = data.terrains || [];
      this.sets = [];

      if (data.sets) {
        data.sets.forEach(setData => {
          const interiorObj = this.terrains.find(t => t.id === setData.interior) || {};
          const exteriorObj = this.terrains.find(t => t.id === setData.exterior) || {};
          
          const set = new TerrainSet(
            setData.id,
            setData.interior,
            setData.exterior,
            !!interiorObj.is_transparent,
            !!exteriorObj.is_transparent
          );

          if (setData.tiles) {
            setData.tiles.forEach(tileData => {
              set.addOrUpdateRule(tileData.name, tileData.atlas, tileData.mask);
            });
          }
          this.sets.push(set);
        });
      }

      if (this.sets.length > 0) {
        this.activeSetId = this.sets[0].id;
      } else {
        this.activeSetId = "";
      }

      return true;
    } catch (e) {
      console.error("Erro ao importar JSON:", e);
      alert("JSON inválido ou corrompido!");
      return false;
    }
  }
}

// Visual layout & canvas elements classes
class AtlasView {
  constructor(canvasId, project) {
    this.canvas = document.getElementById(canvasId);
    this.ctx = this.canvas.getContext('2d');
    this.project = project;
    this.selectedTile = [0, 0]; // [x, y] in tile units
    this.hoveredTile = null; // [x, y] or null
    this.scale = 2; // zoom scaling

    // Event listener
    this.canvas.addEventListener('click', (e) => this.handleCanvasClick(e));
    this.canvas.addEventListener('mousemove', (e) => this.handleCanvasMouseMove(e));
    this.canvas.addEventListener('mouseleave', () => {
      this.hoveredTile = null;
      this.draw();
    });
  }

  initImage(imageElement) {
    this.canvas.width = imageElement.naturalWidth * this.scale;
    this.canvas.height = imageElement.naturalHeight * this.scale;
    this.draw();
  }

  handleCanvasClick(e) {
    if (!this.project.imageName) return;
    const rect = this.canvas.getBoundingClientRect();
    const mouseX = (e.clientX - rect.left) / this.scale;
    const mouseY = (e.clientY - rect.top) / this.scale;

    const tileCoord = this.getTileAtlasCoordFromMouse(mouseX, mouseY);
    if (tileCoord) {
      this.selectedTile = tileCoord;
      this.draw();
      
      // Notify controller
      if (window.onTileSelected) {
        window.onTileSelected(tileCoord[0], tileCoord[1]);
      }
    }
  }

  handleCanvasMouseMove(e) {
    if (!this.project.imageName) return;
    const rect = this.canvas.getBoundingClientRect();
    const mouseX = (e.clientX - rect.left) / this.scale;
    const mouseY = (e.clientY - rect.top) / this.scale;

    const tileCoord = this.getTileAtlasCoordFromMouse(mouseX, mouseY);
    if (tileCoord) {
      if (!this.hoveredTile || this.hoveredTile[0] !== tileCoord[0] || this.hoveredTile[1] !== tileCoord[1]) {
        this.hoveredTile = tileCoord;
        this.draw();
      }
    }
  }

  getTileAtlasCoordFromMouse(x, y) {
    const tileW = this.project.tileSize[0];
    const tileH = this.project.tileSize[1];
    const margin = this.project.margin;
    const spacing = this.project.spacing;

    // Check boundary
    if (x < margin || y < margin) return null;

    const col = Math.floor((x - margin) / (tileW + spacing));
    const row = Math.floor((y - margin) / (tileH + spacing));

    // Verify cell bounds
    const cellX = margin + col * (tileW + spacing);
    const cellY = margin + row * (tileH + spacing);

    if (x >= cellX && x < cellX + tileW && y >= cellY && y < cellY + tileH) {
      // Check maximum columns/rows based on image size
      const maxCol = Math.floor((this.project.imageElement.naturalWidth - margin) / (tileW + spacing));
      const maxRow = Math.floor((this.project.imageElement.naturalHeight - margin) / (tileH + spacing));
      
      if (col >= 0 && col < maxCol && row >= 0 && row < maxRow) {
        return [col, row];
      }
    }
    return null;
  }

  draw() {
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.ctx.imageSmoothingEnabled = false;

    if (!this.project.imageName || !this.project.imageElement.complete) return;

    // Draw the image
    this.ctx.drawImage(
      this.project.imageElement,
      0, 0, this.project.imageElement.naturalWidth, this.project.imageElement.naturalHeight,
      0, 0, this.canvas.width, this.canvas.height
    );

    const tileW = this.project.tileSize[0] * this.scale;
    const tileH = this.project.tileSize[1] * this.scale;
    const margin = this.project.margin * this.scale;
    const spacing = this.project.spacing * this.scale;
    const showGrid = document.getElementById('checkShowGrid').checked;
    const showRuleIndicators = document.getElementById('checkShowRuleIndicators').checked;

    const maxCol = Math.floor((this.project.imageElement.naturalWidth - this.project.margin) / (this.project.tileSize[0] + this.project.spacing));
    const maxRow = Math.floor((this.project.imageElement.naturalHeight - this.project.margin) / (this.project.tileSize[1] + this.project.spacing));

    const activeSet = this.project.getActiveSet();

    for (let r = 0; r < maxRow; r++) {
      for (let c = 0; c < maxCol; c++) {
        const x = margin + c * (tileW + spacing);
        const y = margin + r * (tileH + spacing);

        // Draw regular grid
        if (showGrid) {
          this.ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
          this.ctx.lineWidth = 1;
          this.ctx.strokeRect(x, y, tileW, tileH);
        }

        // Draw active rule indicators (little dots/checkmarks)
        if (showRuleIndicators && activeSet) {
          const rule = activeSet.getRuleByCoords(c, r);
          if (rule) {
            this.ctx.fillStyle = '#2ec4b6';
            this.ctx.beginPath();
            this.ctx.arc(x + 6, y + 6, 3, 0, Math.PI * 2);
            this.ctx.fill();
            
            // Draw a small font indicator
            this.ctx.fillStyle = '#2ec4b6';
            this.ctx.font = '8px Outfit';
            this.ctx.fillText(rule.name.substring(0, 4), x + 3, y + tileH - 3);
          }
        }
      }
    }

    // Draw hovered cell
    if (this.hoveredTile) {
      const hX = margin + this.hoveredTile[0] * (tileW + spacing);
      const hY = margin + this.hoveredTile[1] * (tileH + spacing);
      this.ctx.strokeStyle = 'rgba(71, 160, 255, 0.6)';
      this.ctx.lineWidth = 2;
      this.ctx.strokeRect(hX, hY, tileW, tileH);
    }

    // Draw selected cell
    if (this.selectedTile) {
      const sX = margin + this.selectedTile[0] * (tileW + spacing);
      const sY = margin + this.selectedTile[1] * (tileH + spacing);
      this.ctx.strokeStyle = '#ffb703';
      this.ctx.lineWidth = 2.5;
      this.ctx.strokeRect(sX, sY, tileW, tileH);
      
      // Draw inner glow
      this.ctx.strokeStyle = 'rgba(255, 183, 3, 0.3)';
      this.ctx.lineWidth = 4;
      this.ctx.strokeRect(sX + 2, sY + 2, tileW - 4, tileH - 4);
    }
  }
}

class MaskEditor {
  constructor(gridContainerId) {
    this.container = document.getElementById(gridContainerId);
    this.values = [
      ["*", "*", "*"],
      ["*", "*", "*"],
      ["*", "*", "*"]
    ]; // default all wildcard
    this.initGrid();
  }

  initGrid() {
    this.container.innerHTML = "";
    for (let r = 0; r < 3; r++) {
      for (let c = 0; c < 3; c++) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "mask-cell any";
        button.textContent = "*";
        button.dataset.row = r;
        button.dataset.col = c;
        button.addEventListener("click", () => this.toggleCell(r, c, button));
        this.container.appendChild(button);
      }
    }
  }

  toggleCell(row, col, element) {
    const current = this.values[row][col];
    let next = "*";
    if (current === "*") {
      next = "interior";
    } else if (current === "interior") {
      next = "exterior";
    } else {
      next = "*";
    }
    this.setCell(row, col, next, element);
  }

  setCell(row, col, value, element) {
    this.values[row][col] = value;
    if (!element) {
      element = this.container.querySelector(`[data-row="${row}"][data-col="${col}"]`);
    }
    
    // Style update
    element.className = "mask-cell " + value;
    if (value === "interior") {
      element.textContent = "IN";
    } else if (value === "exterior") {
      element.textContent = "EX";
    } else {
      element.textContent = "*";
    }
  }

  getMaskValues() {
    return JSON.parse(JSON.stringify(this.values));
  }

  setMaskValues(mask) {
    for (let r = 0; r < 3; r++) {
      for (let c = 0; c < 3; c++) {
        this.setCell(r, c, mask[r][c]);
      }
    }
  }

  applyPreset(name) {
    const presets = {
      center: [
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"]
      ],
      top_edge: [
        ["exterior", "exterior", "exterior"],
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"]
      ],
      bottom_edge: [
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"],
        ["exterior", "exterior", "exterior"]
      ],
      left_edge: [
        ["exterior", "interior", "interior"],
        ["exterior", "interior", "interior"],
        ["exterior", "interior", "interior"]
      ],
      right_edge: [
        ["interior", "interior", "exterior"],
        ["interior", "interior", "exterior"],
        ["interior", "interior", "exterior"]
      ],
      top_left_corner: [
        ["exterior", "exterior", "exterior"],
        ["exterior", "interior", "interior"],
        ["exterior", "interior", "interior"]
      ],
      top_right_corner: [
        ["exterior", "exterior", "exterior"],
        ["interior", "interior", "exterior"],
        ["interior", "interior", "exterior"]
      ],
      bottom_left_corner: [
        ["exterior", "interior", "interior"],
        ["exterior", "interior", "interior"],
        ["exterior", "exterior", "exterior"]
      ],
      bottom_right_corner: [
        ["interior", "interior", "exterior"],
        ["interior", "interior", "exterior"],
        ["exterior", "exterior", "exterior"]
      ],
      inner_top_left_corner: [
        ["exterior", "interior", "interior"],
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"]
      ],
      inner_top_right_corner: [
        ["interior", "interior", "exterior"],
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"]
      ],
      inner_bottom_left_corner: [
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"],
        ["exterior", "interior", "interior"]
      ],
      inner_bottom_right_corner: [
        ["interior", "interior", "interior"],
        ["interior", "interior", "interior"],
        ["interior", "interior", "exterior"]
      ],
      isolated: [
        ["exterior", "exterior", "exterior"],
        ["exterior", "interior", "exterior"],
        ["exterior", "exterior", "exterior"]
      ],
      horizontal_single: [
        ["exterior", "exterior", "exterior"],
        ["interior", "interior", "interior"],
        ["exterior", "exterior", "exterior"]
      ],
      vertical_single: [
        ["exterior", "interior", "exterior"],
        ["exterior", "interior", "exterior"],
        ["exterior", "interior", "exterior"]
      ]
    };

    if (presets[name]) {
      this.setMaskValues(presets[name]);
    }
  }
}

class RuleMatcher {
  static getSpecificity(mask) {
    let wildcards = 0;
    for (let r = 0; r < 3; r++) {
      for (let c = 0; c < 3; c++) {
        if (mask[r][c] === "*") wildcards++;
      }
    }
    return 9 - wildcards;
  }

  static match(localGrid, rules, interiorId, exteriorId, cellX = 0, cellY = 0) {
    let matchingRules = [];
    let maxSpecificity = -1;

    for (const rule of rules) {
      let matches = true;
      
      for (let r = 0; r < 3; r++) {
        for (let c = 0; c < 3; c++) {
          const ruleVal = rule.mask[r][c];
          
          if (ruleVal === "*") continue;
          
          const concreteId = ruleVal === "interior" ? interiorId : exteriorId;
          const neighborId = localGrid[r][c];

          if (concreteId !== neighborId) {
            matches = false;
            break;
          }
        }
        if (!matches) break;
      }

      if (matches) {
        const spec = this.getSpecificity(rule.mask);
        if (spec > maxSpecificity) {
          maxSpecificity = spec;
          matchingRules = [rule];
        } else if (spec === maxSpecificity) {
          matchingRules.push(rule);
        }
      }
    }

    if (matchingRules.length === 0) return null;
    if (matchingRules.length === 1) return matchingRules[0];
    
    // Deterministic selection based on cell coordinates to prevent flickering
    const seed = (cellY * 17 + cellX * 23) % matchingRules.length;
    return matchingRules[seed];
  }
}

class PreviewRenderer {
  constructor(canvasId, project) {
    this.canvas = document.getElementById(canvasId);
    this.ctx = this.canvas.getContext('2d');
    this.project = project;
    this.gridW = 20;
    this.gridH = 20;
    this.grid = []; // 20x20 containing terrain IDs
    this.scale = 2; // preview zoom
  }

  generateGrid(mode, interiorId, exteriorId) {
    this.grid = Array(this.gridH).fill().map(() => Array(this.gridW).fill(exteriorId));

    if (mode === "rectangle") {
      for (let y = 4; y < 16; y++) {
        for (let x = 4; x < 16; x++) {
          this.grid[y][x] = interiorId;
        }
      }
    } else if (mode === "island") {
      const centerX = this.gridW / 2;
      const centerY = this.gridH / 2;
      for (let y = 0; y < this.gridH; y++) {
        for (let x = 0; x < this.gridW; x++) {
          const dx = x - centerX;
          const dy = y - centerY;
          const angle = Math.atan2(dy, dx);
          const dist = Math.sqrt(dx*dx + dy*dy);
          // Blob radius using sine waves
          const r = 5.5 + Math.sin(angle * 5) * 1.5 + Math.cos(angle * 3) * 0.8;
          if (dist < r) {
            this.grid[y][x] = interiorId;
          }
        }
      }
    } else if (mode === "hole") {
      // Solid interior, central exterior hole
      for (let y = 2; y < 18; y++) {
        for (let x = 2; x < 18; x++) {
          this.grid[y][x] = interiorId;
        }
      }
      const centerX = this.gridW / 2;
      const centerY = this.gridH / 2;
      for (let y = 0; y < this.gridH; y++) {
        for (let x = 0; x < this.gridW; x++) {
          const dx = x - centerX;
          const dy = y - centerY;
          const dist = Math.sqrt(dx*dx + dy*dy);
          if (dist < 4.2) {
            this.grid[y][x] = exteriorId;
          }
        }
      }
    } else if (mode === "corridor") {
      // Horizontal corridor and vertical corridor (T junction)
      for (let x = 2; x < 18; x++) {
        this.grid[8][x] = interiorId;
        this.grid[9][x] = interiorId;
        this.grid[10][x] = interiorId;
      }
      for (let y = 4; y < 16; y++) {
        this.grid[y][9] = interiorId;
        this.grid[y][10] = interiorId;
      }
    } else if (mode === "thin_line") {
      // Cross 1 tile wide
      for (let x = 2; x < 18; x++) {
        this.grid[10][x] = interiorId;
      }
      for (let y = 2; y < 18; y++) {
        this.grid[y][10] = interiorId;
      }
    } else if (mode === "random") {
      for (let y = 2; y < this.gridH - 2; y++) {
        for (let x = 2; x < this.gridW - 2; x++) {
          if (Math.random() < 0.38) {
            this.grid[y][x] = interiorId;
          }
        }
      }
    }
  }

  buildNeighborMask(x, y, exteriorId) {
    const mask = [
      ["", "", ""],
      ["", "", ""],
      ["", "", ""]
    ];

    for (let r = -1; r <= 1; r++) {
      for (let c = -1; c <= 1; c++) {
        const ny = y + r;
        const nx = x + c;

        // Boundary is considered exterior
        if (nx < 0 || ny < 0 || nx >= this.gridW || ny >= this.gridH) {
          mask[r + 1][c + 1] = exteriorId;
        } else {
          mask[r + 1][c + 1] = this.grid[ny][nx];
        }
      }
    }
    return mask;
  }

  draw(activeSet) {
    const tileW = this.project.tileSize[0];
    const tileH = this.project.tileSize[1];
    
    this.canvas.width = this.gridW * tileW * this.scale;
    this.canvas.height = this.gridH * tileH * this.scale;

    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.ctx.imageSmoothingEnabled = false;

    const showGrid = document.getElementById('checkPreviewGrid').checked;

    if (!activeSet) {
      // Paint generic solid color grid
      for (let y = 0; y < this.gridH; y++) {
        for (let x = 0; x < this.gridW; x++) {
          const isInterior = this.grid[y][x] === "rock"; // mock default
          this.ctx.fillStyle = isInterior ? 'rgba(46, 196, 182, 0.4)' : 'rgba(231, 29, 54, 0.1)';
          this.ctx.fillRect(x * tileW * this.scale, y * tileH * this.scale, tileW * this.scale, tileH * this.scale);
          if (showGrid) {
            this.ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
            this.ctx.strokeRect(x * tileW * this.scale, y * tileH * this.scale, tileW * this.scale, tileH * this.scale);
          }
        }
      }
      return;
    }

    const interiorId = activeSet.interior;
    const exteriorId = activeSet.exterior;

    for (let y = 0; y < this.gridH; y++) {
      for (let x = 0; x < this.gridW; x++) {
        const cellType = this.grid[y][x];
        const screenX = x * tileW * this.scale;
        const screenY = y * tileH * this.scale;

        if (cellType === interiorId) {
          const localGrid = this.buildNeighborMask(x, y, exteriorId);
          const matchedRule = RuleMatcher.match(localGrid, activeSet.tiles, interiorId, exteriorId, x, y);

          if (matchedRule) {
            // Draw matching sprite tile
            if (this.project.imageName && this.project.imageElement.complete) {
              const atlasX = this.project.margin + matchedRule.atlas[0] * (this.project.tileSize[0] + this.project.spacing);
              const atlasY = this.project.margin + matchedRule.atlas[1] * (this.project.tileSize[1] + this.project.spacing);
              
              this.ctx.drawImage(
                this.project.imageElement,
                atlasX, atlasY, this.project.tileSize[0], this.project.tileSize[1],
                screenX, screenY, tileW * this.scale, tileH * this.scale
              );
            } else {
              // Neutral sprite loading fallback
              this.ctx.fillStyle = 'rgba(46, 196, 182, 0.8)';
              this.ctx.fillRect(screenX, screenY, tileW * this.scale, tileH * this.scale);
            }
          } else {
            // Fallback match to "center" rules if exists
            const centerRules = activeSet.getRulesByName("center");
            if (centerRules.length > 0 && this.project.imageName && this.project.imageElement.complete) {
              const seed = (y * 17 + x * 23) % centerRules.length;
              const centerRule = centerRules[seed];
              const atlasX = this.project.margin + centerRule.atlas[0] * (this.project.tileSize[0] + this.project.spacing);
              const atlasY = this.project.margin + centerRule.atlas[1] * (this.project.tileSize[1] + this.project.spacing);
              
              this.ctx.drawImage(
                this.project.imageElement,
                atlasX, atlasY, this.project.tileSize[0], this.project.tileSize[1],
                screenX, screenY, tileW * this.scale, tileH * this.scale
              );
              
              // Draw small error overlay dot
              this.ctx.fillStyle = 'rgba(255, 0, 255, 0.4)';
              this.ctx.fillRect(screenX, screenY, tileW * this.scale, tileH * this.scale);
            } else {
              // Hot pink/magenta fallback for unmapped tiles
              this.ctx.fillStyle = '#ff00ff';
              this.ctx.fillRect(screenX, screenY, tileW * this.scale, tileH * this.scale);
            }
          }
        } else {
          // Draw exterior tile
          // If we have an "exterior_center" or similar rule, we could draw it, but standard grass color is clean
          this.ctx.fillStyle = activeSet.exteriorTransparent ? 'rgba(0, 0, 0, 0)' : 'rgba(47, 52, 71, 0.7)';
          this.ctx.fillRect(screenX, screenY, tileW * this.scale, tileH * this.scale);
        }

        // Draw grid
        if (showGrid) {
          this.ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
          this.ctx.strokeRect(screenX, screenY, tileW * this.scale, tileH * this.scale);
        }
      }
    }
  }
}

// Controller Initialization
const project = new AutoTileProject();
let atlasView = null;
let maskEditor = null;
let previewRenderer = null;

// DOM Elements
const el = {
  pngFile: document.getElementById("pngFileInput"),
  jsonFile: document.getElementById("jsonFileInput"),
  btnImportJson: document.getElementById("btnImportJson"),
  btnExportJson: document.getElementById("btnExportJson"),
  btnCopyJson: document.getElementById("btnCopyJson"),
  
  tileW: document.getElementById("inputTileW"),
  tileH: document.getElementById("inputTileH"),
  margin: document.getElementById("inputMargin"),
  spacing: document.getElementById("inputSpacing"),
  gridToggle: document.getElementById("checkShowGrid"),
  ruleIndicatorsToggle: document.getElementById("checkShowRuleIndicators"),

  selectTerrainSet: document.getElementById("selectTerrainSet"),
  setIdInput: document.getElementById("inputSetId"),
  interiorInput: document.getElementById("inputInteriorId"),
  exteriorInput: document.getElementById("inputExteriorId"),
  interiorTransparent: document.getElementById("checkInteriorTransparent"),
  exteriorTransparent: document.getElementById("checkExteriorTransparent"),
  btnCreateSet: document.getElementById("btnCreateSet"),

  ruleNameInput: document.getElementById("inputRuleName"),
  btnSaveRule: document.getElementById("btnSaveRule"),
  btnDeleteRule: document.getElementById("btnDeleteRule"),
  rulesList: document.getElementById("rulesList"),
  
  previewMode: document.getElementById("selectPreviewMode"),
  btnRefreshPreview: document.getElementById("btnRefreshPreview"),
  previewGridToggle: document.getElementById("checkPreviewGrid"),
  
  validationLog: document.getElementById("validationLog"),
  jsonOutput: document.getElementById("textareaJsonOutput"),
  appStatus: document.getElementById("appStatus")
};

// Start application
window.addEventListener('DOMContentLoaded', () => {
  atlasView = new AtlasView("atlasCanvas", project);
  maskEditor = new MaskEditor("maskGrid");
  previewRenderer = new PreviewRenderer("previewCanvas", project);

  setupEventListeners();
  updateRulesListUI();
  validateProject();
});

function setupEventListeners() {
  // 1. Settings listeners
  el.pngFile.addEventListener("change", handlePngUpload);
  el.tileW.addEventListener("change", updateSettings);
  el.tileH.addEventListener("change", updateSettings);
  el.margin.addEventListener("change", updateSettings);
  el.spacing.addEventListener("change", updateSettings);
  el.gridToggle.addEventListener("change", () => atlasView.draw());
  el.ruleIndicatorsToggle.addEventListener("change", () => atlasView.draw());
  
  // 2. Terrain sets listeners
  el.btnCreateSet.addEventListener("click", handleCreateSet);
  el.selectTerrainSet.addEventListener("change", handleSetSelection);

  // 3. Tile Rule Saving listeners
  el.btnSaveRule.addEventListener("click", handleSaveRule);
  el.btnDeleteRule.addEventListener("click", handleDeleteRule);

  // 4. Presets listeners
  document.querySelectorAll(".preset-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      maskEditor.applyPreset(btn.dataset.preset);
      if (!el.ruleNameInput.value.trim()) {
        el.ruleNameInput.value = btn.dataset.preset;
      }
    });
  });

  // 5. Preview live controls
  el.btnRefreshPreview.addEventListener("click", refreshPreview);
  el.previewMode.addEventListener("change", refreshPreview);
  el.previewGridToggle.addEventListener("change", () => {
    previewRenderer.draw(project.getActiveSet());
  });

  // 6. JSON Actions
  el.btnImportJson.addEventListener("click", () => el.jsonFile.click());
  el.jsonFile.addEventListener("change", handleJsonImport);
  el.btnExportJson.addEventListener("click", handleJsonExport);
  el.btnCopyJson.addEventListener("click", handleJsonCopy);

  // Callback from canvas clicks
  window.onTileSelected = (col, row) => {
    el.ruleNameInput.value = "";
    
    const activeSet = project.getActiveSet();
    if (activeSet) {
      const existingRule = activeSet.getRuleByCoords(col, row);
      if (existingRule) {
        el.ruleNameInput.value = existingRule.name;
        maskEditor.setMaskValues(existingRule.mask);
      } else {
        // Clear editor selection but suggest name based on coordinates
        maskEditor.setMaskValues([["*", "*", "*"], ["*", "*", "*"], ["*", "*", "*"]]);
      }
      
      // Update validation visual list items selection highlight
      document.querySelectorAll(".rule-item").forEach(item => {
        item.classList.remove("selected");
        if (existingRule && item.dataset.name === existingRule.name) {
          item.classList.add("selected");
        }
      });
    }
  };
}

// Event Handlers
function handlePngUpload(e) {
  const file = e.target.files[0];
  if (!file) return;

  project.imageName = file.name;
  
  const reader = new FileReader();
  reader.onload = (event) => {
    project.imageElement.onload = () => {
      atlasView.initImage(project.imageElement);
      el.appStatus.textContent = `Carregado: ${file.name}`;
      refreshPreview();
      validateProject();
      updateJsonOutput();
    };
    project.imageElement.src = event.target.result;
  };
  reader.readAsDataURL(file);
}

function updateSettings() {
  project.tileSize = [parseInt(el.tileW.value) || 16, parseInt(el.tileH.value) || 16];
  project.margin = parseInt(el.margin.value) || 0;
  project.spacing = parseInt(el.spacing.value) || 0;
  
  if (project.imageElement.src) {
    atlasView.initImage(project.imageElement);
  }
  refreshPreview();
  validateProject();
  updateJsonOutput();
}

function handleCreateSet() {
  const setId = el.setIdInput.value.trim();
  const interior = el.interiorInput.value.trim();
  const exterior = el.exteriorInput.value.trim();
  const intTrans = el.interiorTransparent.checked;
  const extTrans = el.exteriorTransparent.checked;

  if (!setId || !interior || !exterior) {
    alert("Preencha todos os campos do Terrain Set!");
    return;
  }

  if (project.sets.some(s => s.id === setId)) {
    alert("Já existe um Terrain Set com este ID!");
    return;
  }

  project.addTerrainSet(setId, interior, exterior, intTrans, extTrans);
  
  // Update select input options
  const option = document.createElement("option");
  option.value = setId;
  option.textContent = `${setId} (${interior} ➔ ${exterior})`;
  el.selectTerrainSet.appendChild(option);
  el.selectTerrainSet.value = setId;

  // Reset creation form
  el.setIdInput.value = "";
  
  handleSetSelection();
}

function handleSetSelection() {
  project.activeSetId = el.selectTerrainSet.value;
  updateRulesListUI();
  refreshPreview();
  validateProject();
  updateJsonOutput();
  atlasView.draw();
}

function handleSaveRule() {
  const activeSet = project.getActiveSet();
  if (!activeSet) {
    alert("Selecione ou crie um Terrain Set ativo antes de salvar regras!");
    return;
  }

  const name = el.ruleNameInput.value.trim();
  if (!name) {
    alert("Insira um nome válido para a regra!");
    return;
  }

  const mask = maskEditor.getMaskValues();
  activeSet.addOrUpdateRule(name, [...atlasView.selectedTile], mask);
  
  updateRulesListUI();
  refreshPreview();
  validateProject();
  updateJsonOutput();
  atlasView.draw();
}

function handleDeleteRule() {
  const activeSet = project.getActiveSet();
  if (!activeSet) return;

  const [selX, selY] = atlasView.selectedTile;
  if (activeSet.deleteRuleByCoords(selX, selY)) {
    el.ruleNameInput.value = "";
    maskEditor.setMaskValues([["*", "*", "*"], ["*", "*", "*"], ["*", "*", "*"]]);
    updateRulesListUI();
    refreshPreview();
    validateProject();
    updateJsonOutput();
    atlasView.draw();
  }
}

function refreshPreview() {
  const activeSet = project.getActiveSet();
  const interior = activeSet ? activeSet.interior : "rock";
  const exterior = activeSet ? activeSet.exterior : "grass";

  previewRenderer.generateGrid(el.previewMode.value, interior, exterior);
  previewRenderer.draw(activeSet);
}

function updateRulesListUI() {
  el.rulesList.innerHTML = "";
  const activeSet = project.getActiveSet();

  if (!activeSet || activeSet.tiles.length === 0) {
    el.rulesList.innerHTML = `<div class="empty-state">Nenhuma regra criada. Selecione um tile e configure a máscara para criar.</div>`;
    return;
  }

  activeSet.tiles.forEach(rule => {
    const item = document.createElement("div");
    item.className = "rule-item";
    item.dataset.name = rule.name;
    if (el.ruleNameInput.value === rule.name) {
      item.classList.add("selected");
    }

    const tileW = project.tileSize[0];
    const tileH = project.tileSize[1];
    const margin = project.margin;
    const spacing = project.spacing;
    
    // Draw miniature coordinates
    const sx = margin + rule.atlas[0] * (tileW + spacing);
    const sy = margin + rule.atlas[1] * (tileH + spacing);

    // Create item contents
    item.innerHTML = `
      <div class="rule-item-info">
        <span class="rule-item-name">${rule.name}</span>
        <span class="rule-item-meta">atlas: [${rule.atlas[0]}, ${rule.atlas[1]}]</span>
      </div>
      <div class="rule-item-thumb" id="thumb_${rule.name}"></div>
    `;

    // Render tile thumbnail in list
    item.addEventListener("click", () => {
      el.ruleNameInput.value = rule.name;
      maskEditor.setMaskValues(rule.mask);
      atlasView.selectedTile = [...rule.atlas];
      atlasView.draw();
      
      document.querySelectorAll(".rule-item").forEach(i => i.classList.remove("selected"));
      item.classList.add("selected");
    });

    el.rulesList.appendChild(item);

    // Dynamic background clip for the rule thumbnail if PNG is loaded
    if (project.imageName && project.imageElement.src) {
      const thumb = item.querySelector(`#thumb_${rule.name}`);
      const factor = 24 / tileW; // scale thumbnail to fit 24px box
      thumb.style.backgroundImage = `url("${project.imageElement.src}")`;
      thumb.style.backgroundPosition = `-${sx * factor}px -${sy * factor}px`;
      thumb.style.backgroundSize = `${project.imageElement.naturalWidth * factor}px ${project.imageElement.naturalHeight * factor}px`;
    }
  });
}

function validateProject() {
  const logs = [];
  
  if (!project.imageName || !project.imageElement.src) {
    logs.push({ type: 'warning', text: "⚠ Nenhuma imagem de atlas PNG carregada." });
    updateValidationUI(logs);
    return;
  }
  
  if (project.tileSize[0] <= 0 || project.tileSize[1] <= 0) {
    logs.push({ type: 'error', text: "✖ Erro: Tamanho do tile inválido." });
  }
  
  const activeSet = project.getActiveSet();
  if (!activeSet) {
    logs.push({ type: 'warning', text: "⚠ Nenhum Terrain Set criado ou ativo." });
    updateValidationUI(logs);
    return;
  }
  
  if (!activeSet.interior || !activeSet.exterior) {
    logs.push({ type: 'error', text: "✖ Erro: Terreno Interior ou Exterior não definidos no set." });
  }
  
  // Check essential rules
  const essential = ['center', 'top_edge', 'bottom_edge', 'left_edge', 'right_edge', 'top_left_corner', 'top_right_corner', 'bottom_left_corner', 'bottom_right_corner'];
  const rules = activeSet.tiles;
  const ruleNames = rules.map(r => r.name);
  
  const missing = essential.filter(name => !ruleNames.includes(name));
  if (missing.length > 0) {
    logs.push({ type: 'warning', text: `⚠ Regras essenciais faltando: ${missing.join(', ')}` });
  }
  
  // Count texture variations
  const uniqueNames = new Set(ruleNames);
  if (rules.length > uniqueNames.size) {
    logs.push({ type: 'success', text: `✔ Info: ${rules.length - uniqueNames.size} variações de texturas configuradas.` });
  }
  
  if (logs.length === 0) {
    logs.push({ type: 'success', text: "✔ Todas as regras validadas com sucesso!" });
  }
  
  updateValidationUI(logs);
}

function updateValidationUI(logs) {
  el.validationLog.innerHTML = "";
  logs.forEach(log => {
    const item = document.createElement("div");
    item.className = "log-item " + log.type;
    item.textContent = log.text;
    el.validationLog.appendChild(item);
  });
}

function updateJsonOutput() {
  el.jsonOutput.value = project.exportJSON();
}

// JSON Imports/Exports
function handleJsonImport(e) {
  const file = e.target.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = async (event) => {
    const success = project.importJSON(event.target.result);
    if (success) {
      // Restore Settings inputs
      el.tileW.value = project.tileSize[0];
      el.tileH.value = project.tileSize[1];
      el.margin.value = project.margin;
      el.spacing.value = project.spacing;

      // Populate Select sets dropwdown
      el.selectTerrainSet.innerHTML = "";
      project.sets.forEach(set => {
        const option = document.createElement("option");
        option.value = set.id;
        option.textContent = `${set.id} (${set.interior} ➔ ${set.exterior})`;
        el.selectTerrainSet.appendChild(option);
      });
      el.selectTerrainSet.value = project.activeSetId;

      // Attempt to load PNG if it's placed in same folder
      if (project.imageName) {
        el.appStatus.textContent = `JSON Carregado: ${file.name}. Aguardando PNG: ${project.imageName}`;
        alert(`JSON Carregado! Por favor, selecione o arquivo de imagem correspondente (${project.imageName}) para habilitar visualização.`);
      }

      handleSetSelection();
    }
  };
  reader.readAsText(file);
  e.target.value = "";
}

function handleJsonExport() {
  const jsonString = project.exportJSON();
  const blob = new Blob([jsonString], { type: "application/json" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  
  const baseName = project.imageName 
    ? project.imageName.replace(/\.[^/.]+$/, "") 
    : "autotile";
  
  link.download = `${baseName}_autotile_rules.json`;
  document.body.appendChild(link);
  link.click();
  URL.revokeObjectURL(link.href);
  link.remove();
}

function handleJsonCopy() {
  const jsonString = project.exportJSON();
  navigator.clipboard.writeText(jsonString).then(() => {
    alert("JSON copiado para a área de transferência!");
  }).catch(err => {
    console.error("Erro ao copiar:", err);
  });
}
