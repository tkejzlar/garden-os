import { Snowflake, Sun, ThermometerSun } from 'lucide-react'
import { getSeasonDates } from '../lib/season'

export function FrostCountdown() {
  const now = new Date()
  const { start, end } = getSeasonDates(now.getFullYear())

  const daysToLastFrost = Math.ceil((start.getTime() - now.getTime()) / 86400000)
  const daysToFirstFrost = Math.ceil((end.getTime() - now.getTime()) / 86400000)

  // Before last frost
  if (daysToLastFrost > 0 && daysToLastFrost <= 60) {
    return (
      <div className="flex items-center gap-3 px-4 py-3 bg-blue-50 border border-blue-200 rounded-xl">
        <Snowflake size={20} className="text-blue-500 shrink-0" />
        <div>
          <p className="text-sm font-medium text-blue-900">
            {daysToLastFrost} day{daysToLastFrost !== 1 ? 's' : ''} to last frost
          </p>
          <p className="text-xs text-blue-700">
            {daysToLastFrost > 30 ? 'Start seeds indoors now' :
             daysToLastFrost > 14 ? 'Begin hardening off seedlings' :
             'Almost safe to transplant — watch the forecast!'}
          </p>
        </div>
      </div>
    )
  }

  // Growing season
  if (daysToLastFrost <= 0 && daysToFirstFrost > 0) {
    if (daysToFirstFrost <= 30) {
      return (
        <div className="flex items-center gap-3 px-4 py-3 bg-amber-50 border border-amber-200 rounded-xl">
          <ThermometerSun size={20} className="text-amber-500 shrink-0" />
          <div>
            <p className="text-sm font-medium text-amber-900">
              {daysToFirstFrost} day{daysToFirstFrost !== 1 ? 's' : ''} until first frost
            </p>
            <p className="text-xs text-amber-700">
              Harvest remaining crops, protect tender plants, mulch perennials
            </p>
          </div>
        </div>
      )
    }
    return null // Mid-season, no warning needed
  }

  // After first frost
  if (daysToFirstFrost <= 0) {
    return (
      <div className="flex items-center gap-3 px-4 py-3 bg-gray-50 border border-gray-200 rounded-xl">
        <Snowflake size={20} className="text-gray-400 shrink-0" />
        <div>
          <p className="text-sm font-medium text-gray-700">Season ended</p>
          <p className="text-xs text-gray-500">Time to plan for next year!</p>
        </div>
      </div>
    )
  }

  return null
}
