import { useState, useRef, useEffect } from 'react'
import { Search, X, Sprout, Package, Map } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { plants as plantsApi, seeds as seedsApi, beds as bedsApi } from '../lib/api'
import type { Plant, Seed, Bed } from '../lib/api'
import { getCropColor } from '../lib/crops'

interface SearchResult {
  type: 'plant' | 'seed' | 'bed'
  id: number
  name: string
  subtitle: string
  color: string
  url: string
}

export function GlobalSearch() {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchResult[]>([])
  const [allData, setAllData] = useState<{ plants: Plant[]; seeds: Seed[]; beds: Bed[] } | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const navigate = useNavigate()

  // Load all data on first open
  useEffect(() => {
    if (open && !allData) {
      Promise.all([plantsApi.list(), seedsApi.list(), bedsApi.list()])
        .then(([p, s, b]) => setAllData({ plants: p, seeds: s, beds: b }))
    }
    if (open) setTimeout(() => inputRef.current?.focus(), 100)
  }, [open, allData])

  // Filter on query change
  useEffect(() => {
    if (!allData || !query.trim()) { setResults([]); return }
    const q = query.toLowerCase()
    const r: SearchResult[] = []

    allData.plants.filter(p => p.variety_name.toLowerCase().includes(q) || p.crop_type.toLowerCase().includes(q))
      .slice(0, 5).forEach(p => r.push({
        type: 'plant', id: p.id, name: p.variety_name, subtitle: p.crop_type,
        color: getCropColor(p.crop_type), url: `/plants/${p.id}`
      }))

    allData.seeds.filter(s => s.variety_name.toLowerCase().includes(q) || s.crop_type.toLowerCase().includes(q))
      .slice(0, 5).forEach(s => r.push({
        type: 'seed', id: s.id, name: s.variety_name, subtitle: s.crop_type,
        color: getCropColor(s.crop_type), url: `/seeds/${s.id}`
      }))

    allData.beds.filter(b => b.name.toLowerCase().includes(q))
      .slice(0, 3).forEach(b => r.push({
        type: 'bed', id: b.id, name: b.name, subtitle: `${b.plants.length} plants`,
        color: b.canvas_color || '#86efac', url: `/plan?tab=beds&bed=${b.id}`
      }))

    setResults(r)
  }, [query, allData])

  const handleSelect = (url: string) => {
    setOpen(false)
    setQuery('')
    navigate(url)
  }

  // Keyboard shortcut: Cmd+K or /
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') { e.preventDefault(); setOpen(true) }
      if (e.key === '/' && !['INPUT', 'TEXTAREA'].includes((e.target as HTMLElement)?.tagName)) { e.preventDefault(); setOpen(true) }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  const icons = { plant: Sprout, seed: Package, bed: Map }

  if (!open) return null

  return (
    <div className="fixed inset-0 z-[9998] flex items-start justify-center pt-[15vh]">
      <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" onClick={() => setOpen(false)} />
      <div className="relative w-full max-w-md bg-white rounded-2xl shadow-2xl overflow-hidden mx-4" style={{ animation: 'slideUp 150ms ease-out' }}>
        <div className="flex items-center gap-3 px-4 border-b border-gray-100">
          <Search size={18} className="text-gray-400 shrink-0" />
          <input
            ref={inputRef}
            value={query}
            onChange={e => setQuery(e.target.value)}
            onKeyDown={e => { if (e.key === 'Escape') setOpen(false) }}
            placeholder="Search plants, seeds, beds..."
            className="flex-1 py-4 text-sm outline-none bg-transparent"
          />
          {query && (
            <button onClick={() => setQuery('')} className="p-1 text-gray-400 hover:text-gray-600 min-h-[44px] min-w-[44px] flex items-center justify-center">
              <X size={16} />
            </button>
          )}
        </div>

        {results.length > 0 && (
          <div className="max-h-[50vh] overflow-y-auto p-2">
            {results.map(r => {
              const Icon = icons[r.type]
              return (
                <button
                  key={`${r.type}-${r.id}`}
                  onClick={() => handleSelect(r.url)}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-gray-50 text-left transition-colors min-h-[44px]"
                >
                  <div className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0" style={{ backgroundColor: r.color + '20' }}>
                    <Icon size={16} style={{ color: r.color }} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-900 truncate">{r.name}</p>
                    <p className="text-xs text-gray-500">{r.subtitle} &middot; {r.type}</p>
                  </div>
                </button>
              )
            })}
          </div>
        )}

        {query && results.length === 0 && (
          <div className="p-6 text-center text-sm text-gray-400">No results for &ldquo;{query}&rdquo;</div>
        )}

        {!query && (
          <div className="p-4 text-center text-xs text-gray-400">
            Type to search &middot; <kbd className="px-1.5 py-0.5 bg-gray-100 rounded text-gray-500">&#8984;K</kbd> to open
          </div>
        )}
      </div>
    </div>
  )
}
