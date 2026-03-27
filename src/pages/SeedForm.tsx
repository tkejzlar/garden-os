import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate, Link, useSearchParams } from 'react-router-dom'
import { ArrowLeft, Trash2, Sprout } from 'lucide-react'
import { seeds as seedsApi, plants as plantsApi, type Seed, type SeedLookup, type Plant } from '../lib/api'
import { useApi } from '../hooks/useApi'
import { getCropColor, CROP_TYPES } from '../lib/crops'
import { toast } from '../lib/toast'
import { PageTransition } from '../components/PageTransition'

export function SeedForm() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const isEdit = Boolean(id)
  const [searchParams] = useSearchParams()
  const prefillName = searchParams.get('name')

  // Form state
  const [varietyName, setVarietyName] = useState(prefillName || '')
  const [cropType, setCropType] = useState('')
  const [source, setSource] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  // Typeahead state
  const [lookupResults, setLookupResults] = useState<SeedLookup[]>([])
  const [showDropdown, setShowDropdown] = useState(false)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const dropdownRef = useRef<HTMLDivElement>(null)

  // Delete confirmation
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [deleting, setDeleting] = useState(false)

  // Fetch existing seed for edit
  const { data: allSeeds, loading: seedsLoading } = useApi(
    () => isEdit ? seedsApi.list() : Promise.resolve([]),
    [id]
  )

  // Fetch related plants (edit mode)
  const { data: allPlants } = useApi(
    () => isEdit ? plantsApi.list() : Promise.resolve([]),
    [id]
  )

  // Populate form when seed is loaded
  useEffect(() => {
    if (!isEdit || !allSeeds) return
    const seed = allSeeds.find(s => s.id === Number(id))
    if (seed) {
      setVarietyName(seed.variety_name)
      setCropType(seed.crop_type)
      setSource(seed.source || '')
      setNotes(seed.notes || '')
    }
  }, [allSeeds, id, isEdit])

  // Related plants — match on variety_name + crop_type
  const relatedPlants: Plant[] = isEdit && allPlants
    ? allPlants.filter(p =>
        p.variety_name.toLowerCase() === varietyName.toLowerCase() &&
        p.crop_type.toLowerCase() === cropType.toLowerCase()
      )
    : []

  // Close dropdown on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setShowDropdown(false)
      }
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  // Typeahead: debounced lookup
  function handleVarietyChange(value: string) {
    setVarietyName(value)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    if (value.trim().length < 2) {
      setLookupResults([])
      setShowDropdown(false)
      return
    }
    debounceRef.current = setTimeout(async () => {
      try {
        const results = await seedsApi.lookup(value.trim())
        setLookupResults(results)
        setShowDropdown(results.length > 0)
      } catch {
        setLookupResults([])
        setShowDropdown(false)
      }
    }, 300)
  }

  function selectLookup(match: SeedLookup) {
    setVarietyName(match.variety_name)
    setCropType(match.crop_type)
    setSource(match.supplier || '')
    setShowDropdown(false)
    setLookupResults([])
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!varietyName.trim()) {
      toast.error('Variety name is required')
      return
    }

    setSaving(true)
    try {
      const data: Partial<Seed> = {
        variety_name: varietyName.trim(),
        crop_type: cropType.trim(),
        source: source.trim(),
        notes: notes.trim(),
      }

      if (isEdit) {
        await seedsApi.update(Number(id), data)
        toast.success('Seed updated')
        navigate(`/seeds/${id}`)
      } else {
        const created = await seedsApi.create(data)
        toast.success('Seed added')
        navigate(`/seeds/${created.id}`)
      }
    } catch {
      toast.error(isEdit ? 'Failed to update seed' : 'Failed to create seed')
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete() {
    if (!confirmDelete) {
      setConfirmDelete(true)
      return
    }
    setDeleting(true)
    try {
      await seedsApi.remove(Number(id))
      toast.success('Seed deleted')
      navigate('/seeds')
    } catch {
      toast.error('Failed to delete seed')
    } finally {
      setDeleting(false)
    }
  }

  if (isEdit && seedsLoading) {
    return (
      <div className="space-y-4">
        <Link to="/seeds" className="text-sm text-gray-500 hover:text-[var(--green-900)] flex items-center gap-1">
          <ArrowLeft size={14} /> All seeds
        </Link>
        <p className="text-sm text-gray-400">Loading...</p>
      </div>
    )
  }

  // Check seed exists for edit
  const existingSeed = isEdit && allSeeds ? allSeeds.find(s => s.id === Number(id)) : null
  if (isEdit && !seedsLoading && !existingSeed) {
    return (
      <div className="space-y-4">
        <Link to="/seeds" className="text-sm text-gray-500 hover:text-[var(--green-900)] flex items-center gap-1">
          <ArrowLeft size={14} /> All seeds
        </Link>
        <p className="text-sm text-gray-500">Seed not found</p>
      </div>
    )
  }

  return (
    <PageTransition>
    <div className="space-y-5">
      {/* Back link */}
      <Link to="/seeds" className="text-sm text-gray-500 hover:text-[var(--green-900)] flex items-center gap-1">
        <ArrowLeft size={14} /> All seeds
      </Link>

      <h1 className="text-xl font-bold text-[var(--green-900)]">
        {isEdit ? 'Edit Seed' : 'Add Seed'}
      </h1>

      {/* Form */}
      <form onSubmit={handleSave} className="space-y-4">
        {/* Variety name with typeahead */}
        <div className="relative" ref={dropdownRef}>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Variety name <span className="text-red-500">*</span>
          </label>
          <input
            type="text"
            required
            value={varietyName}
            onChange={e => handleVarietyChange(e.target.value)}
            onFocus={() => lookupResults.length > 0 && setShowDropdown(true)}
            placeholder="e.g. San Marzano"
            className="w-full min-h-[44px] px-3 py-2 text-sm border border-gray-200 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500"
          />

          {/* Typeahead dropdown */}
          {showDropdown && lookupResults.length > 0 && (
            <div className="absolute z-10 mt-1 w-full bg-white border border-gray-200 rounded-lg shadow-lg max-h-60 overflow-y-auto">
              {lookupResults.map((match, i) => (
                <button
                  key={`${match.variety_name}-${match.crop_type}-${i}`}
                  type="button"
                  onClick={() => selectLookup(match)}
                  className="w-full min-h-[44px] px-3 py-2 text-left hover:bg-emerald-50 transition-colors flex items-center gap-3 border-b border-gray-100 last:border-0"
                >
                  <div
                    className="w-3 h-3 rounded-full flex-shrink-0"
                    style={{ backgroundColor: getCropColor(match.crop_type) }}
                  />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-900 truncate">{match.variety_name}</p>
                    <p className="text-xs text-gray-400 truncate">
                      {match.crop_type}{match.supplier ? ` \u00b7 ${match.supplier}` : ''}
                    </p>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Crop type */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Crop type</label>
          <input
            type="text"
            list="crop-types"
            value={cropType}
            onChange={e => setCropType(e.target.value)}
            placeholder="e.g. tomato"
            className="w-full min-h-[44px] px-3 py-2 text-sm border border-gray-200 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500"
          />
          <datalist id="crop-types">
            {CROP_TYPES.map(ct => (
              <option key={ct} value={ct} />
            ))}
          </datalist>
        </div>

        {/* Source / supplier */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Source / supplier</label>
          <input
            type="text"
            value={source}
            onChange={e => setSource(e.target.value)}
            placeholder="e.g. Johnny's Seeds"
            className="w-full min-h-[44px] px-3 py-2 text-sm border border-gray-200 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500"
          />
        </div>

        {/* Notes */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Notes</label>
          <textarea
            rows={3}
            value={notes}
            onChange={e => setNotes(e.target.value)}
            placeholder="Any notes about this seed..."
            className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500 resize-y"
          />
        </div>

        {/* Actions */}
        <div className="flex items-center gap-3 pt-2">
          <button
            type="submit"
            disabled={saving}
            className="min-h-[44px] px-6 py-2 text-sm font-medium text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg transition-colors disabled:opacity-50"
          >
            {saving ? 'Saving...' : 'Save'}
          </button>

          {isEdit && (
            <>
              {confirmDelete ? (
                <span className="flex items-center gap-2 text-sm">
                  <span className="text-red-600 font-medium">Sure?</span>
                  <button
                    type="button"
                    onClick={handleDelete}
                    disabled={deleting}
                    className="min-h-[44px] px-3 py-2 text-sm font-medium text-red-600 hover:text-red-700 transition-colors disabled:opacity-50"
                  >
                    {deleting ? 'Deleting...' : 'Delete'}
                  </button>
                  <button
                    type="button"
                    onClick={() => setConfirmDelete(false)}
                    className="min-h-[44px] px-3 py-2 text-sm text-gray-500 hover:text-gray-700 transition-colors"
                  >
                    Cancel
                  </button>
                </span>
              ) : (
                <button
                  type="button"
                  onClick={handleDelete}
                  className="min-h-[44px] px-3 py-2 text-sm font-medium text-red-500 hover:text-red-700 transition-colors flex items-center gap-1"
                >
                  <Trash2 size={14} />
                  Delete
                </button>
              )}
            </>
          )}
        </div>
      </form>

      {/* Related plants (edit mode only) */}
      {isEdit && relatedPlants.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
          <h2 className="text-sm font-semibold text-gray-700 flex items-center gap-2">
            <Sprout size={14} /> Related Plants ({relatedPlants.length})
          </h2>
          <div className="space-y-2">
            {relatedPlants.map(plant => (
              <Link
                key={plant.id}
                to={`/plants/${plant.id}`}
                className="flex items-center gap-3 p-2 rounded-lg hover:bg-gray-50 transition-colors min-h-[44px]"
              >
                <div
                  className="w-3 h-3 rounded-full flex-shrink-0"
                  style={{ backgroundColor: getCropColor(plant.crop_type) }}
                />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 truncate">{plant.variety_name}</p>
                  <p className="text-xs text-gray-400 capitalize">{plant.lifecycle_stage?.replace(/_/g, ' ')}</p>
                </div>
              </Link>
            ))}
          </div>
        </div>
      )}
    </div>
    </PageTransition>
  )
}
