import { useToastStore } from '../lib/toast'
import { CheckCircle, AlertTriangle, Info } from 'lucide-react'

const icons = {
  success: CheckCircle,
  error: AlertTriangle,
  info: Info,
}

const styles: Record<string, string> = {
  success: 'bg-green-50 text-green-800 border-green-200',
  error: 'bg-red-50 text-red-800 border-red-200',
  info: 'bg-white text-[var(--color-fg)] border-[var(--color-border)]',
}

export function Toasts() {
  const toasts = useToastStore(s => s.toasts)
  const dismiss = useToastStore(s => s.dismiss)

  if (!toasts.length) return null

  return (
    <div className="fixed top-4 right-4 z-[9999] flex flex-col gap-2 pointer-events-none">
      {toasts.map(t => {
        const Icon = icons[t.type]
        return (
          <div
            key={t.id}
            className={`pointer-events-auto flex items-center gap-2.5 px-4 py-3 rounded-2xl border shadow-lg text-sm font-medium cursor-pointer ${styles[t.type]}`}
            onClick={() => dismiss(t.id)}
            style={{ animation: 'slideIn 200ms ease-out' }}
          >
            <Icon size={16} className="shrink-0" />
            {t.message}
          </div>
        )
      })}
    </div>
  )
}
