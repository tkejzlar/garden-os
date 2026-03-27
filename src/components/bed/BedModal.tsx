import { useRef, useEffect, useState, useCallback } from 'react'
import type { Bed, BedPlant, Seed } from '../../lib/api'
import { beds, seeds as seedsApi, plants } from '../../lib/api'
import { getCropSpacing } from '../../lib/crops'
import { toast } from '../../lib/toast'
import BedCanvas from './BedCanvas'
import { BedSidebar } from './BedSidebar'
import { X, Shuffle, Loader2 } from 'lucide-react'
import { useUndoStore } from '../../lib/undo'
import { ShareBedButton } from '../ShareBed'

interface BedModalProps {
  bedId: number | null
  onClose: () => void
  onOpenAI?: (bedName: string) => void
}

export function BedModal({ bedId, onClose: onClose_prop, onOpenAI }: BedModalProps) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const [bed, setBed] = useState<Bed | null>(null)
  const [seedList, setSeedList] = useState<Seed[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [selectedPlantId, setSelectedPlantId] = useState<number | null>(null)
  const [placingSeed, setPlacingSeed] = useState<Seed | null>(null)

  const refreshBed = useCallback(async () => {
    if (!bedId) return
    const found = await beds.get(bedId)
    if (found) setBed(found)
  }, [bedId])

  // Fetch bed + seeds when bedId changes
  useEffect(() => {
    if (!bedId) {
      setBed(null)
      return
    }
    setLoading(true)
    setSelectedPlantId(null)
    setPlacingSeed(null)
    Promise.all([beds.get(bedId), seedsApi.list()])
      .then(([foundBed, allSeeds]) => {
        if (foundBed) setBed(foundBed)
        setSeedList(allSeeds)
      })
      .catch(err => toast.error(err.message))
      .finally(() => setLoading(false))
  }, [bedId])

  // Open/close dialog
  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return
    if (bedId) {
      if (!dialog.open) dialog.showModal()
    } else {
      if (dialog.open) dialog.close()
    }
  }, [bedId])

  // Backdrop click to close
  const onDialogClick = useCallback(
    (e: React.MouseEvent<HTMLDialogElement>) => {
      if (e.target === dialogRef.current) onClose_prop()
    },
    [onClose_prop],
  )

  // Intercept Escape key — cancel placing/search before closing
  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return

    const onCancel = (e: Event) => {
      if (placingSeed) {
        e.preventDefault()
        setPlacingSeed(null)
        return
      }
      // Otherwise let the dialog close naturally
    }

    const onClose = () => onClose_prop()

    dialog.addEventListener('cancel', onCancel)
    dialog.addEventListener('close', onClose)
    return () => {
      dialog.removeEventListener('cancel', onCancel)
      dialog.removeEventListener('close', onClose)
    }
  }, [onClose_prop, placingSeed])

  const selectedPlant = bed?.plants.find(p => p.id === selectedPlantId) || null

  // ── Mutations ──

  const withSave = useCallback(
    async (fn: () => Promise<void>) => {
      setSaving(true)
      try {
        await fn()
        await refreshBed()
      } catch (err: unknown) {
        toast.error(err instanceof Error ? err.message : 'Something went wrong')
      } finally {
        setSaving(false)
      }
    },
    [refreshBed],
  )

  const handleAddPlant = useCallback(
    async (seed: Seed) => {
      if (!bedId) return
      await withSave(async () => {
        const [gw, gh] = getCropSpacing(seed.crop_type)
        await plants.create({
          bed_id: bedId,
          variety_name: seed.variety_name,
          crop_type: seed.crop_type,
          source: seed.source || 'seed',
          lifecycle_stage: 'seed_packet',
          grid_x: 0,
          grid_y: 0,
          grid_w: gw,
          grid_h: gh,
          quantity: 1,
        })
        toast.success(`Added ${seed.variety_name}`)
      })
    },
    [bedId, withSave],
  )

  const handleAddRow = useCallback(
    async (seed: Seed, direction: 'h' | 'v') => {
      if (!bedId || !bed) return
      await withSave(async () => {
        const [gw, gh] = getCropSpacing(seed.crop_type)
        const cols = bed.grid_cols || 10
        const rows = bed.grid_rows || 10
        const plantW = direction === 'h' ? cols : gw
        const plantH = direction === 'v' ? rows : gh
        const qty = direction === 'h' ? Math.floor(cols / gw) : Math.floor(rows / gh)
        await plants.create({
          bed_id: bedId,
          variety_name: seed.variety_name,
          crop_type: seed.crop_type,
          source: seed.source || 'seed',
          lifecycle_stage: 'seed_packet',
          grid_x: 0,
          grid_y: 0,
          grid_w: plantW,
          grid_h: plantH,
          quantity: qty,
        })
        toast.success(`Added ${qty} ${seed.variety_name} in a ${direction === 'h' ? 'row' : 'column'}`)
      })
    },
    [bedId, bed, withSave],
  )

  const handleRemovePlant = useCallback(
    async (plantId: number) => {
      const plantData = bed?.plants.find(p => p.id === plantId)
      if (!plantData) return

      // Optimistically remove from local state
      setBed(prev => prev ? { ...prev, plants: prev.plants.filter(p => p.id !== plantId) } : prev)
      if (selectedPlantId === plantId) setSelectedPlantId(null)

      useUndoStore.getState().push(
        `Removed ${plantData.variety_name}`,
        async () => {
          // Undo — refresh to get the plant back (it wasn't actually deleted)
          await refreshBed()
        },
        async () => {
          // Actually delete on expiry
          try {
            await plants.remove(plantId)
          } catch {
            toast.error('Failed to remove plant')
            await refreshBed()
          }
        }
      )
    },
    [bed, selectedPlantId, refreshBed],
  )

  const handleDuplicatePlant = useCallback(
    async (plant: BedPlant) => {
      if (!bedId) return
      await withSave(async () => {
        const cols = bed?.grid_cols || 20
        const rows = bed?.grid_rows || 20
        const pw = plant.grid_w || 1
        const ph = plant.grid_h || 1
        let nx = (plant.grid_x || 0) + pw
        let ny = plant.grid_y || 0
        if (nx + pw > cols) { nx = 0; ny += ph }
        if (ny + ph > rows) { ny = 0 }
        await plants.create({
          bed_id: bedId,
          variety_name: plant.variety_name,
          crop_type: plant.crop_type,
          source: 'seed',
          lifecycle_stage: plant.lifecycle_stage,
          grid_x: nx,
          grid_y: ny,
          grid_w: pw,
          grid_h: ph,
          quantity: plant.quantity || 1,
        })
        toast.success(`Duplicated ${plant.variety_name}`)
      })
    },
    [bedId, withSave],
  )

  const handleMovePlant = useCallback(
    (plantId: number, gridX: number, gridY: number) => {
      withSave(async () => {
        await plants.update(plantId, { grid_x: gridX, grid_y: gridY })
      })
    },
    [withSave],
  )

  const handlePlaceSeed = useCallback(
    (gridX: number, gridY: number) => {
      if (!placingSeed || !bedId) return
      const seed = placingSeed
      setPlacingSeed(null)  // Cancel placing mode after placement
      const [gw, gh] = getCropSpacing(seed.crop_type)
      withSave(async () => {
        await plants.create({
          bed_id: bedId,
          variety_name: seed.variety_name,
          crop_type: seed.crop_type,
          source: seed.source || 'seed',
          lifecycle_stage: 'seed_packet',
          grid_x: gridX,
          grid_y: gridY,
          grid_w: gw,
          grid_h: gh,
          quantity: 1,
        })
        toast.success(`Placed ${seed.variety_name}`)
      })
    },
    [placingSeed, bedId, withSave],
  )

  const handleDistribute = useCallback(async () => {
    if (!bedId) return
    setSaving(true)
    try {
      const result = await beds.distribute(bedId)
      await refreshBed()
      toast.success(`Auto-arranged: ${result.moves} moves, ${result.empty_pct}% free space`)
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Auto-arrange failed')
    } finally {
      setSaving(false)
    }
  }, [bedId, refreshBed])

  return (
    <dialog
      ref={dialogRef}
      onClick={onDialogClick}
      className="backdrop:bg-black/50 bg-transparent p-0 m-0 fixed inset-0 w-full h-full max-w-none max-h-none"
    >
      <div className="flex items-center justify-center w-full h-full p-4 max-sm:p-0 max-sm:items-end">
        <div className="bg-white rounded-2xl max-sm:rounded-none max-sm:rounded-t-2xl shadow-2xl w-full max-w-5xl h-[min(85vh,800px)] max-sm:h-[95dvh] flex flex-col overflow-hidden">
          {loading ? (
            <div className="flex-1 flex items-center justify-center">
              <Loader2 className="w-8 h-8 text-[var(--green-700)] animate-spin" />
            </div>
          ) : bed ? (
            <div className="flex flex-1 min-h-0 max-sm:flex-col">
              {/* Left panel: header + canvas */}
              <div className="flex-1 flex flex-col min-w-0 max-sm:flex-none max-sm:h-[45vh]">
                {/* Header */}
                <div className="flex items-center gap-3 px-4 py-3 border-b border-gray-100">
                  <div className="flex-1 min-w-0">
                    <h2 className="text-lg font-bold text-gray-900 truncate">{bed.name}</h2>
                    <p className="text-xs text-gray-500">
                      {bed.width_cm} x {bed.length_cm} cm
                      {bed.plants.length > 0 && ` \u00b7 ${bed.plants.length} plant${bed.plants.length === 1 ? '' : 's'}`}
                    </p>
                  </div>
                  {saving && (
                    <span className="flex items-center gap-1.5 text-xs text-gray-400">
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      Saving
                    </span>
                  )}
                  <button
                    onClick={handleDistribute}
                    disabled={saving}
                    title="Auto-arrange plants on the grid"
                    className="px-3 py-2 text-xs font-medium text-gray-500 hover:text-[var(--color-primary)] hover:bg-green-50 rounded-lg transition-colors min-h-[44px] flex items-center gap-1.5 disabled:opacity-40"
                  >
                    <Shuffle className="w-4 h-4" />
                    <span className="hidden sm:inline">Arrange</span>
                  </button>
                  <ShareBedButton bed={bed} />
                  <button
                    onClick={onClose_prop}
                    title="Close"
                    className="p-2.5 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
                  >
                    <X className="w-5 h-5" />
                  </button>
                </div>

                {/* Canvas */}
                <div className="flex-1 p-4 overflow-hidden flex items-center justify-center">
                  <BedCanvas
                    bed={bed}
                    selectedPlantId={selectedPlantId}
                    onSelectPlant={setSelectedPlantId}
                    onMovePlant={handleMovePlant}
                    placingSeed={placingSeed}
                    onPlaceSeed={handlePlaceSeed}
                  />
                </div>
              </div>

              {/* Right panel: sidebar */}
              <BedSidebar
                bed={bed}
                seeds={seedList}
                selectedPlant={selectedPlant}
                onSelectPlant={setSelectedPlantId}
                onAddPlant={handleAddPlant}
                onAddRow={handleAddRow}
                onRemovePlant={handleRemovePlant}
                onDuplicatePlant={handleDuplicatePlant}
                onStartPlacing={setPlacingSeed}
                placingSeed={placingSeed}
                onCancelPlacing={() => setPlacingSeed(null)}
                onOpenAI={onOpenAI && bed ? () => { onClose_prop(); onOpenAI(bed.name) } : undefined}
              />
            </div>
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-gray-400 text-sm gap-4">
              <p>Bed not found</p>
              <button onClick={onClose_prop} className="btn-secondary text-xs">Close</button>
            </div>
          )}
        </div>
      </div>
    </dialog>
  )
}
