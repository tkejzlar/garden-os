export function SkeletonLine({ width = '100%', height = '16px' }: { width?: string; height?: string }) {
  return (
    <div
      className="rounded-lg animate-pulse"
      style={{ width, height, background: 'linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%)', backgroundSize: '200% 100%' }}
    />
  )
}

export function SkeletonCard() {
  return (
    <div className="bg-white rounded-xl border border-gray-100 p-4 space-y-3">
      <SkeletonLine width="60%" height="20px" />
      <SkeletonLine width="40%" height="14px" />
      <SkeletonLine width="100%" height="8px" />
    </div>
  )
}

export function SkeletonList({ count = 5 }: { count?: number }) {
  return (
    <div className="space-y-3">
      {Array.from({ length: count }).map((_, i) => (
        <SkeletonCard key={i} />
      ))}
    </div>
  )
}
