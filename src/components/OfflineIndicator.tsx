import { useState, useEffect } from 'react'
import { WifiOff } from 'lucide-react'

export function OfflineIndicator() {
  const [online, setOnline] = useState(navigator.onLine)

  useEffect(() => {
    const goOnline = () => setOnline(true)
    const goOffline = () => setOnline(false)
    window.addEventListener('online', goOnline)
    window.addEventListener('offline', goOffline)
    return () => {
      window.removeEventListener('online', goOnline)
      window.removeEventListener('offline', goOffline)
    }
  }, [])

  if (online) return null

  return (
    <div className="fixed top-0 left-0 right-0 z-[9998] bg-gray-900 text-white px-4 py-2 flex items-center justify-center gap-2 text-sm"
         style={{ paddingTop: 'calc(4px + env(safe-area-inset-top, 0px))' }}>
      <WifiOff size={14} />
      <span>You're offline — changes will sync when connected</span>
    </div>
  )
}
