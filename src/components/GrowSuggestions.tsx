import { useMemo } from 'react'
import { Lightbulb } from 'lucide-react'
import type { Plant, Seed } from '../lib/api'
import { COMPANION_GOOD } from '../lib/crops'
import { PlantAvatar } from './PlantAvatar'

interface GrowSuggestionsProps {
  plants: Plant[]
  seeds: Seed[]
}

interface Suggestion {
  cropType: string
  reason: string
  score: number
}

export function GrowSuggestions({ plants, seeds }: GrowSuggestionsProps) {
  const suggestions = useMemo(() => {
    const planted = new Set(plants.map(p => p.crop_type.toLowerCase()))
    const available = new Set(seeds.map(s => s.crop_type.toLowerCase()))
    const results: Suggestion[] = []

    // For each seed we have but haven't planted
    for (const ct of available) {
      if (planted.has(ct)) continue

      let score = 0
      const reasons: string[] = []

      // Check if it's a good companion to something we already have
      for (const existing of planted) {
        if (COMPANION_GOOD[existing]?.includes(ct)) {
          score += 3
          reasons.push(`companion to ${existing}`)
        }
        if (COMPANION_GOOD[ct]?.includes(existing)) {
          score += 3
          reasons.push(`benefits from ${existing}`)
        }
      }

      // Bonus for variety — encourage diversity
      if (!planted.has(ct)) {
        score += 1
        reasons.push('adds variety')
      }

      // Season-appropriate bonus
      const month = new Date().getMonth()
      const earlyStarters = ['tomato', 'pepper', 'eggplant']
      const springDirect = ['lettuce', 'radish', 'pea', 'spinach', 'carrot']

      if (month >= 1 && month <= 3 && earlyStarters.includes(ct)) {
        score += 2
        reasons.push('start indoors now')
      }
      if (month >= 3 && month <= 5 && springDirect.includes(ct)) {
        score += 2
        reasons.push('direct sow now')
      }

      if (score > 0) {
        results.push({
          cropType: ct,
          reason: reasons.slice(0, 2).join(' · '),
          score,
        })
      }
    }

    return results.sort((a, b) => b.score - a.score).slice(0, 5)
  }, [plants, seeds])

  if (suggestions.length === 0) return null

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4">
      <h3 className="text-sm font-semibold text-gray-900 mb-3 flex items-center gap-2" style={{ fontFamily: 'Lora, serif' }}>
        <Lightbulb size={16} className="text-amber-500" />
        Suggested to Grow
      </h3>
      <div className="space-y-2">
        {suggestions.map(s => (
          <div key={s.cropType} className="flex items-center gap-3 p-2 rounded-xl hover:bg-gray-50 transition-colors">
            <PlantAvatar cropType={s.cropType} size="sm" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-800 capitalize">{s.cropType}</p>
              <p className="text-xs text-gray-500">{s.reason}</p>
            </div>
            <div className="flex gap-0.5">
              {Array.from({ length: Math.min(s.score, 5) }).map((_, i) => (
                <div key={i} className="w-1.5 h-1.5 rounded-full bg-amber-400" />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
