<script setup lang="ts">
withDefaults(defineProps<{
  text: string
  position?: 'top' | 'bottom' | 'left' | 'right'
}>(), {
  position: 'top'
})
</script>

<template>
  <div class="relative inline-flex items-center group">
    <slot />
    
    <!-- Burbuja del Tooltip -->
    <div 
      :class="[
        'absolute z-[9999] hidden group-hover:flex items-center gap-2 bg-brand-surface/95 border border-brand-primary/20 text-white/90 text-[10px] font-bold uppercase tracking-wider py-2.5 px-3.5 rounded-xl shadow-2xl shadow-black/80 backdrop-blur-xl w-48 text-center justify-center transition-all duration-300 animate-in fade-in zoom-in-95 pointer-events-none',
        position === 'top' ? 'bottom-full left-1/2 -translate-x-1/2 mb-3.5' : '',
        position === 'bottom' ? 'top-full left-1/2 -translate-x-1/2 mt-3.5' : '',
        position === 'left' ? 'right-full top-1/2 -translate-y-1/2 mr-3.5' : '',
        position === 'right' ? 'left-full top-1/2 -translate-y-1/2 ml-3.5' : ''
      ]"
    >
      <!-- Pequeña flecha de indicación -->
      <div 
        :class="[
          'absolute w-2 h-2 bg-brand-surface border-brand-primary/20 rotate-45 pointer-events-none',
          position === 'top' ? 'top-full left-1/2 -translate-x-1/2 -mt-1 border-r border-b' : '',
          position === 'bottom' ? 'bottom-full left-1/2 -translate-x-1/2 -mb-1 border-l border-t' : '',
          position === 'left' ? 'left-full top-1/2 -translate-y-1/2 -ml-1 border-r border-t' : '',
          position === 'right' ? 'right-full top-1/2 -translate-y-1/2 -mr-1 border-l border-b' : ''
        ]"
      ></div>
      <span class="leading-snug select-none text-center">{{ text }}</span>
    </div>
  </div>
</template>
