import { useRef, useCallback, memo } from 'react'
import type { BedPlant } from '../../lib/api'
import { getCropColor, getCropAbbr } from '../../lib/crops'

export interface PlantRectProps {
  plant: BedPlant
  cell: number // 5
  selected: boolean
  onSelect: () => void
  onDragEnd: (newGridX: number, newGridY: number) => void
}

/** SVG filter ID for selected plant glow */
export const SELECTED_FILTER_ID = 'plant-shadow'

/**
 * Renders a single plant as an SVG <g> with colored rect + abbreviation text.
 * Handles drag (mouse + touch) and click selection.
 */
const PlantRect = memo(function PlantRect({
  plant,
  cell,
  selected,
  onSelect,
  onDragEnd,
}: PlantRectProps) {
  const gRef = useRef<SVGGElement>(null)
  const dragState = useRef<{
    isDragging: boolean
    startClientX: number
    startClientY: number
    offsetDx: number
    offsetDy: number
    currentTx: number
    currentTy: number
    svg: SVGSVGElement | null
    hasMoved: boolean
  } | null>(null)

  const px = (plant.grid_x || 0) * cell
  const py = (plant.grid_y || 0) * cell
  const pw = (plant.grid_w || 1) * cell
  const ph = (plant.grid_h || 1) * cell
  const color = getCropColor(plant.crop_type)
  const abbr = getCropAbbr(plant.crop_type)

  const isRowCrop = ['radish', 'carrot', 'onion', 'spinach', 'lettuce', 'pea'].includes(
    plant.crop_type?.toLowerCase() || ''
  )
  const isBandPlant = isRowCrop && (pw <= 15 || ph <= 15)

  // Text sizing
  const abbrFs = Math.min(pw * 0.35, ph * 0.4, 14)
  const showVariety = pw >= 15 && ph >= 12
  const nameFs = showVariety ? Math.min(pw * 0.15, ph * 0.18, 8) : 0
  const maxChars = showVariety ? Math.floor(pw / (nameFs * 0.6)) : 0
  const displayName = showVariety
    ? plant.variety_name.length > maxChars
      ? plant.variety_name.slice(0, maxChars - 2) + '..'
      : plant.variety_name
    : ''

  /** Convert a mouse/touch event to SVG coordinates */
  const eventToSvg = useCallback(
    (e: MouseEvent | TouchEvent, svg: SVGSVGElement) => {
      const pt = svg.createSVGPoint()
      const src = 'touches' in e ? e.touches[0] ?? (e as TouchEvent).changedTouches[0] : e
      if (!src) return { x: 0, y: 0 }
      pt.x = src.clientX
      pt.y = src.clientY
      const ctm = svg.getScreenCTM()
      if (!ctm) return { x: pt.x, y: pt.y }
      const svgPt = pt.matrixTransform(ctm.inverse())
      return { x: svgPt.x, y: svgPt.y }
    },
    [],
  )

  const onMove = useCallback(
    (e: MouseEvent | TouchEvent) => {
      const ds = dragState.current
      if (!ds?.isDragging || !ds.svg) return

      const svgPt = eventToSvg(e, ds.svg)
      const newGridX = Math.floor((svgPt.x - ds.offsetDx) / cell)
      const newGridY = Math.floor((svgPt.y - ds.offsetDy) / cell)
      const tx = (newGridX - (plant.grid_x || 0)) * cell
      const ty = (newGridY - (plant.grid_y || 0)) * cell
      ds.currentTx = tx
      ds.currentTy = ty

      if (Math.abs(tx) > 1 || Math.abs(ty) > 1) {
        ds.hasMoved = true
      }

      const g = gRef.current
      if (g) {
        g.setAttribute('transform', `translate(${tx},${ty})`)
        g.style.opacity = '0.7'
      }

      // Dispatch a custom event so BedCanvas can update drop target
      const detail = {
        plantId: plant.id,
        gridX: newGridX,
        gridY: newGridY,
        gridW: plant.grid_w || 1,
        gridH: plant.grid_h || 1,
      }
      ds.svg.dispatchEvent(
        new CustomEvent('plantdragmove', { detail }),
      )
    },
    [cell, plant.grid_x, plant.grid_y, plant.grid_w, plant.grid_h, plant.id, eventToSvg],
  )

  const onEnd = useCallback(
    (e: MouseEvent | TouchEvent) => {
      const ds = dragState.current
      if (!ds?.isDragging) return

      // Clean up listeners
      document.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseup', onEnd)
      document.removeEventListener('touchmove', onMove)
      document.removeEventListener('touchend', onEnd)
      document.removeEventListener('touchcancel', onEnd)

      const g = gRef.current
      if (g) {
        g.removeAttribute('transform')
        g.style.opacity = '1'
        g.style.cursor = 'grab'
      }

      // Hide drop target
      if (ds.svg) {
        ds.svg.dispatchEvent(new CustomEvent('plantdragend'))
      }

      if (ds.hasMoved) {
        const svgPt = eventToSvg(e, ds.svg!)
        const newGridX = Math.floor((svgPt.x - ds.offsetDx) / cell)
        const newGridY = Math.floor((svgPt.y - ds.offsetDy) / cell)
        onDragEnd(newGridX, newGridY)
      }

      dragState.current = null
    },
    [cell, onMove, eventToSvg, onDragEnd],
  )

  const onStart = useCallback(
    (e: React.MouseEvent | React.TouchEvent) => {
      e.preventDefault()
      e.stopPropagation()

      const g = gRef.current
      const svg = g?.closest('svg') as SVGSVGElement | null
      if (!svg) return

      const nativeEvt = e.nativeEvent as MouseEvent | TouchEvent
      const svgPt = eventToSvg(nativeEvt, svg)

      dragState.current = {
        isDragging: true,
        startClientX: svgPt.x,
        startClientY: svgPt.y,
        offsetDx: svgPt.x - (plant.grid_x || 0) * cell,
        offsetDy: svgPt.y - (plant.grid_y || 0) * cell,
        currentTx: 0,
        currentTy: 0,
        svg,
        hasMoved: false,
      }

      if (g) g.style.cursor = 'grabbing'

      document.addEventListener('mousemove', onMove)
      document.addEventListener('mouseup', onEnd)
      document.addEventListener('touchmove', onMove, { passive: false })
      document.addEventListener('touchend', onEnd)
      document.addEventListener('touchcancel', onEnd)
    },
    [cell, plant.grid_x, plant.grid_y, eventToSvg, onMove, onEnd],
  )

  const onClick = useCallback(
    (e: React.MouseEvent) => {
      // If we just finished a drag, don't fire select
      if (dragState.current?.hasMoved) return
      e.stopPropagation()
      onSelect()
    },
    [onSelect],
  )

  return (
    <g
      ref={gRef}
      style={{ cursor: 'grab' }}
      onMouseDown={onStart}
      onTouchStart={onStart}
      onClick={onClick}
      data-plant-id={plant.id}
    >
      <rect
        x={px + 1}
        y={py + 1}
        width={pw - 2}
        height={ph - 2}
        rx={isBandPlant ? 1 : 2}
        fill={color}
        fillOpacity={isBandPlant ? 0.12 + (plant.id % 5) * 0.03 : 0.22}
        stroke={color}
        strokeWidth={selected ? 2 : (isBandPlant ? 0.5 : 1.2)}
        strokeDasharray={isBandPlant ? '2,1' : undefined}
        filter={selected ? `url(#${SELECTED_FILTER_ID})` : undefined}
      />
      <text
        x={px + pw / 2}
        y={py + ph / 2 - (showVariety ? abbrFs * 0.5 : 0)}
        textAnchor="middle"
        dominantBaseline="central"
        fontSize={abbrFs}
        fontWeight={700}
        fill={color}
        style={{ pointerEvents: 'none', userSelect: 'none' }}
      >
        {abbr}
      </text>
      {showVariety && (
        <text
          x={px + pw / 2}
          y={py + ph / 2 + abbrFs * 0.6}
          textAnchor="middle"
          dominantBaseline="central"
          fontSize={nameFs}
          fill="#6b7280"
          style={{ pointerEvents: 'none', userSelect: 'none' }}
        >
          {displayName}
        </text>
      )}
      {plant.quantity > 1 && pw >= 10 && (
        <g>
          <circle
            cx={px + pw - 4}
            cy={py + 4}
            r={3.5}
            fill={color}
            fillOpacity={0.8}
          />
          <text
            x={px + pw - 4}
            y={py + 4}
            textAnchor="middle"
            dominantBaseline="central"
            fontSize={4}
            fontWeight={700}
            fill="white"
            style={{ pointerEvents: 'none', userSelect: 'none' }}
          >
            {plant.quantity > 99 ? '99+' : plant.quantity}
          </text>
        </g>
      )}
      {'notes' in plant && plant.notes && pw >= 10 && (
        <text
          x={px + pw - 3}
          y={py + ph - 3}
          textAnchor="middle"
          dominantBaseline="central"
          fontSize={5}
          style={{ pointerEvents: 'none', userSelect: 'none' }}
        >
          💬
        </text>
      )}
    </g>
  )
})

export default PlantRect
