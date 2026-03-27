import { Link } from 'react-router-dom'
import { Plus, Scan, Sprout, Map, BookOpen, Sparkles } from 'lucide-react'

export function QuickActions() {
  const actions = [
    { icon: Plus, label: 'Add seed', to: '/seeds/new', color: 'bg-green-50 text-green-700' },
    { icon: Sprout, label: 'My plants', to: '/plants', color: 'bg-emerald-50 text-emerald-700' },
    { icon: Map, label: 'Bed planner', to: '/plan?tab=beds', color: 'bg-blue-50 text-blue-700' },
    { icon: BookOpen, label: 'Companions', to: '/companions', color: 'bg-purple-50 text-purple-700' },
  ]

  return (
    <div className="grid grid-cols-4 gap-2">
      {actions.map(({ icon: Icon, label, to, color }) => (
        <Link
          key={label}
          to={to}
          className={`flex flex-col items-center gap-1.5 p-3 rounded-xl ${color} transition-all hover:scale-[1.02] active:scale-[0.98] min-h-[44px]`}
        >
          <Icon size={20} />
          <span className="text-[10px] font-medium leading-tight text-center">{label}</span>
        </Link>
      ))}
    </div>
  )
}
