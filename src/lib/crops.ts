// Single source of truth for crop colors, abbreviations, spacing, and companions

export const CROP_COLORS: Record<string, string> = {
  tomato: '#ef4444', pepper: '#ef4444', eggplant: '#ef4444',
  lettuce: '#22c55e', spinach: '#22c55e', chard: '#22c55e', kale: '#22c55e',
  herb: '#10b981', basil: '#10b981',
  flower: '#eab308',
  cucumber: '#3b82f6', squash: '#3b82f6', melon: '#3b82f6', zucchini: '#3b82f6',
  radish: '#f97316', carrot: '#f97316', onion: '#f97316',
  bean: '#8b5cf6', pea: '#8b5cf6',
}

export const CROP_ABBR: Record<string, string> = {
  tomato: 'T', pepper: 'P', eggplant: 'E',
  lettuce: 'Le', spinach: 'Sp', chard: 'Ch', kale: 'K',
  herb: 'H', basil: 'Ba', flower: 'F',
  cucumber: 'Cu', squash: 'Sq', melon: 'Me', zucchini: 'Zu',
  radish: 'R', carrot: 'Ca', onion: 'On',
  bean: 'Be', pea: 'Pe',
}

export const CROP_SPACING: Record<string, [number, number]> = {
  tomato: [6, 6], pepper: [6, 6], eggplant: [6, 6],
  lettuce: [4, 4], spinach: [2, 4], chard: [4, 6], kale: [6, 6],
  herb: [4, 4], basil: [4, 4], cucumber: [6, 6],
  squash: [8, 8], zucchini: [6, 8], melon: [8, 8],
  flower: [4, 4], radish: [2, 2], carrot: [2, 2], onion: [2, 2],
  bean: [4, 4], pea: [2, 4],
}

export const COMPANION_GOOD: Record<string, string[]> = {
  tomato: ['basil', 'herb', 'carrot', 'lettuce', 'radish', 'onion', 'flower', 'celery'],
  pepper: ['basil', 'herb', 'carrot', 'onion', 'lettuce', 'tomato'],
  eggplant: ['basil', 'herb', 'lettuce', 'bean', 'pepper'],
  cucumber: ['radish', 'lettuce', 'bean', 'pea', 'flower', 'onion'],
  squash: ['radish', 'bean', 'flower', 'onion', 'corn'],
  zucchini: ['radish', 'bean', 'flower', 'onion', 'corn'],
  melon: ['corn', 'radish', 'flower'],
  bean: ['carrot', 'radish', 'lettuce', 'cucumber', 'squash', 'corn', 'celery', 'eggplant'],
  pea: ['carrot', 'radish', 'lettuce', 'cucumber', 'corn'],
  lettuce: ['carrot', 'radish', 'onion', 'bean'],
  carrot: ['tomato', 'lettuce', 'onion', 'pea', 'radish', 'bean'],
  radish: ['lettuce', 'pea', 'bean', 'cucumber', 'carrot', 'spinach'],
  onion: ['carrot', 'lettuce', 'tomato', 'pepper'],
  kale: ['bean', 'onion', 'lettuce', 'spinach', 'herb'],
  chard: ['bean', 'onion', 'lettuce'],
  basil: ['tomato', 'pepper', 'lettuce'],
  herb: ['tomato', 'pepper', 'carrot', 'lettuce'],
  flower: ['tomato', 'cucumber', 'squash', 'bean'],
}

export const COMPANION_BAD: Record<string, string[]> = {
  tomato: ['fennel', 'kale', 'kohlrabi', 'dill'],
  pepper: ['fennel', 'bean', 'kohlrabi'],
  bean: ['onion', 'garlic', 'pepper', 'fennel', 'chive'],
  pea: ['onion', 'garlic', 'chive'],
  cucumber: ['potato', 'melon', 'sage'],
  squash: ['potato'],
  lettuce: ['celery'],
  carrot: ['dill', 'parsnip'],
  onion: ['bean', 'pea', 'sage'],
  kale: ['tomato', 'strawberry'],
  fennel: ['tomato', 'bean', 'pepper', 'carrot'],
}

export const CROP_TYPES = Object.keys(CROP_COLORS)

export function getCropColor(ct: string): string {
  return CROP_COLORS[ct?.toLowerCase()] || '#9ca3af'
}

export function getCropAbbr(ct: string): string {
  return CROP_ABBR[ct?.toLowerCase()] || (ct || '?').slice(0, 2)
}

export function getCropSpacing(ct: string): [number, number] {
  return CROP_SPACING[ct?.toLowerCase()] || [4, 4]
}

export function getCompanionStatus(cropType: string, bedCrops: string[]): 'good' | 'bad' | 'neutral' {
  const ct = cropType.toLowerCase()
  for (const c of bedCrops) {
    const cl = c.toLowerCase()
    if (COMPANION_BAD[cl]?.includes(ct) || COMPANION_BAD[ct]?.includes(cl)) return 'bad'
  }
  for (const c of bedCrops) {
    const cl = c.toLowerCase()
    if (COMPANION_GOOD[cl]?.includes(ct) || COMPANION_GOOD[ct]?.includes(cl)) return 'good'
  }
  return 'neutral'
}

export function getCompanionPairs(crops: string[]): { good: [string, string][]; bad: [string, string][] } {
  const good: [string, string][] = []
  const bad: [string, string][] = []
  for (let i = 0; i < crops.length; i++) {
    for (let j = i + 1; j < crops.length; j++) {
      const a = crops[i], b = crops[j]
      if (COMPANION_GOOD[a]?.includes(b) || COMPANION_GOOD[b]?.includes(a)) good.push([a, b])
      if (COMPANION_BAD[a]?.includes(b) || COMPANION_BAD[b]?.includes(a)) bad.push([a, b])
    }
  }
  return { good, bad }
}
