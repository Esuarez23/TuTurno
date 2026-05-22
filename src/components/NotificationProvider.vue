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
  if (type === 'success') return 'border-brand-primary/30 bg-brand-surface text-brand-primary shadow-brand-primary/5'
  if (type === 'error') return 'border-red-500/30 bg-brand-surface text-red-500 shadow-red-500/5'
  return 'border-white/10 bg-brand-surface text-white shadow-white/5'
}
</script>

<template>
  <div class="fixed bottom-8 right-8 z-[9999] flex flex-col gap-3 w-full max-w-sm pointer-events-none">
    <TransitionGroup 
      enter-active-class="transform transition duration-500 cubic-bezier(0.175, 0.885, 0.32, 1.275)"
      enter-from-class="translate-y-12 opacity-0 scale-90"
      enter-to-class="translate-y-0 opacity-100 scale-100"
      leave-active-class="transform transition duration-300 ease-in"
      leave-from-class="opacity-100 scale-100"
      leave-to-class="translate-x-12 opacity-0 scale-90"
    >
      <div 
        v-for="n in notifications" 
        :key="n.id"
        class="pointer-events-auto p-5 rounded-[25px] border backdrop-blur-2xl shadow-2xl flex items-center gap-4 relative overflow-hidden group"
        :class="getColors(n.type)"
      >
        <!-- Luxury Progress Line -->
        <div 
          class="absolute bottom-0 left-0 h-1 bg-current opacity-20"
          :style="{ animation: `progress ${n.duration}ms linear forwards` }"
        ></div>

        <div class="shrink-0">
          <component :is="getIcon(n.type)" class="w-6 h-6" />
        </div>
        
        <div class="flex-1">
          <p class="text-xs font-black uppercase italic tracking-tighter leading-tight">{{ n.message }}</p>
        </div>

        <button @click="removeNotification(n.id)" class="opacity-0 group-hover:opacity-100 transition-opacity p-1 hover:bg-white/5 rounded-lg cursor-pointer">
          <X class="w-4 h-4 opacity-40" />
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
