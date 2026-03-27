import { useState } from 'react'
import { ArrowLeft, MapPin, Bell, Download, Moon, Sun } from 'lucide-react'
import { useDarkMode } from '../hooks/useDarkMode'
import { Link } from 'react-router-dom'
import { SEASON_CONFIG } from '../lib/season'
import { toast } from '../lib/toast'
import { PageTransition } from '../components/PageTransition'
import { plants as plantsApi, seeds as seedsApi } from '../lib/api'
import { useApi } from '../hooks/useApi'
import { stageLabel } from '../lib/stages'

function exportAllData(plantData: unknown[], seedData: unknown[]) {
  const data = {
    exported_at: new Date().toISOString(),
    plants: plantData,
    seeds: seedData,
  }
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `gardenOS-export-${new Date().toISOString().split('T')[0]}.json`
  a.click()
  URL.revokeObjectURL(url)
}

export function Settings() {
  const { data: plantData } = useApi(() => plantsApi.list(), [])
  const { data: seedData } = useApi(() => seedsApi.list(), [])
  const { dark, toggle: toggleDark } = useDarkMode()
  const [frostMonth] = useState(SEASON_CONFIG.lastFrostMonth)
  const [frostDay] = useState(SEASON_CONFIG.lastFrostDay)

  return (
    <PageTransition>
    <div className="space-y-6 max-w-lg">
      <div className="flex items-center gap-3">
        <Link to="/" className="p-2 -ml-2 text-gray-500 hover:text-gray-700 min-h-[44px] min-w-[44px] flex items-center justify-center">
          <ArrowLeft size={20} />
        </Link>
        <h1 className="text-xl font-bold text-[var(--color-primary-dark)]" style={{ fontFamily: 'Lora, serif' }}>Settings</h1>
      </div>

      {/* Appearance */}
      <div className="bg-[var(--color-card)] rounded-xl border border-[var(--color-border-muted)] p-4 space-y-4">
        <h2 className="text-sm font-semibold text-[var(--color-fg)] flex items-center gap-2">
          {dark ? <Moon size={16} className="text-[var(--color-primary)]" /> : <Sun size={16} className="text-[var(--color-primary)]" />}
          Appearance
        </h2>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-[var(--color-fg)]">Dark mode</p>
            <p className="text-xs text-[var(--color-muted)]">{dark ? 'Dark theme active' : 'Light theme active'}</p>
          </div>
          <button
            onClick={toggleDark}
            className={`relative w-12 h-7 rounded-full transition-colors ${dark ? 'bg-[var(--color-primary)]' : 'bg-gray-300'}`}
          >
            <div className={`absolute top-0.5 w-6 h-6 bg-white rounded-full shadow transition-transform ${dark ? 'translate-x-5' : 'translate-x-0.5'}`} />
          </button>
        </div>
      </div>

      {/* Climate */}
      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-4">
        <h2 className="text-sm font-semibold text-gray-900 flex items-center gap-2">
          <MapPin size={16} className="text-[var(--color-primary)]" />
          Climate & Location
        </h2>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs text-gray-500 block mb-1">Last frost date</label>
            <div className="px-3 py-2 bg-gray-50 rounded-lg text-sm text-gray-700">
              {['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][frostMonth]} {frostDay}
            </div>
          </div>
          <div>
            <label className="text-xs text-gray-500 block mb-1">First frost date</label>
            <div className="px-3 py-2 bg-gray-50 rounded-lg text-sm text-gray-700">
              {['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][SEASON_CONFIG.firstFrostMonth]} {SEASON_CONFIG.firstFrostDay}
            </div>
          </div>
        </div>
        <p className="text-xs text-gray-400">
          Currently configured for Prague (zone 6b/7a). Edit src/lib/season.ts to change.
        </p>
      </div>

      {/* Notifications */}
      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-4">
        <h2 className="text-sm font-semibold text-gray-900 flex items-center gap-2">
          <Bell size={16} className="text-[var(--color-primary)]" />
          Notifications
        </h2>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-gray-700">Push notifications</p>
            <p className="text-xs text-gray-400">Get reminded about tasks and sowing dates</p>
          </div>
          <button
            onClick={() => {
              if ('Notification' in window) {
                Notification.requestPermission().then(p => {
                  toast.info(p === 'granted' ? 'Notifications enabled!' : 'Notifications blocked')
                })
              } else {
                toast.info('Notifications not supported in this browser')
              }
            }}
            className="btn-secondary text-xs py-1.5 px-3"
          >
            Enable
          </button>
        </div>
      </div>

      {/* Data */}
      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-4">
        <h2 className="text-sm font-semibold text-gray-900 flex items-center gap-2">
          <Download size={16} className="text-[var(--color-primary)]" />
          Data
        </h2>

        <button
          onClick={() => {
            exportAllData(plantData ?? [], seedData ?? [])
            toast.success('Data exported!')
          }}
          className="w-full flex items-center gap-3 p-3 rounded-xl border border-gray-100 hover:bg-gray-50 transition-colors text-left min-h-[44px]"
        >
          <Download size={16} className="text-gray-400" />
          <div>
            <p className="text-sm font-medium text-gray-700">Export all data</p>
            <p className="text-xs text-gray-400">Download plants + seeds as JSON</p>
          </div>
        </button>
      </div>

      {/* About */}
      <div className="text-center text-xs text-gray-400 py-4 space-y-1">
        <p className="font-medium">GardenOS</p>
        <p>Open-source garden planner</p>
        <p>Built with React, Sinatra, and AI</p>
      </div>
    </div>
    </PageTransition>
  )
}
