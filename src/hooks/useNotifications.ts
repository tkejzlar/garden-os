import { useEffect } from 'react'
import type { Task } from '../lib/api'

export function useTaskNotifications(tasks: Task[]) {
  useEffect(() => {
    if (!('Notification' in window) || Notification.permission !== 'granted') return
    if (tasks.length === 0) return

    // Check once per session if there are overdue tasks
    const key = `notified_${new Date().toDateString()}`
    if (sessionStorage.getItem(key)) return
    sessionStorage.setItem(key, '1')

    const overdue = tasks.filter(t => {
      const d = new Date(t.due_date + 'T00:00:00')
      return d < new Date(new Date().toDateString())
    })

    if (overdue.length > 0) {
      new Notification('GardenOS', {
        body: `You have ${overdue.length} overdue task${overdue.length > 1 ? 's' : ''}: ${overdue[0].title}`,
        icon: '/icon-192.png',
        tag: 'overdue-tasks',
      })
    }

    const today = tasks.filter(t => {
      const d = new Date(t.due_date + 'T00:00:00')
      const now = new Date()
      now.setHours(0, 0, 0, 0)
      return d.getTime() === now.getTime()
    })

    if (today.length > 0 && overdue.length === 0) {
      new Notification('GardenOS', {
        body: `${today.length} task${today.length > 1 ? 's' : ''} due today: ${today[0].title}`,
        icon: '/icon-192.png',
        tag: 'today-tasks',
      })
    }
  }, [tasks])
}
