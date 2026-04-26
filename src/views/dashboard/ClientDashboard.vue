<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { LogOut, Calendar, Scissors, History, MapPin, Search, ChevronRight, Check, Star } from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'

const router = useRouter()
const notify = useNotifications()
const loading = ref(false)
const userProfile = ref<any>(null)

// Estados de Citas
const proximaCita = ref<any>(null)
const historialCitas = ref<any[]>([])
const loadingCitas = ref(false)

// Estados de Reserva (Flow de 4 pasos)
const showReservaModal = ref(false)
const bookingStep = ref(1)
const bookingData = ref({
  barberia: null as any,
  servicio: null as any,
  barbero: null as any,
  fecha_hora: ''
})

const barberias = ref<any[]>([])
const servicios = ref<any[]>([])
const barberos = ref<any[]>([])
const horariosDisponibles = ref<string[]>([])

onMounted(async () => {
  await fetchProfile()
  await fetchCitas()
})

const fetchProfile = async () => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return
  const { data } = await supabase.from('perfiles').select('*').eq('id', session.user.id).single()
  userProfile.value = data
}

const fetchCitas = async () => {
  loadingCitas.value = true
  const { data: { session } } = await supabase.auth.getSession()
  
  // Próxima Cita
  const { data: next } = await supabase
    .from('citas')
    .select('*, barberias(nombre, direccion), perfiles!barbero_id(nombre), servicios(nombre)')
    .eq('cliente_id', session?.user.id)
    .gte('fecha_hora', new Date().toISOString())
    .in('estado', ['pendiente', 'confirmada'])
    .order('fecha_hora', { ascending: true })
    .limit(1)
    .maybeSingle()
  
  proximaCita.value = next

  // Historial
  const { data: history } = await supabase
    .from('citas')
    .select('*, barberias(nombre), servicios(nombre)')
    .eq('cliente_id', session?.user.id)
    .lt('fecha_hora', new Date().toISOString())
    .order('fecha_hora', { ascending: false })
  
  historialCitas.value = history || []
  loadingCitas.value = false
}

// Lógica de Reserva
const startBooking = async () => {
  showReservaModal.value = true
  bookingStep.value = 1
  const { data } = await supabase.from('barberias').select('*')
  barberias.value = data || []
}

const selectBarberia = async (b: any) => {
  bookingData.value.barberia = b
  bookingStep.value = 2
  const { data } = await supabase.from('servicios').select('*').eq('barberia_id', b.id)
  servicios.value = data || []
}

const selectServicio = async (s: any) => {
  bookingData.value.servicio = s
  bookingStep.value = 3
  const { data } = await supabase.from('perfiles').select('*').eq('barberia_id', bookingData.value.barberia.id).eq('rol', 'barbero')
  barberos.value = data || []
}

const selectBarbero = async (b: any) => {
  bookingData.value.barbero = b
  bookingStep.value = 4
  // Generar horarios ficticios por ahora (luego conectar con disponibilidad real)
  horariosDisponibles.value = ['09:00', '10:00', '11:00', '14:00', '15:00', '16:00']
}

const confirmReserva = async (hora: string) => {
  loading.value = true
  const fecha = new Date()
  fecha.setHours(parseInt(hora.split(':')[0]), parseInt(hora.split(':')[1]), 0, 0)
  
  const { error } = await supabase.from('citas').insert([{
    barberia_id: bookingData.value.barberia.id,
    cliente_id: userProfile.value.id,
    barbero_id: bookingData.value.barbero.id,
    servicio_id: bookingData.value.servicio.id,
    fecha_hora: fecha.toISOString(),
    tipo: 'agendado',
    estado: 'pendiente',
    precio_final: bookingData.value.servicio.precio
  }])

  if (!error) {
    showReservaModal.value = false
    bookingStep.value = 1
    fetchCitas()
    notify.success("¡Cita agendada con éxito!")
  } else {
    console.error("Error Supabase:", error)
    notify.error("Error al agendar la cita: " + (error?.message || "Error desconocido"))
  }
  loading.value = false
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
        <span class="font-bold text-xl">TuTurno <span class="text-white/30 font-normal">| Cliente</span></span>
      </div>
      <button @click="handleLogout" class="flex items-center gap-2 text-white/50 hover:text-white transition-colors cursor-pointer" :disabled="loading">
        <LogOut class="w-5 h-5" />
        <span>Salir</span>
      </button>
    </header>

    <!-- Main Content -->
    <main class="flex-1 max-w-7xl w-full mx-auto p-8">
      
      <div class="flex justify-between items-end mb-8">
        <div>
          <h1 class="text-4xl font-black mb-2">Hola, {{ userProfile?.nombre || 'Cliente' }}!</h1>
          <p class="text-white/50 text-lg font-medium">¿Listo para tu próximo estilo?</p>
        </div>
        <button @click="startBooking" class="btn-primary flex items-center gap-2 py-4 px-6 shadow-lg shadow-brand-primary/20">
          <Calendar class="w-5 h-5" />
          Nueva Reserva
        </button>
      </div>

      <div class="grid lg:grid-cols-3 gap-8">
        <div class="lg:col-span-2 space-y-6">
          <h2 class="text-2xl font-bold flex items-center gap-2">
            <Calendar class="w-6 h-6 text-brand-primary" />
            Próxima Cita
          </h2>
          
          <div v-if="loadingCitas" class="card h-48 flex items-center justify-center">
            <div class="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-primary"></div>
          </div>

          <div v-else-if="!proximaCita" class="card p-12 text-center text-white/30 border-dashed border-2">
             <Calendar class="w-12 h-12 mx-auto mb-4 opacity-50" />
             <p class="text-lg font-medium">No tienes ninguna cita agendada.</p>
             <button @click="startBooking" class="text-brand-primary font-bold mt-2 hover:underline cursor-pointer">¡Agenda tu primera cita ahora!</button>
          </div>

          <div v-else class="card bg-gradient-to-br from-brand-surface to-brand-dark border-brand-primary/20 relative overflow-hidden group">
             <div class="absolute top-0 right-0 p-8 opacity-5 group-hover:scale-110 transition-transform duration-700">
                <Scissors class="w-32 h-32" />
             </div>
             
             <div class="relative z-10 flex flex-col md:flex-row gap-6 items-start md:items-center justify-between">
                <div>
                  <span class="inline-block px-3 py-1 bg-brand-primary/20 text-brand-primary rounded-full text-xs font-bold uppercase tracking-wider mb-4 border border-brand-primary/30">
                    {{ proximaCita.estado }}
                  </span>
                  <h3 class="text-3xl font-black mb-1 text-white">{{ proximaCita.servicios?.nombre }}</h3>
                  <div class="space-y-1">
                    <p class="text-white/70 flex items-center gap-2 font-medium">
                      <MapPin class="w-4 h-4 text-brand-primary" /> {{ proximaCita.barberias?.nombre }}
                    </p>
                    <p class="text-white/40 text-sm pl-6">{{ proximaCita.barberias?.direccion }}</p>
                    <p class="text-white/70 flex items-center gap-2 font-medium pt-2">
                      <Scissors class="w-4 h-4 text-brand-primary" /> Barbero: {{ proximaCita.perfiles?.nombre }}
                    </p>
                  </div>
                </div>
                
                <div class="text-left md:text-right bg-white/5 backdrop-blur-md p-6 rounded-2xl border border-white/10 w-full md:w-auto">
                  <p class="text-white/50 text-xs font-black uppercase tracking-widest mb-1">Fecha y Hora</p>
                  <p class="text-3xl font-black text-brand-primary capitalize">
                    {{ new Date(proximaCita.fecha_hora).toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' }) }}
                  </p>
                  <p class="text-xl font-bold text-white/90">
                    {{ new Date(proximaCita.fecha_hora).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }}
                  </p>
                </div>
             </div>
             
             <div class="relative z-10 mt-8 flex gap-3">
               <button class="btn-secondary text-sm py-3 px-6">Reprogramar</button>
               <button class="px-6 py-3 text-red-400 hover:bg-red-400/10 rounded-lg text-sm font-bold transition-colors cursor-pointer">Cancelar Turno</button>
             </div>
          </div>
        </div>

        <div class="space-y-6">
          <h2 class="text-2xl font-bold flex items-center gap-2 text-white/70">
            <History class="w-6 h-6" />
            Historial
          </h2>
          <div class="card space-y-2 p-4">
             <div v-if="historialCitas.length === 0" class="text-center py-8 text-white/30 text-sm">
                No hay citas pasadas.
             </div>
             <div v-for="h in historialCitas" :key="h.id" class="flex justify-between items-center p-3 hover:bg-white/5 rounded-xl transition-colors group cursor-pointer">
               <div>
                 <p class="font-bold text-white/90">{{ h.servicios?.nombre }}</p>
                 <p class="text-xs text-white/40 font-medium">
                   {{ new Date(h.fecha_hora).toLocaleDateString([], { day: 'numeric', month: 'short' }) }} • {{ h.barberias?.nombre }}
                 </p>
               </div>
               <div class="text-right">
                 <span class="text-[10px] font-black uppercase text-white/30 block mb-1">Completada</span>
                 <div class="flex gap-0.5">
                   <Star v-for="i in 5" :key="i" class="w-3 h-3 text-brand-primary/20" />
                 </div>
               </div>
             </div>
          </div>
        </div>
      </div>
    </main>

    <!-- Modal: Nueva Reserva (Flow 4 Pasos) -->
    <div v-if="showReservaModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-50 flex items-center justify-center p-4">
       <div class="w-full max-w-2xl animate-in zoom-in-95 duration-300">
         
         <!-- Header Modal -->
         <div class="flex justify-between items-center mb-8">
            <div>
              <p class="text-brand-primary font-black uppercase tracking-[0.2em] text-xs mb-1">Paso {{ bookingStep }} de 4</p>
              <h2 class="text-4xl font-black text-white">
                <span v-if="bookingStep === 1">Busca tu Barbería</span>
                <span v-if="bookingStep === 2">Elige el Servicio</span>
                <span v-if="bookingStep === 3">Tu Barbero de confianza</span>
                <span v-if="bookingStep === 4">Confirma tu cita</span>
              </h2>
            </div>
            <button @click="showReservaModal = false" class="p-4 bg-white/5 hover:bg-white/10 rounded-full transition-colors cursor-pointer text-white/50">
              <LogOut class="w-6 h-6 rotate-90" />
            </button>
         </div>

         <!-- Paso 1: Barberías -->
         <div v-if="bookingStep === 1" class="grid md:grid-cols-2 gap-4 max-h-[60vh] overflow-y-auto pr-2">
            <div v-for="b in barberias" :key="b.id" @click="selectBarberia(b)" class="card group hover:border-brand-primary/50 cursor-pointer transition-all">
               <div class="flex items-center gap-4">
                  <div class="w-16 h-16 rounded-xl bg-white/5 flex items-center justify-center border border-white/10 overflow-hidden">
                    <img v-if="b.foto_url" :src="b.foto_url" class="w-full h-full object-cover" />
                    <Scissors v-else class="text-white/20 w-8 h-8" />
                  </div>
                  <div>
                    <h3 class="font-bold text-lg group-hover:text-brand-primary">{{ b.nombre }}</h3>
                    <p class="text-white/50 text-sm">{{ b.direccion }}</p>
                  </div>
               </div>
            </div>
         </div>

         <!-- Paso 2: Servicios -->
         <div v-if="bookingStep === 2" class="grid md:grid-cols-2 gap-4">
            <div v-for="s in servicios" :key="s.id" @click="selectServicio(s)" class="card group hover:border-brand-primary/50 cursor-pointer transition-all flex justify-between items-center">
               <div>
                  <h3 class="font-bold text-lg group-hover:text-brand-primary text-white">{{ s.nombre }}</h3>
                  <p class="text-white/50 text-sm">{{ s.duracion_minutos }} min</p>
               </div>
               <span class="text-brand-primary font-black text-xl">${{ s.precio }}</span>
            </div>
            <button @click="bookingStep = 1" class="md:col-span-2 text-white/50 hover:text-white text-sm mt-4 cursor-pointer text-left">← Volver a barberías</button>
         </div>

         <!-- Paso 3: Barberos -->
         <div v-if="bookingStep === 3" class="grid md:grid-cols-2 gap-4">
            <div v-for="b in barberos" :key="b.id" @click="selectBarbero(b)" class="card group hover:border-brand-primary/50 cursor-pointer transition-all flex items-center gap-4">
               <div class="w-12 h-12 rounded-full bg-brand-primary/10 flex items-center justify-center border border-brand-primary/20 overflow-hidden">
                  <img v-if="b.foto_url" :src="b.foto_url" class="w-full h-full object-cover rounded-full" />
                  <Scissors v-else class="text-brand-primary w-6 h-6" />
               </div>
               <h3 class="font-bold text-lg group-hover:text-brand-primary text-white">{{ b.nombre }}</h3>
            </div>
            <button @click="bookingStep = 2" class="md:col-span-2 text-white/50 hover:text-white text-sm mt-4 cursor-pointer text-left">← Volver a servicios</button>
         </div>

         <!-- Paso 4: Horarios -->
         <div v-if="bookingStep === 4" class="space-y-6">
            <div class="bg-white/5 p-6 rounded-2xl border border-white/10 space-y-3">
               <div class="flex justify-between">
                  <span class="text-white/50">Barbería:</span>
                  <span class="font-bold text-white">{{ bookingData.barberia?.nombre }}</span>
               </div>
               <div class="flex justify-between">
                  <span class="text-white/50">Servicio:</span>
                  <span class="font-bold text-brand-primary">{{ bookingData.servicio?.nombre }}</span>
               </div>
               <div class="flex justify-between">
                  <span class="text-white/50">Barbero:</span>
                  <span class="font-bold text-white">{{ bookingData.barbero?.nombre }}</span>
               </div>
            </div>

            <div class="grid grid-cols-3 md:grid-cols-6 gap-3">
               <button v-for="hora in horariosDisponibles" :key="hora" @click="confirmReserva(hora)" class="py-3 bg-white/5 hover:bg-brand-primary hover:text-black rounded-xl font-bold transition-all cursor-pointer text-white">
                  {{ hora }}
               </button>
            </div>
            <button @click="bookingStep = 3" class="w-full text-white/50 hover:text-white text-sm mt-4 cursor-pointer text-center">← Volver a seleccionar barbero</button>
         </div>

       </div>
    </div>
  </div>
</template>
