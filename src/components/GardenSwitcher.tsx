import { useState, useEffect, useRef } from 'react'
import { ChevronDown, Check } from 'lucide-react'
import { gardens as gardensApi, type Garden } from '../lib/api'
import { toast } from '../lib/toast'

export function GardenSwitcher() {
  const [gardens, setGardens] = useState<Garden[]>([])
  const [current, setCurrent] = useState<Garden | null>(null)
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    gardensApi.list().then(data => {
      setGardens(data.gardens)
      const cur = data.gardens.find(g => g.id === data.current_id)
      setCurrent(cur || data.gardens[0] || null)
    }).catch(() => {})
  }, [])

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('click', handler)
    return () => document.removeEventListener('click', handler)
  }, [])

  const switchGarden = async (garden: Garden) => {
    try {
      await gardensApi.switch(garden.id)
      setCurrent(garden)
      setOpen(false)
      toast.success(`Switched to ${garden.name}`)
      // Reload to refresh all data with new garden context
      window.location.reload()
    } catch {
      toast.error('Failed to switch garden')
    }
  }

  if (gardens.length <= 1) return null // Don't show if only one garden

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-1.5 text-sm font-medium text-[var(--color-primary-dark)] hover:text-[var(--color-primary)] transition-colors py-1 min-h-[44px]"
      >
        {current?.name || 'Garden'}
        <ChevronDown size={14} className={`transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && (
        <div className="absolute top-full left-0 mt-1 bg-white rounded-xl shadow-xl border border-gray-100 py-1 min-w-[180px] z-50"
             style={{ animation: 'slideUp 150ms ease-out' }}>
          {gardens.map(g => (
            <button
              key={g.id}
              onClick={() => switchGarden(g)}
              className="w-full flex items-center gap-2 px-4 py-2.5 text-sm text-left hover:bg-gray-50 transition-colors min-h-[44px]"
            >
              <span className="flex-1">{g.name}</span>
              {current?.id === g.id && <Check size={14} className="text-[var(--color-primary)]" />}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
