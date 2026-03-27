import { useState, useEffect } from 'react'
import { X, Keyboard } from 'lucide-react'

const shortcuts = [
  { keys: ['\u2318', 'K'], desc: 'Open search' },
  { keys: ['/'], desc: 'Open search' },
  { keys: ['Esc'], desc: 'Close modal / cancel' },
]

export function KeyboardShortcutsHelp() {
  const [open, setOpen] = useState(false)

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === '?' && !['INPUT', 'TEXTAREA'].includes((e.target as HTMLElement)?.tagName)) {
        e.preventDefault()
        setOpen(prev => !prev)
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  if (!open) return null

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center">
      <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" onClick={() => setOpen(false)} />
      <div className="relative bg-white rounded-2xl shadow-2xl p-6 max-w-sm w-full mx-4" style={{ animation: 'slideUp 150ms ease-out' }}>
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-sm font-semibold flex items-center gap-2" style={{ fontFamily: 'Lora, serif' }}>
            <Keyboard size={16} /> Keyboard Shortcuts
          </h3>
          <button onClick={() => setOpen(false)} className="btn-ghost p-1 min-h-0 min-w-0">
            <X size={16} />
          </button>
        </div>
        <div className="space-y-2">
          {shortcuts.map(s => (
            <div key={s.desc} className="flex items-center justify-between py-1.5">
              <span className="text-sm text-gray-600">{s.desc}</span>
              <div className="flex gap-1">
                {s.keys.map(k => (
                  <kbd key={k} className="px-2 py-1 bg-gray-100 rounded-lg text-xs font-mono text-gray-700 border border-gray-200">{k}</kbd>
                ))}
              </div>
            </div>
          ))}
        </div>
        <p className="text-xs text-gray-400 mt-4 text-center">Press <kbd className="px-1 py-0.5 bg-gray-100 rounded text-gray-500">?</kbd> to toggle this help</p>
      </div>
    </div>
  )
}
