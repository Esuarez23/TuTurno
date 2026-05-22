<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { LogOut, Scissors, Clock, Check, Search, UserPlus, Users, MapPin, Calendar, DollarSign, Zap, History, X } from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'
import { useConfirm } from '../../composables/useConfirm'
import Tooltip from '../../components/Tooltip.vue'

const router = useRouter()
const notify = useNotifications()
const { confirm } = useConfirm()
const loading = ref(true)

const getLocalDateString = (date: Date = new Date()) => {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

const getTimezoneOffsetString = () => {
  const offsetMinutes = new Date().getTimezoneOffset()
  const sign = offsetMinutes > 0 ? '-' : '+'
  const absMinutes = Math.abs(offsetMinutes)
  const hours = String(Math.floor(absMinutes / 60)).padStart(2, '0')
  const minutes = String(absMinutes % 60).padStart(2, '0')
  return `${sign}${hours}:${minutes}`
}

const activeTab = ref('agenda') // 'agenda' o 'historial'
const userProfile = ref<any>(null)
const barberia = ref<any>(null)
const barberiasDisponibles = ref<any[]>([])

// Agenda
const citasAgendadas = ref<any[]>([])
const citasEspera = ref<any[]>([])
const servicios = ref<any[]>([])

// Historial y Búsqueda
const historialCitas = ref<any[]>([])
const filtroHistorial = ref('mes') // 'hoy', 'semana', 'mes'
const searchQuery = ref('')
const selectedServicio = ref('')
const loadingHistorial = ref(false)

// Finanzas
const gananciasHoy = ref(0)
const serviciosMes = ref(0)

const showEsperaModal = ref(false)
const newEspera = ref({ nombre_cliente: '', servicio_id: '' })
const processingAction = ref(false)
let subscription: any = null

onMounted(async () => {
  await fetchInitialData()
  setupRealtime()
})

onUnmounted(() => { if (subscription) supabase.removeChannel(subscription) })

const fetchInitialData = async () => {
  loading.value = true
  try {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) { router.push('/'); return }

    const { data: profile } = await supabase.from('perfiles').select('*').eq('id', session.user.id).maybeSingle()
    if (profile) {
      userProfile.value = profile
      if (profile.barberia_id) {
        const { data: bData } = await supabase.from('barberias').select('*').eq('id', profile.barberia_id).maybeSingle()
        barberia.value = bData
        await Promise.all([fetchAgenda(), fetchServicios(), fetchStats(), fetchHistorial()])
      } else {
        await fetchBarberiasDisponibles()
      }
    }
  } catch (err) {
    console.error(err)
  } finally {
    loading.value = false
  }
}

const fetchStats = async () => {
  if (!userProfile.value) return
  const hoy = getLocalDateString()
  const offset = getTimezoneOffsetString()
  const { data: citasHoy } = await supabase.from('citas').select('*, servicios(precio)').eq('barbero_id', userProfile.value.id).eq('estado', 'completada').gte('fecha_hora', hoy + 'T00:00:00' + offset)
  const { data: citasMes } = await supabase.from('citas').select('id').eq('barbero_id', userProfile.value.id).eq('estado', 'completada').gte('fecha_hora', new Date(new Date().setDate(1)).toISOString())
  
  if (citasHoy) {
    const totalHoy = citasHoy.reduce((acc, c) => acc + (Number(c.servicios?.precio) || 0), 0)
    const factor = userProfile.value.modelo_pago === 'porcentaje' ? (userProfile.value.pago_valor || 50) / 100 : 1
    gananciasHoy.value = totalHoy * factor
  }
  serviciosMes.value = citasMes?.length || 0
}

const fetchAgenda = async () => {
  if (!userProfile.value) return
  const hoy = getLocalDateString()
  const offset = getTimezoneOffsetString()
  const { data } = await supabase
    .from('citas')
    .select('*, servicios(nombre, precio), cliente:perfiles!cliente_id(nombre)')
    .eq('barbero_id', userProfile.value.id)
    .eq('estado', 'confirmada')
    .gte('fecha_hora', hoy + 'T00:00:00' + offset)
    .lte('fecha_hora', hoy + 'T23:59:59' + offset)
    .order('fecha_hora', { ascending: true })
    
  if (data) {
    citasAgendadas.value = data.filter(c => c.tipo === 'agendado')
    citasEspera.value = data.filter(c => c.tipo === 'espera')
  }
}

const fetchHistorial = async () => {
  if (!userProfile.value) return
  loadingHistorial.value = true
  let query = supabase.from('citas').select('*, servicios(nombre, precio)').eq('barbero_id', userProfile.value.id).eq('estado', 'completada').order('fecha_hora', { ascending: false })
  
  const ahora = new Date()
  if (filtroHistorial.value === 'hoy') {
    const hoy = getLocalDateString(ahora)
    const offset = getTimezoneOffsetString()
    query = query.gte('fecha_hora', hoy + 'T00:00:00' + offset)
  } else if (filtroHistorial.value === 'semana') {
    const haceUnaSemana = new Date(ahora.getTime() - 7 * 24 * 60 * 60 * 1000)
    query = query.gte('fecha_hora', haceUnaSemana.toISOString())
  } else if (filtroHistorial.value === 'mes') {
    const inicioMes = new Date(ahora.getFullYear(), ahora.getMonth(), 1)
    query = query.gte('fecha_hora', inicioMes.toISOString())
  }

  const { data } = await query
  historialCitas.value = data || []
  loadingHistorial.value = false
}

const historialFiltrado = computed(() => {
  return historialCitas.value.filter(c => {
    const matchSearch = (c.nombre_cliente_manual || '').toLowerCase().includes(searchQuery.value.toLowerCase())
    const matchServicio = selectedServicio.value === '' || c.servicio_id === selectedServicio.value
    return matchSearch && matchServicio
  })
})

const calcularGananciaBarbero = (precioTotal: number) => {
  if (!userProfile.value) return 0
  const factor = userProfile.value.modelo_pago === 'porcentaje' ? (userProfile.value.pago_valor || 50) / 100 : 1
  return userProfile.value.modelo_pago === 'porcentaje' ? precioTotal * factor : userProfile.value.modelo_pago === 'fijo_servicio' ? userProfile.value.pago_valor : 0
}

const totalGanadoPeriodo = computed(() => {
  return historialFiltrado.value.reduce((acc, c) => acc + calcularGananciaBarbero(Number(c.servicios?.precio) || 0), 0)
})

const agregarAListaEspera = async () => {
  if (!newEspera.value.nombre_cliente || !newEspera.value.servicio_id) return
  if (!barberia.value?.id) return notify.error("No se ha cargado la barbería activa")
  if (!userProfile.value?.id) return notify.error("No se ha cargado el perfil del barbero")
  
  processingAction.value = true
  const servicio = servicios.value.find(s => s.id === newEspera.value.servicio_id)
  
  const ahora = new Date()
  const offset = getTimezoneOffsetString()
  const y = ahora.getFullYear()
  const m = String(ahora.getMonth() + 1).padStart(2, '0')
  const d = String(ahora.getDate()).padStart(2, '0')
  const hh = String(ahora.getHours()).padStart(2, '0')
  const mm = String(ahora.getMinutes()).padStart(2, '0')
  const ss = String(ahora.getSeconds()).padStart(2, '0')
  const fechaHoraLocalConOffset = `${y}-${m}-${d}T${hh}:${mm}:${ss}${offset}`

  const { error } = await supabase.from('citas').insert([{
    barberia_id: barberia.value.id,
    barbero_id: userProfile.value.id,
    servicio_id: newEspera.value.servicio_id,
    nombre_cliente_manual: newEspera.value.nombre_cliente,
    tipo: 'espera',
    estado: 'confirmada',
    fecha_hora: fechaHoraLocalConOffset,
    precio_final: servicio?.precio || 0
  }])
  
  if (error) {
    notify.error("Error al agregar a la lista: " + error.message)
  } else {
    showEsperaModal.value = false
    newEspera.value = { nombre_cliente: '', servicio_id: '' }
    await fetchAgenda()
    notify.success("Cliente en lista con éxito")
  }
  processingAction.value = false
}

const completarCita = async (id: string) => {
  const ok = await confirm({
    title: '¿Finalizar Servicio?',
    message: 'Esta cita se registrará como completada y sumará a tus ganancias del día.',
    confirmText: 'Completar',
    type: 'info'
  })
  if (!ok) return
  const { error } = await supabase.from('citas').update({ estado: 'completada' }).eq('id', id)
  if (!error) {
    await fetchAgenda(); await fetchStats(); await fetchHistorial(); notify.success("¡Servicio completado!")
  } else {
    notify.error("Error al finalizar el servicio: " + error.message)
  }
}

const cancelarCita = async (id: string) => {
  const ok = await confirm({
    title: '¿Cancelar Turno?',
    message: '¿Estás seguro de que deseas cancelar este turno? Esta acción no se puede deshacer.',
    confirmText: 'Sí, Cancelar',
    type: 'danger'
  })
  if (!ok) return
  const { error } = await supabase.from('citas').update({ estado: 'cancelada' }).eq('id', id)
  if (!error) {
    await fetchAgenda(); await fetchStats(); await fetchHistorial(); notify.success("Turno cancelado")
  } else {
    notify.error("Error al cancelar el turno: " + error.message)
  }
}

const setupRealtime = () => {
  if (!userProfile.value) return
  subscription = supabase.channel('barbero-realtime').on('postgres_changes', { event: '*', schema: 'public', table: 'citas', filter: `barbero_id=eq.${userProfile.value.id}` }, () => { fetchAgenda(); fetchStats(); fetchHistorial() }).subscribe()
}

const fetchServicios = async () => { if (barberia.value) { const { data } = await supabase.from('servicios').select('*').eq('barberia_id', barberia.value.id); servicios.value = data || [] } }
const fetchBarberiasDisponibles = async () => { const { data } = await supabase.from('barberias').select('*'); barberiasDisponibles.value = data || [] }
const vincularABarberia = async (id: string) => { loading.value = true; await supabase.from('perfiles').update({ barberia_id: id, estado_vinculacion: 'pendiente' }).eq('id', userProfile.value.id); await fetchInitialData() }
const handleLogout = async () => { await supabase.auth.signOut(); router.push('/') }

const siguienteCita = computed(() => [...citasAgendadas.value, ...citasEspera.value][0])
</script>

<template>
  <div class="min-h-screen bg-brand-dark text-white flex flex-col md:flex-row font-sans">
    
    <!-- Sidebar Slim -->
    <aside class="w-full md:w-20 bg-brand-surface border-r border-white/5 flex flex-col items-center py-6 gap-8 shrink-0">
      <div class="w-11 h-11 bg-gradient-to-br from-brand-primary to-yellow-600 rounded-2xl flex items-center justify-center shadow-lg shadow-brand-primary/20 hover:scale-105 transition-all duration-300 cursor-pointer">
        <Scissors class="text-black w-5 h-5" />
      </div>
      <nav class="flex flex-col gap-4">
        <Tooltip text="Agenda de hoy" position="right">
          <button @click="activeTab = 'agenda'" :class="['p-3 rounded-2xl transition-all duration-300 cursor-pointer hover:scale-105', activeTab === 'agenda' ? 'bg-brand-primary text-black shadow-lg shadow-brand-primary/20' : 'text-white/20 hover:text-white hover:bg-white/5']">
            <Calendar class="w-5 h-5" />
          </button>
        </Tooltip>
        <Tooltip text="Historial de servicios" position="right">
          <button @click="activeTab = 'historial'" :class="['p-3 rounded-2xl transition-all duration-300 cursor-pointer hover:scale-105', activeTab === 'historial' ? 'bg-brand-primary text-black shadow-lg shadow-brand-primary/20' : 'text-white/20 hover:text-white hover:bg-white/5']">
            <History class="w-5 h-5" />
          </button>
        </Tooltip>
      </nav>
      <Tooltip text="Cerrar sesión" position="right" class="mt-auto">
        <button @click="handleLogout" class="p-3 text-red-500/40 hover:text-red-400 hover:bg-red-500/10 rounded-2xl cursor-pointer transition-all duration-300">
          <LogOut class="w-5 h-5" />
        </button>
      </Tooltip>
    </aside>

    <!-- Main Section -->
    <main class="flex-1 flex flex-col overflow-hidden bg-brand-dark">
      <header class="px-8 py-6 border-b border-white/5 bg-white/[0.01] backdrop-blur-md flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-black uppercase italic tracking-tighter leading-none mb-1.5">{{ activeTab === 'agenda' ? 'Mi Agenda' : 'Mi Historial' }}</h1>
          <p class="text-white/25 font-bold uppercase tracking-widest text-[9px] flex items-center gap-1.5">
            <MapPin class="w-3.5 h-3.5 text-brand-primary animate-pulse" /> {{ barberia?.nombre || 'Sincronizando barbería...' }}
          </p>
        </div>
        <div class="flex items-center gap-3">
          <button v-if="barberia && activeTab === 'agenda'" @click="showEsperaModal = true" class="bg-brand-primary text-black px-5 py-2.5 rounded-xl text-[10px] flex items-center gap-2 font-black uppercase italic tracking-widest shadow-lg shadow-brand-primary/10 hover:shadow-brand-primary/30 hover:scale-[1.03] transition-all duration-300 cursor-pointer">
            <UserPlus class="w-4 h-4" /> Cliente en Local
          </button>
          <div v-if="activeTab === 'historial'" class="flex bg-white/5 p-1 rounded-2xl border border-white/5">
             <button v-for="f in ['hoy', 'semana', 'mes']" :key="f" @click="filtroHistorial = f; fetchHistorial()" :class="['px-4 py-2 rounded-xl text-[8px] font-black uppercase tracking-widest transition-all duration-300 cursor-pointer', filtroHistorial === f ? 'bg-brand-primary text-black shadow-md' : 'text-white/30 hover:text-white']">
               {{ f }}
             </button>
          </div>
        </div>
      </header>

      <div class="flex-1 overflow-y-auto px-8 py-6 custom-scrollbar">
        
        <div v-if="loading" class="flex flex-col items-center justify-center py-24">
           <div class="w-10 h-10 border-2 border-brand-primary/20 border-t-brand-primary rounded-full animate-spin"></div>
        </div>

        <!-- PESTAÑA: AGENDA -->
        <div v-else-if="activeTab === 'agenda' && barberia" class="animate-in fade-in duration-500">
          
          <!-- Finanzas y Métricas de Alto Impacto -->
          <section class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
            <div class="bg-white/[0.02] border border-white/5 backdrop-blur-md p-6 rounded-[28px] relative overflow-hidden group hover:border-brand-primary/20 transition-all duration-300">
              <div class="absolute -right-6 -bottom-6 w-20 h-20 bg-brand-primary/5 rounded-full blur-xl group-hover:bg-brand-primary/10 transition-colors"></div>
              <p class="text-white/20 text-[8px] font-black uppercase tracking-widest mb-1.5">Mi Ganancia Hoy</p>
              <p class="text-4xl md:text-5xl font-black italic tracking-tighter text-brand-primary drop-shadow-[0_2px_10px_rgba(218,165,32,0.25)] leading-none">${{ gananciasHoy.toLocaleString() }}</p>
            </div>
            
            <div class="bg-white/[0.02] border border-white/5 backdrop-blur-md p-6 rounded-[28px] relative overflow-hidden group hover:border-white/10 transition-all duration-300">
              <div class="absolute -right-6 -bottom-6 w-20 h-20 bg-white/5 rounded-full blur-xl transition-colors"></div>
              <p class="text-white/20 text-[8px] font-black uppercase tracking-widest mb-1.5">Cortes Mes</p>
              <p class="text-4xl md:text-5xl font-black italic tracking-tighter text-white drop-shadow-[0_2px_10px_rgba(255,255,255,0.05)] leading-none">{{ serviciosMes }}</p>
            </div>
            
            <div class="md:col-span-2 bg-gradient-to-br from-brand-primary/15 via-white/[0.01] to-brand-dark/50 p-6 rounded-[28px] border border-brand-primary/20 text-white shadow-xl flex items-center justify-between relative overflow-hidden group hover:border-brand-primary/30 transition-all duration-300">
              <div class="absolute -right-8 -bottom-8 w-28 h-28 bg-brand-primary/5 rounded-full blur-2xl group-hover:bg-brand-primary/10 transition-all"></div>
              <div>
                <p class="text-[8px] font-black uppercase tracking-widest mb-1.5 text-brand-primary">Siguiente Turno</p>
                <p class="text-xl md:text-2xl font-black italic tracking-tighter uppercase leading-none">{{ siguienteCita?.nombre_cliente_manual || '¡LIBRE POR AHORA!' }}</p>
                <p class="text-white/40 text-[8px] font-bold uppercase tracking-widest mt-2 flex items-center gap-1.5" v-if="siguienteCita"><Clock class="w-3 h-3 text-brand-primary" /> {{ new Date(siguienteCita.fecha_hora).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }} · {{ siguienteCita.servicios?.nombre }}</p>
              </div>
              <div class="w-12 h-12 rounded-2xl bg-brand-primary/10 flex items-center justify-center border border-brand-primary/20 group-hover:scale-110 transition-transform duration-300">
                <Zap class="w-5 h-5 text-brand-primary" />
              </div>
            </div>
          </section>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 pb-10">
            <!-- Columna: Turnos de Hoy -->
            <div class="space-y-4">
              <h3 class="text-xs font-black uppercase italic tracking-widest flex items-center gap-2 px-2 text-white/40">
                <Calendar class="w-4 h-4 text-brand-primary animate-pulse" /> Turnos de Hoy
              </h3>
              <div v-if="citasAgendadas.length === 0" class="py-16 text-center border border-dashed border-white/5 bg-white/[0.01] rounded-[32px] text-white/15 italic text-xs leading-relaxed px-4">
                No tienes turnos agendados para hoy.<br><span class="text-[9px] uppercase tracking-wider text-white/5">Agenda libre y lista</span>
              </div>
              <div v-else class="space-y-3">
                <div v-for="cita in citasAgendadas" :key="cita.id" class="bg-white/[0.02] border border-white/5 backdrop-blur-md p-5 rounded-[26px] hover:border-brand-primary/20 hover:scale-[1.02] duration-300 transition-all flex items-center gap-4 relative group">
                  <div class="w-14 h-14 bg-gradient-to-br from-brand-primary/20 to-yellow-600/10 border border-brand-primary/20 text-brand-primary rounded-2xl flex flex-col items-center justify-center shrink-0 shadow-lg shadow-black/20">
                    <span class="text-[6px] font-black uppercase tracking-widest mb-0.5 text-white/30">Hora</span>
                    <span class="text-base font-black italic leading-none">{{ new Date(cita.fecha_hora).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }) }}</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <h4 class="text-base font-black uppercase italic tracking-tighter truncate leading-none mb-2">{{ cita.cliente?.nombre || cita.nombre_cliente_manual || 'Cliente' }}</h4>
                    <p class="text-white/30 text-[8px] font-black uppercase tracking-widest flex items-center gap-1.5"><Scissors class="w-3.5 h-3.5 text-brand-primary" /> {{ cita.servicios?.nombre }}</p>
                  </div>
                  <div class="flex gap-2.5">
                    <Tooltip text="Cancelar turno" position="top">
                      <button @click="cancelarCita(cita.id)" class="w-11 h-11 flex items-center justify-center rounded-full bg-white/5 hover:bg-red-500/10 text-white/30 hover:text-red-400 border border-white/5 hover:border-red-500/20 cursor-pointer transition-all duration-300">
                        <X class="w-4 h-4" />
                      </button>
                    </Tooltip>
                    <Tooltip text="Finalizar servicio" position="top">
                      <button @click="completarCita(cita.id)" class="w-11 h-11 flex items-center justify-center rounded-full bg-brand-primary/10 hover:bg-brand-primary text-brand-primary hover:text-black shadow-[0_0_15px_rgba(218,165,32,0.1)] hover:shadow-[0_0_20px_rgba(218,165,32,0.4)] border border-brand-primary/20 hover:border-brand-primary cursor-pointer transition-all duration-300">
                        <Check class="w-4.5 h-4.5" />
                      </button>
                    </Tooltip>
                  </div>
                </div>
              </div>
            </div>

            <!-- Columna: Lista de Espera -->
            <div class="space-y-4">
              <h3 class="text-xs font-black uppercase italic tracking-widest flex items-center gap-2 px-2 text-white/40">
                <Users class="w-4 h-4 text-white/30" /> Lista de Espera
              </h3>
              <div v-if="citasEspera.length === 0" class="py-16 text-center border border-dashed border-white/5 bg-white/[0.01] rounded-[32px] text-white/15 italic text-xs leading-relaxed px-4">
                No hay clientes en la lista de espera.<br><span class="text-[9px] uppercase tracking-wider text-white/5">Los clientes presenciales aparecerán aquí</span>
              </div>
              <div v-else class="space-y-3">
                <div v-for="(espera, index) in citasEspera" :key="espera.id" class="bg-white/[0.02] border border-white/5 backdrop-blur-md p-5 rounded-[26px] hover:border-brand-primary/20 hover:scale-[1.02] duration-300 transition-all flex items-center gap-4 relative group">
                  <div class="w-14 h-14 bg-white/5 border border-white/10 rounded-2xl flex flex-col items-center justify-center shrink-0">
                    <span class="text-[6px] font-black text-white/30 uppercase mb-0.5 tracking-widest">POS.</span>
                    <span class="text-xl font-black italic leading-none text-white/95">#{{ index + 1 }}</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <h4 class="text-base font-black uppercase italic tracking-tighter text-white/90 truncate leading-none mb-2">{{ espera.nombre_cliente_manual }}</h4>
                    <p class="text-brand-primary/70 text-[8px] font-black uppercase tracking-widest flex items-center gap-1.5"><Scissors class="w-3.5 h-3.5" /> {{ espera.servicios?.nombre }}</p>
                  </div>
                  <div class="flex gap-2.5">
                    <Tooltip text="Cancelar turno" position="top">
                      <button @click="cancelarCita(espera.id)" class="w-11 h-11 flex items-center justify-center rounded-full bg-white/5 hover:bg-red-500/10 text-white/30 hover:text-red-400 border border-white/5 hover:border-red-500/20 cursor-pointer transition-all duration-300">
                        <X class="w-4 h-4" />
                      </button>
                    </Tooltip>
                    <Tooltip text="Finalizar servicio" position="top">
                      <button @click="completarCita(espera.id)" class="w-11 h-11 flex items-center justify-center rounded-full bg-brand-primary/10 hover:bg-brand-primary text-brand-primary hover:text-black shadow-[0_0_15px_rgba(218,165,32,0.1)] hover:shadow-[0_0_20px_rgba(218,165,32,0.4)] border border-brand-primary/20 hover:border-brand-primary cursor-pointer transition-all duration-300">
                        <Check class="w-4.5 h-4.5" />
                      </button>
                    </Tooltip>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- PESTAÑA: HISTORIAL -->
        <div v-else-if="activeTab === 'historial' && barberia" class="space-y-8 animate-in fade-in duration-500 pb-10">
           
           <!-- Buscador y Filtros SaaS -->
           <section class="flex flex-col md:flex-row gap-4 bg-white/[0.01] p-6 rounded-[32px] border border-white/5 backdrop-blur-md">
              <div class="flex-1 relative">
                 <Search class="absolute left-4.5 top-1/2 -translate-y-1/2 w-4.5 h-4.5 text-white/20" />
                 <input v-model="searchQuery" type="text" placeholder="BUSCAR CLIENTE..." class="w-full bg-white/5 border border-white/10 rounded-2xl pl-12 pr-12 py-4 text-xs font-black uppercase italic tracking-widest outline-none focus:border-brand-primary transition-all duration-300" />
                 <button v-if="searchQuery" @click="searchQuery = ''" class="absolute right-4.5 top-1/2 -translate-y-1/2 text-white/20 hover:text-white transition-colors cursor-pointer"><X class="w-4 h-4" /></button>
              </div>
              <div class="md:w-64">
                 <select v-model="selectedServicio" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-4 text-xs font-black uppercase italic tracking-widest outline-none focus:border-brand-primary cursor-pointer transition-all duration-300">
                    <option value="" class="bg-brand-dark">TODOS LOS SERVICIOS</option>
                    <option v-for="s in servicios" :key="s.id" :value="s.id" class="bg-brand-dark">{{ s.nombre.toUpperCase() }}</option>
                 </select>
              </div>
           </section>

           <!-- Resumen del Historial Filtrado -->
           <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div class="bg-white/[0.02] border border-white/5 p-6 rounded-[28px] relative overflow-hidden group hover:border-white/10 transition-all duration-300">
                 <p class="text-white/20 text-[8px] font-black uppercase tracking-widest mb-1.5">Servicios Completados</p>
                 <p class="text-3xl font-black italic tracking-tighter text-white">{{ historialFiltrado.length }}</p>
              </div>
              <div class="bg-gradient-to-br from-brand-primary/10 via-yellow-600/5 to-transparent border border-brand-primary/20 p-6 rounded-[28px] text-white shadow-xl shadow-brand-primary/5 relative overflow-hidden hover:border-brand-primary/30 transition-all duration-300">
                 <DollarSign class="absolute -right-3 -bottom-3 w-16 h-16 text-brand-primary/10" />
                 <p class="text-brand-primary text-[8px] font-black uppercase tracking-widest mb-1.5">Mi Ganancia Acumulada</p>
                 <p class="text-3xl font-black italic tracking-tighter text-brand-primary drop-shadow-[0_2px_8px_rgba(218,165,32,0.15)]">${{ totalGanadoPeriodo.toLocaleString() }}</p>
              </div>
           </div>

           <!-- Lista de Historial en Tarjetas Premium -->
           <div class="space-y-3">
              <div v-if="loadingHistorial" class="py-16 text-center animate-pulse text-white/20 font-bold uppercase tracking-wider text-[10px]">Cargando historial...</div>
              <div v-else-if="historialFiltrado.length === 0" class="py-20 text-center border border-dashed border-white/5 bg-white/[0.01] rounded-[32px] text-white/15 italic text-sm">No se encontraron servicios registrados.</div>
              <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-4">
                 <div v-for="c in historialFiltrado" :key="c.id" class="bg-white/[0.02] border border-white/5 rounded-[26px] p-5 hover:border-brand-primary/20 hover:scale-[1.01] transition-all duration-300 flex justify-between items-center relative overflow-hidden group">
                    <div class="flex items-center gap-4">
                       <div class="w-12 h-12 bg-white/5 border border-white/10 rounded-xl flex flex-col items-center justify-center shrink-0">
                          <span class="text-[10px] font-black uppercase italic tracking-tighter text-white/80 leading-none">{{ new Date(c.fecha_hora).toLocaleDateString([], { day: 'numeric' }) }}</span>
                          <span class="text-[6px] font-black text-brand-primary uppercase mt-0.5 tracking-wider">{{ new Date(c.fecha_hora).toLocaleDateString([], { month: 'short' }).replace('.', '').toUpperCase() }}</span>
                       </div>
                       <div>
                          <h4 class="text-sm font-black uppercase italic tracking-tighter text-white/95 leading-none mb-1.5">{{ c.nombre_cliente_manual || 'Usuario App' }}</h4>
                          <p class="text-white/25 text-[8px] font-black uppercase tracking-widest flex items-center gap-1"><Clock class="w-3 h-3 text-brand-primary" /> {{ new Date(c.fecha_hora).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }} · {{ c.servicios?.nombre }}</p>
                       </div>
                    </div>
                    <div class="text-right shrink-0">
                       <span class="text-brand-primary/20 text-[7px] font-black uppercase tracking-wider block mb-1">Mi Ganancia</span>
                       <p class="text-lg font-black italic tracking-tighter text-brand-primary drop-shadow-[0_2px_8px_rgba(218,165,32,0.15)]">${{ calcularGananciaBarbero(Number(c.servicios?.precio) || 0).toLocaleString() }}</p>
                    </div>
                 </div>
              </div>
           </div>
        </div>

        <!-- Panel Vinculación Premium -->
        <div v-else-if="!loading" class="max-w-md mx-auto mt-10 animate-in zoom-in-95 duration-500 pb-10">
           <div class="bg-brand-surface border border-white/5 p-8 md:p-12 rounded-[40px] shadow-2xl text-center relative overflow-hidden backdrop-blur-md">
              <div class="absolute -right-16 -top-16 w-32 h-32 bg-brand-primary/5 rounded-full blur-3xl pointer-events-none"></div>
              
              <div v-if="userProfile?.estado_vinculacion === 'pendiente'" class="space-y-6">
                 <div class="w-20 h-20 bg-brand-primary/10 rounded-[28px] flex items-center justify-center mx-auto border border-brand-primary/20 shadow-lg shadow-brand-primary/5"><Clock class="text-brand-primary w-9 h-9 animate-pulse" /></div>
                 <h2 class="text-3xl font-black uppercase italic tracking-tighter leading-none text-white">Acceso Pendiente</h2>
                 <p class="text-white/30 text-xs leading-relaxed italic px-4">Tu solicitud ha sido enviada al administrador. Por favor, espera a que el dueño de la barbería la apruebe para comenzar a agendar.</p>
                 <button @click="handleLogout" class="text-[9px] font-black uppercase tracking-[0.2em] text-white/20 hover:text-white hover:bg-white/5 border border-white/5 hover:border-white/10 px-5 py-2.5 rounded-xl transition-all duration-300 cursor-pointer mt-6">Cerrar Sesión</button>
              </div>
              
              <div v-else class="space-y-8">
                 <h2 class="text-3xl font-black uppercase italic tracking-tighter leading-none text-white">Únete a un Equipo</h2>
                 <p class="text-white/30 text-xs leading-relaxed italic px-4 -mt-4">Para ver tu agenda y comenzar a recibir citas de clientes, debes vincularte a una de nuestras barberías aliadas.</p>
                 <div class="grid gap-3.5 max-h-[35vh] overflow-y-auto pr-2 custom-scrollbar">
                    <div v-for="b in barberiasDisponibles" :key="b.id" class="bg-white/[0.02] p-5 rounded-[26px] flex items-center justify-between border border-white/5 hover:border-brand-primary/30 transition-all duration-300">
                       <div class="text-left flex-1 min-w-0 pr-4">
                         <h4 class="text-base font-black uppercase italic tracking-tighter leading-none truncate text-white/90 mb-1.5">{{ b.nombre }}</h4>
                         <p class="text-white/30 text-[8px] font-bold uppercase tracking-widest flex items-center gap-1"><MapPin class="w-3.5 h-3.5 text-brand-primary" /> {{ b.direccion }}</p>
                       </div>
                       <button @click="vincularABarberia(b.id)" class="bg-brand-primary text-black px-5 py-2.5 rounded-xl text-[9px] font-black uppercase italic tracking-tighter shrink-0 hover:scale-[1.03] transition-all cursor-pointer">Unirme</button>
                    </div>
                 </div>
                 <button @click="handleLogout" class="text-[9px] font-black uppercase tracking-[0.2em] text-white/20 hover:text-white hover:bg-white/5 border border-white/5 hover:border-white/10 px-5 py-2.5 rounded-xl transition-all duration-300 cursor-pointer">Cerrar Sesión</button>
              </div>
           </div>
        </div>

      </div>
    </main>

    <!-- Modal Nuevo Cliente Premium -->
    <div v-if="showEsperaModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[999] flex items-center justify-center p-4">
      <div class="w-full max-w-sm bg-brand-surface border border-white/10 rounded-[36px] p-8 shadow-2xl relative animate-in zoom-in-95 duration-300">
        <button @click="showEsperaModal = false" class="absolute top-5 right-5 w-8 h-8 rounded-full bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/40 hover:text-white cursor-pointer transition-all">
          <X class="w-4 h-4" />
        </button>
        <h2 class="text-2xl font-black uppercase italic tracking-tighter mb-8 flex items-center gap-3"><UserPlus class="text-brand-primary w-6 h-6 animate-pulse" /> Nuevo Cliente</h2>
        <div class="space-y-5">
          <div>
            <label class="block text-[8px] font-black text-white/25 uppercase tracking-widest mb-2 px-2">Nombre Cliente</label>
            <input v-model="newEspera.nombre_cliente" type="text" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-4 focus:border-brand-primary outline-none font-black uppercase italic tracking-tighter text-base text-white transition-all duration-300" placeholder="NOMBRE DEL CLIENTE" />
          </div>
          <div>
            <label class="block text-[8px] font-black text-white/25 uppercase tracking-widest mb-2 px-2">Servicio Solicitado</label>
            <select v-model="newEspera.servicio_id" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-4 focus:border-brand-primary outline-none font-black uppercase italic text-white cursor-pointer transition-all duration-300">
              <option value="" class="bg-brand-dark">SELECCIONAR SERVICIO...</option>
              <option v-for="s in servicios" :key="s.id" :value="s.id" class="bg-brand-dark">{{ s.nombre.toUpperCase() }} - ${{ s.precio }}</option>
            </select>
          </div>
          <div class="flex gap-4 pt-6">
            <button @click="showEsperaModal = false" class="flex-1 py-4 text-white/30 font-black uppercase italic text-[10px] tracking-widest hover:text-white transition-colors cursor-pointer">Cerrar</button>
            <button @click="agregarAListaEspera" :disabled="processingAction" class="flex-[2.5] bg-brand-primary text-black rounded-2xl py-4 font-black uppercase italic tracking-tighter text-base shadow-lg shadow-brand-primary/10 hover:shadow-brand-primary/30 hover:scale-[1.02] cursor-pointer transition-all duration-300">Agregar</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.custom-scrollbar::-webkit-scrollbar { width: 4px; }
.custom-scrollbar::-webkit-scrollbar-track { background: transparent; }
.custom-scrollbar::-webkit-scrollbar-thumb { background: rgba(255, 215, 0, 0.1); border-radius: 10px; }
</style>
