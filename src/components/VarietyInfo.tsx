import { useState, useEffect } from 'react'
import { BookOpen, Loader2 } from 'lucide-react'
import { seeds as seedsApi } from '../lib/api'

interface VarietyInfoProps {
  varietyName: string
  cropType: string
}

export function VarietyInfo({ varietyName, cropType }: VarietyInfoProps) {
  const [info, setInfo] = useState<{ notes: string; crop_type: string } | null>(null)
  const [loading, setLoading] = useState(false)
  const [expanded, setExpanded] = useState(false)

  useEffect(() => {
    if (!expanded || info) return
    setLoading(true)
    seedsApi.lookup(varietyName)
      .then(results => {
        if (Array.isArray(results) && results.length > 0) {
          setInfo({ notes: results[0].notes || '', crop_type: results[0].crop_type })
        }
      })
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [expanded, varietyName, info])

  return (
    <details className="group" onToggle={e => setExpanded((e.target as HTMLDetailsElement).open)}>
      <summary className="flex items-center gap-2 cursor-pointer text-xs text-[var(--color-muted)] hover:text-[var(--color-primary)] transition-colors py-1 list-none">
        <BookOpen size={12} />
        <span>Variety info</span>
      </summary>
      <div className="mt-2 p-3 bg-green-50 dark:bg-green-900/20 border border-green-100 dark:border-green-800 rounded-xl">
        {loading ? (
          <div className="flex items-center gap-2 text-xs text-[var(--color-muted)]">
            <Loader2 size={12} className="animate-spin" /> Looking up variety...
          </div>
        ) : info?.notes ? (
          <p className="text-xs text-green-800 dark:text-green-200 leading-relaxed">{info.notes}</p>
        ) : (
          <p className="text-xs text-[var(--color-muted)]">No catalog info found for {varietyName} ({cropType})</p>
        )}
      </div>
    </details>
  )
}
