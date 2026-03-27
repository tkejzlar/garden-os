import { useRef, useState, type ReactNode } from 'react'

interface SwipeActionProps {
  children: ReactNode
  onSwipeLeft?: () => void
  onSwipeRight?: () => void
  leftLabel?: string
  rightLabel?: string
  leftColor?: string
  rightColor?: string
}

export function SwipeAction({
  children,
  onSwipeLeft,
  onSwipeRight,
  leftLabel = 'Done',
  rightLabel = 'Snooze',
  leftColor = '#22c55e',
  rightColor = '#f59e0b',
}: SwipeActionProps) {
  const startX = useRef(0)
  const [offset, setOffset] = useState(0)
  const [swiping, setSwiping] = useState(false)

  const threshold = 80

  const handleStart = (x: number) => {
    startX.current = x
    setSwiping(true)
  }

  const handleMove = (x: number) => {
    if (!swiping) return
    const dx = x - startX.current
    // Limit swipe range and add resistance
    const limited = dx > 0
      ? Math.min(dx * 0.6, 120)
      : Math.max(dx * 0.6, -120)
    setOffset(limited)
  }

  const handleEnd = () => {
    setSwiping(false)
    if (offset > threshold && onSwipeRight) {
      onSwipeRight()
    } else if (offset < -threshold && onSwipeLeft) {
      onSwipeLeft()
    }
    setOffset(0)
  }

  return (
    <div className="relative overflow-hidden rounded-xl">
      {/* Background actions */}
      <div className="absolute inset-0 flex">
        {/* Right swipe → left action revealed */}
        <div className="flex items-center justify-start px-4 flex-1" style={{ backgroundColor: rightColor }}>
          <span className="text-white text-xs font-semibold">{rightLabel}</span>
        </div>
        {/* Left swipe → right action revealed */}
        <div className="flex items-center justify-end px-4 flex-1" style={{ backgroundColor: leftColor }}>
          <span className="text-white text-xs font-semibold">{leftLabel}</span>
        </div>
      </div>

      {/* Swipeable content */}
      <div
        className="relative bg-white"
        style={{
          transform: `translateX(${offset}px)`,
          transition: swiping ? 'none' : 'transform 200ms ease-out',
        }}
        onTouchStart={e => handleStart(e.touches[0].clientX)}
        onTouchMove={e => handleMove(e.touches[0].clientX)}
        onTouchEnd={handleEnd}
        onMouseDown={e => handleStart(e.clientX)}
        onMouseMove={e => { if (swiping) handleMove(e.clientX) }}
        onMouseUp={handleEnd}
        onMouseLeave={() => { if (swiping) handleEnd() }}
      >
        {children}
      </div>
    </div>
  )
}
