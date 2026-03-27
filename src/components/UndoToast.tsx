import { useState, useEffect } from 'react'
import { Undo2 } from 'lucide-react'

interface UndoToastProps {
  message: string
  duration?: number
  onUndo: () => void
  onExpire: () => void
}

export function UndoToast({ message, duration = 5000, onUndo, onExpire }: UndoToastProps) {
  const [progress, setProgress] = useState(100)

  useEffect(() => {
    const start = Date.now()
    const interval = setInterval(() => {
      const elapsed = Date.now() - start
      const remaining = Math.max(0, 100 - (elapsed / duration) * 100)
      setProgress(remaining)
      if (remaining <= 0) {
        clearInterval(interval)
        onExpire()
      }
    }, 50)
    return () => clearInterval(interval)
  }, [duration, onExpire])

  return (
    <div className="fixed bottom-24 left-1/2 -translate-x-1/2 z-[9999] bg-gray-900 text-white px-4 py-3 rounded-2xl shadow-xl flex items-center gap-3 min-w-[280px]"
         style={{ animation: 'slideUp 200ms ease-out' }}>
      <span className="text-sm flex-1">{message}</span>
      <button
        onClick={onUndo}
        className="flex items-center gap-1.5 px-3 py-1.5 bg-white/20 hover:bg-white/30 rounded-lg text-sm font-medium transition-colors min-h-[36px]"
      >
        <Undo2 size={14} /> Undo
      </button>
      <div className="absolute bottom-0 left-4 right-4 h-0.5 bg-white/20 rounded-full overflow-hidden">
        <div className="h-full bg-white/60 rounded-full transition-all" style={{ width: `${progress}%` }} />
      </div>
    </div>
  )
}
