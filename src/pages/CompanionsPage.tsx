import { ArrowLeft } from 'lucide-react'
import { Link } from 'react-router-dom'
import { CompanionGuide } from '../components/CompanionGuide'
import { PageTransition } from '../components/PageTransition'

export function CompanionsPage() {
  return (
    <PageTransition>
    <div className="space-y-4 max-w-lg">
      <div className="flex items-center gap-3">
        <Link to="/" className="p-2 -ml-2 text-gray-500 hover:text-gray-700 min-h-[44px] min-w-[44px] flex items-center justify-center">
          <ArrowLeft size={20} />
        </Link>
        <h1 className="text-xl font-bold text-[var(--color-primary-dark)]" style={{ fontFamily: 'Lora, serif' }}>
          Companion Planting Guide
        </h1>
      </div>
      <p className="text-sm text-[var(--color-muted)]">
        Plant companions together for better growth. Avoid bad pairings to prevent competition and disease.
      </p>
      <CompanionGuide />
    </div>
    </PageTransition>
  )
}
