import { useMemo } from 'react'
import type { Plant } from '../lib/api'
import { getCropColor } from '../lib/crops'
import { SEASON_CONFIG } from '../lib/season'

interface PlantingCalendarProps {
  plants: Plant[]
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

// When each crop type should be started (month indices, 0-based)
const SOWING_WINDOWS: Record<string, { indoor?: [number, number]; direct?: [number, number]; harvest?: [number, number] }> = {
  tomato:    { indoor: [1, 3], harvest: [6, 9] },
  pepper:    { indoor: [1, 3], harvest: [6, 9] },
  eggplant:  { indoor: [1, 3], harvest: [7, 9] },
  cucumber:  { indoor: [2, 4], harvest: [6, 9] },
  squash:    { direct: [4, 5], harvest: [7, 9] },
  zucchini:  { direct: [4, 5], harvest: [6, 9] },
  lettuce:   { direct: [2, 8], harvest: [4, 10] },
  spinach:   { direct: [2, 4], harvest: [4, 6] },
  radish:    { direct: [2, 8], harvest: [3, 9] },
  carrot:    { direct: [2, 6], harvest: [5, 10] },
  onion:     { indoor: [1, 2], harvest: [6, 8] },
  bean:      { direct: [4, 6], harvest: [6, 9] },
  pea:       { direct: [2, 4], harvest: [5, 7] },
  kale:      { direct: [3, 6], harvest: [5, 11] },
  chard:     { direct: [3, 5], harvest: [5, 10] },
  basil:     { indoor: [2, 3], harvest: [5, 9] },
  herb:      { indoor: [2, 4], harvest: [4, 10] },
  flower:    { indoor: [2, 3], harvest: [5, 9] },
}

export function PlantingCalendar({ plants }: PlantingCalendarProps) {
  // Get unique crop types that are in seed_packet stage
  const cropTypes = useMemo(() => {
    const types = new Map<string, { count: number; color: string }>()
    plants.forEach(p => {
      const ct = p.crop_type.toLowerCase()
      if (!types.has(ct)) {
        types.set(ct, { count: 0, color: getCropColor(ct) })
      }
      types.get(ct)!.count++
    })
    return types
  }, [plants])

  const currentMonth = new Date().getMonth()
  const frostMonth = SEASON_CONFIG.lastFrostMonth

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4 overflow-x-auto">
      <h3 className="text-sm font-semibold text-gray-900 mb-3" style={{ fontFamily: 'Lora, serif' }}>
        Planting Calendar
      </h3>

      <div className="min-w-[600px]">
        {/* Month headers */}
        <div className="grid grid-cols-12 gap-px mb-1">
          {MONTHS.map((m, i) => (
            <div
              key={m}
              className={`text-center text-[10px] py-1 ${i === currentMonth ? 'font-bold text-[var(--color-primary)]' : 'text-gray-400'}`}
            >
              {m}
            </div>
          ))}
        </div>

        {/* Frost line */}
        <div className="grid grid-cols-12 gap-px mb-2">
          {MONTHS.map((_, i) => (
            <div key={i} className="h-px" style={{
              backgroundColor: i < frostMonth || i > SEASON_CONFIG.firstFrostMonth ? '#fecaca' : '#bbf7d0'
            }} />
          ))}
        </div>

        {/* Crop rows */}
        {[...cropTypes.entries()].map(([ct, { count, color }]) => {
          const window = SOWING_WINDOWS[ct]
          return (
            <div key={ct} className="grid grid-cols-12 gap-px mb-1 items-center">
              {MONTHS.map((_, i) => {
                const isIndoor = window?.indoor && i >= window.indoor[0] && i <= window.indoor[1]
                const isDirect = window?.direct && i >= window.direct[0] && i <= window.direct[1]
                const isHarvest = window?.harvest && i >= window.harvest[0] && i <= window.harvest[1]

                return (
                  <div key={i} className="h-5 rounded-sm relative" style={{
                    backgroundColor: isIndoor ? color + '30' : isDirect ? color + '50' : isHarvest ? color + '20' : 'transparent',
                    borderLeft: isIndoor && i === window!.indoor![0] ? `2px solid ${color}` : undefined,
                    borderRight: isDirect && i === window!.direct![1] ? `2px solid ${color}` : undefined,
                  }}>
                    {i === 0 && (
                      <span className="absolute left-0 top-0 text-[9px] font-medium text-gray-600 whitespace-nowrap leading-5 pl-0.5">
                        {ct} ({count})
                      </span>
                    )}
                    {isIndoor && i === window!.indoor![0] && (
                      <span className="absolute inset-0 flex items-center justify-center text-[8px] font-medium" style={{ color }}>
                        sow
                      </span>
                    )}
                    {isHarvest && i === window!.harvest![0] && (
                      <span className="absolute inset-0 flex items-center justify-center text-[8px] text-gray-500">
                        harvest
                      </span>
                    )}
                  </div>
                )
              })}
            </div>
          )
        })}

        {/* Legend */}
        <div className="flex gap-4 mt-3 text-[10px] text-gray-500">
          <span className="flex items-center gap-1"><span className="w-3 h-2 bg-gray-300/30 border-l-2 border-gray-400 rounded-sm" /> Indoor sowing</span>
          <span className="flex items-center gap-1"><span className="w-3 h-2 bg-gray-300/50 rounded-sm" /> Direct sowing</span>
          <span className="flex items-center gap-1"><span className="w-3 h-2 bg-gray-300/20 rounded-sm" /> Harvest</span>
          <span className="flex items-center gap-1"><span className="w-8 h-px bg-red-300" /> Frost risk</span>
        </div>
      </div>
    </div>
  )
}
