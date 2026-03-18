// Plan Tab Alpine.js component
// Used by views/succession.erb — the Plan tab with Tasks, Timeline, Beds tabs + AI drawer

function planTab() {
  return {
    tab: 'tasks',
    expandedBeds: [],
    selectedBed: null,
    activeBed: null,
    timelineData: null,
    loading: false,

    init() {
      this.fetchTimeline();
    },

    async fetchTimeline() {
      this.loading = true;
      try {
        const res = await fetch('/api/plan/bed-timeline');
        this.timelineData = await res.json();
      } catch(e) {
        console.error('Timeline fetch failed:', e);
      }
      this.loading = false;
    },

    toggleBed(bedId) {
      const idx = this.expandedBeds.indexOf(bedId);
      if (idx >= 0) this.expandedBeds.splice(idx, 1);
      else this.expandedBeds.push(bedId);
    },

    isBedExpanded(bedId) {
      return this.expandedBeds.includes(bedId);
    },

    occupancyColor(filled, total) {
      if (total === 0) return 'rgba(34,197,94,0.05)';
      const ratio = filled / total;
      if (ratio === 0) return 'rgba(34,197,94,0.05)';
      if (ratio < 0.5) return 'rgba(34,197,94,0.2)';
      if (ratio < 1) return 'rgba(34,197,94,0.4)';
      return 'rgba(34,197,94,0.6)';
    },

    getAIContext() {
      const ctx = { view: this.tab };
      if (this.tab === 'beds' && this.selectedBed) {
        ctx.bed_name = this.selectedBed.name;
        ctx.empty_slots = this.selectedBed.empty_count;
        ctx.current_plants = this.selectedBed.plants;
      }
      if (this.tab === 'timeline' && this.expandedBeds.length) {
        ctx.expanded_beds = this.expandedBeds;
      }
      return ctx;
    },

    selectBed(name, emptyCount, plants) {
      this.selectedBed = { name, empty_count: emptyCount, plants };
    },

    async openBedModal(bedId) {
      try {
        const res = await fetch('/api/beds');
        const beds = await res.json();
        const bed = beds.find(b => b.id === bedId);
        if (!bed) return;
        this.activeBed = bed;
        this.$nextTick(() => {
          if (this.$refs.bedModal) this.$refs.bedModal.showModal();
          // Render SVG in container (trusted data from our own DB)
          if (this.$refs.bedSvgContainer) {
            this.$refs.bedSvgContainer.textContent = '';
            const parser = new DOMParser();
            const doc = parser.parseFromString(this.renderBedSvg(bed), 'image/svg+xml');
            this.$refs.bedSvgContainer.appendChild(doc.documentElement);
          }
        });
      } catch(e) { console.error('Failed to load bed:', e); }
    },

    renderBedSvg(bed) {
      const cell = 10;
      const w = bed.grid_cols * cell;
      const h = bed.grid_rows * cell;
      const color = bed.canvas_color || '#e8e4df';
      let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" style="width:100%;max-height:400px;min-height:100px;" preserveAspectRatio="xMidYMid meet">`;
      svg += `<rect x="0" y="0" width="${w}" height="${h}" rx="6" fill="${color}" fill-opacity="0.15" stroke="${color}" stroke-width="1.5"/>`;
      for (let i = 1; i < bed.grid_cols; i++) svg += `<line x1="${i*cell}" y1="0" x2="${i*cell}" y2="${h}" stroke="rgba(0,0,0,0.04)" stroke-width="0.3"/>`;
      for (let i = 1; i < bed.grid_rows; i++) svg += `<line x1="0" y1="${i*cell}" x2="${w}" y2="${i*cell}" stroke="rgba(0,0,0,0.04)" stroke-width="0.3"/>`;
      for (const p of bed.plants) {
        const px = (p.grid_x||0)*cell, py = (p.grid_y||0)*cell;
        const pw = (p.grid_w||1)*cell, ph = (p.grid_h||1)*cell;
        const fill = this.plantColor(p.crop_type);
        svg += `<a href="/plants/${p.id}">`;
        svg += `<rect x="${px+0.5}" y="${py+0.5}" width="${pw-1}" height="${ph-1}" rx="3" fill="${fill}" fill-opacity="0.3" stroke="${fill}" stroke-width="0.8"/>`;
        if (pw >= 20 && ph >= 15) {
          const fs = Math.min(pw*0.12, ph*0.18, 8);
          const name = p.variety_name.length > Math.floor(pw/fs*1.2) ? p.variety_name.slice(0, Math.floor(pw/fs)) + '..' : p.variety_name;
          svg += `<text x="${px+pw/2}" y="${py+ph/2}" text-anchor="middle" dominant-baseline="central" font-size="${fs}" font-weight="600" fill="#1a2e05">${name}</text>`;
        }
        svg += `</a>`;
      }
      svg += `</svg>`;
      return svg;
    },

    plantColor(cropType) {
      const c = (cropType || '').toLowerCase();
      if (['tomato','pepper','eggplant'].includes(c)) return '#ef4444';
      if (['lettuce','spinach','chard','kale'].includes(c)) return '#22c55e';
      if (['herb','basil'].includes(c)) return '#10b981';
      if (c === 'flower') return '#eab308';
      if (['cucumber','squash','melon','zucchini'].includes(c)) return '#3b82f6';
      return '#9ca3af';
    },

    openAIForBed(bedName, emptyCount) {
      this.selectedBed = { name: bedName, empty_count: emptyCount, plants: [] };
      if (this.$refs.aiDrawer.showModal) this.$refs.aiDrawer.showModal();
    },

    // AI drawer state and methods
    aiMessages: JSON.parse(document.getElementById('planner-data')?.textContent || '[]'),
    aiInput: '',
    aiSending: false,
    pendingLayout: null,

    async sendAIMessage() {
      if (!this.aiInput.trim() || this.aiSending) return;
      const text = this.aiInput.trim();
      this.aiInput = '';
      this.aiMessages.push({ role: 'user', content: text, id: Date.now() });
      this.aiSending = true;

      const msgId = Date.now() + 1;
      this.aiMessages.push({ role: 'assistant', content: '', id: msgId, streaming: true });

      try {
        const context = this.getAIContext();
        const res = await fetch('/succession/planner/ask', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: text, context })
        });

        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop();

          for (const line of lines) {
            if (!line.startsWith('data: ')) continue;
            try {
              const event = JSON.parse(line.slice(6));
              const msg = this.aiMessages.find(m => m.id === msgId);
              if (!msg) continue;

              if (event.type === 'chunk') {
                msg.content += event.content;
                // Auto-scroll drawer messages to bottom
                this.$nextTick(() => {
                  const el = this.$refs.aiMessages;
                  if (el) el.scrollTop = el.scrollHeight;
                });
              } else if (event.type === 'draft') {
                msg.draft = event.draft;
              } else if (event.type === 'bed_layout') {
                this.pendingLayout = event.bed_layout;
              } else if (event.type === 'error') {
                msg.content = event.content;
              } else if (event.type === 'done') {
                msg.streaming = false;
              }
            } catch(e) { /* skip malformed events */ }
          }
        }

        const msg = this.aiMessages.find(m => m.id === msgId);
        if (msg) msg.streaming = false;
      } catch(e) {
        const msg = this.aiMessages.find(m => m.id === msgId);
        if (msg) { msg.content = 'Sorry, something went wrong.'; msg.streaming = false; }
      }
      this.aiSending = false;
    },

    sendQuickAction(text) {
      this.aiInput = text;
      this.sendAIMessage();
    },

    async applyLayout() {
      if (!this.pendingLayout) return;
      const layout = this.pendingLayout;
      const bed = document.querySelector(`[data-bed-name="${layout.bed_name}"]`);
      const bedId = bed?.dataset?.bedId;
      if (!bedId) return;

      await fetch(`/beds/${bedId}/apply-layout`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(layout)
      });
      this.pendingLayout = null;
      location.reload();
    },

    dismissLayout() {
      this.pendingLayout = null;
    }
  }
}
