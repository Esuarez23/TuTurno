<script setup lang="ts">
import { useNotifications } from '../composables/useNotifications'
import { CheckCircle, AlertCircle, Info, X } from 'lucide-vue-next'

const { notifications, removeNotification } = useNotifications()

const getIcon = (type: string) => {
  if (type === 'success') return CheckCircle
  if (type === 'error') return AlertCircle
  return Info
}

const getColors = (type: string) => {
  if (type === 'success') return 'border-green-500/50 bg-green-500/10 text-green-400'
  if (type === 'error') return 'border-red-500/50 bg-red-500/10 text-red-400'
  return 'border-brand-primary/50 bg-brand-primary/10 text-brand-primary'
}
</script>

<template>
  <div class="fixed top-6 right-6 z-[9999] flex flex-col gap-3 w-full max-w-sm pointer-events-none">
    <TransitionGroup 
      enter-active-class="transform transition duration-300 ease-out"
      enter-from-class="translate-x-12 opacity-0"
      enter-to-class="translate-x-0 opacity-100"
      leave-active-class="transform transition duration-200 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="translate-x-4 opacity-0"
    >
      <div 
        v-for="n in notifications" 
        :key="n.id"
        class="pointer-events-auto p-4 rounded-2xl border backdrop-blur-xl shadow-2xl flex items-start gap-3 relative overflow-hidden group"
        :class="getColors(n.type)"
      >
        <!-- Progress bar animation -->
        <div 
          class="absolute bottom-0 left-0 h-0.5 bg-current opacity-20"
          :style="{ animation: `progress ${n.duration}ms linear forwards` }"
        ></div>

        <component :is="getIcon(n.type)" class="w-5 h-5 mt-0.5 shrink-0" />
        
        <div class="flex-1 pr-4">
          <p class="text-sm font-bold leading-tight">{{ n.message }}</p>
        </div>

        <button @click="removeNotification(n.id)" class="opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer">
          <X class="w-4 h-4" />
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>

<style scoped>
@keyframes progress {
  from { width: 100%; }
  to { width: 0%; }
}
</style>
