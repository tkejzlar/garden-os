import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ChevronRight, Search, Plus, Package } from 'lucide-react'
import { seeds as seedsApi, type Seed } from '../lib/api'
import { useApi } from '../hooks/useApi'
import { getCropColor } from '../lib/crops'
import { getSowingHint } from '../lib/sowing'
import { ScanButton } from '../components/BarcodeScanner'
import { PageTransition } from '../components/PageTransition'
import { SkeletonList } from '../components/Skeleton'
import { Tip } from '../components/Tip'

export function SeedsList() {
  const { data, loading } = useApi(() => seedsApi.list(), [])
  const navigate = useNavigate()
  const [search, setSearch] = useState('')

  const allSeeds = data ?? []

  // Filter by search
  const filtered = search.trim()
    ? allSeeds.filter(s =>
        s.variety_name.toLowerCase().includes(search.toLowerCase()) ||
        s.crop_type.toLowerCase().includes(search.toLowerCase())
      )
    : allSeeds

  // Group by crop type (alphabetically)
  const grouped = filtered.reduce<Record<string, Seed[]>>((acc, s) => {
    const key = s.crop_type || 'other'
    ;(acc[key] ??= []).push(s)
    return acc
  }, {})

  const cropTypes = Object.keys(grouped).sort()

  if (loading) {
    return (
      <PageTransition>
        <div className="space-y-4">
          <h1 className="text-xl font-bold text-[var(--green-900)]">Seeds</h1>
          <SkeletonList count={4} />
        </div>
      </PageTransition>
    )
  }

  return (
    <PageTransition>
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold text-[var(--green-900)]">
          Seeds <span className="text-base font-normal text-gray-400">({allSeeds.length})</span>
        </h1>
        <div className="flex items-center gap-2">
          <ScanButton onScan={(name) => navigate(`/seeds/new?name=${encodeURIComponent(name)}`)} />
          <Link
            to="/seeds/new"
            className="min-h-[44px] inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg transition-colors"
          >
            <Plus size={16} />
            Add seed
          </Link>
        </div>
      </div>

      <Tip id="seeds-scan">
        On mobile, use the <strong>Scan</strong> button to add seeds by scanning the barcode on the packet.
      </Tip>

      {/* Search */}
      {allSeeds.length > 0 && (
        <div className="relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            placeholder="Search by variety or crop type..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full min-h-[44px] pl-9 pr-3 py-2 text-sm border border-gray-200 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500"
          />
        </div>
      )}

      {/* Empty state */}
      {allSeeds.length === 0 && (
        <div className="text-center py-12">
          <Package size={48} className="mx-auto mb-4 text-gray-300" />
          <h3 className="text-base font-semibold text-gray-600 mb-1">No seeds in inventory</h3>
          <p className="text-sm text-gray-400 mb-4">Add your seed packets to start planning your garden</p>
          <Link to="/seeds/new" className="btn-primary text-sm">+ Add your first seed</Link>
        </div>
      )}

      {/* No results from search */}
      {allSeeds.length > 0 && filtered.length === 0 && (
        <p className="text-sm text-gray-400 py-8 text-center">No seeds match your search</p>
      )}

      {/* Grouped by crop type */}
      {cropTypes.map(cropType => (
        <details key={cropType} open className="group">
          <summary className="flex items-center gap-2 cursor-pointer list-none py-2">
            <ChevronRight size={14} className="text-gray-400 transition-transform group-open:rotate-90" />
            <div
              className="w-3 h-3 rounded-full flex-shrink-0"
              style={{ backgroundColor: getCropColor(cropType) }}
            />
            <span className="text-sm font-semibold text-gray-700 capitalize">{cropType}</span>
            <span className="text-xs text-gray-400">({grouped[cropType].length})</span>
          </summary>

          <div className="mt-1 space-y-2 ml-5">
            {grouped[cropType].map(seed => (
              <div
                key={seed.id}
                onClick={() => navigate(`/seeds/${seed.id}`)}
                className="bg-white rounded-xl border border-gray-200 p-3 cursor-pointer hover:border-emerald-300 transition-colors min-h-[44px] flex items-center gap-3"
              >
                <div
                  className="w-3 h-3 rounded-full flex-shrink-0"
                  style={{ backgroundColor: getCropColor(seed.crop_type) }}
                />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 truncate">
                    {seed.variety_name}
                    {seed.quantity != null && seed.quantity > 0 && (
                      <span className="ml-1.5 text-xs bg-gray-100 text-gray-600 px-1.5 rounded">&times;{seed.quantity}</span>
                    )}
                  </p>
                  <div className="flex items-center gap-2">
                    {seed.source && (
                      <p className="text-xs text-gray-400 truncate">{seed.source}</p>
                    )}
                    <span className="text-xs text-emerald-600 bg-emerald-50 px-1.5 py-0.5 rounded">
                      {getSowingHint({ crop_type: seed.crop_type, lifecycle_stage: 'seed_packet' })}
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </details>
      ))}
    </div>
    </PageTransition>
  )
}
