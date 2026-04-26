<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { LogOut, Scissors, LayoutDashboard, Briefcase, Users, Plus, Trash2, Edit2, UserCheck, UserX, Clock } from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'

const router = useRouter()
const notify = useNotifications()
const loading = ref(false)
const activeTab = ref('resumen')
const ownerName = ref('')
const barberia = ref<any>(null)
const loadingBarberia = ref(true)

// Estados para Barbería
const showBarberiaModal = ref(false)
const newBarberia = ref({ nombre: '', direccion: '', foto_url: '' })

// Estados para Servicios
const servicios = ref<any[]>([])
const loadingServicios = ref(false)
const showServicioModal = ref(false)
const newServicio = ref({ nombre: '', precio: '', duracion_minutos: 30 })

// Estados para Equipo
const barberosActivos = ref<any[]>([])
const solicitudesPendientes = ref<any[]>([])
const loadingEquipo = ref(false)

onMounted(async () => {
  const { data: { session } } = await supabase.auth.getSession()
  if (session?.user?.user_metadata?.nombre) {
    ownerName.value = session.user.user_metadata.nombre
  }
  await fetchBarberia()
})

const fetchBarberia = async () => {
  loadingBarberia.value = true
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return

  const { data, error } = await supabase
    .from('barberias')
    .select('*')
    .eq('dueno_id', session.user.id)
    .maybeSingle()

  if (data) {
    barberia.value = data
    fetchServicios()
    fetchBarberos()
  } else {
    showBarberiaModal.value = true
  }
  loadingBarberia.value = false
}

const createBarberia = async () => {
  if (!newBarberia.value.nombre || !newBarberia.value.direccion) return
  
  loading.value = true
  const { data: { session } } = await supabase.auth.getSession()
  
  const { data, error } = await supabase
    .from('barberias')
    .insert([{
      nombre: newBarberia.value.nombre,
      direccion: newBarberia.value.direccion,
      foto_url: newBarberia.value.foto_url,
      dueno_id: session?.user.id
    }])
    .select()
    .single()

  if (!error && data) {
    barberia.value = data
    showBarberiaModal.value = false
    fetchServicios()
    notify.success("¡Barbería creada con éxito!")
  } else {
    console.error("Error Supabase:", error)
    notify.error("Error al crear la barbería: " + (error?.message || "Error desconocido"))
  }
  loading.value = false
}

const fetchBarberos = async () => {
  if (!barberia.value) return
  loadingEquipo.value = true
  
  const { data, error } = await supabase
    .from('perfiles')
    .select('*')
    .eq('barberia_id', barberia.value.id)
    .eq('rol', 'barbero')

  if (!error && data) {
    barberosActivos.value = data.filter(b => b.estado_vinculacion === 'aprobado')
    solicitudesPendientes.value = data.filter(b => b.estado_vinculacion === 'pendiente')
  }
  loadingEquipo.value = false
}

const gestionarSolicitud = async (barberoId: string, nuevoEstado: 'aprobado' | 'ninguno') => {
  const { error } = await supabase
    .from('perfiles')
    .update({ 
      estado_vinculacion: nuevoEstado,
      barberia_id: nuevoEstado === 'aprobado' ? barberia.value.id : null 
    })
    .eq('id', barberoId)

  if (!error) {
    fetchBarberos()
    notify.success(nuevoEstado === 'aprobado' ? "Barbero aprobado" : "Solicitud rechazada")
  } else {
    notify.error("Error al procesar la solicitud")
  }
}

const handleLogout = async () => {
  loading.value = true
  await supabase.auth.signOut()
  router.push('/')
  loading.value = false
}

// Lógica de Servicios
const fetchServicios = async () => {
  if (!barberia.value) return
  loadingServicios.value = true
  const { data, error } = await supabase
    .from('servicios')
    .select('*')
    .eq('barberia_id', barberia.value.id)
    .order('created_at', { ascending: false })
  
  if (!error && data) servicios.value = data
  loadingServicios.value = false
}

const saveServicio = async () => {
  if (!newServicio.value.nombre || !newServicio.value.precio || !barberia.value) return
  
  const { error } = await supabase.from('servicios').insert([{
    nombre: newServicio.value.nombre,
    precio: parseFloat(newServicio.value.precio),
    duracion_minutos: newServicio.value.duracion_minutos,
    barberia_id: barberia.value.id
  }])

  if (!error) {
    showServicioModal.value = false
    newServicio.value = { nombre: '', precio: '', duracion_minutos: 30 }
    fetchServicios()
  } else {
    alert("Error al crear el servicio.")
  }
}

const deleteServicio = async (id: string) => {
  if (!confirm('¿Estás seguro de eliminar este servicio?')) return
  const { error } = await supabase.from('servicios').delete().eq('id', id)
  if (!error) fetchServicios()
}
</script>

<template>
  <div class="min-h-screen bg-brand-dark flex flex-col md:flex-row">
    <!-- Sidebar -->
    <aside class="w-full md:w-64 bg-brand-surface border-r border-white/5 flex flex-col">
      <div class="p-6 border-b border-white/5 flex items-center gap-2">
        <Scissors class="text-brand-primary w-6 h-6" />
        <span class="font-bold text-xl tracking-tight">TuTurno</span>
      </div>
      
      <nav class="flex-1 p-4 space-y-2">
        <button 
          @click="activeTab = 'resumen'"
          :class="['w-full flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-colors cursor-pointer', activeTab === 'resumen' ? 'bg-brand-primary text-black' : 'text-white/50 hover:bg-white/5 hover:text-white']"
        >
          <LayoutDashboard class="w-5 h-5" /> Resumen
        </button>
        <button 
          @click="activeTab = 'servicios'"
          :class="['w-full flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-colors cursor-pointer', activeTab === 'servicios' ? 'bg-brand-primary text-black' : 'text-white/50 hover:bg-white/5 hover:text-white']"
        >
          <Briefcase class="w-5 h-5" /> Servicios
        </button>
        <button 
          @click="activeTab = 'equipo'"
          :class="['w-full flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-colors cursor-pointer', activeTab === 'equipo' ? 'bg-brand-primary text-black' : 'text-white/50 hover:bg-white/5 hover:text-white']"
        >
          <Users class="w-5 h-5" /> Equipo
        </button>
      </nav>

      <div class="p-4 border-t border-white/5">
        <button @click="handleLogout" class="w-full flex items-center gap-3 px-4 py-3 text-red-400 hover:bg-red-400/10 rounded-lg transition-colors font-medium cursor-pointer" :disabled="loading">
          <LogOut class="w-5 h-5" /> Salir
        </button>
      </div>
    </aside>

    <!-- Main Content -->
    <main class="flex-1 p-8 overflow-y-auto">
      
      <!-- Top header -->
      <div class="flex justify-between items-end mb-8">
        <div>
          <h1 class="text-3xl font-black">Hola, {{ ownerName || 'Dueño' }}</h1>
          <p class="text-white/50 capitalize">{{ barberia?.nombre || 'Gestionando tu negocio' }}</p>
        </div>
      </div>

      <!-- Pantalla de Carga de Barbería -->
      <div v-if="loadingBarberia" class="flex flex-col items-center justify-center h-64 text-white/50">
        <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-brand-primary mb-4"></div>
        <p>Cargando información del negocio...</p>
      </div>

      <!-- Tab: Resumen -->
      <div v-if="activeTab === 'resumen' && !loadingBarberia" class="space-y-8 animate-in fade-in duration-500">
        <div class="grid md:grid-cols-3 gap-6">
          <div class="card bg-gradient-to-br from-brand-surface to-brand-dark">
            <p class="text-white/50 text-sm mb-1">Servicios Activos</p>
            <p class="text-4xl font-black text-brand-primary">{{ servicios.length }}</p>
          </div>
          <div class="card bg-gradient-to-br from-brand-surface to-brand-dark">
            <p class="text-white/50 text-sm mb-1">Barberos Registrados</p>
            <p class="text-4xl font-black text-brand-primary">{{ barberosActivos.length }}</p>
          </div>
          <div class="card bg-gradient-to-br from-brand-surface to-brand-dark">
            <p class="text-white/50 text-sm mb-1">Citas Hoy</p>
            <p class="text-4xl font-black text-brand-primary">0</p>
          </div>
        </div>
        
        <div class="card p-8 text-center text-white/50 border-dashed border-2">
           <LayoutDashboard class="w-12 h-12 mx-auto mb-4 opacity-50" />
           <p>Pronto verás aquí gráficos y próximas citas.</p>
        </div>
      </div>

      <!-- Tab: Servicios -->
      <div v-if="activeTab === 'servicios' && !loadingBarberia" class="space-y-6 animate-in fade-in duration-500">
        <div class="flex justify-between items-center">
          <h2 class="text-2xl font-bold">Catálogo de Servicios</h2>
          <button @click="showServicioModal = true" class="btn-primary py-2 px-4 flex items-center gap-2">
            <Plus class="w-4 h-4" /> Nuevo Servicio
          </button>
        </div>

        <div v-if="loadingServicios" class="text-center py-10 text-white/50">Cargando servicios...</div>
        
        <div v-else-if="servicios.length === 0" class="card p-12 text-center text-white/50">
           <Briefcase class="w-12 h-12 mx-auto mb-4 opacity-50" />
           <p class="mb-4">No tienes ningún servicio creado todavía.</p>
           <button @click="showServicioModal = true" class="btn-secondary">Crear mi primer servicio</button>
        </div>

        <div v-else class="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          <div v-for="servicio in servicios" :key="servicio.id" class="card group relative overflow-hidden flex flex-col justify-between">
            <div>
              <div class="flex justify-between items-start mb-2">
                <h3 class="text-xl font-bold">{{ servicio.nombre }}</h3>
                <span class="text-brand-primary font-black text-lg">${{ servicio.precio }}</span>
              </div>
              <p class="text-white/50 text-sm flex items-center gap-1 mb-4">
                <span class="inline-block w-2 h-2 rounded-full bg-white/20"></span>
                {{ servicio.duracion_minutos }} minutos
              </p>
            </div>
            
            <div class="flex gap-2 pt-4 border-t border-white/5">
               <button class="flex-1 py-2 bg-white/5 hover:bg-white/10 rounded-lg text-sm font-medium transition-colors cursor-pointer flex items-center justify-center gap-2">
                 <Edit2 class="w-4 h-4" /> Editar
               </button>
               <button @click="deleteServicio(servicio.id)" class="py-2 px-3 text-red-400 bg-red-400/5 hover:bg-red-400/10 rounded-lg transition-colors cursor-pointer">
                 <Trash2 class="w-4 h-4" />
               </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab: Equipo -->
      <div v-if="activeTab === 'equipo' && !loadingBarberia" class="space-y-12 animate-in fade-in duration-500">
        
        <!-- Sección: Solicitudes Pendientes -->
        <div v-if="solicitudesPendientes.length > 0" class="space-y-6">
          <div class="flex items-center gap-3">
             <div class="p-2 bg-yellow-500/10 rounded-lg text-yellow-500">
                <Clock class="w-5 h-5" />
             </div>
             <h2 class="text-2xl font-bold">Solicitudes por Aprobar</h2>
          </div>
          
          <div class="grid md:grid-cols-2 gap-4">
             <div v-for="solicitud in solicitudesPendientes" :key="solicitud.id" class="card flex items-center justify-between border-2 border-yellow-500/20 bg-yellow-500/5">
                <div class="flex items-center gap-4">
                   <div class="w-12 h-12 rounded-full bg-yellow-500/20 flex items-center justify-center">
                      <Users class="text-yellow-500 w-6 h-6" />
                   </div>
                   <div>
                      <h3 class="font-bold">{{ solicitud.nombre }}</h3>
                      <p class="text-white/40 text-xs">{{ solicitud.email }}</p>
                   </div>
                </div>
                <div class="flex gap-2">
                   <button @click="gestionarSolicitud(solicitud.id, 'ninguno')" class="p-2 text-red-400 hover:bg-red-400/10 rounded-lg transition-colors">
                      <UserX class="w-5 h-5" />
                   </button>
                   <button @click="gestionarSolicitud(solicitud.id, 'aprobado')" class="p-2 text-green-400 bg-green-400/10 hover:bg-green-400/20 rounded-lg transition-colors flex items-center gap-2 px-4">
                      <UserCheck class="w-5 h-5" />
                      <span class="font-bold text-sm">Aprobar</span>
                   </button>
                </div>
             </div>
          </div>
        </div>

        <!-- Sección: Equipo Activo -->
        <div class="space-y-6">
          <div class="flex justify-between items-center">
            <h2 class="text-2xl font-bold">Tu Equipo de Barberos</h2>
          </div>

          <div v-if="loadingEquipo" class="text-center py-10 text-white/50">Cargando equipo...</div>

          <div v-else-if="barberosActivos.length === 0" class="card p-12 text-center text-white/50 border-dashed border-2">
             <Users class="w-12 h-12 mx-auto mb-4 opacity-50" />
             <p class="mb-2 font-medium text-white">No hay barberos activos aún.</p>
             <p class="text-sm">Cuando apruebes una solicitud, aparecerán aquí.</p>
          </div>

          <div v-else class="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div v-for="barbero in barberosActivos" :key="barbero.id" class="card flex items-center gap-4 group">
              <div class="w-16 h-16 rounded-full bg-brand-primary/10 flex items-center justify-center border border-brand-primary/20 overflow-hidden">
                <img v-if="barbero.foto_url" :src="barbero.foto_url" class="w-full h-full object-cover" />
                <Users v-else class="text-brand-primary w-8 h-8" />
              </div>
              <div>
                <h3 class="font-bold text-lg text-white">{{ barbero.nombre }}</h3>
                <p class="text-white/50 text-sm">{{ barbero.email }}</p>
                <div class="mt-2 flex items-center gap-2">
                  <span class="px-2 py-0.5 bg-green-500/10 text-green-500 text-xs rounded-full border border-green-500/20 font-bold">Aprobado</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

    </main>

    <!-- Modal: Nuevo Servicio -->
    <div v-if="showServicioModal" class="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
       <div class="card w-full max-w-md bg-brand-dark border-white/10 shadow-2xl animate-in zoom-in-95 duration-200">
         <h2 class="text-2xl font-bold mb-6">Nuevo Servicio</h2>
         <form @submit.prevent="saveServicio" class="space-y-4">
           <div>
             <label class="block text-sm font-medium text-white/70 mb-1">Nombre del corte/servicio</label>
             <input v-model="newServicio.nombre" type="text" required class="input-field" placeholder="Ej: Corte Clásico" />
           </div>
           <div class="grid grid-cols-2 gap-4">
             <div>
               <label class="block text-sm font-medium text-white/70 mb-1">Precio ($)</label>
               <input v-model="newServicio.precio" type="number" step="0.01" required class="input-field" placeholder="0.00" />
             </div>
             <div>
               <label class="block text-sm font-medium text-white/70 mb-1">Duración (Minutos)</label>
               <input v-model="newServicio.duracion_minutos" type="number" required class="input-field" placeholder="30" />
             </div>
           </div>
           
           <div class="flex gap-3 pt-4">
             <button type="button" @click="showServicioModal = false" class="btn-secondary flex-1">Cancelar</button>
             <button type="submit" class="btn-primary flex-1">Guardar</button>
           </div>
         </form>
       </div>
    </div>

    <!-- Modal: Crear Barbería -->
    <div v-if="showBarberiaModal" class="fixed inset-0 bg-black/90 backdrop-blur-md z-[60] flex items-center justify-center p-4">
       <div class="card w-full max-w-lg bg-brand-dark border-white/10 shadow-2xl animate-in zoom-in-95 duration-300">
         <div class="flex items-center gap-3 mb-6">
            <div class="p-3 bg-brand-primary/10 rounded-xl">
              <Scissors class="text-brand-primary w-8 h-8" />
            </div>
            <div>
              <h2 class="text-2xl font-bold">Configura tu Barbería</h2>
              <p class="text-white/50 text-sm">Antes de empezar, necesitamos los datos de tu negocio.</p>
            </div>
         </div>

         <form @submit.prevent="createBarberia" class="space-y-4">
           <div>
             <label class="block text-sm font-medium text-white/70 mb-1">Nombre de la Barbería</label>
             <input v-model="newBarberia.nombre" type="text" required class="input-field" placeholder="Ej: Elite Cuts Studio" />
           </div>
           <div>
             <label class="block text-sm font-medium text-white/70 mb-1">Dirección</label>
             <input v-model="newBarberia.direccion" type="text" required class="input-field" placeholder="Ej: Calle 10 # 5-20, Centro" />
           </div>
           <div>
             <label class="block text-sm font-medium text-white/70 mb-1">URL de Foto (Opcional)</label>
             <input v-model="newBarberia.foto_url" type="url" class="input-field" placeholder="https://ejemplo.com/foto.jpg" />
           </div>
           
           <div class="pt-6">
             <button type="submit" class="btn-primary w-full py-4 text-lg" :disabled="loading">
               {{ loading ? 'Creando...' : 'Crear mi Barbería' }}
             </button>
           </div>
         </form>
       </div>
    </div>

  </div>
</template>
