import { useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle, Sprout, ListTodo, Package, AlertTriangle, ChevronRight, Clock } from 'lucide-react'
import { plants, tasks as tasksApi, dashboard as dashboardApi, type Plant, type Task, type DashboardData } from '../lib/api'
import { useApi } from '../hooks/useApi'
import { stageLabel, stageProgress } from '../lib/stages'
import { getCropColor } from '../lib/crops'
import { Cloud, Thermometer, Droplets, Settings } from 'lucide-react'
import { toast } from '../lib/toast'
import { getSeasonProgress, formatSeasonRange } from '../lib/season'
import { PlantingCalendar } from '../components/PlantingCalendar'
import { QuickLog } from '../components/QuickLog'
import { TodayFocus } from '../components/TodayFocus'
import { GardenStats } from '../components/GardenStats'
import { GrowSuggestions } from '../components/GrowSuggestions'
import { beds as bedsApi, seeds as seedsApi, type Bed, type Seed } from '../lib/api'
import { journal as journalApi } from '../lib/api'
import { useTaskNotifications } from '../hooks/useNotifications'
import { StreakCounter } from '../components/StreakCounter'
import { FrostCountdown } from '../components/FrostCountdown'
import { QuickActions } from '../components/QuickActions'
import { usePullToRefresh } from '../hooks/usePullToRefresh'
import { PageTransition } from '../components/PageTransition'
import { SkeletonCard, SkeletonLine, SkeletonList } from '../components/Skeleton'
import { Tip } from '../components/Tip'

function greeting(): string {
  const h = new Date().getHours()
  if (h < 12) return 'Good morning'
  if (h < 18) return 'Good afternoon'
  return 'Good evening'
}

function formatDate(d: Date): string {
  return d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
}

function seasonInfo() {
  const sp = getSeasonProgress()
  return { pct: sp.pct, label: sp.label, started: sp.pct > 0 }
}

function relativeDate(dateStr: string): string {
  const d = new Date(dateStr + 'T00:00:00')
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  const diff = Math.round((d.getTime() - now.getTime()) / 86400000)
  if (diff < 0) return `${Math.abs(diff)}d overdue`
  if (diff === 0) return 'Today'
  if (diff === 1) return 'Tomorrow'
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

function isOverdue(dateStr: string): boolean {
  const d = new Date(dateStr + 'T00:00:00')
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  return d.getTime() < now.getTime()
}

function isThisWeek(dateStr: string): boolean {
  const d = new Date(dateStr + 'T00:00:00')
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  const diff = (d.getTime() - now.getTime()) / 86400000
  return diff >= 0 && diff <= 7
}

export function Dashboard() {
  const { data: plantData, refetch: refetchPlants } = useApi(() => plants.list(), [])
  const { data: taskData, refetch: refetchTasks } = useApi(() => tasksApi.list(), [])
  const { data: dashData } = useApi(() => dashboardApi.get().catch(() => null), [])
  const { data: bedsData } = useApi(() => bedsApi.list().catch(() => [] as Bed[]), [])
  const { data: seedData } = useApi(() => seedsApi.list().catch(() => [] as Seed[]), [])
  const [completedIds, setCompletedIds] = useState<Set<number>>(new Set())
  const [completing, setCompleting] = useState<Set<number>>(new Set())

  usePullToRefresh(async () => { await refetchPlants(); await refetchTasks() })

  const season = seasonInfo()
  const allPlants = plantData ?? []
  const allTasks = (taskData ?? []).filter(t => !completedIds.has(t.id) && t.status !== 'completed')

  const activePlants = allPlants.filter(p => p.lifecycle_stage !== 'done' && p.lifecycle_stage !== 'seed_packet')
  const overdueTasks = allTasks.filter(t => isOverdue(t.due_date))
  const weekTasks = allTasks.filter(t => !isOverdue(t.due_date) && isThisWeek(t.due_date))
  const seedlings = allPlants.filter(p => p.lifecycle_stage === 'germinating' || p.lifecycle_stage === 'seedling')
  useTaskNotifications(allTasks)

  async function handleComplete(id: number) {
    setCompleting(prev => new Set(prev).add(id))
    try {
      await tasksApi.complete(id)
      setTimeout(() => {
        setCompletedIds(prev => new Set(prev).add(id))
        setCompleting(prev => { const next = new Set(prev); next.delete(id); return next })
      }, 600)
      toast.success('Task completed')
    } catch {
      setCompleting(prev => { const next = new Set(prev); next.delete(id); return next })
      toast.error('Failed to complete task')
    }
  }

  function TaskRow({ task, overdue }: { task: Task; overdue?: boolean }) {
    const isCompleting = completing.has(task.id)
    return (
      <div className={`w-full flex items-center gap-3 py-3 px-3 border-l-3 transition-all duration-300 ${
          isCompleting ? 'opacity-50 scale-[0.98]' : ''
        } ${overdue ? 'border-l-red-500 bg-red-50' : 'border-l-transparent'}`}
      >
        <button
          onClick={() => handleComplete(task.id)}
          disabled={isCompleting}
          className={`flex-shrink-0 min-h-[44px] min-w-[44px] flex items-center justify-center transition-colors duration-300 active:scale-95 ${
            isCompleting ? 'text-green-500' : 'text-gray-300 hover:text-green-400'
          }`}
          aria-label="Complete task"
        >
          <CheckCircle size={24} className={isCompleting ? 'fill-green-500 text-white' : ''} />
        </button>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-gray-900 truncate">{task.title}</p>
          <div className="flex items-center gap-2 mt-1">
            <span className={`text-xs ${overdue ? 'text-red-600 font-medium' : 'text-gray-500'}`}>
              {relativeDate(task.due_date)}
            </span>
            {task.bed_names?.map(name => (
              <span key={name} className="text-xs bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded">
                {name}
              </span>
            ))}
          </div>
        </div>
        <button
          onClick={() => {
            tasksApi.snooze(task.id).then(() => {
              setCompletedIds(prev => new Set(prev).add(task.id))
              toast.info('Snoozed to tomorrow')
            }).catch(() => toast.error('Failed to snooze'))
          }}
          className="shrink-0 p-2 text-gray-300 hover:text-amber-500 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
          title="Snooze to tomorrow"
        >
          <Clock size={16} />
        </button>
      </div>
    )
  }

  return (
    <PageTransition>
    {!plantData && !taskData ? (
      <div className="space-y-4">
        <SkeletonLine width="200px" height="28px" />
        <SkeletonLine width="100%" height="32px" />
        <div className="grid grid-cols-2 gap-3">
          <SkeletonCard /><SkeletonCard /><SkeletonCard /><SkeletonCard />
        </div>
        <SkeletonList count={3} />
      </div>
    ) : (
    <div className="space-y-6">
      <Tip id="dashboard-intro">
        Welcome to GardenOS! Use the <strong>AI button</strong> (bottom right) to get planting suggestions, or go to <strong>Plan &rarr; Beds</strong> to start adding plants to your beds.
      </Tip>

      {/* Greeting */}
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-bold text-[var(--green-900)]">{greeting()}</h1>
            <StreakCounter />
          </div>
          <p className="text-sm text-gray-500 mt-0.5">{formatDate(new Date())}</p>
        </div>
        <Link to="/settings" className="p-2 text-gray-400 hover:text-gray-600 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center" title="Settings">
          <Settings size={20} />
        </Link>
      </div>

      {/* Quick actions */}
      <QuickActions />

      {/* Frost countdown */}
      <FrostCountdown />

      {/* Today's focus */}
      <TodayFocus plants={allPlants} tasks={allTasks} />

      {/* Quick log */}
      <QuickLog onLog={async (type, note) => { await journalApi.create(type, note) }} />

      {/* Season progress */}
      <div className="space-y-1.5">
        <div className="flex justify-between items-center text-xs text-gray-500">
          <span>{formatSeasonRange()[0]}</span>
          <span className="font-medium text-[var(--green-900)]">{season.label}</span>
          <span>{formatSeasonRange()[1]}</span>
        </div>
        <div className="relative h-2 bg-gray-100 rounded-full overflow-hidden">
          <div
            className="absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-emerald-400 to-green-600"
            style={{ width: `${season.pct}%` }}
          />
          {season.pct > 0 && season.pct < 100 && (
            <div
              className="absolute top-0 bottom-0 w-0.5 bg-[var(--green-900)]"
              style={{ left: `${season.pct}%` }}
            />
          )}
        </div>
      </div>

      {/* Weather strip */}
      {dashData?.weather && dashData.weather.temp != null && (
        <div className="flex items-center gap-4 px-4 py-3 bg-white rounded-xl border border-gray-100">
          <div className="flex items-center gap-1.5 text-sm">
            <Thermometer size={14} className="text-orange-500" />
            <span className="font-semibold">{Math.round(dashData.weather.temp)}°C</span>
          </div>
          {dashData.weather.condition && (
            <div className="flex items-center gap-1.5 text-sm text-gray-500">
              <Cloud size={14} />
              <span className="capitalize">{dashData.weather.condition}</span>
            </div>
          )}
          {dashData.weather.humidity != null && (
            <div className="flex items-center gap-1.5 text-sm text-gray-500">
              <Droplets size={14} />
              <span>{dashData.weather.humidity}%</span>
            </div>
          )}
          {dashData.sensors?.temp != null && (
            <div className="ml-auto text-xs text-gray-400">
              Indoor {Math.round(dashData.sensors.temp)}°C
            </div>
          )}
        </div>
      )}

      {/* Advisories */}
      {dashData?.advisories && dashData.advisories.filter(a => a.message).length > 0 && (
        <div className="space-y-2">
          {dashData.advisories.filter(a => a.message).map(a => (
            <div key={a.id} className={`px-4 py-3 rounded-xl border text-sm ${
              a.severity === 'warning' ? 'bg-amber-50 border-amber-200 text-amber-800' :
              a.severity === 'danger' ? 'bg-red-50 border-red-200 text-red-800' :
              'bg-blue-50 border-blue-200 text-blue-800'
            }`}>
              {a.message}
            </div>
          ))}
        </div>
      )}

      {/* Stats grid */}
      <div className="grid grid-cols-2 gap-3">
        <Link to="/plants" className="bg-white rounded-xl border border-gray-200 p-4 hover:border-[var(--green-900)] transition-colors">
          <div className="flex items-center gap-2 text-[var(--green-900)]">
            <Sprout size={18} />
            <span className="text-2xl font-bold">{activePlants.length}</span>
          </div>
          <p className="text-xs text-gray-500 mt-1 flex items-center gap-1">Active plants <ChevronRight size={12} /></p>
        </Link>
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <div className="flex items-center gap-2 text-[var(--green-900)]">
            <ListTodo size={18} />
            <span className="text-2xl font-bold">{weekTasks.length}</span>
          </div>
          <p className="text-xs text-gray-500 mt-1">Tasks this week</p>
        </div>
        <Link to="/seeds" className="bg-white rounded-xl border border-gray-200 p-4 hover:border-[var(--green-900)] transition-colors">
          <div className="flex items-center gap-2 text-[var(--green-900)]">
            <Package size={18} />
            <span className="text-2xl font-bold">Seeds</span>
          </div>
          <p className="text-xs text-gray-500 mt-1 flex items-center gap-1">
            Manage seed inventory <ChevronRight size={12} />
          </p>
        </Link>
        <div className={`bg-white rounded-xl border p-4 ${overdueTasks.length > 0 ? 'border-red-300' : 'border-gray-200'}`}>
          <div className={`flex items-center gap-2 ${overdueTasks.length > 0 ? 'text-red-600' : 'text-gray-400'}`}>
            <AlertTriangle size={18} />
            <span className="text-2xl font-bold">{overdueTasks.length}</span>
          </div>
          <p className="text-xs text-gray-500 mt-1">Overdue tasks</p>
        </div>
      </div>

      {/* Needs Attention */}
      {(() => {
        const needsTransplant = allPlants.filter(p =>
          p.lifecycle_stage === 'hardening_off' ||
          (p.lifecycle_stage === 'seedling' && p.sow_date && (Date.now() - new Date(p.sow_date + 'T00:00:00').getTime()) > 42 * 86400000)
        )
        const readyToHarvest = allPlants.filter(p => p.lifecycle_stage === 'producing')
        if (needsTransplant.length === 0 && readyToHarvest.length === 0) return null
        return (
          <section className="space-y-2">
            <h2 className="text-sm font-semibold text-[var(--green-900)] uppercase tracking-wide">Needs Attention</h2>
            {needsTransplant.length > 0 && (
              <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium text-amber-900">{needsTransplant.length} plant{needsTransplant.length > 1 ? 's' : ''} ready to transplant</p>
                  <p className="text-xs text-amber-700 mt-0.5">
                    {needsTransplant.slice(0, 3).map(p => p.variety_name).join(', ')}
                    {needsTransplant.length > 3 ? ` +${needsTransplant.length - 3} more` : ''}
                  </p>
                </div>
                <Link to="/plants" className="flex-shrink-0 ml-3 text-xs font-medium py-2 px-3 min-h-[44px] flex items-center rounded-lg bg-amber-600 hover:bg-amber-700 text-white transition-colors">
                  View
                </Link>
              </div>
            )}
            {readyToHarvest.length > 0 && (
              <div className="bg-green-50 border border-green-200 rounded-xl p-4 flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium text-green-900">{readyToHarvest.length} plant{readyToHarvest.length > 1 ? 's' : ''} producing</p>
                  <p className="text-xs text-green-700 mt-0.5">
                    {readyToHarvest.slice(0, 3).map(p => p.variety_name).join(', ')}
                    {readyToHarvest.length > 3 ? ` +${readyToHarvest.length - 3} more` : ''}
                  </p>
                </div>
                <Link to="/plants" className="flex-shrink-0 ml-3 text-xs font-medium py-2 px-3 min-h-[44px] flex items-center rounded-lg bg-[var(--color-primary)] hover:bg-[var(--color-primary-dark)] text-white transition-colors">
                  View
                </Link>
              </div>
            )}
          </section>
        )
      })()}

      {/* Tasks */}
      <section>
        <h2 className="text-sm font-semibold text-[var(--green-900)] uppercase tracking-wide mb-3">Tasks</h2>

        {allTasks.length === 0 && (
          <div className="text-center py-6">
            <p className="text-sm text-gray-400">No pending tasks</p>
            <p className="text-xs text-gray-300 mt-1">Tasks are created when you use the AI planner or set up succession plans</p>
          </div>
        )}

        {overdueTasks.length > 0 && (
          <div className="mb-4">
            <p className="text-xs font-medium text-red-600 mb-1 px-1">Overdue</p>
            <div className="bg-white rounded-xl border border-gray-200 divide-y divide-gray-100">
              {overdueTasks.map(t => <TaskRow key={t.id} task={t} overdue />)}
            </div>
          </div>
        )}

        {weekTasks.length > 0 && (
          <div>
            <p className="text-xs font-medium text-gray-500 mb-1 px-1">This week</p>
            <div className="bg-white rounded-xl border border-gray-200 divide-y divide-gray-100">
              {weekTasks.map(t => <TaskRow key={t.id} task={t} />)}
            </div>
          </div>
        )}
      </section>

      {/* Seeds section */}
      {/* Planting calendar */}
      {allPlants.length > 0 && (
        <PlantingCalendar plants={allPlants} />
      )}

      {/* Grow suggestions */}
      <GrowSuggestions plants={allPlants} seeds={seedData ?? []} />

      <details className="group">
        <summary className="text-sm font-semibold text-[var(--green-900)] uppercase tracking-wide cursor-pointer list-none flex items-center gap-1">
          <ChevronRight size={14} className="transition-transform group-open:rotate-90" />
          Seeds &amp; Seedlings
          {seedlings.length > 0 && (
            <span className="ml-1 text-xs font-normal text-gray-500">({seedlings.length})</span>
          )}
        </summary>
        <div className="mt-3 space-y-2">
          {seedlings.length === 0 && (
            <p className="text-sm text-gray-400 py-2">No germinating or seedling plants</p>
          )}
          {seedlings.map(p => (
            <div key={p.id} className="bg-white rounded-xl border border-gray-200 p-3 flex items-center gap-3">
              <div
                className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                style={{ backgroundColor: getCropColor(p.crop_type) }}
              />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-gray-900 truncate">{p.variety_name}</p>
                <p className="text-xs text-gray-500 capitalize">{stageLabel(p.lifecycle_stage)}</p>
              </div>
              <div className="w-20">
                <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-emerald-500 rounded-full transition-all"
                    style={{ width: `${stageProgress(p.lifecycle_stage)}%` }}
                  />
                </div>
              </div>
            </div>
          ))}
        </div>
      </details>
    {/* Garden stats */}
    {allPlants.length > 3 && (
      <details className="group">
        <summary className="text-sm font-semibold text-[var(--green-900)] uppercase tracking-wide cursor-pointer list-none flex items-center gap-1">
          <ChevronRight size={14} className="transition-transform group-open:rotate-90" />
          Garden Statistics
        </summary>
        <div className="mt-3">
          <GardenStats plants={allPlants} beds={bedsData ?? []} />
        </div>
      </details>
    )}
    </div>
    )}
    </PageTransition>
  )
}
