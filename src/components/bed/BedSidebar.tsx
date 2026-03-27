import { useState, useRef, useEffect, useCallback } from 'react'
import type { Bed, BedPlant, Seed } from '../../lib/api'
import { getCropColor, getCompanionStatus, getCompanionPairs } from '../../lib/crops'
import { getSowingHint } from '../../lib/sowing'
import { Search, X, Copy, Plus } from 'lucide-react'

interface BedSidebarProps {
  bed: Bed
  seeds: Seed[]
  selectedPlant: BedPlant | null
  onSelectPlant: (id: number | null) => void
  onAddPlant: (seed: Seed) => Promise<void>
  onAddRow: (seed: Seed, direction: 'h' | 'v') => Promise<void>
  onRemovePlant: (id: number) => Promise<void>
  onDuplicatePlant: (plant: BedPlant) => Promise<void>
  onStartPlacing: (seed: Seed) => void
  placingSeed: Seed | null
  onCancelPlacing: () => void
  onOpenAI?: () => void
}

export function BedSidebar({
  bed,
  seeds,
  selectedPlant,
  onSelectPlant,
  onAddPlant,
  onAddRow,
  onRemovePlant,
  onDuplicatePlant,
  onStartPlacing,
  placingSeed,
  onCancelPlacing,
  onOpenAI,
}: BedSidebarProps) {
  const [search, setSearch] = useState('')
  const [confirmingId, setConfirmingId] = useState<number | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  // Auto-focus search only on empty beds
  useEffect(() => {
    if (bed.plants.length === 0) inputRef.current?.focus()
  }, [])

  // Escape clears search
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && search) {
        setSearch('')
        inputRef.current?.focus()
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [search])

  // Confirmation timeout
  useEffect(() => {
    if (confirmingId === null) return
    const t = setTimeout(() => setConfirmingId(null), 3000)
    return () => clearTimeout(t)
  }, [confirmingId])

  const bedCropTypes = [...new Set(bed.plants.map(p => p.crop_type.toLowerCase()))]
  const isSearching = search.trim().length > 0
  const q = search.toLowerCase()
  const filteredSeeds = isSearching
    ? seeds.filter(s =>
        s.variety_name.toLowerCase().includes(q) ||
        s.crop_type.toLowerCase().includes(q)
      )
    : []

  const focusSearch = useCallback(() => {
    inputRef.current?.focus()
    inputRef.current?.select()
  }, [])

  const uniqueCropTypes = [...new Set(bed.plants.map(p => p.crop_type.toLowerCase()))]
  const companions = uniqueCropTypes.length > 1 ? getCompanionPairs(uniqueCropTypes) : null

  return (
    <div className="w-[300px] shrink-0 border-l border-gray-200 flex flex-col bg-white overflow-y-auto max-sm:w-full max-sm:border-l-0 max-sm:border-t">
      {/* Search input */}
      <div className="p-3 border-b border-gray-100">
        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            ref={inputRef}
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search seeds..."
            className="w-full pl-9 pr-8 py-2 text-sm rounded-lg border border-gray-200 bg-gray-50 focus:bg-white focus:border-[var(--green-700)] focus:outline-none transition-colors"
          />
          {search && (
            <button
              onClick={() => { setSearch(''); inputRef.current?.focus() }}
              className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-gray-400 hover:text-gray-600"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      </div>

      {/* Placing mode banner */}
      {placingSeed && (
        <div className="mx-3 mt-3 px-3 py-2.5 bg-green-50 border border-green-200 rounded-lg flex items-center justify-between gap-2">
          <span className="text-sm text-green-800 font-medium truncate">
            Click on bed to place {placingSeed.variety_name}
          </span>
          <button
            onClick={onCancelPlacing}
            className="shrink-0 px-2.5 py-1 text-xs font-medium text-green-700 bg-green-100 hover:bg-green-200 rounded transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
          >
            Cancel
          </button>
        </div>
      )}

      {/* Seed results (when searching) */}
      {isSearching && (
        <div className="flex-1 overflow-y-auto">
          {filteredSeeds.length === 0 ? (
            <p className="text-sm text-gray-400 text-center py-6">No seeds match "{search}"</p>
          ) : (
            <div className="p-2 space-y-1">
              {filteredSeeds.map(seed => {
                const status = getCompanionStatus(seed.crop_type, bedCropTypes)
                const borderColor = status === 'good'
                  ? 'border-l-green-500'
                  : status === 'bad'
                    ? 'border-l-red-500'
                    : 'border-l-transparent'
                return (
                  <div
                    key={seed.id}
                    className={`flex items-center gap-2 p-2 rounded-lg border-l-[3px] ${borderColor} bg-gray-50 hover:bg-gray-100 transition-colors`}
                  >
                    <span
                      className="w-3 h-3 rounded-full shrink-0"
                      style={{ backgroundColor: getCropColor(seed.crop_type) }}
                    />
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium text-gray-800 truncate">{seed.variety_name}</div>
                      <div className="text-xs text-gray-500">{seed.crop_type}</div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => onStartPlacing(seed)}
                        title="Click to place on bed"
                        className="px-3 py-2 text-xs font-medium text-green-700 bg-green-50 hover:bg-green-100 rounded-lg transition-colors min-h-[44px]"
                      >
                        Place
                      </button>
                      <button
                        onClick={() => onAddPlant(seed)}
                        title="Quick add"
                        className="p-2 text-gray-400 hover:text-green-700 hover:bg-green-50 rounded-lg transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
                      >
                        <Plus className="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}

      {/* Empty bed prompt */}
      {!isSearching && bed.plants.length === 0 && (
        <div className="flex-1 flex flex-col items-center justify-center gap-3 px-6 py-10 text-center">
          <span className="text-5xl">🌱</span>
          <h3 className="text-lg font-semibold text-gray-700">Empty bed</h3>
          <p className="text-sm text-gray-500">Start planning by adding seeds to this bed.</p>
          <div className="flex gap-2 mt-2">
            <button
              onClick={focusSearch}
              className="px-4 py-2.5 text-sm font-medium bg-[var(--green-900)] text-white rounded-lg hover:opacity-90 transition-opacity min-h-[44px]"
            >
              Search seeds
            </button>
            <button
              onClick={() => {
                if (onOpenAI) onOpenAI()
                else window.dispatchEvent(new Event('open-ai-drawer'))
              }}
              className="px-4 py-2.5 text-sm font-medium border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors min-h-[44px]"
            >
              Ask AI
            </button>
          </div>
        </div>
      )}

      {/* Plant list */}
      {!isSearching && bed.plants.length > 0 && (
        <div className="flex-1 overflow-y-auto">
          <div className="p-2 space-y-0.5">
            {bed.plants.map(plant => {
              const isSelected = selectedPlant?.id === plant.id
              const hint = getSowingHint(plant)
              const isConfirming = confirmingId === plant.id
              return (
                <div
                  key={plant.id}
                  className={`flex items-center gap-2 px-2.5 py-2 rounded-lg cursor-pointer transition-colors ${
                    isSelected
                      ? 'bg-[var(--green-900)]/10 ring-1 ring-[var(--green-700)]'
                      : 'hover:bg-gray-50'
                  }`}
                  onClick={() => onSelectPlant(isSelected ? null : plant.id)}
                >
                  <span
                    className="w-3 h-3 rounded-full shrink-0"
                    style={{ backgroundColor: getCropColor(plant.crop_type) }}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-medium text-gray-800 truncate">
                      {plant.variety_name}
                    </div>
                    {hint && (
                      <span className="inline-block mt-0.5 px-1.5 py-0.5 text-[10px] font-medium rounded bg-amber-50 text-amber-700 border border-amber-200">
                        {hint}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-0.5 shrink-0">
                    <button
                      onClick={e => { e.stopPropagation(); onDuplicatePlant(plant) }}
                      title="Duplicate"
                      className="p-2 text-gray-400 opacity-50 hover:opacity-100 hover:text-[var(--green-700)] rounded transition-all min-h-[44px] min-w-[44px] flex items-center justify-center"
                    >
                      <Copy className="w-3.5 h-3.5" />
                    </button>
                    {isConfirming ? (
                      <button
                        onClick={e => { e.stopPropagation(); onRemovePlant(plant.id) }}
                        className="p-2 text-red-600 font-medium text-xs rounded hover:bg-red-50 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
                      >
                        Sure?
                      </button>
                    ) : (
                      <button
                        onClick={e => { e.stopPropagation(); setConfirmingId(plant.id) }}
                        title="Remove"
                        className="p-2 text-gray-400 opacity-50 hover:opacity-100 hover:text-red-500 rounded transition-all min-h-[44px] min-w-[44px] flex items-center justify-center"
                      >
                        <X className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              )
            })}
          </div>

          {/* Companions panel */}
          {companions && (companions.good.length > 0 || companions.bad.length > 0) && (
            <div className="px-3 py-3 border-t border-gray-100">
              <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Companions</h4>
              <div className="flex flex-wrap gap-1.5">
                {companions.good.map(([a, b]) => (
                  <span key={`${a}-${b}`} className="px-2 py-1 text-xs font-medium rounded-full bg-green-50 text-green-700 border border-green-200">
                    {a} + {b}
                  </span>
                ))}
                {companions.bad.map(([a, b]) => (
                  <span key={`${a}-${b}`} className="px-2 py-1 text-xs font-medium rounded-full bg-red-50 text-red-700 border border-red-200">
                    {a} + {b}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Add more chips */}
          {!isSearching && (
            <div className="px-3 py-3 border-t border-gray-100">
              <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Add more</h4>
              <div className="flex flex-wrap gap-1.5">
                {[...seeds].sort((a, b) => {
                  const order: Record<string, number> = { good: 0, neutral: 1, bad: 2 }
                  return (order[getCompanionStatus(a.crop_type, bedCropTypes)] ?? 1) - (order[getCompanionStatus(b.crop_type, bedCropTypes)] ?? 1)
                }).slice(0, 12).map(seed => {
                  const status = getCompanionStatus(seed.crop_type, bedCropTypes)
                  const borderCls = status === 'good'
                    ? 'border-green-300 bg-green-50 text-green-800'
                    : status === 'bad'
                      ? 'border-red-300 bg-red-50 text-red-800'
                      : 'border-gray-200 bg-gray-50 text-gray-700'
                  return (
                    <button
                      key={seed.id}
                      onClick={() => onStartPlacing(seed)}
                      className={`px-2 py-1 text-xs font-medium rounded-full border ${borderCls} hover:opacity-80 transition-opacity min-h-[44px] flex items-center`}
                    >
                      <span
                        className="w-2 h-2 rounded-full mr-1.5 shrink-0"
                        style={{ backgroundColor: getCropColor(seed.crop_type) }}
                      />
                      {seed.variety_name}
                    </button>
                  )
                })}
                {seeds.length > 12 && (
                  <button
                    onClick={focusSearch}
                    className="px-2 py-1 text-xs font-medium text-[var(--green-700)] hover:underline min-h-[44px] flex items-center"
                  >
                    +{seeds.length - 12} more
                  </button>
                )}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
