import { useState, useEffect } from 'react'
import { Heart } from 'lucide-react'

export function WishlistButton({ seedId }: { seedId: number }) {
  const key = `wishlist_${seedId}`
  const [wished, setWished] = useState(() => {
    try { return localStorage.getItem(key) === '1' } catch { return false }
  })

  useEffect(() => {
    try { localStorage.setItem(key, wished ? '1' : '0') } catch {}
  }, [key, wished])

  return (
    <button
      onClick={e => { e.preventDefault(); e.stopPropagation(); setWished(!wished) }}
      className={`p-1.5 rounded-full transition-all ${wished ? 'text-pink-500' : 'text-gray-300 hover:text-pink-300'}`}
      title={wished ? 'Remove from wishlist' : 'Add to wishlist'}
    >
      <Heart size={14} fill={wished ? 'currentColor' : 'none'} />
    </button>
  )
}

export function useWishlistCount(): number {
  const [count, setCount] = useState(0)
  useEffect(() => {
    let c = 0
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)
      if (k?.startsWith('wishlist_') && localStorage.getItem(k) === '1') c++
    }
    setCount(c)
  }, [])
  return count
}
