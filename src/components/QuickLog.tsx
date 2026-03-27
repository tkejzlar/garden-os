import { useState } from 'react'
import { Plus, Sprout, Droplets, Bug, Sun, X } from 'lucide-react'
import { toast } from '../lib/toast'

interface QuickLogProps {
  onLog: (type: string, note: string) => Promise<void>
}

const LOG_TYPES = [
  { key: 'watered', icon: Droplets, label: 'Watered', color: 'text-blue-500' },
  { key: 'fertilized', icon: Sprout, label: 'Fed', color: 'text-green-500' },
  { key: 'pest', icon: Bug, label: 'Pest issue', color: 'text-red-500' },
  { key: 'weather', icon: Sun, label: 'Weather note', color: 'text-amber-500' },
]

export function QuickLog({ onLog }: QuickLogProps) {
  const [open, setOpen] = useState(false)
  const [note, setNote] = useState('')
  const [saving, setSaving] = useState(false)

  const handleLog = async (type: string) => {
    setSaving(true)
    try {
      await onLog(type, note)
      toast.success(`Logged: ${type}`)
      setNote('')
      setOpen(false)
    } catch {
      toast.error('Failed to log')
    } finally {
      setSaving(false)
    }
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="flex items-center gap-2 px-4 py-2.5 bg-white rounded-xl border border-gray-200 text-sm text-gray-500 hover:border-[var(--color-primary-light)] hover:text-[var(--color-primary)] transition-all w-full"
      >
        <Plus size={16} />
        <span>Quick log (water, feed, note...)</span>
      </button>
    )
  }

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-gray-700">Quick Log</span>
        <button onClick={() => setOpen(false)} className="p-1 text-gray-400 hover:text-gray-600">
          <X size={16} />
        </button>
      </div>

      <input
        value={note}
        onChange={e => setNote(e.target.value)}
        placeholder="Optional note..."
        className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg outline-none focus:border-[var(--color-primary-light)]"
        autoFocus
      />

      <div className="grid grid-cols-2 gap-2">
        {LOG_TYPES.map(({ key, icon: Icon, label, color }) => (
          <button
            key={key}
            onClick={() => handleLog(key)}
            disabled={saving}
            className="flex items-center gap-2 p-3 rounded-xl border border-gray-100 hover:bg-gray-50 transition-colors text-sm min-h-[44px] disabled:opacity-50"
          >
            <Icon size={18} className={color} />
            <span className="font-medium text-gray-700">{label}</span>
          </button>
        ))}
      </div>
    </div>
  )
}
