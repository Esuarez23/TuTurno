import { ref } from 'vue'

export interface Notification {
  id: number
  message: string
  type: 'success' | 'error' | 'info'
  duration?: number
}

const notifications = ref<Notification[]>([])
let nextId = 1

export const useNotifications = () => {
  const notify = (message: string, type: Notification['type'] = 'info', duration = 4000) => {
    const id = nextId++
    notifications.value.push({ id, message, type, duration })

    setTimeout(() => {
      removeNotification(id)
    }, duration)
  }

  const removeNotification = (id: number) => {
    notifications.value = notifications.value.filter(n => n.id !== id)
  }

  return {
    notifications,
    notify,
    removeNotification,
    success: (msg: string) => notify(msg, 'success'),
    error: (msg: string) => notify(msg, 'error'),
    info: (msg: string) => notify(msg, 'info')
  }
}
