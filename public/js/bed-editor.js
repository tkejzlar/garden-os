// Bed Editor — interactive SVG with drag-and-drop plant positioning
// SVG is rendered imperatively (Alpine x-for doesn't work in SVG namespace)
// Alpine manages state; SVG rebuilds on data change

function bedEditor() {
  return {
    bed: null,
    cell: 10,
    dragging: null,
    dragOffset: null,
    hoverGrid: null,
    selectedPlant: null,
    saving: false,
    _svg: null,
    _dropTarget: null,

    init() {
      const parent = this.$el.closest('[x-data="planTab()"]');
      if (parent?._x_dataStack) {
        this.bed = parent._x_dataStack[0]?.activeBed;
      }
      this.$nextTick(() => this.renderSvg());
    },

    renderSvg() {
      const container = this.$refs.svgWrap;
      if (!container || !this.bed) return;

      const bed = this.bed;
      const cell = this.cell;
      const cols = bed.grid_cols || 10;
      const rows = bed.grid_rows || 10;
      const w = cols * cell;
      const h = rows * cell;
      const color = bed.canvas_color || '#e8e4df';
      const NS = 'http://www.w3.org/2000/svg';

      const svg = document.createElementNS(NS, 'svg');
      svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
      svg.style.cssText = 'width:100%;max-height:400px;min-height:120px;display:block;';
      svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');

      // Bed outline — polygon or rectangle
      if (bed.canvas_points && bed.canvas_points.length > 2) {
        const xs = bed.canvas_points.map(p => p[0]);
        const ys = bed.canvas_points.map(p => p[1]);
        const minX = Math.min(...xs), minY = Math.min(...ys);
        const maxX = Math.max(...xs), maxY = Math.max(...ys);
        const polyW = maxX - minX, polyH = maxY - minY;
        // Scale polygon points to fit the grid viewBox
        const scaleX = w / polyW, scaleY = h / polyH;
        const pts = bed.canvas_points.map(p => `${(p[0]-minX)*scaleX},${(p[1]-minY)*scaleY}`).join(' ');
        const outline = document.createElementNS(NS, 'polygon');
        Object.entries({points:pts,fill:color,'fill-opacity':0.12,stroke:color,'stroke-width':1.5}).forEach(([k,v]) => outline.setAttribute(k,v));
        svg.appendChild(outline);
      } else {
        const outline = document.createElementNS(NS, 'rect');
        Object.entries({x:0,y:0,width:w,height:h,rx:6,fill:color,'fill-opacity':0.12,stroke:color,'stroke-width':1.5}).forEach(([k,v]) => outline.setAttribute(k,v));
        svg.appendChild(outline);
      }

      // Grid lines
      for (let i = 1; i < cols; i++) {
        const l = document.createElementNS(NS, 'line');
        Object.entries({x1:i*cell,y1:0,x2:i*cell,y2:h,stroke:'rgba(0,0,0,0.05)','stroke-width':0.3}).forEach(([k,v]) => l.setAttribute(k,v));
        svg.appendChild(l);
      }
      for (let i = 1; i < rows; i++) {
        const l = document.createElementNS(NS, 'line');
        Object.entries({x1:0,y1:i*cell,x2:w,y2:i*cell,stroke:'rgba(0,0,0,0.05)','stroke-width':0.3}).forEach(([k,v]) => l.setAttribute(k,v));
        svg.appendChild(l);
      }

      // Drop target (hidden initially)
      this._dropTarget = document.createElementNS(NS, 'rect');
      Object.entries({rx:3,fill:'none',stroke:'#365314','stroke-width':1.5,'stroke-dasharray':'3,2',opacity:0}).forEach(([k,v]) => this._dropTarget.setAttribute(k,v));
      svg.appendChild(this._dropTarget);

      // Plant regions
      const self = this;
      for (const p of (bed.plants || [])) {
        const px = (p.grid_x||0)*cell, py = (p.grid_y||0)*cell;
        const pw = (p.grid_w||1)*cell, ph = (p.grid_h||1)*cell;
        const fill = this.plantColor(p.crop_type);
        const abbr = this.plantAbbr(p.crop_type);

        const g = document.createElementNS(NS, 'g');
        g.style.cursor = 'grab';
        g.dataset.plantId = p.id;

        const rect = document.createElementNS(NS, 'rect');
        Object.entries({x:px+0.5,y:py+0.5,width:pw-1,height:ph-1,rx:3,fill:fill,'fill-opacity':0.25,stroke:fill,'stroke-width':0.8}).forEach(([k,v]) => rect.setAttribute(k,v));
        g.appendChild(rect);

        // Abbreviation
        const fs = Math.min(pw*0.2, ph*0.25, 10);
        const txt = document.createElementNS(NS, 'text');
        Object.entries({x:px+pw/2,y:py+ph/2-(pw>=25?fs*0.6:0),'text-anchor':'middle','dominant-baseline':'central','font-size':fs,'font-weight':700,fill:fill}).forEach(([k,v]) => txt.setAttribute(k,v));
        txt.textContent = abbr;
        g.appendChild(txt);

        // Variety name if space
        if (pw >= 25 && ph >= 20) {
          const nFs = Math.min(pw*0.1, ph*0.14, 6);
          const name = p.variety_name.length > pw/nFs*0.9 ? p.variety_name.slice(0, Math.floor(pw/nFs*0.7)) + '..' : p.variety_name;
          const nTxt = document.createElementNS(NS, 'text');
          Object.entries({x:px+pw/2,y:py+ph/2+fs*0.7,'text-anchor':'middle','dominant-baseline':'central','font-size':nFs,fill:'#6b7280'}).forEach(([k,v]) => nTxt.setAttribute(k,v));
          nTxt.textContent = name;
          g.appendChild(nTxt);
        }

        // Drag start
        const startDrag = (e) => {
          e.preventDefault(); e.stopPropagation();
          const grid = self.eventToGrid(e, svg);
          self.dragging = { plantId: p.id, origGridX: p.grid_x, origGridY: p.grid_y };
          self.dragOffset = { dx: grid.svgX - p.grid_x*cell, dy: grid.svgY - p.grid_y*cell };
          self.hoverGrid = { x: p.grid_x, y: p.grid_y };
          self.selectedPlant = null;
          g.style.cursor = 'grabbing'; g.style.opacity = '0.7';
        };
        g.addEventListener('mousedown', startDrag);
        g.addEventListener('touchstart', startDrag, { passive: false });
        g.addEventListener('click', (e) => {
          if (self.dragging) return;
          e.stopPropagation();
          self.selectedPlant = self.selectedPlant?.id === p.id ? null : p;
        });

        svg.appendChild(g);
      }

      // SVG-level drag events
      svg.addEventListener('mousemove', (e) => this.onDragMove(e, svg));
      svg.addEventListener('mouseup', (e) => this.endDrag(e, svg));
      svg.addEventListener('mouseleave', (e) => this.endDrag(e, svg));
      svg.addEventListener('touchmove', (e) => { e.preventDefault(); this.onDragMove(e, svg); }, { passive: false });
      svg.addEventListener('touchend', (e) => this.endDrag(e, svg));
      svg.addEventListener('touchcancel', (e) => this.endDrag(e, svg));

      container.textContent = '';
      container.appendChild(svg);
      this._svg = svg;
    },

    eventToGrid(e, svg) {
      const pt = svg.createSVGPoint();
      const touch = e.touches ? e.touches[0] : e;
      pt.x = touch.clientX; pt.y = touch.clientY;
      const svgPt = pt.matrixTransform(svg.getScreenCTM().inverse());
      return { x: Math.floor(svgPt.x/this.cell), y: Math.floor(svgPt.y/this.cell), svgX: svgPt.x, svgY: svgPt.y };
    },

    onDragMove(e, svg) {
      if (!this.dragging) return;
      const grid = this.eventToGrid(e, svg);
      const plant = this.bed.plants.find(p => p.id === this.dragging.plantId);
      if (!plant) return;

      const maxX = (this.bed.grid_cols||10) - (plant.grid_w||1);
      const maxY = (this.bed.grid_rows||10) - (plant.grid_h||1);
      const newX = Math.max(0, Math.min(maxX, Math.floor((grid.svgX - this.dragOffset.dx) / this.cell)));
      const newY = Math.max(0, Math.min(maxY, Math.floor((grid.svgY - this.dragOffset.dy) / this.cell)));
      this.hoverGrid = { x: newX, y: newY };

      // Move plant group visually
      const g = svg.querySelector(`g[data-plant-id="${plant.id}"]`);
      if (g) g.setAttribute('transform', `translate(${(newX-plant.grid_x)*this.cell},${(newY-plant.grid_y)*this.cell})`);

      // Show drop target
      if (this._dropTarget) {
        Object.entries({x:newX*this.cell, y:newY*this.cell, width:(plant.grid_w||1)*this.cell, height:(plant.grid_h||1)*this.cell, opacity:0.5}).forEach(([k,v]) => this._dropTarget.setAttribute(k,v));
      }
    },

    async endDrag(e, svg) {
      if (!this.dragging) return;
      const plant = this.bed.plants.find(p => p.id === this.dragging.plantId);
      const newX = this.hoverGrid?.x ?? this.dragging.origGridX;
      const newY = this.hoverGrid?.y ?? this.dragging.origGridY;
      const moved = newX !== this.dragging.origGridX || newY !== this.dragging.origGridY;

      // Reset visuals
      const g = svg?.querySelector(`g[data-plant-id="${this.dragging.plantId}"]`);
      if (g) { g.removeAttribute('transform'); g.style.cursor = 'grab'; g.style.opacity = '1'; }
      if (this._dropTarget) this._dropTarget.setAttribute('opacity', 0);

      this.dragging = null; this.hoverGrid = null; this.dragOffset = null;
      if (!moved || !plant) return;

      // Update data + re-render
      plant.grid_x = newX; plant.grid_y = newY;
      this.renderSvg();

      // Save
      this.saving = true;
      try {
        await fetch(`/plants/${plant.id}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ grid_x: newX, grid_y: newY })
        });
      } catch(err) { console.error('Save failed:', err); }
      this.saving = false;
    },

    plantColor(ct) {
      const c = (ct||'').toLowerCase();
      if (['tomato','pepper','eggplant'].includes(c)) return '#ef4444';
      if (['lettuce','spinach','chard','kale'].includes(c)) return '#22c55e';
      if (['herb','basil'].includes(c)) return '#10b981';
      if (c==='flower') return '#eab308';
      if (['cucumber','squash','melon','zucchini'].includes(c)) return '#3b82f6';
      if (['radish','carrot','onion'].includes(c)) return '#f97316';
      if (['bean','pea'].includes(c)) return '#8b5cf6';
      return '#9ca3af';
    },

    plantAbbr(ct) {
      const a = {tomato:'T',pepper:'P',eggplant:'E',lettuce:'Le',spinach:'Sp',chard:'Ch',kale:'K',herb:'H',basil:'Ba',flower:'F',cucumber:'Cu',squash:'Sq',melon:'Me',zucchini:'Zu',radish:'R',carrot:'Ca',onion:'On',bean:'Be',pea:'Pe'};
      return a[(ct||'').toLowerCase()] || (ct||'?').slice(0,2);
    }
  }
}
