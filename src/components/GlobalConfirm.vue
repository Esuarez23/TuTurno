<script setup lang="ts">
import { ref } from 'vue'
import { AlertTriangle, Info } from 'lucide-vue-next'

interface ConfirmOptions {
  title?: string
  message: string
  confirmText?: string
  cancelText?: string
  type?: 'warning' | 'info' | 'danger'
}

const isOpen = ref(false)
const options = ref<ConfirmOptions>({ message: '' })
let resolvePromise: (value: boolean) => void

const show = (opts: ConfirmOptions) => {
  options.value = {
    title: opts.title || '¿Estás seguro?',
    confirmText: opts.confirmText || 'Confirmar',
    cancelText: opts.cancelText || 'Cancelar',
    type: opts.type || 'warning',
    ...opts
  }
  isOpen.value = true
  return new Promise<boolean>((resolve) => {
    resolvePromise = resolve
  })
}

const handleConfirm = () => {
  isOpen.value = false
  resolvePromise(true)
}

const handleCancel = () => {
  isOpen.value = false
  resolvePromise(false)
}

defineExpose({ show })
</script>

<template>
  <div v-if="isOpen" class="fixed inset-0 z-[999] flex items-center justify-center p-4 overflow-hidden">
    <!-- Overlay con Blur Extremo -->
    <div class="absolute inset-0 bg-black/80 backdrop-blur-md animate-in fade-in duration-300"></div>
    
    <!-- Modal Card -->
    <div class="relative w-full max-w-sm bg-brand-surface border border-white/10 rounded-[40px] p-8 shadow-2xl shadow-black animate-in zoom-in-95 duration-300">
      <div class="flex flex-col items-center text-center">
        <!-- Icono Dinámico -->
        <div :class="[
          'w-16 h-16 rounded-2xl flex items-center justify-center mb-6 shadow-lg',
          options.type === 'danger' ? 'bg-red-500/10 text-red-500 shadow-red-500/10' : 
          options.type === 'info' ? 'bg-blue-500/10 text-blue-500 shadow-blue-500/10' : 'bg-brand-primary/10 text-brand-primary shadow-brand-primary/10'
        ]">
          <AlertTriangle v-if="options.type === 'warning' || options.type === 'danger'" class="w-8 h-8" />
          <Info v-else class="w-8 h-8" />
        </div>

        <h3 class="text-2xl font-black uppercase italic tracking-tighter mb-2">{{ options.title }}</h3>
        <p class="text-white/40 text-sm font-medium italic mb-8 leading-relaxed">{{ options.message }}</p>

        <div class="flex flex-col w-full gap-3">
          <button @click="handleConfirm" :class="[
            'w-full py-4 rounded-2xl font-black uppercase italic tracking-tighter transition-all shadow-xl hover:scale-[1.02] active:scale-95 cursor-pointer',
            options.type === 'danger' ? 'bg-red-500 text-white shadow-red-500/20' : 'bg-brand-primary text-black shadow-brand-primary/20'
          ]">
            {{ options.confirmText }}
          </button>
          <button @click="handleCancel" class="w-full py-4 text-white/20 font-black uppercase italic tracking-widest text-[10px] hover:text-white transition-colors cursor-pointer">
            {{ options.cancelText }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
