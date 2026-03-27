import { useState, useEffect } from 'react'
import { Flame } from 'lucide-react'

/** Tracks consecutive days the user opened the app */
export function StreakCounter() {
  const [streak, setStreak] = useState(0)

  useEffect(() => {
    try {
      const today = new Date().toDateString()
      const lastVisit = localStorage.getItem('last_visit')
      const currentStreak = parseInt(localStorage.getItem('streak') || '0')

      if (lastVisit === today) {
        setStreak(currentStreak)
        return
      }

      const yesterday = new Date(Date.now() - 86400000).toDateString()
      if (lastVisit === yesterday) {
        const newStreak = currentStreak + 1
        localStorage.setItem('streak', String(newStreak))
        setStreak(newStreak)
      } else {
        localStorage.setItem('streak', '1')
        setStreak(1)
      }
      localStorage.setItem('last_visit', today)
    } catch {
      setStreak(0)
    }
  }, [])

  if (streak < 2) return null

  return (
    <div className="flex items-center gap-1 text-xs font-medium text-amber-600" title={`${streak} day streak!`}>
      <Flame size={14} className={streak >= 7 ? 'text-orange-500' : 'text-amber-400'} />
      <span>{streak}</span>
    </div>
  )
}
