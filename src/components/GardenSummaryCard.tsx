import { Sprout, Package, Map, Scissors, Calendar } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { Plant, Seed, Bed, Harvest } from '../lib/api'

interface GardenSummaryCardProps {
  plants: Plant[]
  seeds: Seed[]
  beds: Bed[]
}

export function GardenSummaryCard({ plants, seeds, beds }: GardenSummaryCardProps) {
  const producing = plants.filter(p => p.lifecycle_stage === 'producing').length
  const seedling = plants.filter(p => ['germinating', 'seedling', 'sown_indoor'].includes(p.lifecycle_stage)).length
  const totalBedArea = beds.reduce((s, b) => s + (b.width_cm || 0) * (b.length_cm || 0), 0) / 10000 // m²
  const uniqueCrops = new Set(plants.map(p => p.crop_type.toLowerCase())).size

  const stats = [
    { icon: Sprout, label: 'Active plants', value: plants.length, link: '/plants', color: 'text-green-600' },
    { icon: Package, label: 'Seed varieties', value: seeds.length, link: '/seeds', color: 'text-purple-600' },
    { icon: Map, label: 'Beds', value: `${beds.length} (${totalBedArea.toFixed(1)}m²)`, link: '/plan?tab=beds', color: 'text-blue-600' },
    { icon: Calendar, label: 'Crop types', value: uniqueCrops, link: '/companions', color: 'text-amber-600' },
  ]

  return (
    <div className="bg-[var(--color-card)] rounded-xl border border-[var(--color-border)] p-4">
      <h3 className="text-sm font-semibold text-[var(--color-fg)] mb-3" style={{ fontFamily: 'Lora, serif' }}>
        Garden Overview
      </h3>
      <div className="grid grid-cols-2 gap-3">
        {stats.map(({ icon: Icon, label, value, link, color }) => (
          <Link
            key={label}
            to={link}
            className="flex items-center gap-3 p-2 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors"
          >
            <Icon size={18} className={color} />
            <div>
              <p className="text-sm font-bold text-[var(--color-fg)]">{value}</p>
              <p className="text-[10px] text-[var(--color-muted)]">{label}</p>
            </div>
          </Link>
        ))}
      </div>
      {producing > 0 && (
        <div className="mt-3 pt-3 border-t border-[var(--color-border)] flex items-center gap-2 text-xs text-green-700">
          <Scissors size={12} />
          <span>{producing} plant{producing > 1 ? 's' : ''} ready to harvest</span>
        </div>
      )}
      {seedling > 0 && (
        <div className="mt-1 flex items-center gap-2 text-xs text-amber-700">
          <Sprout size={12} />
          <span>{seedling} seedling{seedling > 1 ? 's' : ''} growing</span>
        </div>
      )}
    </div>
  )
}
