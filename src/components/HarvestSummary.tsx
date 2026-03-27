import { useMemo } from 'react'
import { Apple } from 'lucide-react'
import type { Harvest } from '../lib/api'

interface HarvestSummaryProps {
  harvests: Harvest[]
}

const QTY_VALUES: Record<string, number> = {
  small: 1,
  medium: 2,
  large: 4,
  huge: 8,
}

export function HarvestSummary({ harvests }: HarvestSummaryProps) {
  const stats = useMemo(() => {
    if (!harvests.length) return null
    const total = harvests.length
    const score = harvests.reduce((s, h) => s + (QTY_VALUES[h.quantity] || 1), 0)
    const thisMonth = harvests.filter(h => {
      const d = new Date(h.date)
      const now = new Date()
      return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
    }).length
    return { total, score, thisMonth }
  }, [harvests])

  if (!stats) return null

  return (
    <div className="flex items-center gap-4 px-4 py-3 bg-[var(--color-card)] rounded-xl border border-[var(--color-border)]">
      <Apple size={20} className="text-red-400 shrink-0" />
      <div className="flex-1 flex gap-6">
        <div>
          <p className="text-lg font-bold text-[var(--color-fg)]">{stats.total}</p>
          <p className="text-[10px] text-[var(--color-muted)]">Total harvests</p>
        </div>
        <div>
          <p className="text-lg font-bold text-[var(--color-fg)]">{stats.thisMonth}</p>
          <p className="text-[10px] text-[var(--color-muted)]">This month</p>
        </div>
        <div>
          <p className="text-lg font-bold text-amber-600">{stats.score}</p>
          <p className="text-[10px] text-[var(--color-muted)]">Yield score</p>
        </div>
      </div>
    </div>
  )
}
