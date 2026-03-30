import { useRef, useState, useCallback, useEffect } from 'react'
import type { Bed, BedPlant, Seed } from '../../lib/api'
import { getCropColor, getCropSpacing } from '../../lib/crops'
import PlantRect, { SELECTED_FILTER_ID } from './PlantRect'

export interface BedCanvasProps {
  bed: Bed
  selectedPlantId: number | null
  onSelectPlant: (id: number | null) => void
  onMovePlant: (id: number, gridX: number, gridY: number) => void
  placingSeed: Seed | null
  onPlaceSeed: (gridX: number, gridY: number) => void
}

const CELL = 5

export default function BedCanvas({
  bed,
  selectedPlantId,
  onSelectPlant,
  onMovePlant,
  placingSeed,
  onPlaceSeed,
}: BedCanvasProps) {
  const svgRef = useRef<SVGSVGElement>(null)

  // Drop target state (updated via custom events from PlantRect)
  const [dropTarget, setDropTarget] = useState<{
    x: number
    y: number
    w: number
    h: number
    colliding: boolean
  } | null>(null)

  // Ghost preview state for click-to-place mode
  const [ghost, setGhost] = useState<{ x: number; y: number } | null>(null)

  const cols = bed.grid_cols || 10
  const rows = bed.grid_rows || 10
  const w = cols * CELL
  const h = rows * CELL
  const color = bed.canvas_color || '#e8e4df'

  /** Convert event to SVG grid coords */
  const eventToGrid = useCallback(
    (e: React.MouseEvent | MouseEvent) => {
      const svg = svgRef.current
      if (!svg) return { x: 0, y: 0 }
      const pt = svg.createSVGPoint()
      pt.x = e.clientX
      pt.y = e.clientY
      const ctm = svg.getScreenCTM()
      if (!ctm) return { x: 0, y: 0 }
      const svgPt = pt.matrixTransform(ctm.inverse())
      return {
        x: Math.max(0, Math.min(cols - 1, Math.floor(svgPt.x / CELL))),
        y: Math.max(0, Math.min(rows - 1, Math.floor(svgPt.y / CELL))),
      }
    },
    [cols, rows],
  )

  /** Check collision between a proposed rect and existing plants */
  const checkCollision = useCallback(
    (
      plantId: number,
      gx: number,
      gy: number,
      gw: number,
      gh: number,
    ): boolean => {
      return bed.plants.some((other: BedPlant) => {
        if (other.id === plantId) return false
        const ox = other.grid_x || 0
        const oy = other.grid_y || 0
        const ow = other.grid_w || 1
        const oh = other.grid_h || 1
        return gx < ox + ow && gx + gw > ox && gy < oy + oh && gy + gh > oy
      })
    },
    [bed.plants],
  )

  // Listen for custom drag events from PlantRect
  useEffect(() => {
    const svg = svgRef.current
    if (!svg) return

    const onDragMove = (e: Event) => {
      const { plantId, gridX, gridY, gridW, gridH } = (e as CustomEvent).detail
      const maxX = cols - gridW
      const maxY = rows - gridH
      const clampedX = Math.max(0, Math.min(maxX, gridX))
      const clampedY = Math.max(0, Math.min(maxY, gridY))
      const colliding = checkCollision(plantId, clampedX, clampedY, gridW, gridH)
      setDropTarget({
        x: clampedX * CELL,
        y: clampedY * CELL,
        w: gridW * CELL,
        h: gridH * CELL,
        colliding,
      })
    }

    const onDragEnd = () => {
      setDropTarget(null)
    }

    svg.addEventListener('plantdragmove', onDragMove)
    svg.addEventListener('plantdragend', onDragEnd)
    return () => {
      svg.removeEventListener('plantdragmove', onDragMove)
      svg.removeEventListener('plantdragend', onDragEnd)
    }
  }, [cols, rows, checkCollision])

  /** Handle mouse move for ghost preview in place mode */
  const onMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (!placingSeed) {
        if (ghost) setGhost(null)
        return
      }
      const grid = eventToGrid(e)
      setGhost(grid)
    },
    [placingSeed, ghost, eventToGrid],
  )

  /** Handle click on SVG background */
  const onSvgClick = useCallback(
    (e: React.MouseEvent) => {
      if (placingSeed) {
        const grid = eventToGrid(e)
        onPlaceSeed(grid.x, grid.y)
      } else {
        onSelectPlant(null)
      }
    },
    [placingSeed, eventToGrid, onPlaceSeed, onSelectPlant],
  )

  /** Handle plant drag end with grid clamping */
  const handlePlantDragEnd = useCallback(
    (plantId: number, plant: BedPlant) =>
      (newGridX: number, newGridY: number) => {
        const maxX = cols - (plant.grid_w || 1)
        const maxY = rows - (plant.grid_h || 1)
        const clampedX = Math.max(0, Math.min(maxX, newGridX))
        const clampedY = Math.max(0, Math.min(maxY, newGridY))
        onMovePlant(plantId, clampedX, clampedY)
      },
    [cols, rows, onMovePlant],
  )

  // Build bed outline
  let outlineEl: React.ReactNode
  if (bed.canvas_points && bed.canvas_points.length > 2) {
    const xs = bed.canvas_points.map((p) => p[0])
    const ys = bed.canvas_points.map((p) => p[1])
    const minX = Math.min(...xs)
    const minY = Math.min(...ys)
    const maxX = Math.max(...xs)
    const maxY = Math.max(...ys)
    const polyW = maxX - minX
    const polyH = maxY - minY
    const scaleX = w / polyW
    const scaleY = h / polyH
    const pts = bed.canvas_points
      .map((p) => `${(p[0] - minX) * scaleX},${(p[1] - minY) * scaleY}`)
      .join(' ')
    outlineEl = (
      <polygon
        points={pts}
        fill={color}
        fillOpacity={0.12}
        stroke={color}
        strokeWidth={1.5}
      />
    )
  } else {
    outlineEl = (
      <rect
        x={0}
        y={0}
        width={w}
        height={h}
        rx={6}
        fill={color}
        fillOpacity={0.12}
        stroke={color}
        strokeWidth={1.5}
      />
    )
  }

  let clipId: string | undefined
  let clipDef: React.ReactNode = null
  if (bed.canvas_points && bed.canvas_points.length > 2) {
    clipId = `bed-clip-${bed.id}`
    const xs = bed.canvas_points.map((p) => p[0])
    const ys = bed.canvas_points.map((p) => p[1])
    const minX = Math.min(...xs)
    const minY = Math.min(...ys)
    const polyW = Math.max(...xs) - minX
    const polyH = Math.max(...ys) - minY
    const scaleX = w / polyW
    const scaleY = h / polyH
    const clipPts = bed.canvas_points
      .map((p) => `${(p[0] - minX) * scaleX},${(p[1] - minY) * scaleY}`)
      .join(' ')
    clipDef = (
      <defs>
        <clipPath id={clipId}>
          <polygon points={clipPts} />
        </clipPath>
      </defs>
    )
  }

  // Front edge indicator
  const frontLabel = (
    <text
      x={w / 2}
      y={3}
      textAnchor="middle"
      dominantBaseline="hanging"
      fontSize={Math.min(6, w * 0.05)}
      fill="rgba(0,0,0,0.15)"
      fontWeight={600}
      style={{ pointerEvents: 'none', userSelect: 'none', letterSpacing: '1px' }}
    >
      front
    </text>
  )

  // Build grid lines (every 2 cells = 10cm)
  const gridLines: React.ReactNode[] = []
  const gridStep = 2
  for (let i = gridStep; i < cols; i += gridStep) {
    gridLines.push(
      <line
        key={`v${i}`}
        x1={i * CELL}
        y1={0}
        x2={i * CELL}
        y2={h}
        stroke="rgba(0,0,0,0.05)"
        strokeWidth={0.3}
      />,
    )
  }
  for (let i = gridStep; i < rows; i += gridStep) {
    gridLines.push(
      <line
        key={`h${i}`}
        x1={0}
        y1={i * CELL}
        x2={w}
        y2={i * CELL}
        stroke="rgba(0,0,0,0.05)"
        strokeWidth={0.3}
      />,
    )
  }

  // Ghost preview for placing seed
  let ghostEl: React.ReactNode = null
  if (placingSeed && ghost) {
    const [gw, gh] = getCropSpacing(placingSeed.crop_type)
    const ghostColor = getCropColor(placingSeed.crop_type)
    const gx = Math.max(0, Math.min(ghost.x, cols - gw))
    const gy = Math.max(0, Math.min(ghost.y, rows - gh))
    ghostEl = (
      <rect
        x={gx * CELL}
        y={gy * CELL}
        width={gw * CELL}
        height={gh * CELL}
        fill={ghostColor}
        fillOpacity={0.15}
        stroke={ghostColor}
        strokeWidth={1}
        strokeDasharray="3,2"
        rx={2}
        style={{ pointerEvents: 'none' }}
      />
    )
  }

  return (
    <svg
      ref={svgRef}
      xmlns="http://www.w3.org/2000/svg"
      viewBox={`0 0 ${w} ${h}`}
      preserveAspectRatio="xMidYMid meet"
      width="100%"
      height="100%"
      style={{
        display: 'block',
        cursor: placingSeed ? 'crosshair' : 'default',
      }}
      onMouseMove={onMouseMove}
      onMouseLeave={() => setGhost(null)}
      onClick={onSvgClick}
    >
      {/* SVG filter for selected plant glow */}
      <defs>
        <filter id={SELECTED_FILTER_ID} x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx={0} dy={0} stdDeviation={1.5} floodColor="#000" floodOpacity={0.25} />
        </filter>
      </defs>

      {/* Polygon clip path for non-rectangular beds */}
      {clipDef}

      {/* Bed outline */}
      {outlineEl}

      {/* Front edge label */}
      {frontLabel}

      {/* Grid lines, drop target, and plants clipped to bed shape */}
      <g clipPath={clipId ? `url(#${clipId})` : undefined}>
        {/* Grid lines */}
        {gridLines}

        {/* Drop target during drag */}
        {dropTarget && (
          <rect
            x={dropTarget.x}
            y={dropTarget.y}
            width={dropTarget.w}
            height={dropTarget.h}
            rx={3}
            fill={dropTarget.colliding ? 'rgba(239,68,68,0.1)' : 'none'}
            stroke={dropTarget.colliding ? '#ef4444' : '#365314'}
            strokeWidth={1.5}
            strokeDasharray="3,2"
            opacity={0.5}
            style={{ pointerEvents: 'none' }}
          />
        )}

        {/* Plant rects */}
        {bed.plants.map((plant) => (
          <PlantRect
            key={plant.id}
            plant={plant}
            cell={CELL}
            selected={selectedPlantId === plant.id}
            onSelect={() => onSelectPlant(selectedPlantId === plant.id ? null : plant.id)}
            onDragEnd={handlePlantDragEnd(plant.id, plant)}
          />
        ))}

        {/* Ghost preview for click-to-place */}
        {ghostEl}
      </g>
    </svg>
  )
}
