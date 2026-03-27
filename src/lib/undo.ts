import { create } from 'zustand'

interface UndoAction {
  id: number
  message: string
  undoFn: () => Promise<void>
  expiryFn: () => Promise<void>
}

interface UndoStore {
  action: UndoAction | null
  push: (message: string, undoFn: () => Promise<void>, expiryFn: () => Promise<void>) => void
  clear: () => void
}

let nextId = 0

export const useUndoStore = create<UndoStore>((set) => ({
  action: null,
  push: (message, undoFn, expiryFn) => {
    set({ action: { id: ++nextId, message, undoFn, expiryFn } })
  },
  clear: () => set({ action: null }),
}))
