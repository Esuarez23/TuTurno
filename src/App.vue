<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from './lib/supabase'
import { useRouter } from 'vue-router'
import NotificationProvider from './components/NotificationProvider.vue'

const user = ref(null)
const router = useRouter()

onMounted(async () => {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    user.value = session?.user ?? null

    supabase.auth.onAuthStateChange(async (_event, session) => {
      user.value = session?.user ?? null
      
      if (_event === 'SIGNED_OUT') {
        router.push('/')
      }
    })
  } catch (error) {
    console.warn('Supabase no está configurado todavía.')
  }
})
</script>

<template>
  <NotificationProvider />
  <router-view />
</template>

<style>
/* Estilos globales */
</style>
