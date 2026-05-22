<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from './lib/supabase'
import GlobalConfirm from './components/GlobalConfirm.vue'
import NotificationProvider from './components/NotificationProvider.vue'
import { useConfirm } from './composables/useConfirm'

const router = useRouter()
const { setConfirmRef } = useConfirm()

onMounted(() => {
  // Evitar advertencia de TS por no lectura
  setConfirmRef
  
  supabase.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_IN' || event === 'INITIAL_SESSION') {
      const rol = session?.user?.user_metadata?.rol
      
      // Detección robusta de Dueño (con o sin ñ)
      if (rol === 'superadmin') {
        router.push('/super-admin')
      } else if (rol === 'dueno' || rol === 'dueño') {
        router.push('/owner-dashboard')
      } 
      else if (rol === 'barbero') {
        router.push('/barber-dashboard')
      } 
      else if (rol === 'cliente') {
        router.push('/client-dashboard')
      }
    } else if (event === 'SIGNED_OUT') {
      router.push('/')
    }
  })
})
</script>

<template>
  <div class="app-container relative min-h-screen bg-brand-dark">
    <router-view />
    <GlobalConfirm :ref="setConfirmRef" />
    <NotificationProvider />
  </div>
</template>

<style>
@import "tailwindcss";

:root {
  --brand-primary: #FFD700;
  --brand-dark: #0A0A0A;
  --brand-surface: #121212;
}

body {
  background-color: var(--brand-dark);
  color: white;
  margin: 0;
  padding: 0;
  font-family: 'Inter', sans-serif;
  backdrop-filter: none !important;
}

.btn-primary {
  background-color: var(--brand-primary);
  color: black;
  border: none;
  cursor: pointer;
  transition: all 0.3s ease;
}

.btn-primary:hover {
  transform: translateY(-2px);
  filter: brightness(1.1);
}

::-webkit-scrollbar {
  width: 5px;
}
::-webkit-scrollbar-track {
  background: transparent;
}
::-webkit-scrollbar-thumb {
  background: rgba(255, 215, 0, 0.1);
  border-radius: 20px;
}
</style>
