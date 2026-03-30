import { useState, useRef, useCallback, useEffect } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Plus, ZoomIn, ZoomOut, Trash2, ExternalLink, Loader2 } from 'lucide-react'
import { beds as bedsApi, type Bed } from '../lib/api'
import { useApi } from '../hooks/useApi'
import { getCropColor } from '../lib/crops'
import { toast } from '../lib/toast'
import { PageTransition } from '../components/PageTransition'

const PRESET_COLORS = [
  '#8B5E3C', '#6B8E23', '#2E8B57', '#4682B4',
  '#9370DB', '#CD853F', '#708090', '#B22222',
]

const MIN_ZOOM = 0.5
const MAX_ZOOM = 3
const ZOOM_STEP = 0.25

export function GardenDesigner() {
  const { data: bedList, loading, refetch } = useApi(() => bedsApi.list(), [])
  const allBeds = bedList ?? []

  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [zoom, setZoom] = useState(1)
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const [isPanning, setIsPanning] = useState(false)
  const [panStart, setPanStart] = useState({ x: 0, y: 0 })
  const [dragBed, setDragBed] = useState<{ id: number; startX: number; startY: number; origX: number; origY: number } | null>(null)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [showAddForm, setShowAddForm] = useState(false)
  const [newBedName, setNewBedName] = useState('')

  const svgRef = useRef<SVGSVGElement>(null)
  const navigate = useNavigate()

  const selected = allBeds.find(b => b.id === selectedId) ?? null

  // Fit to content on mount
  useEffect(() => {
    if (!allBeds.length) return
    const svg = svgRef.current
    if (!svg) return

    const rect = svg.getBoundingClientRect()
    const padding = 60

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const b of allBeds) {
      if (b.canvas_points && b.canvas_points.length > 2) {
        for (const [px, py] of b.canvas_points) {
          minX = Math.min(minX, px)
          minY = Math.min(minY, py)
          maxX = Math.max(maxX, px)
          maxY = Math.max(maxY, py)
        }
      } else {
        minX = Math.min(minX, b.canvas_x)
        minY = Math.min(minY, b.canvas_y)
        maxX = Math.max(maxX, b.canvas_x + b.canvas_width)
        maxY = Math.max(maxY, b.canvas_y + b.canvas_height)
      }
    }

    const contentW = maxX - minX
    const contentH = maxY - minY
    if (contentW <= 0 || contentH <= 0) return

    const scaleX = (rect.width - padding * 2) / contentW
    const scaleY = (rect.height - padding * 2) / contentH
    const fitZoom = Math.min(Math.max(Math.min(scaleX, scaleY), MIN_ZOOM), MAX_ZOOM)

    const cx = minX + contentW / 2
    const cy = minY + contentH / 2
    const fitPanX = rect.width / 2 - cx * fitZoom
    const fitPanY = rect.height / 2 - cy * fitZoom

    setZoom(fitZoom)
    setPan({ x: fitPanX, y: fitPanY })
    // Only run on initial data load
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading])

  // ── Zoom ──
  const zoomIn = () => setZoom(z => Math.min(z + ZOOM_STEP, MAX_ZOOM))
  const zoomOut = () => setZoom(z => Math.max(z - ZOOM_STEP, MIN_ZOOM))

  // ── Pan handlers ──
  const handlePointerDown = useCallback((e: React.PointerEvent<SVGSVGElement>) => {
    // Only start panning from empty space (target is the SVG itself or the background rect)
    const target = e.target as SVGElement
    if (target.dataset.bedId || target.closest('[data-bed-id]')) return

    setIsPanning(true)
    setPanStart({ x: e.clientX - pan.x, y: e.clientY - pan.y })
    setSelectedId(null)
    setConfirmDelete(false)
    ;(e.currentTarget as SVGSVGElement).setPointerCapture(e.pointerId)
  }, [pan])

  // ── Bed drag start ──
  const handleBedPointerDown = useCallback((e: React.PointerEvent, bed: Bed) => {
    e.stopPropagation()
    setSelectedId(bed.id)
    setConfirmDelete(false)
    setDragBed({
      id: bed.id,
      startX: e.clientX,
      startY: e.clientY,
      origX: bed.canvas_x,
      origY: bed.canvas_y,
    })
    svgRef.current?.setPointerCapture(e.pointerId)
  }, [])

  // ── Wheel zoom ──
  const handleWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault()
    const delta = e.deltaY > 0 ? -ZOOM_STEP : ZOOM_STEP
    setZoom(z => Math.min(Math.max(z + delta, MIN_ZOOM), MAX_ZOOM))
  }, [])

  // ── Add bed ──
  const addBed = async () => {
    if (!newBedName.trim()) return
    try {
      await bedsApi.create({
        name: newBedName.trim(),
        canvas_x: 100,
        canvas_y: 100,
        canvas_width: 200,
        canvas_height: 120,
        canvas_color: PRESET_COLORS[Math.floor(Math.random() * PRESET_COLORS.length)],
      })
      toast.success('Bed created')
      setNewBedName('')
      setShowAddForm(false)
      refetch()
    } catch {
      toast.error('Failed to create bed')
    }
  }

  // ── Update bed field ──
  const updateField = async (field: string, value: string | number) => {
    if (!selected) return
    try {
      await bedsApi.update(selected.id, { [field]: value })
      toast.success('Bed updated')
      refetch()
    } catch {
      toast.error('Failed to update bed')
    }
  }

  // ── Delete bed ──
  const deleteBed = async () => {
    if (!selected) return
    try {
      await bedsApi.remove(selected.id)
      toast.success('Bed deleted')
      setSelectedId(null)
      setConfirmDelete(false)
      refetch()
    } catch {
      toast.error('Failed to delete bed')
    }
  }

  // Ref for current drag delta (visual feedback during drag)

  const dragDelta = useRef({ dx: 0, dy: 0 })

  const handlePointerMoveWrapped = useCallback((e: React.PointerEvent) => {
    if (isPanning) {
      setPan({ x: e.clientX - panStart.x, y: e.clientY - panStart.y })
    }
    if (dragBed) {
      dragDelta.current = {
        dx: (e.clientX - dragBed.startX) / zoom,
        dy: (e.clientY - dragBed.startY) / zoom,
      }
      // Force re-render for visual drag feedback
      setDragBed(prev => prev ? { ...prev } : null)
    }
  }, [isPanning, panStart, dragBed, zoom])

  const handlePointerUpWrapped = useCallback((e: React.PointerEvent) => {
    if (isPanning) {
      setIsPanning(false)
    }
    if (dragBed) {
      const dx = (e.clientX - dragBed.startX) / zoom
      const dy = (e.clientY - dragBed.startY) / zoom
      const newX = Math.round(dragBed.origX + dx)
      const newY = Math.round(dragBed.origY + dy)

      if (Math.abs(dx) > 2 || Math.abs(dy) > 2) {
        bedsApi.updatePosition(dragBed.id, { canvas_x: newX, canvas_y: newY })
          .then(() => { toast.success('Bed moved'); refetch() })
          .catch(() => toast.error('Failed to move bed'))
      }
      dragDelta.current = { dx: 0, dy: 0 }
      setDragBed(null)
    }
  }, [isPanning, dragBed, zoom, refetch])

  // ── Render bed shape ──
  const renderBed = (bed: Bed) => {
    const isSelected = bed.id === selectedId
    const isDragging = dragBed?.id === bed.id
    const offsetX = isDragging ? dragDelta.current.dx : 0
    const offsetY = isDragging ? dragDelta.current.dy : 0
    const color = bed.canvas_color || '#6B8E23'

    const isPolygon = bed.canvas_points && bed.canvas_points.length > 2

    // Compute bounding box for text placement
    let cx: number, cy: number, bw: number, bh: number
    if (isPolygon) {
      const xs = bed.canvas_points!.map(p => p[0])
      const ys = bed.canvas_points!.map(p => p[1])
      const minX = Math.min(...xs), maxX = Math.max(...xs)
      const minY = Math.min(...ys), maxY = Math.max(...ys)
      cx = (minX + maxX) / 2
      cy = (minY + maxY) / 2
      bw = maxX - minX
      bh = maxY - minY
    } else {
      cx = bed.canvas_x + bed.canvas_width / 2
      cy = bed.canvas_y + bed.canvas_height / 2
      bw = bed.canvas_width
      bh = bed.canvas_height
    }

    return (
      <g
        key={bed.id}
        data-bed-id={bed.id}
        style={{ transform: `translate(${offsetX}px, ${offsetY}px)`, cursor: 'grab' }}
        onPointerDown={(e) => handleBedPointerDown(e, bed)}
      >
        {isPolygon ? (
          <polygon
            points={bed.canvas_points!.map(p => p.join(',')).join(' ')}
            fill={color}
            fillOpacity={0.2}
            stroke={color}
            strokeWidth={isSelected ? 3 : 1.5}
            strokeDasharray={isSelected ? '6 3' : 'none'}
          />
        ) : (
          <rect
            x={bed.canvas_x}
            y={bed.canvas_y}
            width={bed.canvas_width || 200}
            height={bed.canvas_height || 120}
            rx={4}
            fill={color}
            fillOpacity={0.2}
            stroke={color}
            strokeWidth={isSelected ? 3 : 1.5}
            strokeDasharray={isSelected ? '6 3' : 'none'}
          />
        )}
        {/* Bed name */}
        <text
          x={cx}
          y={cy}
          textAnchor="middle"
          dominantBaseline="central"
          fill={color}
          fontWeight={600}
          fontSize={14}
          style={{ pointerEvents: 'none', userSelect: 'none' }}
        >
          {bed.name}
        </text>

        {/* Plant dots — always visible, more subtle on non-selected beds */}
        {bed.plants && bed.plants.length > 0 && (
          <>
            {bed.plants.map((plant, i) => {
              const cellW = bw / (bed.grid_cols || 1)
              const cellH = bh / (bed.grid_rows || 1)
              const baseX = isPolygon
                ? (Math.min(...bed.canvas_points!.map(p => p[0])))
                : bed.canvas_x
              const baseY = isPolygon
                ? (Math.min(...bed.canvas_points!.map(p => p[1])))
                : bed.canvas_y
              const dotX = baseX + (plant.grid_x + 0.5) * cellW
              const dotY = baseY + (plant.grid_y + 0.5) * cellH
              const dotColor = getCropColor(plant.crop_type)

              return (
                <circle
                  key={plant.id || i}
                  cx={dotX}
                  cy={dotY}
                  r={Math.min(cellW, cellH) * 0.3}
                  fill={dotColor}
                  fillOpacity={isSelected ? 0.9 : 0.5}
                  stroke="#fff"
                  strokeWidth={isSelected ? 1 : 0.5}
                  style={{ pointerEvents: 'none' }}
                />
              )
            })}
          </>
        )}
      </g>
    )
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-96">
        <Loader2 className="w-6 h-6 animate-spin text-[var(--green-600)]" />
      </div>
    )
  }

  // ── Empty state ──
  if (!allBeds.length) {
    return (
      <div className="flex flex-col items-center justify-center h-96 gap-4">
        <p className="text-gray-500">No beds in your garden yet.</p>
        {showAddForm ? (
          <div className="flex items-center gap-2">
            <input
              autoFocus
              value={newBedName}
              onChange={e => setNewBedName(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') addBed(); if (e.key === 'Escape') setShowAddForm(false) }}
              placeholder="Bed name"
              className="px-3 py-2 text-sm border border-gray-300 rounded-lg outline-none focus:border-[var(--green-500)] min-h-[44px]"
            />
            <button onClick={addBed} className="px-4 py-2 bg-[var(--green-600)] text-white rounded-lg hover:bg-[var(--green-700)] text-sm font-medium min-h-[44px]">Add</button>
            <button onClick={() => setShowAddForm(false)} className="px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-lg text-sm min-h-[44px]">Cancel</button>
          </div>
        ) : (
          <button
            onClick={() => setShowAddForm(true)}
            className="flex items-center gap-2 px-4 py-2 bg-[var(--green-600)] text-white rounded-lg hover:bg-[var(--green-700)] min-h-[44px]"
          >
            <Plus className="w-5 h-5" />
            Add your first bed
          </button>
        )}
      </div>
    )
  }

  return (
    <PageTransition>
    <div className="flex flex-col h-full">
      {/* ── Toolbar ── */}
      <div className="flex items-center gap-2 px-3 py-2 border-b border-gray-200 bg-white shrink-0 flex-wrap">
        {showAddForm ? (
          <div className="flex items-center gap-2">
            <input
              autoFocus
              value={newBedName}
              onChange={e => setNewBedName(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') addBed(); if (e.key === 'Escape') setShowAddForm(false) }}
              placeholder="Bed name"
              className="px-3 py-2 text-sm border border-gray-300 rounded-lg outline-none focus:border-[var(--green-500)] min-h-[44px]"
            />
            <button onClick={addBed} className="px-4 py-2 bg-[var(--green-600)] text-white rounded-lg hover:bg-[var(--green-700)] text-sm font-medium min-h-[44px]">Add</button>
            <button onClick={() => setShowAddForm(false)} className="px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-lg text-sm min-h-[44px]">Cancel</button>
          </div>
        ) : (
          <button
            onClick={() => setShowAddForm(true)}
            className="flex items-center gap-1.5 px-3 py-2 bg-[var(--green-600)] text-white rounded-lg hover:bg-[var(--green-700)] text-sm font-medium min-h-[44px]"
          >
            <Plus className="w-4 h-4" />
            Add Bed
          </button>
        )}

        <div className="flex items-center gap-1 ml-auto">
          <button
            onClick={zoomOut}
            disabled={zoom <= MIN_ZOOM}
            className="p-2 rounded-lg hover:bg-gray-100 disabled:opacity-30 min-w-[44px] min-h-[44px] flex items-center justify-center"
          >
            <ZoomOut className="w-4 h-4" />
          </button>
          <span className="text-xs text-gray-500 w-12 text-center tabular-nums">
            {Math.round(zoom * 100)}%
          </span>
          <button
            onClick={zoomIn}
            disabled={zoom >= MAX_ZOOM}
            className="p-2 rounded-lg hover:bg-gray-100 disabled:opacity-30 min-w-[44px] min-h-[44px] flex items-center justify-center"
          >
            <ZoomIn className="w-4 h-4" />
          </button>
        </div>

        <Link
          to="/plan"
          className="flex items-center gap-1 px-3 py-2 text-sm text-[var(--green-700)] hover:bg-[var(--green-50)] rounded-lg min-h-[44px]"
        >
          Plan view
          <ExternalLink className="w-3.5 h-3.5" />
        </Link>
      </div>

      {/* ── Canvas + Panel layout ── */}
      <div className="flex flex-col lg:flex-row flex-1 min-h-0">
        {/* ── SVG Canvas ── */}
        <svg
          ref={svgRef}
          className="flex-1 bg-[var(--green-50)] cursor-grab active:cursor-grabbing select-none"
          style={{ minHeight: 400, touchAction: 'none' }}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMoveWrapped}
          onPointerUp={handlePointerUpWrapped}
          onWheel={handleWheel}
        >
          {/* Grid pattern */}
          <defs>
            <pattern id="grid" width={50 * zoom} height={50 * zoom} patternUnits="userSpaceOnUse">
              <path
                d={`M ${50 * zoom} 0 L 0 0 0 ${50 * zoom}`}
                fill="none"
                stroke="var(--green-200)"
                strokeWidth={0.5}
              />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#grid)" />

          {/* Transformed content */}
          <g transform={`translate(${pan.x}, ${pan.y}) scale(${zoom})`}>
            {allBeds.map(renderBed)}
          </g>
        </svg>

        {/* ── Properties Panel ── */}
        {selected && (
          <div className="w-full lg:w-72 border-t lg:border-t-0 lg:border-l border-gray-200 bg-white p-4 overflow-y-auto shrink-0">
            <h3 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
              Bed Properties
            </h3>

            {/* Name */}
            <label className="block mb-3">
              <span className="text-xs text-gray-500">Name</span>
              <input
                type="text"
                defaultValue={selected.name}
                key={selected.id + '-name'}
                onBlur={(e) => {
                  const v = e.target.value.trim()
                  if (v && v !== selected.name) updateField('name', v)
                }}
                className="mt-1 w-full px-2 py-1.5 border border-gray-300 rounded-md text-sm focus:ring-1 focus:ring-[var(--green-500)] focus:border-[var(--green-500)] min-h-[44px]"
              />
            </label>

            {/* Dimensions */}
            <div className="grid grid-cols-2 gap-2 mb-3">
              <label className="block">
                <span className="text-xs text-gray-500">Width</span>
                <input
                  type="number"
                  defaultValue={selected.canvas_width}
                  key={selected.id + '-w'}
                  onBlur={(e) => {
                    const v = parseInt(e.target.value)
                    if (v > 0 && v !== selected.canvas_width) updateField('canvas_width', v)
                  }}
                  className="mt-1 w-full px-2 py-1.5 border border-gray-300 rounded-md text-sm focus:ring-1 focus:ring-[var(--green-500)] focus:border-[var(--green-500)] min-h-[44px]"
                />
              </label>
              <label className="block">
                <span className="text-xs text-gray-500">Height</span>
                <input
                  type="number"
                  defaultValue={selected.canvas_height}
                  key={selected.id + '-h'}
                  onBlur={(e) => {
                    const v = parseInt(e.target.value)
                    if (v > 0 && v !== selected.canvas_height) updateField('canvas_height', v)
                  }}
                  className="mt-1 w-full px-2 py-1.5 border border-gray-300 rounded-md text-sm focus:ring-1 focus:ring-[var(--green-500)] focus:border-[var(--green-500)] min-h-[44px]"
                />
              </label>
            </div>

            {/* Color swatches */}
            <div className="mb-3">
              <span className="text-xs text-gray-500 block mb-1">Color</span>
              <div className="flex flex-wrap gap-2">
                {PRESET_COLORS.map(c => (
                  <button
                    key={c}
                    onClick={() => updateField('canvas_color', c)}
                    className="w-7 h-7 rounded-full border-2 min-w-[44px] min-h-[44px] flex items-center justify-center"
                    style={{
                      backgroundColor: c,
                      borderColor: selected.canvas_color === c ? '#1f2937' : 'transparent',
                    }}
                    title={c}
                  />
                ))}
              </div>
            </div>

            {/* Plant count */}
            <p className="text-sm text-gray-600 mb-4">
              {selected.plants?.length ?? 0} plant{(selected.plants?.length ?? 0) !== 1 ? 's' : ''}
            </p>

            {/* Actions */}
            <div className="flex flex-col gap-2">
              <button
                onClick={() => navigate(`/plan?bed=${selected.id}`)}
                className="flex items-center justify-center gap-1.5 px-3 py-2 bg-[var(--green-50)] text-[var(--green-700)] rounded-lg hover:bg-[var(--green-100)] text-sm font-medium min-h-[44px]"
              >
                <ExternalLink className="w-4 h-4" />
                Open bed editor
              </button>

              {!confirmDelete ? (
                <button
                  onClick={() => setConfirmDelete(true)}
                  className="flex items-center justify-center gap-1.5 px-3 py-2 text-red-600 hover:bg-red-50 rounded-lg text-sm min-h-[44px]"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete bed
                </button>
              ) : (
                <div className="flex gap-2">
                  <button
                    onClick={deleteBed}
                    className="flex-1 px-3 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 text-sm font-medium min-h-[44px]"
                  >
                    Confirm delete
                  </button>
                  <button
                    onClick={() => setConfirmDelete(false)}
                    className="px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-lg text-sm min-h-[44px]"
                  >
                    Cancel
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
    </PageTransition>
  )
}
