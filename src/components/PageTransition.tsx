import { ReactNode } from 'react'

export function PageTransition({ children }: { children: ReactNode }) {
  return (
    <div style={{ animation: 'pageEnter 250ms ease-out' }}>
      {children}
    </div>
  )
}
