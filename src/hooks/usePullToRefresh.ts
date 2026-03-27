import { useRef, useEffect, useCallback } from 'react'

export function usePullToRefresh(onRefresh: () => Promise<void>) {
  const startY = useRef(0)
  const pulling = useRef(false)
  const indicator = useRef<HTMLDivElement | null>(null)

  const createIndicator = useCallback(() => {
    const wrapper = document.createElement('div')
    wrapper.className = 'fixed top-0 left-0 right-0 flex justify-center pt-4 z-50 pointer-events-none'

    const circle = document.createElement('div')
    circle.className = 'w-8 h-8 rounded-full bg-white shadow-lg flex items-center justify-center'

    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('class', 'w-4 h-4 text-green-600 animate-spin')
    svg.setAttribute('viewBox', '0 0 24 24')
    svg.setAttribute('fill', 'none')
    svg.setAttribute('stroke', 'currentColor')
    svg.setAttribute('stroke-width', '2')

    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    path.setAttribute('d', 'M21 12a9 9 0 11-6.219-8.56')

    svg.appendChild(path)
    circle.appendChild(svg)
    wrapper.appendChild(circle)
    return wrapper
  }, [])

  const handleTouchStart = useCallback((e: TouchEvent) => {
    if (window.scrollY === 0) {
      startY.current = e.touches[0].clientY
      pulling.current = true
    }
  }, [])

  const handleTouchMove = useCallback((e: TouchEvent) => {
    if (!pulling.current) return
    const diff = e.touches[0].clientY - startY.current
    if (diff > 0 && diff < 150) {
      if (!indicator.current) {
        indicator.current = createIndicator()
        document.body.appendChild(indicator.current)
      }
      indicator.current.style.opacity = String(Math.min(1, diff / 80))
      indicator.current.style.transform = `translateY(${Math.min(diff * 0.5, 40)}px)`
    }
  }, [createIndicator])

  const handleTouchEnd = useCallback(async () => {
    if (!pulling.current) return
    pulling.current = false

    if (indicator.current) {
      const el = indicator.current
      // If pulled enough, trigger refresh
      const opacity = parseFloat(el.style.opacity || '0')
      if (opacity >= 1) {
        await onRefresh()
      }
      el.style.opacity = '0'
      setTimeout(() => el.remove(), 200)
      indicator.current = null
    }
  }, [onRefresh])

  useEffect(() => {
    window.addEventListener('touchstart', handleTouchStart, { passive: true })
    window.addEventListener('touchmove', handleTouchMove, { passive: true })
    window.addEventListener('touchend', handleTouchEnd)
    return () => {
      window.removeEventListener('touchstart', handleTouchStart)
      window.removeEventListener('touchmove', handleTouchMove)
      window.removeEventListener('touchend', handleTouchEnd)
    }
  }, [handleTouchStart, handleTouchMove, handleTouchEnd])
}
