import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { ArrowLeft, Calendar, MapPin, Hash, ShoppingBag } from 'lucide-react'
import { plants as plantsApi, harvests as harvestsApi, photos, type Harvest, type Photo } from '../lib/api'
import { useApi } from '../hooks/useApi'
import { stageLabel, stageProgress, nextStages, LIFECYCLE_STAGES, STAGE_INSTRUCTIONS } from '../lib/stages'
import { getCropColor } from '../lib/crops'
import { toast } from '../lib/toast'
import { PageTransition } from '../components/PageTransition'
import { VarietyInfo } from '../components/VarietyInfo'

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '—'
  const d = new Date(dateStr + 'T00:00:00')
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

export function PlantDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { data: plant, loading, refetch } = useApi(
    () => plantsApi.get(Number(id)),
    [id]
  )
  const [advancingStage, setAdvancingStage] = useState<string | null>(null)
  const [editingField, setEditingField] = useState<string | null>(null)
  const [showHarvestForm, setShowHarvestForm] = useState(false)
  const [harvestQty, setHarvestQty] = useState('medium')
  const [harvestNotes, setHarvestNotes] = useState('')
  const [harvestList, setHarvestList] = useState<Harvest[]>([])
  const [photoList, setPhotoList] = useState<Photo[]>([])
  const [uploading, setUploading] = useState(false)

  useEffect(() => {
    if (id) {
      harvestsApi.list(parseInt(id)).then(setHarvestList).catch(() => {})
      photos.list(parseInt(id)).then(setPhotoList).catch(() => {})
    }
  }, [id])

  const handlePhotoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !id) return
    setUploading(true)
    try {
      await photos.upload(parseInt(id), file)
      toast.success('Photo uploaded!')
      const updated = await photos.list(parseInt(id))
      setPhotoList(updated)
    } catch { toast.error('Failed to upload photo') }
    finally { setUploading(false); e.target.value = '' }
  }

  const logHarvest = async () => {
    if (!id) return
    try {
      await harvestsApi.create(parseInt(id), {
        quantity: harvestQty,
        notes: harvestNotes || undefined,
        date: new Date().toISOString().split('T')[0],
      })
      toast.success('Harvest logged!')
      setShowHarvestForm(false)
      setHarvestNotes('')
      const updated = await harvestsApi.list(parseInt(id))
      setHarvestList(updated)
    } catch {
      toast.error('Failed to log harvest')
    }
  }

  async function handleAdvance(stage: string) {
    if (!plant) return
    setAdvancingStage(stage)
    try {
      await plantsApi.advance(plant.id, stage)
      toast.success(`Advanced to ${stageLabel(stage)}`)
      refetch()
    } catch {
      toast.error('Failed to advance stage')
    } finally {
      setAdvancingStage(null)
    }
  }

  if (loading) {
    return (
      <div className="space-y-4">
        <Link to="/plants" className="text-sm text-gray-500 hover:text-[var(--green-900)] flex items-center gap-1">
          <ArrowLeft size={14} /> All plants
        </Link>
        <p className="text-sm text-gray-400">Loading...</p>
      </div>
    )
  }

  if (!plant) {
    return (
      <div className="space-y-4">
        <Link to="/plants" className="text-sm text-gray-500 hover:text-[var(--green-900)] flex items-center gap-1">
          <ArrowLeft size={14} /> All plants
        </Link>
        <p className="text-sm text-gray-500">Plant not found</p>
      </div>
    )
  }

  const progress = stageProgress(plant.lifecycle_stage)
  const next = nextStages(plant.lifecycle_stage, 2)
  const stageIdx = LIFECYCLE_STAGES.indexOf(plant.lifecycle_stage)

  // Stage instruction text
  const stageInstructions: Record<string, string> = {
    seed_packet: 'Seeds are stored and ready to be planted.',
    pre_treating: 'Soaking or stratifying seeds before sowing.',
    sown_indoor: 'Seeds have been sown indoors. Keep soil moist and warm.',
    germinating: 'Watch for sprouts! Keep soil consistently moist.',
    seedling: 'Young plant is growing. Ensure adequate light.',
    potted_up: 'Transplanted to a larger pot for stronger root growth.',
    hardening_off: 'Gradually exposing to outdoor conditions over 7–10 days.',
    planted_out: 'Transplanted to the garden bed. Water well after planting.',
    producing: 'Plant is actively producing. Harvest regularly.',
    done: 'Plant has completed its lifecycle.',
  }

  const keyDates = [
    { label: 'Sow date', date: plant.sow_date, field: 'sow_date' },
    { label: 'Germination', date: plant.germination_date, field: 'germination_date' },
    { label: 'Transplant', date: plant.transplant_date, field: 'transplant_date' },
  ]

  return (
    <PageTransition>
    <div className="space-y-5">
      {/* Header */}
      <div>
        <Link to="/plants" className="text-sm text-gray-500 hover:text-[var(--green-900)] flex items-center gap-1 mb-3">
          <ArrowLeft size={14} /> All plants
        </Link>
        <div className="flex items-center gap-3">
          <div
            className="w-4 h-4 rounded-full flex-shrink-0"
            style={{ backgroundColor: getCropColor(plant.crop_type) }}
          />
          <div>
            <h1 className="text-xl font-bold text-[var(--green-900)]">{plant.variety_name}</h1>
            <p className="text-sm text-gray-500 capitalize">{plant.crop_type}</p>
          </div>
        </div>
        {plant.bed_id && (
          <Link
            to={`/garden`}
            className="inline-block mt-2 text-xs bg-gray-100 text-gray-600 px-2 py-1 rounded hover:bg-gray-200 transition-colors"
          >
            Bed {plant.bed_id}
          </Link>
        )}
      </div>

      {/* Variety info (AI catalog lookup) */}
      {plant && <VarietyInfo varietyName={plant.variety_name} cropType={plant.crop_type} />}

      {/* Stage card */}
      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-gray-700">Current Stage</h2>
          <span className="text-xs text-gray-400">{stageIdx + 1} of {LIFECYCLE_STAGES.length}</span>
        </div>
        <div className="flex items-center justify-between">
          <p className="text-lg font-medium text-[var(--green-900)] capitalize">{stageLabel(plant.lifecycle_stage)}</p>
          {plant.days_in_stage != null && plant.days_in_stage > 0 && (
            <span className="text-xs px-2 py-1 bg-gray-100 text-gray-500 rounded-full">
              {plant.days_in_stage}d in stage
            </span>
          )}
        </div>

        {/* Progress bar */}
        <div className="space-y-1">
          <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-emerald-400 to-green-600 rounded-full transition-all"
              style={{ width: `${progress}%` }}
            />
          </div>
          <p className="text-xs text-gray-400 text-right">{progress}%</p>
        </div>

        {/* Advance buttons */}
        {next.length > 0 && (
          <div className="flex gap-2 pt-1">
            {next.map(stage => (
              <button
                key={stage}
                onClick={() => handleAdvance(stage)}
                disabled={advancingStage !== null}
                className="min-h-[44px] flex-1 px-3 py-2 text-sm font-medium text-[var(--green-900)] bg-emerald-50 hover:bg-emerald-100 rounded-lg transition-colors disabled:opacity-50 capitalize"
              >
                → {stageLabel(stage)}
              </button>
            ))}
          </div>
        )}

        {/* What's next hint */}
        {STAGE_INSTRUCTIONS[plant.lifecycle_stage] && (
          <div className="mt-4 p-3 bg-green-50 border border-green-100 rounded-xl">
            <p className="text-xs font-medium text-green-800 mb-1">What to do now</p>
            <p className="text-xs text-green-700 leading-relaxed">
              {STAGE_INSTRUCTIONS[plant.lifecycle_stage]}
            </p>
          </div>
        )}
      </div>

      {/* Harvest section — only for planted_out or producing plants */}
      {plant && ['planted_out', 'producing'].includes(plant.lifecycle_stage) && (
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-semibold text-gray-900">Harvests</h3>
            <button
              onClick={() => setShowHarvestForm(!showHarvestForm)}
              className="btn-secondary text-xs py-1.5 px-3 min-h-0"
            >
              {showHarvestForm ? 'Cancel' : '+ Log harvest'}
            </button>
          </div>

          {showHarvestForm && (
            <div className="space-y-3 mb-4 p-3 bg-green-50 rounded-xl border border-green-100">
              <div>
                <label className="text-xs font-medium text-gray-600 block mb-1.5">Amount</label>
                <div className="flex gap-2">
                  {['small', 'medium', 'large', 'huge'].map(q => (
                    <button
                      key={q}
                      onClick={() => setHarvestQty(q)}
                      className={`flex-1 py-2 text-xs font-medium rounded-lg border transition-colors min-h-[44px] capitalize ${
                        harvestQty === q
                          ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]'
                          : 'bg-white text-gray-600 border-gray-200 hover:border-gray-300'
                      }`}
                    >
                      {q}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-600 block mb-1.5">Notes (optional)</label>
                <input
                  value={harvestNotes}
                  onChange={e => setHarvestNotes(e.target.value)}
                  placeholder="e.g., First harvest of the season"
                  className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg outline-none focus:border-[var(--color-primary-light)] min-h-[44px]"
                />
              </div>
              <button onClick={logHarvest} className="btn-primary w-full text-sm">
                Log Harvest
              </button>
            </div>
          )}

          {harvestList.length > 0 ? (
            <div className="space-y-2">
              {harvestList.slice(0, 5).map(h => (
                <div key={h.id} className="flex items-center gap-3 py-2 border-b border-gray-50 last:border-0">
                  <span className="text-xs font-medium text-green-700 bg-green-50 px-2 py-1 rounded capitalize">{h.quantity}</span>
                  <span className="text-xs text-gray-500 flex-1">{h.notes || ''}</span>
                  <span className="text-xs text-gray-400">{new Date(h.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}</span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-xs text-gray-400 text-center py-2">No harvests logged yet</p>
          )}
        </div>
      )}

      {/* Photos */}
      {plant && (
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-semibold text-gray-900">Photos</h3>
            <label className={`btn-secondary text-xs py-1.5 px-3 min-h-0 cursor-pointer ${uploading ? 'opacity-50' : ''}`}>
              {uploading ? 'Uploading...' : '+ Add photo'}
              <input type="file" accept="image/*" capture="environment" onChange={handlePhotoUpload} className="hidden" disabled={uploading} />
            </label>
          </div>
          {photoList.length > 0 ? (
            <div className="grid grid-cols-3 gap-2">
              {photoList.map(p => (
                <div key={p.id} className="relative aspect-square rounded-lg overflow-hidden bg-gray-100 group">
                  <img src={p.url} alt="" className="w-full h-full object-cover" loading="lazy" />
                  <button
                    onClick={async () => {
                      if (!id) return
                      try {
                        await photos.remove(parseInt(id), p.id)
                        setPhotoList(prev => prev.filter(x => x.id !== p.id))
                        toast.success('Photo deleted')
                      } catch { toast.error('Failed to delete') }
                    }}
                    className="absolute top-1 right-1 w-6 h-6 bg-black/50 text-white rounded-full text-xs opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center"
                  >&times;</button>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-xs text-gray-400 text-center py-4">No photos yet — take one to track progress</p>
          )}
        </div>
      )}

      {/* Key dates */}
      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
        <h2 className="text-sm font-semibold text-gray-700 flex items-center gap-2">
          <Calendar size={14} /> Key Dates
        </h2>
        <div className="relative pl-4 space-y-4">
          {/* Timeline line */}
          <div className="absolute left-[5px] top-1 bottom-1 w-px bg-gray-200" />
          {keyDates.map(({ label, date, field }) => (
            <div key={label} className="relative flex items-center gap-3">
              <div className={`absolute left-[-12px] w-2.5 h-2.5 rounded-full border-2 ${date ? 'bg-emerald-500 border-emerald-500' : 'bg-white border-gray-300'}`} />
              <div>
                <p className="text-xs text-gray-500">{label}</p>
                {editingField === field ? (
                  <input
                    type="date"
                    autoFocus
                    defaultValue={date || ''}
                    onBlur={async (e) => {
                      const val = e.target.value || null
                      setEditingField(null)
                      if (val !== date && plant) {
                        try {
                          await plantsApi.update(plant.id, { [field]: val })
                          toast.success(`${label} updated`)
                          refetch()
                        } catch {
                          toast.error(`Failed to update ${label.toLowerCase()}`)
                        }
                      }
                    }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
                      if (e.key === 'Escape') setEditingField(null)
                    }}
                    className="text-sm font-medium text-gray-900 border border-gray-300 rounded px-1 py-0.5 outline-none focus:border-emerald-500"
                  />
                ) : (
                  <p
                    className="text-sm font-medium text-gray-900 cursor-pointer hover:text-emerald-700"
                    onClick={() => setEditingField(field)}
                    title="Click to edit"
                  >
                    {formatDate(date)}
                  </p>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Info */}
      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
        <h2 className="text-sm font-semibold text-gray-700">Details</h2>
        <div className="grid grid-cols-2 gap-3">
          {plant.grid_x !== null && plant.grid_y !== null && (
            <div className="flex items-center gap-2 text-sm text-gray-600">
              <MapPin size={14} className="text-gray-400" />
              <span>Grid {plant.grid_x},{plant.grid_y}</span>
            </div>
          )}
          {plant.quantity > 0 && (
            <div className="flex items-center gap-2 text-sm text-gray-600">
              <Hash size={14} className="text-gray-400" />
              <span>Qty {plant.quantity}</span>
            </div>
          )}
          {plant.source && (
            <div className="flex items-center gap-2 text-sm text-gray-600">
              <ShoppingBag size={14} className="text-gray-400" />
              <span className="capitalize">{plant.source}</span>
            </div>
          )}
        </div>
      </div>
    </div>

    {/* Timeline — merged stage history + harvests */}
    {plant && (plant.history?.length || harvestList.length > 0 || photoList.length > 0) ? (
      <div className="bg-white rounded-xl border border-gray-200 p-4">
        <h3 className="text-sm font-semibold text-gray-900 mb-4">Timeline</h3>
        <div className="relative pl-6 space-y-0">
          {/* Vertical line */}
          <div className="absolute left-[9px] top-2 bottom-2 w-px bg-gray-200" />

          {/* Merge and sort all events */}
          {[
            ...(plant.history || []).map(h => ({
              type: 'stage' as const,
              date: h.changed_at,
              label: `${stageLabel(h.from_stage)} → ${stageLabel(h.to_stage)}`,
              note: h.note,
            })),
            ...harvestList.map(h => ({
              type: 'harvest' as const,
              date: h.date || h.created_at,
              label: `Harvested (${h.quantity})`,
              note: h.notes,
            })),
            ...photoList.map(p => ({
              type: 'photo' as const,
              date: p.taken_at || '',
              label: 'Photo taken',
              note: p.caption,
            })),
          ]
            .filter(e => e.date)
            .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
            .slice(0, 20)
            .map((event, i) => (
              <div key={`${event.type}-${i}`} className="relative pb-4 last:pb-0">
                {/* Dot */}
                <div className={`absolute -left-6 top-1 w-[10px] h-[10px] rounded-full border-2 ${
                  event.type === 'stage' ? 'border-green-500 bg-green-100' :
                  event.type === 'harvest' ? 'border-amber-500 bg-amber-100' :
                  'border-blue-500 bg-blue-100'
                }`} />
                <div>
                  <p className="text-sm font-medium text-gray-800">{event.label}</p>
                  <p className="text-xs text-gray-400 mt-0.5">
                    {new Date(event.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                  </p>
                  {event.note && <p className="text-xs text-gray-500 mt-1">{event.note}</p>}
                </div>
              </div>
            ))}
        </div>
      </div>
    ) : null}
    </PageTransition>
  )
}
