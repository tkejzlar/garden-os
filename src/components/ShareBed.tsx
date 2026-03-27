import { Share2 } from 'lucide-react'
import type { Bed } from '../lib/api'
import { toast } from '../lib/toast'

export function ShareBedButton({ bed }: { bed: Bed }) {
  const handleShare = async () => {
    const text = `${bed.name}: ${bed.plants.length} plants (${bed.width_cm}×${bed.length_cm}cm)\n` +
      bed.plants.map(p => `- ${p.variety_name} (${p.crop_type})`).join('\n')

    if (navigator.share) {
      try {
        await navigator.share({ title: `Garden bed: ${bed.name}`, text })
        toast.success('Shared!')
      } catch { /* user cancelled */ }
    } else {
      await navigator.clipboard.writeText(text)
      toast.success('Bed info copied to clipboard')
    }
  }

  return (
    <button
      onClick={handleShare}
      className="p-2 text-gray-400 hover:text-[var(--color-primary)] rounded-lg transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
      title="Share bed"
    >
      <Share2 size={16} />
    </button>
  )
}
