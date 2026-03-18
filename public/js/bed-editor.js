// Bed Editor — interactive SVG with drag-and-drop plant positioning
// Used inside the bed detail modal in succession.erb

function bedEditor() {
  return {
    bed: null,
    cell: 10,
    dragging: null,     // { plantId, startX, startY, origGridX, origGridY }
    dragOffset: null,    // { dx, dy } offset from plant origin to mouse
    hoverGrid: null,     // { x, y } grid cell the drag is over
    selectedPlant: null, // plant object for info popover
    saving: false,

    init() {
      // Get bed data from parent planTab component
      const parent = this.$el.closest('[x-data]');
      if (parent && parent._x_dataStack) {
        this.bed = parent._x_dataStack[0]?.activeBed;
      }
    },

    get svgWidth() { return (this.bed?.grid_cols || 10) * this.cell; },
    get svgHeight() { return (this.bed?.grid_rows || 10) * this.cell; },
    get bedColor() { return this.bed?.canvas_color || '#e8e4df'; },

    // Convert mouse/touch event to SVG grid coordinates
    eventToGrid(e, svg) {
      const pt = svg.createSVGPoint();
      const touch = e.touches ? e.touches[0] : e;
      pt.x = touch.clientX;
      pt.y = touch.clientY;
      const svgPt = pt.matrixTransform(svg.getScreenCTM().inverse());
      return {
        x: Math.floor(svgPt.x / this.cell),
        y: Math.floor(svgPt.y / this.cell),
        svgX: svgPt.x,
        svgY: svgPt.y
      };
    },

    // Start dragging a plant
    startDrag(e, plant) {
      e.preventDefault();
      e.stopPropagation();
      const svg = this.$refs.bedSvg;
      if (!svg) return;

      const grid = this.eventToGrid(e, svg);
      this.dragging = {
        plantId: plant.id,
        origGridX: plant.grid_x,
        origGridY: plant.grid_y
      };
      this.dragOffset = {
        dx: grid.svgX - (plant.grid_x * this.cell),
        dy: grid.svgY - (plant.grid_y * this.cell)
      };
      this.hoverGrid = { x: plant.grid_x, y: plant.grid_y };
      this.selectedPlant = null; // close popover during drag
    },

    // Handle drag movement
    onDragMove(e) {
      if (!this.dragging) return;
      e.preventDefault();
      const svg = this.$refs.bedSvg;
      if (!svg) return;

      const grid = this.eventToGrid(e, svg);
      const plant = this.bed.plants.find(p => p.id === this.dragging.plantId);
      if (!plant) return;

      // Snap to grid, clamped to bed bounds
      const maxX = (this.bed.grid_cols || 10) - (plant.grid_w || 1);
      const maxY = (this.bed.grid_rows || 10) - (plant.grid_h || 1);
      this.hoverGrid = {
        x: Math.max(0, Math.min(maxX, Math.floor((grid.svgX - this.dragOffset.dx) / this.cell))),
        y: Math.max(0, Math.min(maxY, Math.floor((grid.svgY - this.dragOffset.dy) / this.cell)))
      };
    },

    // End drag — save new position
    async endDrag(e) {
      if (!this.dragging) return;

      const plant = this.bed.plants.find(p => p.id === this.dragging.plantId);
      const newX = this.hoverGrid?.x ?? this.dragging.origGridX;
      const newY = this.hoverGrid?.y ?? this.dragging.origGridY;
      const moved = newX !== this.dragging.origGridX || newY !== this.dragging.origGridY;

      this.dragging = null;
      this.hoverGrid = null;
      this.dragOffset = null;

      if (!moved || !plant) return;

      // Optimistic update
      plant.grid_x = newX;
      plant.grid_y = newY;

      // Save to server
      this.saving = true;
      try {
        await fetch(`/plants/${plant.id}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ grid_x: newX, grid_y: newY })
        });
      } catch(err) {
        console.error('Failed to save plant position:', err);
        // Revert on failure
        plant.grid_x = this.dragging?.origGridX ?? plant.grid_x;
        plant.grid_y = this.dragging?.origGridY ?? plant.grid_y;
      }
      this.saving = false;
    },

    // Click plant (not drag) — show info
    onPlantClick(e, plant) {
      if (this.dragging) return;
      e.stopPropagation();
      this.selectedPlant = this.selectedPlant?.id === plant.id ? null : plant;
    },

    // Get display position for a plant (uses hover position during drag)
    plantX(plant) {
      if (this.dragging?.plantId === plant.id && this.hoverGrid) return this.hoverGrid.x * this.cell;
      return (plant.grid_x || 0) * this.cell;
    },
    plantY(plant) {
      if (this.dragging?.plantId === plant.id && this.hoverGrid) return this.hoverGrid.y * this.cell;
      return (plant.grid_y || 0) * this.cell;
    },
    plantW(plant) { return (plant.grid_w || 1) * this.cell; },
    plantH(plant) { return (plant.grid_h || 1) * this.cell; },

    isDragging(plant) {
      return this.dragging?.plantId === plant.id;
    },

    plantColor(cropType) {
      const c = (cropType || '').toLowerCase();
      if (['tomato','pepper','eggplant'].includes(c)) return '#ef4444';
      if (['lettuce','spinach','chard','kale'].includes(c)) return '#22c55e';
      if (['herb','basil'].includes(c)) return '#10b981';
      if (c === 'flower') return '#eab308';
      if (['cucumber','squash','melon','zucchini'].includes(c)) return '#3b82f6';
      if (['radish','carrot','onion'].includes(c)) return '#f97316';
      if (['bean','pea'].includes(c)) return '#8b5cf6';
      return '#9ca3af';
    },

    plantAbbr(cropType) {
      const abbrs = {
        tomato:'T', pepper:'P', eggplant:'E',
        lettuce:'Le', spinach:'Sp', chard:'Ch', kale:'K',
        herb:'H', basil:'Ba', flower:'F',
        cucumber:'Cu', squash:'Sq', melon:'Me', zucchini:'Zu',
        radish:'R', carrot:'Ca', onion:'On', bean:'Be', pea:'Pe'
      };
      return abbrs[(cropType||'').toLowerCase()] || (cropType||'?').slice(0,2);
    }
  }
}
