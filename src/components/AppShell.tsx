import { ReactNode, useState, useEffect } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { Home, Sprout, Map, Package, CalendarDays } from 'lucide-react'
import { Toasts } from './Toasts'
import { AIDrawer, AIFab } from './AIDrawer'
import { UndoToast } from './UndoToast'
import { useUndoStore } from '../lib/undo'
import { GlobalSearch } from './GlobalSearch'
import { KeyboardShortcutsHelp } from './KeyboardShortcutsHelp'
import { GardenSwitcher } from './GardenSwitcher'
import { OfflineIndicator } from './OfflineIndicator'

const tabs = [
  { to: '/', icon: Home, label: 'Home', end: true },
  { to: '/garden', icon: Map, label: 'Garden' },
  { to: '/seeds', icon: Package, label: 'Seeds' },
  { to: '/plants', icon: Sprout, label: 'Plants' },
  { to: '/plan', icon: CalendarDays, label: 'Plan' },
]

export function AppShell({ children }: { children: ReactNode }) {
  const [aiOpen, setAiOpen] = useState(false)
  const location = useLocation()
  const undoAction = useUndoStore(s => s.action)
  const clearUndo = useUndoStore(s => s.clear)

  // Listen for custom "open-ai" event from other components
  useEffect(() => {
    const handler = () => setAiOpen(true)
    window.addEventListener('open-ai-drawer', handler)
    return () => window.removeEventListener('open-ai-drawer', handler)
  }, [])

  // Build AI context based on current page
  const aiContext: Record<string, unknown> = { view: location.pathname }
  const bedMatch = location.search.match(/bed=(\d+)/)
  if (bedMatch) aiContext.bed_id = parseInt(bedMatch[1])

  return (
    <div className="min-h-dvh flex flex-col">
      {/* Main content */}
      <main className="flex-1 max-w-4xl mx-auto w-full px-4 py-5 pb-24">
        <div className="flex items-center justify-between mb-2">
          <GardenSwitcher />
        </div>
        {children}
      </main>

      {/* Bottom tab bar */}
      <nav
        className="fixed bottom-0 left-0 right-0 backdrop-blur-md border-t border-[var(--color-border)] z-40"
        style={{ backgroundColor: 'color-mix(in srgb, var(--color-card) 95%, transparent)', paddingBottom: 'env(safe-area-inset-bottom, 0px)' }}
      >
        <div className="flex max-w-4xl mx-auto">
          {tabs.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                `flex-1 flex flex-col items-center gap-0.5 py-2.5 text-[11px] font-medium transition-all duration-200 ${
                  isActive
                    ? 'text-[var(--color-primary)]'
                    : 'text-[var(--color-muted-light)] hover:text-[var(--color-muted)]'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  <div className={`p-1 rounded-xl transition-all duration-200 ${isActive ? 'bg-green-50' : ''}`}>
                    <Icon size={20} strokeWidth={isActive ? 2.2 : 1.8} />
                  </div>
                  <span>{label}</span>
                </>
              )}
            </NavLink>
          ))}
        </div>
      </nav>

      {/* AI FAB + Drawer */}
      <AIFab onClick={() => setAiOpen(true)} />
      <AIDrawer open={aiOpen} onClose={() => setAiOpen(false)} context={aiContext} />

      <Toasts />
      {undoAction && (
        <UndoToast
          key={undoAction.id}
          message={undoAction.message}
          onUndo={async () => { await undoAction.undoFn(); clearUndo() }}
          onExpire={async () => { await undoAction.expiryFn(); clearUndo() }}
        />
      )}
      <GlobalSearch />
      <KeyboardShortcutsHelp />
      <OfflineIndicator />
    </div>
  )
}
