import { getCropColor, getCropAbbr } from '../lib/crops'

interface PlantAvatarProps {
  cropType: string
  size?: 'sm' | 'md' | 'lg'
  className?: string
}

const sizes = {
  sm: { box: 'w-6 h-6', text: 'text-[8px]', radius: 'rounded-md' },
  md: { box: 'w-8 h-8', text: 'text-[10px]', radius: 'rounded-lg' },
  lg: { box: 'w-12 h-12', text: 'text-sm', radius: 'rounded-xl' },
}

export function PlantAvatar({ cropType, size = 'md', className = '' }: PlantAvatarProps) {
  const color = getCropColor(cropType)
  const abbr = getCropAbbr(cropType)
  const s = sizes[size]

  return (
    <div
      className={`${s.box} ${s.radius} ${s.text} flex items-center justify-center font-bold text-white shrink-0 ${className}`}
      style={{ backgroundColor: color }}
    >
      {abbr}
    </div>
  )
}
