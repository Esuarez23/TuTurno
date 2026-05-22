<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { Scissors, ArrowLeft, Mail } from 'lucide-vue-next'

const router = useRouter()
const email = ref('')
const password = ref('')
const loading = ref(false)
const errorMessage = ref('')

// Recuperar Contraseña
const showForgot = ref(false)
const forgotEmail = ref('')
const forgotLoading = ref(false)
const forgotSuccess = ref(false)
const forgotError = ref('')

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
      let { data: perfil, error: perfilError } = await supabase
        .from('perfiles')
        .select('rol')
        .eq('id', data.session.user.id)
        .maybeSingle()
        
      if (perfilError) {
        throw new Error('No se pudo obtener tu perfil. Intenta de nuevo o contacta al administrador.')
      }

      // Autorreparar perfil usando función RPC del servidor (bypasea RLS)
      if (!perfil) {
        console.warn('Perfil no encontrado por ID. Invocando sync_user_profile RPC...')
        
        const { data: syncResult, error: syncError } = await supabase.rpc('sync_user_profile')
        
        if (syncError) {
          throw new Error(`No se pudo sincronizar tu perfil. Detalle: [${syncError.code}] ${syncError.message}`)
        }
        
        if (syncResult && syncResult.success) {
          perfil = { rol: syncResult.rol }
        } else {
          const detalle = syncResult?.error || 'Respuesta inesperada del servidor'
          throw new Error(`No se pudo sincronizar tu perfil. Detalle: ${detalle}`)
        }
      }

      if (perfil) {
        const rol = perfil.rol
        if (rol === 'superadmin') {
          router.push('/super-admin')
        } else if (rol === 'dueno' || rol === 'dueño') {
          router.push('/owner-dashboard')
        } else if (rol === 'barbero') {
          router.push('/barber-dashboard')
        } else if (rol === 'cliente') {
          router.push('/client-dashboard')
        } else {
          router.push('/')
        }
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

const handleForgotPassword = async () => {
  forgotLoading.value = true
  forgotError.value = ''
  forgotSuccess.value = false
  
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(forgotEmail.value, {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    if (error) throw error
    forgotSuccess.value = true
  } catch (error: any) {
    forgotError.value = error.message || 'Error al enviar el correo de recuperación'
  } finally {
    forgotLoading.value = false
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
      
      <!-- Vista de Login -->
      <div v-if="!showForgot" class="animate-in fade-in slide-in-from-left-4 duration-300">
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
            <div class="flex justify-between items-center mb-2">
              <label class="block text-sm font-medium text-white/70">Contraseña</label>
              <a @click="showForgot = true; errorMessage = ''; forgotSuccess = false; forgotError = ''" class="text-[10px] font-black uppercase text-brand-primary hover:underline cursor-pointer tracking-wider">¿Olvidaste tu contraseña?</a>
            </div>
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

      <!-- Vista de Recuperación -->
      <div v-else class="animate-in fade-in slide-in-from-right-4 duration-300">
        <button @click="showForgot = false" class="flex items-center gap-2 text-white/40 hover:text-white mb-6 text-xs transition-colors cursor-pointer font-bold uppercase italic tracking-tighter">
          <ArrowLeft class="w-4 h-4" /> Volver al inicio
        </button>
        <h2 class="text-3xl font-black text-center mb-2">Recuperar Contraseña</h2>
        <p class="text-white/50 text-center mb-8">Te enviaremos un correo electrónico con las instrucciones para restablecer tu acceso.</p>
        
        <div v-if="forgotSuccess" class="p-6 bg-brand-primary/5 border border-brand-primary/20 text-brand-primary rounded-3xl text-center space-y-4">
          <div class="w-12 h-12 bg-brand-primary/10 rounded-full flex items-center justify-center mx-auto"><Mail class="w-6 h-6 text-brand-primary animate-bounce" /></div>
          <p class="font-black uppercase tracking-widest text-xs italic">¡Correo Enviado!</p>
          <p class="text-white/60 text-xs leading-relaxed">Por favor revisa tu bandeja de entrada (y spam) de <strong>{{ forgotEmail }}</strong> para cambiar tu contraseña.</p>
        </div>
        
        <form v-else @submit.prevent="handleForgotPassword" class="space-y-6">
          <div>
            <label class="block text-sm font-medium text-white/70 mb-2">Correo electrónico</label>
            <input 
              v-model="forgotEmail" 
              type="email" 
              required 
              class="input-field" 
              placeholder="tu@email.com"
            />
          </div>
          
          <div v-if="forgotError" class="p-3 bg-red-500/10 border border-red-500/20 text-red-400 rounded-lg text-sm text-center">
            {{ forgotError }}
          </div>
          
          <button type="submit" class="btn-primary w-full" :disabled="forgotLoading">
            {{ forgotLoading ? 'Enviando...' : 'Enviar Instrucciones' }}
          </button>
        </form>
      </div>
    </div>
  </div>
</template>
