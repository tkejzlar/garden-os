// Season configuration — defaults for Prague, CZ
// TODO: make this user-configurable via garden settings
export const SEASON_CONFIG = {
  lastFrostMonth: 4,   // May (0-indexed)
  lastFrostDay: 13,
  firstFrostMonth: 9,  // October (0-indexed)
  firstFrostDay: 15,
  timezone: 'Europe/Prague',
}

export function getSeasonDates(year: number) {
  const start = new Date(year, SEASON_CONFIG.lastFrostMonth, SEASON_CONFIG.lastFrostDay)
  const end = new Date(year, SEASON_CONFIG.firstFrostMonth, SEASON_CONFIG.firstFrostDay)
  return { start, end }
}

export function getSeasonProgress() {
  const now = new Date()
  const { start, end } = getSeasonDates(now.getFullYear())
  const totalDays = (end.getTime() - start.getTime()) / 86400000
  const elapsed = (now.getTime() - start.getTime()) / 86400000

  if (elapsed < 0) {
    return { pct: 0, label: `${Math.ceil(-elapsed)} days to growing season` }
  }
  if (elapsed > totalDays) {
    return { pct: 100, label: 'Season ended' }
  }

  const pct = Math.round((elapsed / totalDays) * 100)
  const week = Math.ceil(elapsed / 7)
  const totalWeeks = Math.ceil(totalDays / 7)
  return { pct, label: `Week ${week} of ${totalWeeks}` }
}

export function formatSeasonRange(): [string, string] {
  const { start, end } = getSeasonDates(new Date().getFullYear())
  const fmt = (d: Date) => d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
  return [fmt(start), fmt(end)]
}
