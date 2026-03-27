import type { Plant, Bed } from '../lib/api'
import { getCropColor } from '../lib/crops'
import { stageLabel } from '../lib/stages'

interface GardenStatsProps {
  plants: Plant[]
  beds: Bed[]
}

export function GardenStats({ plants, beds }: GardenStatsProps) {
  // Crop type distribution
  const cropCounts = plants.reduce((acc, p) => {
    const ct = p.crop_type.toLowerCase()
    acc[ct] = (acc[ct] || 0) + 1
    return acc
  }, {} as Record<string, number>)

  const sortedCrops = Object.entries(cropCounts).sort((a, b) => b[1] - a[1])
  const maxCount = Math.max(...Object.values(cropCounts), 1)

  // Stage distribution
  const stageCounts = plants.reduce((acc, p) => {
    acc[p.lifecycle_stage] = (acc[p.lifecycle_stage] || 0) + 1
    return acc
  }, {} as Record<string, number>)

  // Bed utilization
  const bedUtil = beds.map(b => {
    const area = b.grid_cols * b.grid_rows
    const planted = b.plants.reduce((s, p) => s + (p.grid_w || 1) * (p.grid_h || 1), 0)
    return { name: b.name, pct: area > 0 ? Math.round((planted / area) * 100) : 0, color: b.canvas_color || '#86efac' }
  })

  return (
    <div className="space-y-4">
      {/* Crop distribution */}
      <div className="bg-white rounded-xl border border-gray-200 p-4">
        <h3 className="text-sm font-semibold text-gray-900 mb-3" style={{ fontFamily: 'Lora, serif' }}>
          Crops ({plants.length} plants)
        </h3>
        <div className="space-y-2">
          {sortedCrops.slice(0, 10).map(([crop, count]) => (
            <div key={crop} className="flex items-center gap-3">
              <span className="text-xs text-gray-600 w-20 truncate capitalize">{crop}</span>
              <div className="flex-1 h-4 bg-gray-50 rounded-full overflow-hidden">
                <div
                  className="h-full rounded-full transition-all"
                  style={{ width: `${(count / maxCount) * 100}%`, backgroundColor: getCropColor(crop) }}
                />
              </div>
              <span className="text-xs text-gray-500 w-6 text-right">{count}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Stage breakdown */}
      <div className="bg-white rounded-xl border border-gray-200 p-4">
        <h3 className="text-sm font-semibold text-gray-900 mb-3" style={{ fontFamily: 'Lora, serif' }}>
          By Stage
        </h3>
        <div className="flex flex-wrap gap-2">
          {Object.entries(stageCounts).map(([stage, count]) => (
            <div key={stage} className="px-3 py-2 bg-green-50 border border-green-100 rounded-xl text-center min-w-[70px]">
              <p className="text-lg font-bold text-[var(--color-primary)]">{count}</p>
              <p className="text-[10px] text-gray-500 capitalize">{stageLabel(stage)}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Bed utilization */}
      {beds.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <h3 className="text-sm font-semibold text-gray-900 mb-3" style={{ fontFamily: 'Lora, serif' }}>
            Bed Utilization
          </h3>
          <div className="space-y-2">
            {bedUtil.map(b => (
              <div key={b.name} className="flex items-center gap-3">
                <span className="text-xs text-gray-600 w-16 truncate">{b.name}</span>
                <div className="flex-1 h-3 bg-gray-50 rounded-full overflow-hidden">
                  <div
                    className="h-full rounded-full transition-all"
                    style={{ width: `${b.pct}%`, backgroundColor: b.pct > 80 ? '#f59e0b' : b.color }}
                  />
                </div>
                <span className="text-xs text-gray-500 w-10 text-right">{b.pct}%</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
