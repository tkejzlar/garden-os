const BASE = ''  // same origin, Vite proxies to Sinatra in dev

async function request<T>(path: string, opts?: RequestInit): Promise<T> {
  const res = await fetch(BASE + path, {
    ...opts,
    headers: { 'Content-Type': 'application/json', ...opts?.headers },
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(text || `${res.status} ${res.statusText}`)
  }
  return res.json()
}

// ── Gardens ──
export const gardens = {
  list: () => request<{ current_id: number; gardens: Garden[] }>('/api/gardens'),
  switch: (id: number) => request<{ ok: boolean }>(`/api/gardens/switch/${id}`, { method: 'POST' }),
}

// ── Beds ──
export const beds = {
  list: () => request<Bed[]>('/api/beds'),
  get: (id: number) => request<Bed>(`/api/beds/${id}`),
  create: (data: { name: string; canvas_x?: number; canvas_y?: number; canvas_width?: number; canvas_height?: number; canvas_color?: string }) =>
    request<Bed>('/api/beds', { method: 'POST', body: JSON.stringify(data) }),
  update: (id: number, data: Partial<Bed>) =>
    request('/api/beds/' + id, { method: 'PATCH', body: JSON.stringify(data) }),
  updatePosition: (id: number, data: { canvas_x: number; canvas_y: number; canvas_width?: number; canvas_height?: number }) =>
    request('/api/beds/' + id + '/position', { method: 'PATCH', body: JSON.stringify(data) }),
  remove: (id: number) =>
    request('/api/beds/' + id, { method: 'DELETE' }),
  reorder: (ids: number[]) => request('/api/beds/reorder', { method: 'PATCH', body: JSON.stringify({ bed_ids: ids }) }),
  distribute: (id: number) => request<{ ok: boolean; moves: number; empty_pct: number }>(`/beds/${id}/distribute`, { method: 'POST' }),
}

// ── Plants ──
export const plants = {
  list: () => request<Plant[]>('/api/plants'),
  get: (id: number) => request<Plant>(`/api/plants/${id}`),
  create: (data: Partial<Plant>) => request<Plant>('/api/plants', { method: 'POST', body: JSON.stringify(data) }),
  update: (id: number, data: Partial<Plant>) => request<Plant>(`/api/plants/${id}`, { method: 'PATCH', body: JSON.stringify(data) }),
  remove: (id: number) => request('/api/plants/' + id, { method: 'DELETE' }),
  advance: (id: number, stage: string) => request(`/api/plants/${id}/advance`, { method: 'POST', body: JSON.stringify({ stage }) }),
}

// ── Seeds ──
export const seeds = {
  list: () => request<Seed[]>('/api/seeds'),
  create: (data: Partial<Seed>) => request<Seed>('/api/seeds', { method: 'POST', body: JSON.stringify(data) }),
  update: (id: number, data: Partial<Seed>) => request(`/api/seeds/${id}`, { method: 'PATCH', body: JSON.stringify(data) }),
  remove: (id: number) => request(`/api/seeds/${id}`, { method: 'DELETE' }),
  lookup: (q: string) => request<SeedLookup[]>(`/api/seeds/lookup?q=${encodeURIComponent(q)}`),
}

// ── Tasks ──
export const tasks = {
  list: () => request<Task[]>('/api/tasks'),
  complete: (id: number) => request(`/api/tasks/${id}/complete`, { method: 'POST' }),
  snooze: (id: number, days = 1) => request<{ ok: boolean; new_date: string }>(`/api/tasks/${id}/snooze`, {
    method: 'POST', body: JSON.stringify({ days })
  }),
}

// ── Photos ──
export const photos = {
  list: (plantId: number) => request<Photo[]>(`/api/plants/${plantId}/photos`),
  remove: (plantId: number, photoId: number) => request(`/api/plants/${plantId}/photos/${photoId}`, { method: 'DELETE' }),
  upload: async (plantId: number, file: File) => {
    const formData = new FormData()
    formData.append('photo', file)
    const res = await fetch(`/api/plants/${plantId}/photos`, { method: 'POST', body: formData })
    if (!res.ok) throw new Error(await res.text())
    return res.json()
  },
}

// ── Harvests ──
export const harvests = {
  list: (plantId: number) => request<Harvest[]>(`/api/plants/${plantId}/harvests`),
  create: (plantId: number, data: { quantity: string; notes?: string; date?: string }) =>
    request<Harvest>(`/api/plants/${plantId}/harvests`, { method: 'POST', body: JSON.stringify(data) }),
}

// ── Timeline ──
export const timeline = {
  get: () => request<TimelineData>('/api/plan/bed-timeline'),
}

// ── Journal ──
export const journal = {
  list: () => request<JournalEntry[]>('/api/journal'),
  create: (type: string, note: string) => request<JournalEntry>('/api/journal', {
    method: 'POST', body: JSON.stringify({ type, note })
  }),
}

export interface JournalEntry {
  id: number
  garden_id: number
  log_type: string
  note: string | null
  created_at: string
}

// ── Dashboard ──
export const dashboard = {
  get: () => request<DashboardData>('/api/dashboard'),
}

// ── Planner (SSE) ──
export function streamPlanner(message: string, context: Record<string, unknown>, onChunk: (data: SSEEvent) => void) {
  const controller = new AbortController()
  fetch('/api/planner/ask', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, context }),
    signal: controller.signal,
  }).then(async res => {
    const reader = res.body?.getReader()
    if (!reader) return
    const decoder = new TextDecoder()
    let buffer = ''
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split('\n')
      buffer = lines.pop() || ''
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          try { onChunk(JSON.parse(line.slice(6))) } catch {}
        }
      }
    }
  })
  return () => controller.abort()
}

// ── Types ──
export interface Garden {
  id: number
  name: string
}

export interface Bed {
  id: number
  name: string
  garden_id: number
  bed_type: string
  width_cm: number
  length_cm: number
  orientation: string
  grid_cols: number
  grid_rows: number
  canvas_x: number
  canvas_y: number
  canvas_width: number
  canvas_height: number
  canvas_color: string
  canvas_points: number[][] | null
  position: number
  plants: BedPlant[]
}

export interface BedPlant {
  id: number
  variety_name: string
  crop_type: string
  lifecycle_stage: string
  grid_x: number
  grid_y: number
  grid_w: number
  grid_h: number
  quantity: number
}

export interface Plant {
  id: number
  garden_id: number
  bed_id: number | null
  variety_name: string
  crop_type: string
  lifecycle_stage: string
  source: string
  grid_x: number
  grid_y: number
  grid_w: number
  grid_h: number
  quantity: number
  sow_date: string | null
  germination_date: string | null
  transplant_date: string | null
  days_in_stage?: number
  history?: Array<{ id: number; from_stage: string; to_stage: string; changed_at: string; note: string | null }>
}

export interface Seed {
  id: number
  variety_name: string
  crop_type: string
  source: string
  quantity?: number
  notes?: string
}

export interface SeedLookup {
  variety_name: string
  crop_type: string
  supplier: string
  notes: string
}

export interface Task {
  id: number
  title: string
  due_date: string
  status: string
  priority: string
  bed_names: string[]
}

export interface Harvest {
  id: number
  plant_id?: number
  quantity: string
  notes: string | null
  date: string
  created_at: string
}

export interface Photo {
  id: number
  url: string
  taken_at: string | null
  caption: string | null
  lifecycle_stage: string | null
}

export interface DashboardData {
  weather?: { temp?: number; condition?: string; humidity?: number } | null
  sensors?: { present: boolean; temp?: number; rain?: boolean }
  advisories?: Array<{ id: number; message: string; severity: string }>
}

export interface SSEEvent {
  type: 'chunk' | 'draft' | 'bed_layout' | 'error' | 'done'
  content?: string
  [key: string]: unknown
}

export interface TimelineData {
  today: string
  season_start: string
  season_end: string
  beds: TimelineBed[]
}

export interface TimelineBed {
  bed_id: number
  bed_name: string
  grid_cols: number
  grid_rows: number
  occupancy: Array<{ month: string; filled: number }>
  crops: TimelineCrop[]
}

export interface TimelineCrop {
  crop: string
  varieties: string[]
  plant_count: number
  periods: Array<{ start: string | null; end: string | null; status: string }>
}
