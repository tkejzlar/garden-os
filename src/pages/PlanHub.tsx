import { useState, useEffect, useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'
import { CheckCircle2, Circle, ChevronDown, ChevronRight, Loader2, Sprout, GripVertical } from 'lucide-react'
import { DndContext, closestCenter, PointerSensor, useSensor, useSensors, type DragEndEvent } from '@dnd-kit/core'
import { SortableContext, useSortable, rectSortingStrategy } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { tasks as tasksApi, beds as bedsApi, timeline as timelineApi } from '../lib/api'
import type { Task, Bed, TimelineData, TimelineBed } from '../lib/api'
import { getCropColor } from '../lib/crops'
import { toast } from '../lib/toast'
import { getSeasonDates, getSeasonProgress } from '../lib/season'
import { BedModal } from '../components/bed/BedModal'
import { PageTransition } from '../components/PageTransition'

type Tab = 'tasks' | 'timeline' | 'beds'

// Generate months from one month before season start to season end
const _seasonDates = getSeasonDates(new Date().getFullYear())
const MONTHS: string[] = []
const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
for (let m = Math.max(0, _seasonDates.start.getMonth() - 1); m <= _seasonDates.end.getMonth(); m++) {
  MONTHS.push(_monthNames[m])
}

function seasonProgress(): number {
  return getSeasonProgress().pct
}

// ── Relative date helper ──
function relativeDate(dateStr: string): string {
  const d = new Date(dateStr + 'T00:00:00')
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  const diff = Math.round((d.getTime() - now.getTime()) / (1000 * 60 * 60 * 24))
  if (diff === 0) return 'Today'
  if (diff === 1) return 'Tomorrow'
  if (diff === -1) return 'Yesterday'
  if (diff < -1) return `${Math.abs(diff)}d overdue`
  if (diff <= 7) return `In ${diff}d`
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

function isOverdue(dateStr: string): boolean {
  const d = new Date(dateStr + 'T00:00:00')
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  return d < now
}

function isThisWeek(dateStr: string): boolean {
  const d = new Date(dateStr + 'T00:00:00')
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  const diff = (d.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
  return diff >= 0 && diff <= 7
}

// ── Occupancy color ──
function occupancyColor(pct: number): string {
  if (pct === 0) return 'bg-gray-100'
  if (pct < 25) return 'bg-green-100'
  if (pct < 50) return 'bg-green-200'
  if (pct < 75) return 'bg-green-400'
  return 'bg-green-600'
}

function occupancyText(pct: number): string {
  if (pct === 0) return 'text-gray-400'
  if (pct < 75) return 'text-green-900'
  return 'text-white'
}

// ═══════════════════════════════════════════════════════
// Tasks Tab
// ═══════════════════════════════════════════════════════

function TasksTab() {
  const [taskList, setTaskList] = useState<Task[]>([])
  const [loading, setLoading] = useState(true)
  const [fadingIds, setFadingIds] = useState<Set<number>>(new Set())
  const [showLater, setShowLater] = useState(false)

  useEffect(() => {
    tasksApi.list()
      .then(setTaskList)
      .catch(err => toast.error(err.message))
      .finally(() => setLoading(false))
  }, [])

  const completeTask = useCallback(async (id: number) => {
    setFadingIds(s => new Set(s).add(id))
    try {
      await tasksApi.complete(id)
      toast.success('Task completed')
      setTimeout(() => {
        setTaskList(prev => prev.filter(t => t.id !== id))
        setFadingIds(s => { const n = new Set(s); n.delete(id); return n })
      }, 300)
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Failed to complete task')
      setFadingIds(s => { const n = new Set(s); n.delete(id); return n })
    }
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-6 h-6 text-[var(--green-700)] animate-spin" />
      </div>
    )
  }

  const active = taskList.filter(t => t.status !== 'done')
  const done = taskList.filter(t => t.status === 'done')
  const overdue = active.filter(t => t.due_date && isOverdue(t.due_date))
  const thisWeek = active.filter(t => t.due_date && isThisWeek(t.due_date))
  const later = active.filter(t => !t.due_date || (!isOverdue(t.due_date) && !isThisWeek(t.due_date)))

  const progress = seasonProgress()

  return (
    <div className="space-y-4">
      {/* Summary strip */}
      <div className="bg-white rounded-xl p-4 shadow-sm border border-gray-100">
        <div className="flex items-center justify-between text-sm mb-2">
          <span className="text-gray-600">
            <span className="font-semibold text-[var(--green-700)]">{done.length}</span> done
            {' \u00b7 '}
            <span className="font-semibold">{active.length}</span> remaining
          </span>
          <span className="text-xs text-gray-400">Season {progress}%</span>
        </div>
        <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
          <div
            className="h-full bg-[var(--green-600)] rounded-full transition-all duration-500"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      {/* Overdue */}
      {overdue.length > 0 && (
        <TaskGroup label="Overdue" tasks={overdue} borderColor="border-l-red-500" fadingIds={fadingIds} onComplete={completeTask} />
      )}

      {/* This week */}
      {thisWeek.length > 0 && (
        <TaskGroup label="This week" tasks={thisWeek} borderColor="border-l-[var(--green-600)]" fadingIds={fadingIds} onComplete={completeTask} />
      )}

      {/* Later */}
      {later.length > 0 && (
        <div>
          <button
            onClick={() => setShowLater(!showLater)}
            className="flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 py-2 min-h-[44px]"
          >
            {showLater ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
            {showLater ? 'Hide' : 'Show'} {later.length} later task{later.length === 1 ? '' : 's'}
          </button>
          {showLater && (
            <TaskGroup label="" tasks={later} borderColor="border-l-gray-300" fadingIds={fadingIds} onComplete={completeTask} />
          )}
        </div>
      )}

      {active.length === 0 && (
        <div className="text-center py-12 text-gray-400 text-sm">
          <Sprout className="w-8 h-8 mx-auto mb-2 opacity-50" />
          All caught up!
        </div>
      )}
    </div>
  )
}

function TaskGroup({ label, tasks, borderColor, fadingIds, onComplete }: {
  label: string
  tasks: Task[]
  borderColor: string
  fadingIds: Set<number>
  onComplete: (id: number) => void
}) {
  return (
    <div className="space-y-1">
      {label && <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide px-1 mb-1">{label}</h3>}
      {tasks.map(task => (
        <div
          key={task.id}
          className={`flex items-center gap-3 bg-white rounded-xl px-4 py-3 shadow-sm border border-gray-100 border-l-4 ${borderColor} transition-opacity duration-300 ${fadingIds.has(task.id) ? 'opacity-0' : 'opacity-100'}`}
        >
          <button
            onClick={() => onComplete(task.id)}
            className="shrink-0 text-gray-300 hover:text-[var(--green-600)] transition-colors min-h-[36px] min-w-[36px] flex items-center justify-center"
            title="Complete task"
          >
            {fadingIds.has(task.id) ? (
              <CheckCircle2 className="w-6 h-6 text-[var(--green-600)]" />
            ) : (
              <Circle className="w-6 h-6" />
            )}
          </button>
          <div className="flex-1 min-w-0">
            <p className="text-sm text-gray-900 truncate">{task.title}</p>
            <div className="flex items-center gap-2 mt-0.5">
              {task.due_date && (
                <span className={`text-xs ${isOverdue(task.due_date) ? 'text-red-500 font-medium' : 'text-gray-400'}`}>
                  {relativeDate(task.due_date)}
                </span>
              )}
              {task.bed_names?.map(name => (
                <span key={name} className="text-xs bg-green-50 text-[var(--green-700)] rounded-full px-2 py-0.5">
                  {name}
                </span>
              ))}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}

// ═══════════════════════════════════════════════════════
// Timeline Tab
// ═══════════════════════════════════════════════════════

function TimelineTab() {
  const [data, setData] = useState<TimelineData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    timelineApi.get()
      .then(setData)
      .catch(err => toast.error(err.message))
      .finally(() => setLoading(false))
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-6 h-6 text-[var(--green-700)] animate-spin" />
      </div>
    )
  }

  if (!data || data.beds.length === 0) {
    return (
      <div className="text-center py-12 text-gray-400 text-sm">
        <Sprout className="w-8 h-8 mx-auto mb-2 opacity-50" />
        No timeline data yet
      </div>
    )
  }

  // Extract month labels from the data
  const monthLabels = data.beds[0]?.occupancy.map(o => {
    const [y, m] = o.month.split('-')
    return new Date(parseInt(y), parseInt(m) - 1).toLocaleDateString('en-US', { month: 'short' })
  }) || []

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-100">
            <th className="text-left text-xs font-semibold text-gray-500 px-4 py-3 sticky left-0 bg-white min-w-[100px]">Bed</th>
            {monthLabels.map((m, i) => (
              <th key={i} className="text-center text-xs font-semibold text-gray-500 px-2 py-3 min-w-[50px]">{m}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.beds.map((bed: TimelineBed) => {
            const totalSlots = bed.grid_cols * bed.grid_rows
            return (
              <tr key={bed.bed_name} className="border-b border-gray-50 last:border-0">
                <td className="px-4 py-2.5 font-medium text-gray-900 sticky left-0 bg-white">{bed.bed_name}</td>
                {bed.occupancy.map((o, i) => {
                  const pct = totalSlots > 0 ? Math.round((o.filled / totalSlots) * 100) : 0
                  return (
                    <td key={i} className="px-1 py-1.5">
                      <div className={`rounded-md text-center py-1.5 text-xs font-medium ${occupancyColor(pct)} ${occupancyText(pct)}`}>
                        {o.filled > 0 ? o.filled : '·'}
                      </div>
                    </td>
                  )
                })}
              </tr>
            )
          })}
        </tbody>
      </table>

      {/* Crop legend */}
      <div className="px-4 py-3 border-t border-gray-100">
        <p className="text-xs font-semibold text-gray-500 mb-2">Crops per bed</p>
        <div className="space-y-1.5">
          {data.beds.map((bed: TimelineBed) => (
            <div key={bed.bed_name} className="flex items-center gap-2 flex-wrap">
              <span className="text-xs text-gray-500 w-24 shrink-0 truncate">{bed.bed_name}</span>
              {bed.crops.map((crop, i) => (
                <span
                  key={i}
                  className="inline-flex items-center gap-1 text-xs rounded-full px-2 py-0.5"
                  style={{ backgroundColor: getCropColor(crop.crop) + '20', color: getCropColor(crop.crop) }}
                >
                  <span className="w-2 h-2 rounded-full" style={{ backgroundColor: getCropColor(crop.crop) }} />
                  {crop.varieties.join(', ')} ({crop.plant_count})
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════
// Beds Tab
// ═══════════════════════════════════════════════════════

function SortableBedCard({ bed, onClick }: { bed: Bed; onClick: () => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: bed.id })
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
    zIndex: isDragging ? 10 : 0,
  }

  const bedArea = bed.grid_cols * bed.grid_rows
  const plantArea = bed.plants.reduce((sum, p) => sum + (p.grid_w || 1) * (p.grid_h || 1), 0)
  const occupancy = bedArea > 0 ? Math.min(100, Math.round((plantArea / bedArea) * 100)) : 0

  return (
    <div ref={setNodeRef} style={style} className="relative">
      {/* Drag handle */}
      <div {...attributes} {...listeners} className="absolute top-2 right-2 p-1 text-gray-300 hover:text-gray-500 cursor-grab active:cursor-grabbing z-10">
        <GripVertical size={14} />
      </div>
      <button
        onClick={onClick}
        className="w-full bg-white rounded-xl p-3 shadow-sm border border-gray-100 text-left hover:shadow-md hover:border-green-200 transition-all min-h-[44px] card-interactive"
      >
        <div className="w-full h-10 rounded-lg mb-2" style={{ backgroundColor: bed.canvas_color || '#86efac' }} />
        <p className="text-sm font-semibold text-gray-900 truncate">{bed.name}</p>
        <p className="text-xs text-gray-400 mt-0.5">
          {bed.plants.length} plant{bed.plants.length === 1 ? '' : 's'} · {bed.width_cm} × {bed.length_cm}cm
        </p>
        {bed.plants.length > 0 && (
          <div className="mt-2 h-1 bg-gray-100 rounded-full overflow-hidden">
            <div className="h-full rounded-full transition-all"
                 style={{ width: `${occupancy}%`, backgroundColor: occupancy > 80 ? '#f59e0b' : 'var(--color-primary-light)' }} />
          </div>
        )}
      </button>
    </div>
  )
}

function BedsTab({ onOpenBed }: { onOpenBed: (id: number) => void }) {
  const [bedList, setBedList] = useState<Bed[]>([])
  const [loading, setLoading] = useState(true)
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }))

  useEffect(() => {
    bedsApi.list()
      .then(list => setBedList(list.sort((a, b) => a.position - b.position)))
      .catch(err => toast.error(err.message))
      .finally(() => setLoading(false))
  }, [])

  const handleDragEnd = async (event: DragEndEvent) => {
    const { active, over } = event
    if (!over || active.id === over.id) return

    const oldIds = bedList.map(b => b.id)
    const oldIdx = oldIds.indexOf(active.id as number)
    const newIdx = oldIds.indexOf(over.id as number)
    if (oldIdx < 0 || newIdx < 0) return

    // Optimistic reorder
    const newList = [...bedList]
    const [moved] = newList.splice(oldIdx, 1)
    newList.splice(newIdx, 0, moved)
    setBedList(newList)

    try {
      await bedsApi.reorder(newList.map(b => b.id))
    } catch {
      // Revert
      setBedList(bedList)
      toast.error('Failed to reorder')
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-6 h-6 animate-spin text-gray-400" />
      </div>
    )
  }

  if (bedList.length === 0) {
    return (
      <div className="text-center py-12 text-gray-400 text-sm">
        <Sprout className="w-8 h-8 mx-auto mb-2 opacity-50" />
        No beds yet
      </div>
    )
  }

  return (
    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
      <SortableContext items={bedList.map(b => b.id)} strategy={rectSortingStrategy}>
        <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))' }}>
          {bedList.map(bed => (
            <SortableBedCard key={bed.id} bed={bed} onClick={() => onOpenBed(bed.id)} />
          ))}
        </div>
      </SortableContext>
    </DndContext>
  )
}

// ═══════════════════════════════════════════════════════
// Main PlanHub
// ═══════════════════════════════════════════════════════

const TAB_CONFIG: { key: Tab; label: string }[] = [
  { key: 'tasks', label: 'Tasks' },
  { key: 'timeline', label: 'Timeline' },
  { key: 'beds', label: 'Beds' },
]

export function PlanHub() {
  const [searchParams, setSearchParams] = useSearchParams()
  const activeTab = (searchParams.get('tab') as Tab) || 'tasks'
  const setActiveTab = useCallback((tab: Tab) => {
    const params = new URLSearchParams(searchParams)
    params.set('tab', tab)
    // Preserve bed param if present
    setSearchParams(params)
  }, [searchParams, setSearchParams])
  const bedId = searchParams.get('bed') ? parseInt(searchParams.get('bed')!) : null

  const openBed = useCallback((id: number) => {
    const params = new URLSearchParams(searchParams)
    params.set('bed', String(id))
    setSearchParams(params)
  }, [searchParams, setSearchParams])

  const closeBed = useCallback(() => {
    const params = new URLSearchParams(searchParams)
    params.delete('bed')
    setSearchParams(params)
  }, [searchParams, setSearchParams])

  return (
    <PageTransition>
    <div className="pb-24">
      <h1 className="text-xl font-bold text-[var(--green-900)] mb-4">Plan</h1>

      {/* Tab bar */}
      <div className="flex gap-1 bg-gray-100 rounded-xl p-1 mb-4">
        {TAB_CONFIG.map(tab => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={`flex-1 text-sm font-medium py-2 rounded-lg transition-colors min-h-[44px] ${
              activeTab === tab.key
                ? 'bg-white text-[var(--green-900)] shadow-sm'
                : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {activeTab === 'tasks' && <TasksTab />}
      {activeTab === 'timeline' && <TimelineTab />}
      {activeTab === 'beds' && <BedsTab onOpenBed={openBed} />}

      {/* Bed modal — AI FAB is global in AppShell, no need for a Plan-specific one */}
      <BedModal bedId={bedId} onClose={closeBed} />
    </div>
    </PageTransition>
  )
}
