import { ref } from 'vue'

interface ConfirmOptions {
  title?: string
  message: string
  confirmText?: string
  cancelText?: string
  type?: 'warning' | 'info' | 'danger'
}

const confirmRef = ref<any>(null)

export const useConfirm = () => {
  const setConfirmRef = (el: any) => {
    confirmRef.value = el
  }

  const confirm = (opts: string | ConfirmOptions) => {
    if (!confirmRef.value) {
      console.error('ConfirmProvider no encontrado')
      return Promise.resolve(false)
    }

    const options: ConfirmOptions = typeof opts === 'string' ? { message: opts } : opts
    return confirmRef.value.show(options) as Promise<boolean>
  }

  return { setConfirmRef, confirm }
}
