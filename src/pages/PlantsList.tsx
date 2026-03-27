import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ChevronRight, Sprout } from 'lucide-react'
import { plants as plantsApi, beds as bedsApi, type Plant } from '../lib/api'
import { useApi } from '../hooks/useApi'
import { stageLabel, stageProgress, nextStages, LIFECYCLE_STAGES } from '../lib/stages'
import { getCropColor } from '../lib/crops'
import { toast } from '../lib/toast'
import { ExportButton } from '../components/ExportButton'
import { usePullToRefresh } from '../hooks/usePullToRefresh'
import { PageTransition } from '../components/PageTransition'
import { SkeletonList } from '../components/Skeleton'
import { Tip } from '../components/Tip'

export function PlantsList() {
  const { data, loading, refetch } = useApi(() => plantsApi.list(), [])
  const { data: bedsData } = useApi(() => bedsApi.list(), [])
  const bedNames: Record<number, string> = {}
  bedsData?.forEach(b => { bedNames[b.id] = b.name })
  const navigate = useNavigate()
  const [advancingId, setAdvancingId] = useState<number | null>(null)
  const [selectMode, setSelectMode] = useState(false)
  const [selected, setSelected] = useState<Set<number>>(new Set())

  usePullToRefresh(async () => { await refetch() })

  const allPlants = data ?? []

  // Group by crop type
  const grouped = allPlants.reduce<Record<string, Plant[]>>((acc, p) => {
    const key = p.crop_type || 'other'
    ;(acc[key] ??= []).push(p)
    return acc
  }, {})

  const cropTypes = Object.keys(grouped).sort()

  async function handleAdvance(plant: Plant, stage: string) {
    setAdvancingId(plant.id)
    try {
      await plantsApi.advance(plant.id, stage)
      toast.success(`${plant.variety_name} → ${stageLabel(stage)}`)
      refetch()
    } catch {
      toast.error('Failed to advance stage')
    } finally {
      setAdvancingId(null)
    }
  }

  if (loading) {
    return (
      <PageTransition>
        <div className="space-y-4">
          <h1 className="text-xl font-bold text-[var(--green-900)]">Plants</h1>
          <SkeletonList count={4} />
        </div>
      </PageTransition>
    )
  }

  return (
    <PageTransition>
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold text-[var(--green-900)]">
          Plants <span className="text-base font-normal text-gray-400">({allPlants.length})</span>
        </h1>
        <div className="flex items-center gap-2">
          <ExportButton plants={allPlants} />
          <button
            onClick={() => { setSelectMode(!selectMode); setSelected(new Set()) }}
            className={selectMode ? 'btn-primary text-xs py-2' : 'btn-secondary text-xs py-2'}
          >
            {selectMode ? 'Cancel' : 'Select'}
          </button>
        </div>
      </div>

      <Tip id="plants-select">
        Tap <strong>Select</strong> to choose multiple plants and advance their stage at once. Tap a plant name to see its details.
      </Tip>

      {/* Stage summary pills */}
      {allPlants.length > 0 && (() => {
        const stageCounts = allPlants.reduce((acc, p) => {
          const label = stageLabel(p.lifecycle_stage)
          acc[label] = (acc[label] || 0) + 1
          return acc
        }, {} as Record<string, number>)
        return (
          <div className="flex gap-2 overflow-x-auto pb-2 -mx-1 px-1">
            {Object.entries(stageCounts).map(([stage, count]) => (
              <span key={stage} className="flex-shrink-0 text-xs px-3 py-1.5 rounded-full bg-white border border-[var(--color-border)] text-[var(--color-fg)] font-medium whitespace-nowrap">
                {count} {stage}
              </span>
            ))}
          </div>
        )
      })()}

      {allPlants.length === 0 && (
        <div className="text-center py-12">
          <Sprout size={48} className="mx-auto mb-4 text-gray-300" />
          <h3 className="text-base font-semibold text-gray-600 mb-1">No plants yet</h3>
          <p className="text-sm text-gray-400 mb-4">Plants appear here when you add seeds to a bed</p>
          <Link to="/plan?tab=beds" className="btn-primary text-sm">Open bed planner</Link>
        </div>
      )}

      {/* Grouped by crop type */}
      {cropTypes.map(cropType => (
        <details key={cropType} open className="group">
          <summary className="flex items-center gap-2 cursor-pointer list-none py-2">
            <ChevronRight size={14} className="text-gray-400 transition-transform group-open:rotate-90" />
            <div
              className="w-3 h-3 rounded-full flex-shrink-0"
              style={{ backgroundColor: getCropColor(cropType) }}
            />
            <span className="text-sm font-semibold text-gray-700 capitalize">{cropType}</span>
            <span className="text-xs text-gray-400">({grouped[cropType].length})</span>
          </summary>

          <div className="mt-1 space-y-2 ml-5">
            {grouped[cropType].map(plant => {
              const next = nextStages(plant.lifecycle_stage, 1)
              const progress = stageProgress(plant.lifecycle_stage)

              return (
                <div key={plant.id} className="bg-white rounded-xl border border-gray-200 p-3">
                  <div className="flex items-center gap-3">
                    {selectMode && (
                      <input
                        type="checkbox"
                        checked={selected.has(plant.id)}
                        onChange={e => {
                          const next = new Set(selected)
                          e.target.checked ? next.add(plant.id) : next.delete(plant.id)
                          setSelected(next)
                        }}
                        className="w-5 h-5 accent-[var(--color-primary)] shrink-0"
                        onClick={e => e.stopPropagation()}
                      />
                    )}
                    {/* Plant info */}
                    <div
                      className="flex-1 min-w-0 cursor-pointer"
                      onClick={() => navigate(`/plants/${plant.id}`)}
                    >
                      <p className="text-sm font-medium text-gray-900 truncate hover:text-[var(--green-900)] transition-colors">
                        {plant.variety_name}
                      </p>
                      <div className="flex items-center gap-2 mt-1">
                        <span className="text-xs capitalize bg-emerald-50 text-emerald-700 px-1.5 py-0.5 rounded">
                          {stageLabel(plant.lifecycle_stage)}
                        </span>
                        {plant.bed_id && (
                          <Link to={`/plan?bed=${plant.bed_id}`} className="text-xs bg-green-50 text-green-700 px-1.5 py-0.5 rounded hover:bg-green-100 transition-colors">
                            {bedNames[plant.bed_id] || `Bed ${plant.bed_id}`}
                          </Link>
                        )}
                      </div>
                    </div>

                    {/* Advance button */}
                    {next.length > 0 && (
                      <button
                        onClick={() => handleAdvance(plant, next[0])}
                        disabled={advancingId === plant.id}
                        className="min-h-[44px] px-3 text-xs font-medium text-[var(--green-900)] bg-emerald-50 hover:bg-emerald-100 rounded-lg transition-colors disabled:opacity-50 flex-shrink-0 whitespace-nowrap"
                      >
                        {stageLabel(next[0])} →
                      </button>
                    )}
                  </div>

                  {/* Progress bar */}
                  <div className="mt-2 h-1 bg-gray-100 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-emerald-500 rounded-full transition-all"
                      style={{ width: `${progress}%` }}
                    />
                  </div>
                </div>
              )
            })}
          </div>
        </details>
      ))}
      {selectMode && selected.size > 0 && (
        <div className="fixed bottom-16 left-0 right-0 bg-white border-t border-gray-200 px-4 py-3 flex items-center gap-3 z-30 shadow-lg"
             style={{ paddingBottom: 'calc(8px + env(safe-area-inset-bottom, 0px))' }}>
          <span className="text-sm font-medium text-gray-700 flex-1">{selected.size} selected</span>
          <select
            id="batch-stage"
            className="text-sm border border-gray-200 rounded-lg px-3 py-2 min-h-[44px]"
            defaultValue=""
          >
            <option value="" disabled>Advance to...</option>
            {LIFECYCLE_STAGES.filter(s => s !== 'done').map(s => (
              <option key={s} value={s}>{stageLabel(s)}</option>
            ))}
          </select>
          <button
            onClick={async () => {
              const stage = (document.getElementById('batch-stage') as HTMLSelectElement)?.value
              if (!stage) { toast.error('Select a target stage'); return }
              try {
                await Promise.all([...selected].map(id => plantsApi.advance(id, stage)))
                toast.success(`Advanced ${selected.size} plants to ${stageLabel(stage)}`)
                setSelected(new Set())
                setSelectMode(false)
                refetch()
              } catch { toast.error('Some advances failed') }
            }}
            className="btn-primary text-sm py-2 px-4 min-h-[44px]"
          >
            Advance
          </button>
        </div>
      )}
    </div>
    </PageTransition>
  )
}
