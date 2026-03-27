import { useState } from 'react'
import { Search } from 'lucide-react'
import { COMPANION_GOOD, COMPANION_BAD, CROP_TYPES, getCropColor } from '../lib/crops'
import { PlantAvatar } from './PlantAvatar'

export function CompanionGuide() {
  const [search, setSearch] = useState('')
  const q = search.toLowerCase()

  const crops = CROP_TYPES.filter(ct => !q || ct.includes(q))

  return (
    <div className="space-y-4">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-muted)]" />
        <input
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Filter crops..."
          className="w-full pl-10 pr-4 py-3 text-sm border border-[var(--color-border)] rounded-xl bg-[var(--color-card)] outline-none focus:border-[var(--color-primary-light)]"
        />
      </div>

      <div className="space-y-3">
        {crops.map(crop => {
          const good = COMPANION_GOOD[crop] || []
          const bad = COMPANION_BAD[crop] || []
          if (good.length === 0 && bad.length === 0) return null

          return (
            <div key={crop} className="bg-[var(--color-card)] rounded-xl border border-[var(--color-border)] p-4">
              <div className="flex items-center gap-2 mb-3">
                <PlantAvatar cropType={crop} size="sm" />
                <h3 className="text-sm font-semibold text-[var(--color-fg)] capitalize">{crop}</h3>
              </div>

              {good.length > 0 && (
                <div className="mb-2">
                  <p className="text-[10px] font-medium text-green-600 uppercase tracking-wider mb-1">Good companions</p>
                  <div className="flex flex-wrap gap-1.5">
                    {good.map(g => (
                      <span key={g} className="px-2 py-1 text-xs rounded-full bg-green-50 text-green-700 border border-green-200 capitalize flex items-center gap-1">
                        <span className="w-2 h-2 rounded-full" style={{ backgroundColor: getCropColor(g) }} />
                        {g}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {bad.length > 0 && (
                <div>
                  <p className="text-[10px] font-medium text-red-600 uppercase tracking-wider mb-1">Avoid</p>
                  <div className="flex flex-wrap gap-1.5">
                    {bad.map(b => (
                      <span key={b} className="px-2 py-1 text-xs rounded-full bg-red-50 text-red-700 border border-red-200 capitalize flex items-center gap-1">
                        <span className="w-2 h-2 rounded-full" style={{ backgroundColor: getCropColor(b) }} />
                        {b}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
