<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { Scissors, Lock, CheckCircle2, AlertCircle } from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'

const router = useRouter()
const notify = useNotifications()

const password = ref('')
const confirmPassword = ref('')
const loading = ref(false)
const errorMessage = ref('')
const successMessage = ref('')

onMounted(async () => {
  // Verificar si hay una sesión activa para restablecer la contraseña.
  // Cuando el usuario hace clic en el enlace del correo, Supabase establece automáticamente la sesión
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) {
    errorMessage.value = 'El enlace de recuperación es inválido, ha expirado o no se encuentra una sesión activa.'
  }
})

const handleResetPassword = async () => {
  if (password.value !== confirmPassword.value) {
    return errorMessage.value = 'Las contraseñas no coinciden.'
  }

  if (password.value.length < 6) {
    return errorMessage.value = 'La contraseña debe tener al menos 6 caracteres.'
  }

  loading.value = true
  errorMessage.value = ''
  successMessage.value = ''

  try {
    const { error } = await supabase.auth.updateUser({
      password: password.value
    })

    if (error) throw error

    successMessage.value = '¡Contraseña actualizada con éxito!'
    notify.success("¡Tu contraseña ha sido restablecida!")
    
    // Cerrar sesión para forzar inicio de sesión limpio con la nueva contraseña
    await supabase.auth.signOut()

    setTimeout(() => {
      router.push('/login')
    }, 2500)
  } catch (error: any) {
    errorMessage.value = error.message || 'Error al actualizar la contraseña'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen bg-brand-dark text-white flex items-center justify-center p-4 font-sans">
    <div class="card w-full max-w-md animate-in fade-in zoom-in-95 duration-500">
      <div class="flex justify-center mb-8">
        <div class="p-3 bg-brand-primary rounded-xl cursor-pointer" @click="router.push('/')">
          <Scissors class="text-black w-8 h-8" />
        </div>
      </div>

      <h2 class="text-3xl font-black text-center mb-2 uppercase italic tracking-tighter">Establecer Contraseña</h2>
      <p class="text-white/50 text-center mb-8">Ingresa tu nueva contraseña para acceder a TuTurno</p>

      <div v-if="successMessage" class="p-6 bg-brand-primary/5 border border-brand-primary/20 text-brand-primary rounded-[30px] text-center space-y-4 animate-in zoom-in duration-300">
        <div class="w-12 h-12 bg-brand-primary/10 rounded-full flex items-center justify-center mx-auto">
          <CheckCircle2 class="w-6 h-6 text-brand-primary animate-pulse" />
        </div>
        <p class="font-black uppercase tracking-widest text-xs italic">¡Contraseña Guardada!</p>
        <p class="text-white/60 text-xs leading-relaxed">Tu acceso ha sido reconfigurado con éxito. Serás redirigido al inicio de sesión.</p>
      </div>

      <form v-else @submit.prevent="handleResetPassword" class="space-y-6">
        <div>
          <label class="block text-sm font-medium text-white/70 mb-2">Nueva Contraseña</label>
          <div class="relative">
            <Lock class="w-4 h-4 text-white/30 absolute left-4 top-1/2 -translate-y-1/2" />
            <input 
              v-model="password" 
              type="password" 
              required 
              class="input-field pl-12" 
              placeholder="Mínimo 6 caracteres"
            />
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-white/70 mb-2">Confirmar Nueva Contraseña</label>
          <div class="relative">
            <Lock class="w-4 h-4 text-white/30 absolute left-4 top-1/2 -translate-y-1/2" />
            <input 
              v-model="confirmPassword" 
              type="password" 
              required 
              class="input-field pl-12" 
              placeholder="Repite la contraseña"
            />
          </div>
        </div>

        <div v-if="errorMessage" class="p-4 bg-red-500/5 border border-red-500/10 text-red-400 rounded-2xl text-xs flex items-start gap-3">
          <AlertCircle class="w-4 h-4 shrink-0 mt-0.5" />
          <span class="leading-relaxed font-bold">{{ errorMessage }}</span>
        </div>

        <button type="submit" class="btn-primary w-full py-4 text-sm font-black uppercase italic tracking-tighter" :disabled="loading || (errorMessage.includes('enlace') && !password)">
          {{ loading ? 'Actualizando...' : 'Cambiar Contraseña' }}
        </button>
      </form>
    </div>
  </div>
</template>
