import { Link } from 'react-router-dom'
import { Sun, Droplets, Sprout, Scissors, AlertTriangle } from 'lucide-react'
import type { Plant, Task } from '../lib/api'

interface TodayFocusProps {
  plants: Plant[]
  tasks: Task[]
}

interface FocusItem {
  icon: typeof Sun
  color: string
  bg: string
  title: string
  detail: string
  link?: string
}

export function TodayFocus({ plants, tasks }: TodayFocusProps) {
  const items: FocusItem[] = []

  // Overdue tasks
  const overdue = tasks.filter(t => {
    const d = new Date(t.due_date + 'T00:00:00')
    return d < new Date(new Date().toDateString())
  })
  if (overdue.length > 0) {
    items.push({
      icon: AlertTriangle,
      color: 'text-red-600',
      bg: 'bg-red-50',
      title: `${overdue.length} overdue task${overdue.length > 1 ? 's' : ''}`,
      detail: overdue.slice(0, 2).map(t => t.title).join(', '),
      link: '/plan?tab=tasks',
    })
  }

  // Plants needing transplant (hardening_off stage)
  const transplant = plants.filter(p => p.lifecycle_stage === 'hardening_off')
  if (transplant.length > 0) {
    items.push({
      icon: Sprout,
      color: 'text-amber-600',
      bg: 'bg-amber-50',
      title: `${transplant.length} ready to transplant`,
      detail: transplant.slice(0, 3).map(p => p.variety_name).join(', '),
      link: '/plants',
    })
  }

  // Plants producing (harvest time)
  const producing = plants.filter(p => p.lifecycle_stage === 'producing')
  if (producing.length > 0) {
    items.push({
      icon: Scissors,
      color: 'text-green-600',
      bg: 'bg-green-50',
      title: `${producing.length} plant${producing.length > 1 ? 's' : ''} producing`,
      detail: 'Check for harvest today',
      link: '/plants',
    })
  }

  // Seedlings needing water (general reminder if any seedlings exist)
  const seedlings = plants.filter(p => ['germinating', 'seedling', 'sown_indoor'].includes(p.lifecycle_stage))
  if (seedlings.length > 0) {
    items.push({
      icon: Droplets,
      color: 'text-blue-500',
      bg: 'bg-blue-50',
      title: `${seedlings.length} seedling${seedlings.length > 1 ? 's' : ''} to check`,
      detail: 'Water if soil is dry, check for germination',
    })
  }

  // Nice day for gardening (simple heuristic based on month)
  const month = new Date().getMonth()
  if (month >= 3 && month <= 9 && items.length < 3) {
    items.push({
      icon: Sun,
      color: 'text-amber-500',
      bg: 'bg-amber-50',
      title: 'Good weather for gardening',
      detail: 'Consider direct sowing or transplanting outdoor beds',
    })
  }

  if (items.length === 0) return null

  return (
    <div className="space-y-2">
      <h2 className="text-sm font-semibold text-[var(--color-primary-dark)] uppercase tracking-wide" style={{ fontFamily: 'Lora, serif' }}>
        Today&apos;s Focus
      </h2>
      {items.slice(0, 3).map((item, i) => {
        const Icon = item.icon
        const content = (
          <div className={`flex items-start gap-3 p-3 rounded-xl ${item.bg} transition-all`}>
            <div className={`mt-0.5 ${item.color}`}>
              <Icon size={18} />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900">{item.title}</p>
              <p className="text-xs text-gray-600 mt-0.5 truncate">{item.detail}</p>
            </div>
          </div>
        )
        return item.link ? (
          <Link key={i} to={item.link} className="block hover:opacity-90">{content}</Link>
        ) : (
          <div key={i}>{content}</div>
        )
      })}
    </div>
  )
}
