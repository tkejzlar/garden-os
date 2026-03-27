export const LIFECYCLE_STAGES = [
  'seed_packet', 'pre_treating', 'sown_indoor', 'germinating', 'seedling',
  'potted_up', 'hardening_off', 'planted_out', 'producing', 'done'
]

export function stageLabel(stage: string): string {
  return stage.replace(/_/g, ' ').replace(/(^\w|\s\w)/g, c => c.toUpperCase())
}

export function stageProgress(stage: string): number {
  const idx = LIFECYCLE_STAGES.indexOf(stage)
  if (idx < 0) return 0
  return Math.round((idx / (LIFECYCLE_STAGES.length - 1)) * 100)
}

export function nextStages(currentStage: string, count = 2): string[] {
  const idx = LIFECYCLE_STAGES.indexOf(currentStage)
  if (idx < 0) return []
  return LIFECYCLE_STAGES.slice(idx + 1, idx + 1 + count)
}

export const STAGE_INSTRUCTIONS: Record<string, string> = {
  seed_packet: 'Check sow-by date. Plan your sowing schedule based on crop type and last frost date.',
  pre_treating: 'Soak seeds 12-24h in lukewarm water, or cold-stratify in fridge for seeds that need it.',
  sown_indoor: 'Fill modules with seed compost, sow at correct depth. Label clearly. Keep warm and moist.',
  germinating: 'Keep warm and moist. Move to light immediately when seedlings emerge.',
  seedling: 'Ensure 12-16h of light. Feed with half-strength fertilizer weekly once true leaves appear.',
  potted_up: 'Move to individual pots when true leaves are developed. Keep under lights.',
  hardening_off: 'Gradually expose to outdoor conditions over 7-10 days before transplanting.',
  planted_out: 'Transplant after last frost. Water deeply, mulch, and protect from slugs.',
  producing: 'Harvest regularly to encourage more production. Feed weekly with appropriate fertilizer.',
  done: 'Remove spent plants. Compost healthy material. Save seeds if open-pollinated.',
}
