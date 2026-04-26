<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { LogOut, Scissors, Clock, CheckCircle, Search, UserPlus, AlertCircle, Users } from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'

const router = useRouter()
const notify = useNotifications()
const loading = ref(false)
const userProfile = ref<any>(null)
const barberia = ref<any>(null)
const barberiasDisponibles = ref<any[]>([])
// Estados para Equipo
const barberosActivos = ref<any[]>([]) // No se usa aquí, pero lo mantenemos si es necesario
const solicitudesPendientes = ref<any[]>([]) // No se usa aquí

// Estados para Agenda
const citasAgendadas = ref<any[]>([])
const citasEspera = ref<any[]>([])
const loadingAgenda = ref(false)
const servicios = ref<any[]>([])

// Modales y Formularios
const showEsperaModal = ref(false)
const newEspera = ref({ nombre_cliente: '', servicio_id: '' })
const processingAction = ref(false)
let subscription: any = null

onMounted(async () => {
  await fetchProfile()
  setupRealtimeSubscription()
})

onUnmounted(() => {
  if (subscription) {
    supabase.removeChannel(subscription)
  }
})

const fetchProfile = async () => {
  loading.value = true
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) {
    console.warn("No hay sesión activa")
    return
  }

  const { data, error } = await supabase
    .from('perfiles')
    .select('*, barberias(*)')
    .eq('id', session.user.id)
    .maybeSingle() // Usamos maybeSingle para que no de error si no hay perfil

  if (error) {
    console.error("Error cargando perfil:", error)
  }

  if (data) {
    userProfile.value = data
    if (data.barberias) {
      barberia.value = data.barberias
      fetchAgenda()
      fetchServicios() // Cargamos servicios para el modal de espera
    } else {
      console.log("Perfil encontrado sin barbería, cargando disponibles...")
      fetchBarberiasDisponibles()
    }
  } else {
    console.warn("No se encontró perfil para este usuario. Intentando cargar barberías de todos modos...")
    fetchBarberiasDisponibles()
  }
  loading.value = false
}

const fetchBarberiasDisponibles = async () => {
  loadingBarberias.value = true
  const { data, error } = await supabase.from('barberias').select('*')
  if (error) {
    console.error("Error cargando barberías:", error)
  } else {
    console.log("Barberías encontradas en DB:", data)
    barberiasDisponibles.value = data || []
  }
  loadingBarberias.value = false
}

const vincularABarberia = async (id: string) => {
  loading.value = true
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return

  const { error } = await supabase
    .from('perfiles')
    .upsert({ 
      id: session.user.id,
      nombre: session.user.user_metadata.nombre || 'Barbero',
      email: session.user.email,
      rol: 'barbero',
      barberia_id: id,
      estado_vinculacion: 'pendiente'
    })

  if (!error) {
    await fetchProfile()
    notify.success("Solicitud enviada correctamente")
  } else {
    console.error("Error al vincularse:", error)
    notify.error("Error al enviar la solicitud: " + error.message)
  }
  loading.value = false
}

const setupRealtimeSubscription = () => {
  if (!userProfile.value) return

  subscription = supabase
    .channel('cambios-agenda')
    .on(
      'postgres_changes',
      { 
        event: '*', 
        schema: 'public', 
        table: 'citas',
        filter: `barbero_id=eq.${userProfile.value.id}`
      },
      (payload) => {
        console.log("Cambio detectado en tiempo real:", payload)
        fetchAgenda()
        
        // Notificación especial si es una nueva cita
        if (payload.eventType === 'INSERT') {
          notify.info("¡Nuevo turno agendado!")
        }
      }
    )
    .subscribe()
}

const fetchServicios = async () => {
  if (!barberia.value) return
  const { data } = await supabase
    .from('servicios')
    .select('*')
    .eq('barberia_id', barberia.value.id)
  if (data) servicios.value = data
}

const agregarAListaEspera = async () => {
  if (!newEspera.value.nombre_cliente || !newEspera.value.servicio_id) return
  
  processingAction.value = true
  const { error } = await supabase
    .from('citas')
    .insert([{
      barberia_id: barberia.value.id,
      barbero_id: userProfile.value.id,
      servicio_id: newEspera.value.servicio_id,
      nombre_cliente_manual: newEspera.value.nombre_cliente,
      tipo: 'espera',
      estado: 'confirmada',
      fecha_hora: new Date().toISOString()
    }])

  if (!error) {
    showEsperaModal.value = false
    newEspera.value = { nombre_cliente: '', servicio_id: '' }
    fetchAgenda()
    notify.success("Cliente agregado a la lista")
  } else {
    notify.error("Error al agregar a la lista: " + error.message)
  }
  processingAction.value = false
}

const completarCita = async (id: string) => {
  const { error } = await supabase
    .from('citas')
    .update({ estado: 'completada' })
    .eq('id', id)
  
  if (!error) fetchAgenda()
}

const cancelarCita = async (id: string) => {
  if (!confirm("¿Seguro que deseas cancelar este turno?")) return
  const { error } = await supabase
    .from('citas')
    .update({ estado: 'cancelada' })
    .eq('id', id)
  
  if (!error) fetchAgenda()
}

const fetchAgenda = async () => {
  if (!barberia.value) return
  loadingAgenda.value = true
  
  const hoy = new Date().toISOString().split('T')[0]
  
  const { data, error } = await supabase
    .from('citas')
    .select('*, perfiles!cliente_id(nombre), servicios(nombre)')
    .eq('barberia_id', barberia.value.id)
    .eq('barbero_id', userProfile.value.id)
    .gte('fecha_hora', `${hoy}T00:00:00`)
    .lte('fecha_hora', `${hoy}T23:59:59`)
    .order('fecha_hora', { ascending: true })

  if (!error && data) {
    citasAgendadas.value = data.filter(c => c.tipo === 'agendado')
    citasEspera.value = data.filter(c => c.tipo === 'espera')
  }
  loadingAgenda.value = false
}

const handleLogout = async () => {
  loading.value = true
  await supabase.auth.signOut()
  router.push('/')
  loading.value = false
}
</script>

<template>
  <div class="min-h-screen bg-brand-dark flex flex-col">
    <!-- Topbar -->
    <header class="bg-brand-surface border-b border-white/5 px-8 py-4 flex justify-between items-center">
      <div class="flex items-center gap-2">
        <Scissors class="text-brand-primary w-6 h-6" />
        <span class="font-bold text-xl">TuTurno <span class="text-white/30 font-normal">| Barbero</span></span>
      </div>
      <button @click="handleLogout" class="flex items-center gap-2 text-white/50 hover:text-white transition-colors cursor-pointer" :disabled="loading">
        <LogOut class="w-5 h-5" />
        <span>Salir</span>
      </button>
    </header>

    <!-- Main Content -->
    <main class="flex-1 max-w-7xl w-full mx-auto p-8">
      
      <!-- Estado: No Vinculado -->
      <div v-if="!barberia && !loading" class="animate-in fade-in slide-in-from-bottom-4 duration-500">
        <div class="mb-8">
          <h1 class="text-4xl font-black mb-2">Bienvenido, Barbero</h1>
          <p class="text-white/50 text-lg">Para comenzar a trabajar, selecciona la barbería a la que perteneces.</p>
        </div>

        <div v-if="loadingBarberias" class="text-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-brand-primary mx-auto mb-4"></div>
          <p class="text-white/50">Buscando barberías disponibles...</p>
        </div>

        <div v-else-if="barberiasDisponibles.length === 0" class="card p-12 text-center text-white/50 border-dashed border-2">
           <AlertCircle class="w-12 h-12 mx-auto mb-4 opacity-50" />
           <p class="text-lg font-bold text-white mb-2">No hay barberías registradas</p>
           <p>Dile a tu dueño que registre su barbería primero.</p>
        </div>

        <div v-else class="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          <div v-for="b in barberiasDisponibles" :key="b.id" class="card group hover:border-brand-primary/50 transition-all cursor-pointer flex flex-col justify-between" @click="vincularABarberia(b.id)">
            <div>
              <div class="w-full h-40 rounded-xl bg-white/5 mb-4 overflow-hidden border border-white/10 group-hover:border-brand-primary/20">
                <img v-if="b.foto_url" :src="b.foto_url" class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" />
                <div v-else class="w-full h-full flex items-center justify-center text-white/20">
                  <Scissors class="w-12 h-12" />
                </div>
              </div>
              <h3 class="text-xl font-bold mb-1 group-hover:text-brand-primary transition-colors">{{ b.nombre }}</h3>
              <p class="text-white/50 text-sm mb-4">{{ b.direccion }}</p>
            </div>
            <button class="btn-secondary w-full py-3 flex items-center justify-center gap-2">
              <UserPlus class="w-4 h-4" /> Unirme a este equipo
            </button>
          </div>
        </div>
      </div>

      <!-- Estado: Vinculado / Agenda -->
      <div v-if="barberia" class="animate-in fade-in duration-500">
        
        <!-- Mensaje de Espera si está Pendiente -->
        <div v-if="userProfile?.estado_vinculacion === 'pendiente'" class="card bg-brand-primary/10 border-brand-primary/20 p-8 text-center mb-8">
           <Clock class="w-16 h-16 text-brand-primary mx-auto mb-4 animate-pulse" />
           <h2 class="text-3xl font-black mb-2 text-white">Solicitud Enviada</h2>
           <p class="text-white/70 text-lg max-w-md mx-auto">
             Tu solicitud para unirte a <span class="text-brand-primary font-bold">{{ barberia.nombre }}</span> está pendiente de aprobación por el dueño.
           </p>
           <button @click="vincularABarberia('')" class="mt-6 text-white/30 hover:text-red-400 text-sm transition-colors cursor-pointer">Cancelar solicitud y elegir otra</button>
        </div>

        <div v-else-if="userProfile?.estado_vinculacion === 'aprobado'">
          <div class="flex justify-between items-end mb-8">
            <div>
              <h1 class="text-4xl font-black mb-2">Mi Agenda</h1>
              <p class="text-white/50">Gestionando turnos en <span class="text-brand-primary font-bold">{{ barberia.nombre }}</span></p>
            </div>
            <button @click="showEsperaModal = true" class="btn-primary flex items-center gap-2">
              <UserPlus class="w-5 h-5" /> Agregar Lista de Espera
            </button>
          </div>
          
          <div class="grid lg:grid-cols-2 gap-8">
            <!-- Columna: Agendados -->
            <div class="space-y-6">
              <div class="flex items-center gap-3 border-b border-white/5 pb-4">
                <div class="p-2 bg-brand-primary/10 rounded-lg text-brand-primary">
                  <Clock class="w-5 h-5" />
                </div>
                <h2 class="text-2xl font-bold">Agendados <span class="text-white/30 text-lg font-medium ml-2">{{ citasAgendadas.length }}</span></h2>
              </div>

              <div v-if="loadingAgenda" class="text-center py-10 text-white/50">Cargando citas...</div>
              <div v-else-if="citasAgendadas.length === 0" class="card p-8 text-center text-white/30 border-dashed border-2">
                No hay citas agendadas para hoy.
              </div>
              
              <div v-else class="space-y-4">
                <div v-for="cita in citasAgendadas" :key="cita.id" class="card flex items-center justify-between border-l-4 border-l-brand-primary group">
                  <div class="flex items-center gap-6">
                    <div class="text-center w-20">
                      <p class="text-2xl font-bold">{{ new Date(cita.fecha_hora).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }}</p>
                      <p class="text-[10px] text-brand-primary font-black uppercase tracking-wider">Turno Fijo</p>
                    </div>
                    <div>
                      <h3 class="text-lg font-bold">{{ cita.perfiles?.nombre || 'Cliente' }}</h3>
                      <p class="text-white/50 flex items-center gap-1 text-sm">
                        <Scissors class="w-3 h-3" /> {{ cita.servicios?.nombre || 'Servicio' }}
                      </p>
                    </div>
                  </div>
                  <div class="flex gap-2">
                    <button @click="cancelarCita(cita.id)" class="p-2 text-white/20 hover:text-red-400 transition-colors cursor-pointer" title="Cancelar">
                      <LogOut class="w-5 h-5 rotate-180" />
                    </button>
                    <button @click="completarCita(cita.id)" class="btn-primary text-xs py-2 px-4 flex items-center gap-2">
                      <CheckCircle class="w-4 h-4" /> Finalizar
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- Columna: Lista de Espera -->
            <div class="space-y-6">
              <div class="flex items-center gap-3 border-b border-white/5 pb-4">
                <div class="p-2 bg-white/5 rounded-lg text-white/50">
                  <Users class="w-5 h-5" />
                </div>
                <h2 class="text-2xl font-bold text-white/70">En Espera <span class="text-white/30 text-lg font-medium ml-2">{{ citasEspera.length }}</span></h2>
              </div>

              <div v-if="citasEspera.length === 0" class="card p-8 text-center text-white/30 border-dashed border-2">
                No hay clientes en espera.
              </div>

              <div v-else class="space-y-4">
                <div v-for="espera in citasEspera" :key="espera.id" class="card flex items-center justify-between border-l-4 border-l-white/20 bg-white/2">
                  <div class="flex items-center gap-6">
                    <div class="text-center w-20">
                      <p class="text-2xl font-bold opacity-30">#{{ citasEspera.indexOf(espera) + 1 }}</p>
                      <p class="text-[10px] text-white/30 font-black uppercase tracking-wider">En espera</p>
                    </div>
                    <div>
                      <h3 class="text-lg font-bold">{{ espera.nombre_cliente_manual || espera.perfiles?.nombre }}</h3>
                      <p class="text-white/50 flex items-center gap-1 text-sm">
                        <Scissors class="w-3 h-3" /> {{ espera.servicios?.nombre || 'Servicio' }}
                      </p>
                    </div>
                  </div>
                  <button @click="completarCita(espera.id)" class="btn-secondary text-xs py-2 px-4">Atender ahora</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>

    <!-- Modal: Agregar a Lista de Espera -->
    <div v-if="showEsperaModal" class="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div class="card w-full max-w-md animate-in zoom-in-95 duration-300">
        <h2 class="text-2xl font-bold mb-6 flex items-center gap-2">
          <Users class="text-brand-primary" /> Agregar Cliente
        </h2>
        
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-white/50 mb-1">Nombre del Cliente</label>
            <input v-model="newEspera.nombre_cliente" type="text" class="input-field" placeholder="Ej. Juan Pérez" />
          </div>
          
          <div>
            <label class="block text-sm font-medium text-white/50 mb-1">Servicio</label>
            <select v-model="newEspera.servicio_id" class="input-field">
              <option value="">Selecciona un servicio</option>
              <option v-for="s in servicios" :key="s.id" :value="s.id">
                {{ s.nombre }} - ${{ s.precio }}
              </option>
            </select>
          </div>

          <div class="flex gap-3 mt-8">
            <button @click="showEsperaModal = false" class="btn-secondary flex-1 py-3">Cancelar</button>
            <button @click="agregarAListaEspera" :disabled="processingAction" class="btn-primary flex-1 py-3">
              {{ processingAction ? 'Agregando...' : 'Confirmar' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
