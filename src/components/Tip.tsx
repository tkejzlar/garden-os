import { useState } from 'react'
import { X, Lightbulb } from 'lucide-react'

interface TipProps {
  id: string  // unique key for localStorage
  children: React.ReactNode
}

export function Tip({ id, children }: TipProps) {
  const storageKey = `tip_dismissed_${id}`
  const [dismissed, setDismissed] = useState(() => {
    try { return localStorage.getItem(storageKey) === '1' } catch { return false }
  })

  if (dismissed) return null

  const dismiss = () => {
    setDismissed(true)
    try { localStorage.setItem(storageKey, '1') } catch {}
  }

  return (
    <div className="flex items-start gap-3 p-3 bg-amber-50 border border-amber-200 rounded-xl mb-4">
      <Lightbulb size={16} className="text-amber-600 shrink-0 mt-0.5" />
      <div className="flex-1 text-xs text-amber-800 leading-relaxed">{children}</div>
      <button onClick={dismiss} className="p-1 text-amber-400 hover:text-amber-600 shrink-0 min-h-[44px] min-w-[44px] flex items-center justify-center">
        <X size={14} />
      </button>
    </div>
  )
}
