import { SEASON_CONFIG } from './season'

export function getSowingHint(plant: { crop_type: string; lifecycle_stage: string }): string {
  const stage = plant.lifecycle_stage?.toLowerCase() || ''
  if (stage === 'producing') return 'producing'
  if (stage === 'planted_out') return 'in ground'
  if (stage === 'hardening_off') return 'hardening off'
  if (stage === 'seedling' || stage === 'potted_up') return 'growing'
  if (stage === 'germinating') return 'germinating'
  if (stage === 'sown_indoor') return 'sown indoor'
  if (stage === 'seed_packet') {
    const ct = plant.crop_type?.toLowerCase() || ''
    const month = new Date().getMonth()
    const frostMonth = SEASON_CONFIG.lastFrostMonth
    const indoor = ['tomato', 'pepper', 'eggplant']
    const direct = ['radish', 'carrot', 'bean', 'pea', 'lettuce', 'spinach']
    if (indoor.includes(ct)) {
      if (month < frostMonth - 2) return 'sow indoor Feb\u2013Mar'
      if (month < frostMonth) return 'sow indoor now!'
      if (month < frostMonth + 1) return 'transplant soon'
      return 'transplant now'
    }
    if (direct.includes(ct)) {
      if (month < frostMonth) return 'direct sow Apr\u2013May'
      if (month < SEASON_CONFIG.firstFrostMonth) return 'direct sow now'
      return 'next season'
    }
    if (month < frostMonth - 1) return 'start indoor'
    if (month < frostMonth + 1) return 'sow soon'
    return 'plant out'
  }
  return stage.replace(/_/g, ' ')
}
