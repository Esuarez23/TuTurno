<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { Scissors } from 'lucide-vue-next'

const router = useRouter()
const email = ref('')
const password = ref('')
const loading = ref(false)
const errorMessage = ref('')

const handleLogin = async () => {
  loading.value = true
  errorMessage.value = ''
  
  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.value,
      password: password.value,
    })

    if (error) throw error
    
    if (data.session) {
      const { data: perfil, error: perfilError } = await supabase
        .from('perfiles')
        .select('rol')
        .eq('id', data.session.user.id)
        .single()
        
      if (perfilError) {
        throw new Error('Error al obtener el perfil. ¿Ejecutaste el script SQL en Supabase?')
      }

      if (perfil) {
         router.push(`/dashboard/${perfil.rol === 'dueño' ? 'owner' : perfil.rol}`)
      } else {
         throw new Error('Perfil no encontrado.')
      }
    }
  } catch (error: any) {
    errorMessage.value = error.message || 'Error al iniciar sesión'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center p-4">
    <div class="card w-full max-w-md animate-in fade-in zoom-in-95 duration-500">
      <div class="flex justify-center mb-8">
        <div class="p-3 bg-brand-primary rounded-xl cursor-pointer" @click="router.push('/')">
          <Scissors class="text-black w-8 h-8" />
        </div>
      </div>
      
      <h2 class="text-3xl font-black text-center mb-2">Bienvenido de nuevo</h2>
      <p class="text-white/50 text-center mb-8">Ingresa a tu cuenta para continuar</p>

      <form @submit.prevent="handleLogin" class="space-y-6">
        <div>
          <label class="block text-sm font-medium text-white/70 mb-2">Correo electrónico</label>
          <input 
            v-model="email" 
            type="email" 
            required 
            class="input-field" 
            placeholder="tu@email.com"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-white/70 mb-2">Contraseña</label>
          <input 
            v-model="password" 
            type="password" 
            required 
            class="input-field" 
            placeholder="••••••••"
          />
        </div>

        <div v-if="errorMessage" class="p-3 bg-red-500/10 border border-red-500/20 text-red-400 rounded-lg text-sm text-center">
          {{ errorMessage }}
        </div>

        <button type="submit" class="btn-primary w-full" :disabled="loading">
          {{ loading ? 'Iniciando...' : 'Iniciar Sesión' }}
        </button>
      </form>

      <p class="text-center mt-6 text-white/50">
        ¿No tienes cuenta? 
        <a @click="router.push('/register')" class="text-brand-primary hover:underline cursor-pointer font-medium">Regístrate aquí</a>
      </p>
    </div>
  </div>
</template>
