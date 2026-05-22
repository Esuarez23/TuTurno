<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { Scissors } from 'lucide-vue-next'

const router = useRouter()
const nombre = ref('')
const email = ref('')
const password = ref('')
const rol = ref('cliente')
const loading = ref(false)
const errorMessage = ref('')
const successMessage = ref('')

const handleRegister = async () => {
  loading.value = true
  errorMessage.value = ''
  successMessage.value = ''
  
  try {
    // Filtrar y asegurar que el rol a registrar sea estrictamente uno de los permitidos públicamente
    const rolesPermitidos = ['cliente', 'barbero', 'dueño']
    const rolFiltrado = rolesPermitidos.includes(rol.value) ? rol.value : 'cliente'

    const { data, error } = await supabase.auth.signUp({
      email: email.value,
      password: password.value,
      options: {
        data: {
          nombre: nombre.value,
          rol: rolFiltrado
        }
      }
    })

    if (error) throw error
    
    if (data.session) {
      // Login automático
    } else {
      successMessage.value = 'Registro exitoso. Revisa tu correo para confirmar (si está activado).'
      setTimeout(() => router.push('/login'), 3000)
    }
  } catch (error: any) {
    errorMessage.value = error.message || 'Error al registrarse'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center p-4">
    <div class="card w-full max-w-md animate-in fade-in zoom-in-95 duration-500 my-8">
      <div class="flex justify-center mb-6">
        <div class="p-3 bg-brand-primary rounded-xl cursor-pointer" @click="router.push('/')">
          <Scissors class="text-black w-8 h-8" />
        </div>
      </div>
      
      <h2 class="text-3xl font-black text-center mb-2">Crea tu cuenta</h2>
      <p class="text-white/50 text-center mb-6">Únete a la plataforma premium de barberías</p>

      <form @submit.prevent="handleRegister" class="space-y-5">
        <div>
          <label class="block text-sm font-medium text-white/70 mb-2">Nombre completo</label>
          <input 
            v-model="nombre" 
            type="text" 
            required 
            class="input-field" 
            placeholder="Tu nombre"
          />
        </div>

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

        <div>
          <label class="block text-sm font-medium text-white/70 mb-2">¿Qué tipo de usuario eres?</label>
          <div class="grid grid-cols-3 gap-2">
            <button 
              type="button" 
              @click="rol = 'cliente'"
              :class="['px-2 py-3 rounded-lg border text-sm font-medium transition-colors cursor-pointer', rol === 'cliente' ? 'bg-brand-primary/20 border-brand-primary text-brand-primary' : 'bg-brand-dark border-white/10 text-white/50 hover:border-white/30']"
            >
              Cliente
            </button>
            <button 
              type="button" 
              @click="rol = 'barbero'"
              :class="['px-2 py-3 rounded-lg border text-sm font-medium transition-colors cursor-pointer', rol === 'barbero' ? 'bg-brand-primary/20 border-brand-primary text-brand-primary' : 'bg-brand-dark border-white/10 text-white/50 hover:border-white/30']"
            >
              Barbero
            </button>
            <button 
              type="button" 
              @click="rol = 'dueño'"
              :class="['px-2 py-3 rounded-lg border text-sm font-medium transition-colors cursor-pointer', rol === 'dueño' ? 'bg-brand-primary/20 border-brand-primary text-brand-primary' : 'bg-brand-dark border-white/10 text-white/50 hover:border-white/30']"
            >
              Dueño
            </button>
          </div>
        </div>

        <div v-if="errorMessage" class="p-3 bg-red-500/10 border border-red-500/20 text-red-400 rounded-lg text-sm text-center">
          {{ errorMessage }}
        </div>
        
        <div v-if="successMessage" class="p-3 bg-green-500/10 border border-green-500/20 text-green-400 rounded-lg text-sm text-center">
          {{ successMessage }}
        </div>

        <button type="submit" class="btn-primary w-full mt-2" :disabled="loading">
          {{ loading ? 'Creando cuenta...' : 'Registrarse' }}
        </button>
      </form>

      <p class="text-center mt-6 text-white/50">
        ¿Ya tienes cuenta? 
        <a @click="router.push('/login')" class="text-brand-primary hover:underline cursor-pointer font-medium">Inicia sesión</a>
      </p>
    </div>
  </div>
</template>
