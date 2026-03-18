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

    async moveBed(bedId, direction) {
      try {
        const res = await fetch('/api/beds');
        const beds = await res.json();
        const sorted = beds.sort((a, b) => (a.position ?? 999) - (b.position ?? 999));
        const idx = sorted.findIndex(b => b.id === bedId);
        if (idx < 0) return;
        const newIdx = idx + direction;
        if (newIdx < 0 || newIdx >= sorted.length) return;
        // Swap positions
        const ids = sorted.map(b => b.id);
        [ids[idx], ids[newIdx]] = [ids[newIdx], ids[idx]];
        await fetch('/api/beds/reorder', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ bed_ids: ids })
        });
        location.reload();
      } catch(e) { console.error('Reorder failed:', e); }
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
        });
      } catch(e) { console.error('Failed to load bed:', e); }
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
        radish:'R', carrot:'Ca', onion:'On',
        bean:'Be', pea:'Pe'
      };
      return abbrs[(cropType||'').toLowerCase()] || (cropType||'?').slice(0,2);
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
