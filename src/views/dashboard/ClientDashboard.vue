<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { LogOut, Scissors, Calendar, MapPin, Star, CheckCircle2, History, MessageSquare, Award, AlertCircle, Clock } from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'

const router = useRouter()
const notify = useNotifications()
const activeTab = ref('reservar')
const userName = ref('')

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

// Flujo de Reserva
const bookingStep = ref(1)
const barberias = ref<any[]>([])
const servicios = ref<any[]>([])
const barberos = ref<any[]>([])
const barberoServiciosMap = ref<any[]>([])
const horariosTotales = ref<string[]>([])
const horariosOcupados = ref<string[]>([])
const loadingBarberias = ref(false)
const loadingServicios = ref(false)
const loadingHorarios = ref(false)

const bookingData = ref({
  barberia: null as any,
  servicio: null as any,
  barbero: null as any,
  fecha: getLocalDateString(),
  hora: ''
})

watch(() => bookingData.value.fecha, () => {
  if (bookingData.value.barbero) {
    generarHorariosDisponibles()
  }
})

const formatFechaCita = (fechaHoraStr: string) => {
  try {
    const partes = fechaHoraStr.split('T')
    if (partes.length > 0) {
      const [y, m, d] = partes[0].split('-').map(Number)
      const fechaLocal = new Date(y, m - 1, d)
      let horaMinuto = ''
      if (partes.length > 1) {
        const hm = partes[1].split(':')
        if (hm.length >= 2) {
          horaMinuto = ` · ${hm[0].padStart(2, '0')}:${hm[1].padStart(2, '0')}`
        }
      }
      // Formato latinoamericano premium (ej: 22 de may de 2026 a las 10:30)
      return `${fechaLocal.toLocaleDateString([], { day: 'numeric', month: 'short' }).toUpperCase()}${horaMinuto}`
    }
  } catch (e) {
    console.error(e)
  }
  return new Date(fechaHoraStr).toLocaleString()
}

const barberosFiltrados = computed(() => {
  if (!bookingData.value.servicio) return barberos.value
  return barberos.value.filter(b => {
    const asignaciones = barberoServiciosMap.value.filter(m => m.barbero_id === b.id)
    if (asignaciones.length === 0) return true
    return asignaciones.some(m => m.servicio_id === bookingData.value.servicio.id)
  })
})

// Historial y Reseñas
const historialCitas = ref<any[]>([])
const showResenaModal = ref(false)
const citaParaCalificar = ref<any>(null)
const resenaForm = ref({ calificacion: 5, comentario: '' })

const loading = ref(false)
const guestForm = ref({
  nombre: '',
  telefono: '',
  email: ''
})
const showGuestForm = ref(false)

onMounted(async () => {
  const { data: { session } } = await supabase.auth.getSession()
  if (session) {
    userName.value = session.user.user_metadata?.nombre || session.user.email || 'Cliente'
    fetchHistorial()
  } else {
    userName.value = 'Invitado'
  }
  fetchBarberias()
})

const fetchBarberias = async () => {
  loadingBarberias.value = true
  const { data } = await supabase.from('barberias').select('*')
  barberias.value = data || []
  loadingBarberias.value = false
}

const selectBarberia = async (b: any) => {
  bookingData.value.barberia = b
  bookingStep.value = 2
  loadingServicios.value = true
  
  // 1. Cargar servicios de la barbería
  const { data: srv } = await supabase.from('servicios').select('*').eq('barberia_id', b.id)
  servicios.value = srv || []
  
  // 2. Cargar perfiles de la barbería (incluye barberos oficiales y dueños-barberos habilitados)
  const { data: profiles } = await supabase.from('perfiles').select('*').eq('barberia_id', b.id)
  barberos.value = (profiles || []).filter(p => 
    (p.rol === 'barbero' && p.estado_vinculacion === 'aprobado') ||
    ((p.rol === 'dueño' || p.rol === 'dueno') && p.es_barbero)
  )
  
  // 3. Cargar mapeos de servicios específicos para estos barberos
  const barberIds = barberos.value.map(x => x.id)
  if (barberIds.length > 0) {
    const { data: maps } = await supabase.from('barbero_servicios').select('*').in('barbero_id', barberIds)
    barberoServiciosMap.value = maps || []
  } else {
    barberoServiciosMap.value = []
  }
  
  loadingServicios.value = false
}

const selectServicio = (s: any) => { bookingData.value.servicio = s; bookingStep.value = 3 }
const selectBarbero = (b: any) => { bookingData.value.barbero = b; bookingStep.value = 4; generarHorariosDisponibles() }

const generarHorariosDisponibles = async () => {
  loadingHorarios.value = true

  // Consultar datos actualizados de la barbería para asegurar horas de apertura y cierre frescas de manera tolerante a fallos
  try {
    if (bookingData.value.barberia?.id) {
      const { data: bFresca, error } = await supabase
        .from('barberias')
        .select('*')
        .eq('id', bookingData.value.barberia.id)
        .single()
      if (!error && bFresca) {
        bookingData.value.barberia = bFresca
      }
    }
  } catch (err) {
    console.warn("No se pudo refrescar la barbería de la base de datos, usando datos en memoria:", err)
  }

  const slots = []
  
  const horaInicio = bookingData.value.barberia?.hora_apertura || '08:00'
  const horaFin = bookingData.value.barberia?.hora_cierre || '20:00'

  let [hActual, mActual] = (horaInicio || '08:00').split(':').map(Number)
  let [hLimite, mLimite] = (horaFin || '20:00').split(':').map(Number)

  // Validaciones de seguridad para evitar NaN
  if (isNaN(hActual) || isNaN(mActual)) { hActual = 8; mActual = 0 }
  if (isNaN(hLimite) || isNaN(mLimite)) { hLimite = 20; mLimite = 0 }

  // Auto-corrección AM/PM: si el dueño configuró p.ej. apertura a las 08:00 (AM) y cierre a las 08:00 o 06:00
  // pensando en PM, pero se guardó en formato de 12 horas, le sumamos 12 a la hora límite si es <= 12.
  if (hLimite < hActual || (hLimite === hActual && mLimite <= mActual)) {
    if (hLimite <= 12) {
      hLimite += 12
    }
  }

  // Si aun así la hora de cierre sigue siendo menor o igual por mala configuración,
  // forzamos por seguridad un cierre predeterminado a las 20:00 para garantizar que la grilla no salga vacía.
  if (hLimite < hActual || (hLimite === hActual && mLimite <= mActual)) {
    hLimite = 20
    mLimite = 0
  }

  // Generamos todos los slots del rango
  while (hActual < hLimite || (hActual === hLimite && mActual < mLimite)) {
    slots.push(`${hActual.toString().padStart(2, '0')}:${mActual.toString().padStart(2, '0')}`)
    mActual += 30
    if (mActual >= 60) { mActual = 0; hActual++ }
  }
  horariosTotales.value = slots

  // Consultamos ocupados
  const { data: citasExistentes } = await supabase
    .from('citas')
    .select('fecha_hora')
    .eq('barbero_id', bookingData.value.barbero.id)
    .gte('fecha_hora', `${bookingData.value.fecha}T00:00:00${getTimezoneOffsetString()}`)
    .lte('fecha_hora', `${bookingData.value.fecha}T23:59:59${getTimezoneOffsetString()}`)

  horariosOcupados.value = citasExistentes?.map(c => {
    const partes = c.fecha_hora.split('T')
    if (partes.length > 1) {
      const horaMinutoSegundos = partes[1] // Ej: "10:30:00+00:00" o "10:30:00Z"
      const hm = horaMinutoSegundos.split(':')
      if (hm.length >= 2) {
        return `${hm[0].padStart(2, '0')}:${hm[1].padStart(2, '0')}`
      }
    }
    // Fallback tolerante por si acaso
    const d = new Date(c.fecha_hora)
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
  }) || []

  loadingHorarios.value = false
}

const isTimePassed = (horaSlot: string) => {
  if (bookingData.value.fecha !== getLocalDateString()) return false
  const [h, m] = horaSlot.split(':').map(Number)
  const ahora = new Date()
  return (h < ahora.getHours()) || (h === ahora.getHours() && m <= ahora.getMinutes())
}

const isOccupied = (horaSlot: string) => horariosOcupados.value.includes(horaSlot)

// Computado para saber si quedan huecos reales
const hayHorariosDisponibles = computed(() => {
  return horariosTotales.value.some(h => !isTimePassed(h) && !isOccupied(h))
})

const resetReserva = () => {
  bookingStep.value = 1
  bookingData.value = { barberia: null, servicio: null, barbero: null, fecha: getLocalDateString(), hora: '' }
  showGuestForm.value = false
}

const confirmarReserva = async () => {
  const { data: { session } } = await supabase.auth.getSession()
  const { error } = await supabase.from('citas').insert([{
    cliente_id: session?.user.id,
    barbero_id: bookingData.value.barbero.id,
    barberia_id: bookingData.value.barberia.id,
    servicio_id: bookingData.value.servicio.id,
    fecha_hora: `${bookingData.value.fecha}T${bookingData.value.hora}:00${getTimezoneOffsetString()}`,
    estado: 'confirmada',
    precio_final: bookingData.value.servicio.precio,
    nombre_cliente_manual: session?.user.user_metadata?.nombre || 'Cliente App'
  }])
  if (!error) { notify.success("¡Turno reservado!"); bookingStep.value = 5; fetchHistorial() }
}

const confirmarReservaInvitado = async () => {
  if (!guestForm.value.nombre.trim()) {
    notify.error("Por favor, ingresa tu nombre completo")
    return
  }
  if (!guestForm.value.telefono.trim()) {
    notify.error("Por favor, ingresa tu número de teléfono")
    return
  }

  loading.value = true
  try {
    // 1. Buscar si ya existe un perfil de cliente con el mismo teléfono
    const { data: perfilExistente, error: selectError } = await supabase
      .from('perfiles')
      .select('id')
      .eq('telefono', guestForm.value.telefono.trim())
      .eq('rol', 'cliente')
      .maybeSingle()

    if (selectError) {
      console.error("Error al buscar perfil:", selectError)
    }

    let clienteId = perfilExistente?.id

    if (!clienteId) {
      // 2. Si no existe, crear un nuevo perfil de cliente con ID autogenerado
      clienteId = crypto.randomUUID()
      const { error: insertError } = await supabase
        .from('perfiles')
        .insert([{
          id: clienteId,
          nombre: guestForm.value.nombre.trim(),
          telefono: guestForm.value.telefono.trim(),
          email: guestForm.value.email.trim() || null,
          rol: 'cliente'
        }])

      if (insertError) {
        throw new Error("No se pudo registrar tus datos de contacto: " + insertError.message)
      }
    }

    // 3. Crear la cita asociada al perfil del cliente (nuevo o reutilizado)
    const { error: citaError } = await supabase
      .from('citas')
      .insert([{
        cliente_id: clienteId,
        barbero_id: bookingData.value.barbero.id,
        barberia_id: bookingData.value.barberia.id,
        servicio_id: bookingData.value.servicio.id,
        fecha_hora: `${bookingData.value.fecha}T${bookingData.value.hora}:00${getTimezoneOffsetString()}`,
        estado: 'confirmada',
        precio_final: bookingData.value.servicio.precio,
        nombre_cliente_manual: guestForm.value.nombre.trim()
      }])

    if (citaError) {
      throw new Error("No se pudo agendar la cita: " + citaError.message)
    }

    notify.success("¡Turno reservado exitosamente!")
    bookingStep.value = 5
    guestForm.value = { nombre: '', telefono: '', email: '' }
    showGuestForm.value = false
  } catch (err: any) {
    notify.error(err.message || "Ocurrió un error inesperado al procesar la reserva")
  } finally {
    loading.value = false
  }
}

const handleConfirmarClick = () => {
  if (userName.value === 'Invitado') {
    showGuestForm.value = true
  } else {
    confirmarReserva()
  }
}

const fetchHistorial = async () => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) {
    historialCitas.value = []
    return
  }
  const { data } = await supabase.from('citas').select('*, barberias(nombre), barberos:perfiles!barbero_id(nombre), servicios(nombre, precio)').eq('cliente_id', session.user.id).order('fecha_hora', { ascending: false })
  historialCitas.value = data || []
}

const openResenaModal = (cita: any) => { citaParaCalificar.value = cita; showResenaModal.value = true }
const enviarResena = async () => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return
  const { error } = await supabase.from('resenas').insert([{ cita_id: citaParaCalificar.value.id, cliente_id: session.user.id, barbero_id: citaParaCalificar.value.barbero_id, calificacion: resenaForm.value.calificacion, comentario: resenaForm.value.comentario }])
  if (!error) { showResenaModal.value = false; notify.success("¡Gracias!"); fetchHistorial() }
}

const handleLogout = async () => {
  if (userName.value === 'Invitado') {
    router.push('/')
  } else {
    await supabase.auth.signOut()
    router.push('/')
  }
}
const isVIP = computed(() => historialCitas.value.filter(c => c.estado === 'completada').length >= 3)
</script>

<template>
  <div class="min-h-screen bg-brand-dark text-white flex flex-col md:flex-row font-sans">
    <aside class="w-full md:w-56 bg-brand-surface border-r border-white/5 flex flex-col">
      <div class="p-6 border-b border-white/5 flex items-center gap-2"><div class="w-8 h-8 bg-brand-primary rounded-lg flex items-center justify-center text-black"><Scissors class="w-5 h-5" /></div><span class="font-black text-xl uppercase italic tracking-tighter">TuTurno</span></div>
      <nav class="flex-1 p-3 space-y-1 py-6">
        <button @click="activeTab = 'reservar'" :class="['w-full flex items-center gap-3 px-4 py-3 rounded-xl font-bold uppercase italic tracking-tighter transition-all cursor-pointer text-xs', activeTab === 'reservar' ? 'bg-brand-primary text-black' : 'text-white/30 hover:bg-white/5 hover:text-white']"><Calendar class="w-4 h-4" /> Reservar</button>
        <button v-if="userName !== 'Invitado'" @click="activeTab = 'historial'" :class="['w-full flex items-center gap-3 px-4 py-3 rounded-xl font-bold uppercase italic tracking-tighter transition-all cursor-pointer text-xs', activeTab === 'historial' ? 'bg-brand-primary text-black' : 'text-white/30 hover:bg-white/5 hover:text-white']"><History class="w-4 h-4" /> Mis Turnos</button>
      </nav>
      <div class="p-4 border-t border-white/5">
        <button @click="handleLogout" :class="['w-full flex items-center gap-3 px-4 py-3 rounded-xl transition-all font-bold uppercase italic tracking-tighter text-xs cursor-pointer', userName === 'Invitado' ? 'text-brand-primary hover:bg-brand-primary/10' : 'text-red-400 hover:bg-red-400/10']">
          <LogOut class="w-4 h-4" /> {{ userName === 'Invitado' ? 'Iniciar Sesión' : 'Salir' }}
        </button>
      </div>
    </aside>

    <main class="flex-1 flex flex-col overflow-hidden">
      <header class="px-8 py-6 border-b border-white/5 bg-white/[0.01] flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-black uppercase italic tracking-tighter leading-none flex items-center gap-2">Hola, {{ userName.split(' ')[0] }} <span v-if="isVIP" class="px-2 py-0.5 bg-brand-primary text-black text-[7px] font-black uppercase tracking-widest rounded-full flex items-center gap-1"><Award class="w-2.5 h-2.5" /> CLIENTE VIP</span></h1>
          <p class="text-white/20 font-bold uppercase tracking-widest text-[9px] mt-1">¿Qué estilo buscamos hoy?</p>
        </div>
      </header>

      <div class="flex-1 overflow-y-auto px-8 py-8 custom-scrollbar">
        <div v-if="activeTab === 'reservar'" class="max-w-4xl mx-auto">
          <div v-if="bookingStep < 5" class="flex gap-2 mb-8"><div v-for="i in 4" :key="i" class="flex-1 h-1 rounded-full transition-all duration-500" :class="i <= bookingStep ? 'bg-brand-primary' : 'bg-white/5'"></div></div>
          
          <!-- Step 1 al 3 siguen igual... -->
          <div v-if="bookingStep === 1" class="space-y-6 animate-in fade-in slide-in-from-bottom-4">
            <h2 class="text-xl font-black uppercase italic tracking-tighter">Elige tu Barbería</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div v-for="b in barberias" :key="b.id" @click="selectBarberia(b)" class="group bg-white/5 border border-white/5 p-5 rounded-2xl hover:border-brand-primary/30 transition-all cursor-pointer relative overflow-hidden">
                <div v-if="b.logo_url" class="w-10 h-10 rounded-full border border-white/10 overflow-hidden mb-3"><img :src="b.logo_url" class="w-full h-full object-cover" /></div>
                <MapPin class="w-8 h-8 text-white/5 absolute -right-2 -bottom-2 group-hover:text-brand-primary/10 transition-colors" /><h3 class="text-lg font-black uppercase italic tracking-tighter mb-1">{{ b.nombre }}</h3><p class="text-white/30 text-[9px] font-bold uppercase tracking-widest">{{ b.direccion }}</p>
              </div>
            </div>
          </div>

          <div v-if="bookingStep > 1 && bookingStep < 5" class="mb-8 animate-in fade-in zoom-in duration-500">
             <div class="w-full h-24 rounded-3xl overflow-hidden relative border border-white/5 shadow-2xl">
                <img :src="bookingData.barberia?.banner_url || 'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&q=80&w=1000'" class="w-full h-full object-cover opacity-50 blur-[2px]" />
                <div class="absolute inset-0 bg-gradient-to-t from-brand-dark to-transparent"></div>
                <div class="absolute bottom-4 left-6 flex items-center gap-4">
                   <div v-if="bookingData.barberia?.logo_url" class="w-12 h-12 rounded-2xl border-2 border-brand-primary overflow-hidden bg-brand-dark shadow-xl"><img :src="bookingData.barberia.logo_url" class="w-full h-full object-cover" /></div>
                   <div><h3 class="text-xl font-black uppercase italic tracking-tighter leading-none">{{ bookingData.barberia?.nombre }}</h3><p class="text-white/50 text-[8px] font-black uppercase tracking-widest">{{ bookingData.barberia?.direccion }}</p></div>
                </div>
             </div>
          </div>

          <div v-if="bookingStep === 2" class="space-y-6 animate-in fade-in slide-in-from-right-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-black uppercase italic tracking-tighter">Servicios Disponibles</h2>
              <button @click="bookingStep = 1" class="text-[9px] font-black uppercase text-brand-primary hover:underline cursor-pointer">Cambiar Barbería</button>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div v-for="s in servicios" :key="s.id" @click="selectServicio(s)" class="bg-white/[0.02] border border-white/5 p-6 rounded-3xl hover:border-brand-primary/30 hover:scale-[1.02] duration-300 transition-all cursor-pointer flex justify-between items-center group relative overflow-hidden">
                <div class="absolute -right-6 -bottom-6 w-16 h-16 bg-brand-primary/5 rounded-full blur-xl group-hover:bg-brand-primary/10 transition-colors"></div>
                <div>
                  <h3 class="text-sm font-black uppercase italic tracking-tighter mb-1.5">{{ s.nombre }}</h3>
                  <p class="text-white/30 text-[8px] font-black uppercase tracking-widest flex items-center gap-1"><Clock class="w-3.5 h-3.5 text-brand-primary" /> {{ s.duracion_minutos }} MIN</p>
                </div>
                <p class="text-xl font-black italic tracking-tighter text-brand-primary leading-none">${{ s.precio }}</p>
              </div>
            </div>
          </div>

          <div v-if="bookingStep === 3" class="space-y-6 animate-in fade-in slide-in-from-right-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-black uppercase italic tracking-tighter">¿Quién te atiende?</h2>
              <button @click="bookingStep = 2" class="text-[9px] font-black uppercase text-brand-primary hover:underline cursor-pointer">Volver</button>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div v-for="b in barberosFiltrados" :key="b.id" @click="selectBarbero(b)" class="bg-white/[0.02] border border-white/5 p-6 rounded-3xl hover:border-brand-primary/30 hover:scale-[1.02] duration-300 transition-all cursor-pointer text-center group relative overflow-hidden">
                <div class="absolute top-2 right-2 px-2 py-0.5 bg-brand-primary/10 text-brand-primary text-[7px] font-black uppercase tracking-widest rounded-full" v-if="b.rol === 'dueño' || b.rol === 'dueno'">
                  MÁSTER / DUEÑO
                </div>
                <div class="w-14 h-14 bg-gradient-to-br from-brand-primary/20 to-yellow-600/10 rounded-2xl mx-auto mb-4 flex items-center justify-center text-brand-primary group-hover:scale-110 duration-300 transition-transform shadow-lg border border-brand-primary/15">
                  <span class="font-black text-xl italic uppercase">{{ b.nombre[0] }}</span>
                </div>
                <h3 class="text-sm font-black uppercase italic tracking-tighter leading-none mb-2">{{ b.nombre }}</h3>
                <div class="flex items-center justify-center gap-1 text-brand-primary">
                  <Star class="w-3 h-3 fill-current" />
                  <span class="text-[10px] font-black italic tracking-tighter">{{ b.rating > 0 ? b.rating.toFixed(1) : '5.0' }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Step 4: Horarios con Lógica de Bloqueo y Mensaje -->
          <div v-if="bookingStep === 4" class="space-y-6 animate-in fade-in slide-in-from-right-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-black uppercase italic tracking-tighter">
                {{ showGuestForm ? 'Datos de Contacto' : 'Elige tu Horario' }}
              </h2>
              <button @click="showGuestForm ? (showGuestForm = false) : (bookingStep = 3)" class="text-[9px] font-black uppercase text-brand-primary hover:underline cursor-pointer">Volver</button>
            </div>
            
            <div v-if="!showGuestForm" class="space-y-6">
              <div class="bg-white/5 p-4 rounded-2xl flex items-center gap-3">
                <Calendar class="w-4 h-4 text-brand-primary" />
                <input type="date" v-model="bookingData.fecha" class="bg-transparent border-none outline-none font-black uppercase italic text-sm w-full text-white cursor-pointer" :min="getLocalDateString()" />
              </div>
              
              <div v-if="loadingHorarios" class="py-10 text-center animate-pulse text-white/10 italic text-[10px]">Consultando agenda...</div>
              
              <!-- Mensaje cuando NO hay horarios -->
              <div v-else-if="!hayHorariosDisponibles" class="p-8 bg-brand-primary/5 border border-brand-primary/20 rounded-[30px] text-center space-y-6 animate-in zoom-in duration-300">
                 <AlertCircle class="w-12 h-12 text-brand-primary mx-auto opacity-50" />
                 <p class="text-sm font-medium italic text-white/80 leading-relaxed px-4">
                   No hay horarios disponibles por ahora. Puedes buscar otra barbería o ir directamente al local y el barbero te agregará a la lista de espera.
                 </p>
                 <div class="flex flex-col gap-3">
                    <button @click="bookingStep = 1" class="btn-primary py-3 text-xs font-black uppercase italic tracking-tighter cursor-pointer">Buscar otra barbería</button>
                    <button @click="resetReserva" class="text-[9px] font-black uppercase tracking-widest text-white/30 hover:text-white transition-colors cursor-pointer">Entendido</button>
                 </div>
              </div>

              <!-- Grilla de Horarios -->
              <div v-else class="grid grid-cols-4 md:grid-cols-6 gap-2">
                <button v-for="h in horariosTotales" :key="h" 
                  @click="!isTimePassed(h) && !isOccupied(h) && (bookingData.hora = h)" 
                  :disabled="isTimePassed(h) || isOccupied(h)" 
                  :class="['py-3 rounded-xl text-[10px] font-black tracking-widest transition-all cursor-pointer select-none', 
                    bookingData.hora === h ? 'bg-brand-primary text-black shadow-[0_0_15px_rgba(218,165,32,0.35)] scale-[1.05] border border-brand-primary' : 
                    isOccupied(h) ? 'bg-white/5 text-white/10 border border-white/5 cursor-not-allowed opacity-30 grayscale' :
                    isTimePassed(h) ? 'bg-red-500/5 text-red-500/30 border border-red-500/10 cursor-not-allowed' : 'bg-white/5 text-white hover:bg-white/10 hover:scale-[1.02]']">
                  {{ h }}
                </button>
              </div>
              
              <button v-if="bookingData.hora" @click="handleConfirmarClick" class="w-full btn-primary py-4 text-base font-black uppercase italic tracking-tighter shadow-xl shadow-brand-primary/20 mt-4 cursor-pointer">Confirmar Turno</button>
            </div>

            <!-- Formulario Inmersivo de Contacto para Invitados -->
            <div v-else class="space-y-6 animate-in fade-in slide-in-from-right-4">
              <p class="text-white/40 text-[9px] font-bold uppercase tracking-widest px-1">
                Estás agendando como invitado. Ingresa tus datos para confirmarte el turno.
              </p>
              
              <div class="space-y-5">
                <div>
                  <label class="block text-white/50 text-[9px] font-black uppercase tracking-widest mb-2 px-1">Nombre Completo *</label>
                  <input type="text" v-model="guestForm.nombre" placeholder="EJ: JUAN PÉREZ" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 outline-none focus:border-brand-primary text-xs font-black uppercase italic tracking-tighter text-white transition-all duration-300" />
                </div>
                <div>
                  <label class="block text-white/50 text-[9px] font-black uppercase tracking-widest mb-2 px-1">Teléfono Móvil *</label>
                  <input type="tel" v-model="guestForm.telefono" placeholder="EJ: 3001234567" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 outline-none focus:border-brand-primary text-xs font-black uppercase italic tracking-tighter text-white transition-all duration-300" />
                </div>
                <div>
                  <label class="block text-white/50 text-[9px] font-black uppercase tracking-widest mb-2 px-1">Correo Electrónico (Opcional)</label>
                  <input type="email" v-model="guestForm.email" placeholder="EJ: JUAN@GMAIL.COM" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 outline-none focus:border-brand-primary text-xs font-black uppercase italic tracking-tighter text-white transition-all duration-300" />
                </div>
              </div>

              <button @click="confirmarReservaInvitado" :disabled="loading" class="w-full btn-primary py-4 text-base font-black uppercase italic tracking-tighter shadow-xl shadow-brand-primary/20 mt-4 cursor-pointer flex items-center justify-center gap-2">
                <span v-if="loading" class="w-5 h-5 border-2 border-black border-t-transparent rounded-full animate-spin"></span>
                <span>Confirmar Reserva</span>
              </button>
            </div>
          </div>

          <div v-if="bookingStep === 5" class="py-10 text-center animate-in zoom-in duration-500">
            <div class="w-12 h-12 bg-green-500/20 text-green-500 rounded-full flex items-center justify-center mx-auto mb-4"><CheckCircle2 class="w-8 h-8" /></div>
            <h2 class="text-3xl font-black uppercase italic tracking-tighter mb-1">¡Reserva Exitosa!</h2>
            <p class="text-white/30 text-[9px] font-bold uppercase tracking-widest mb-6">Te esperamos en {{ bookingData.barberia.nombre }}</p>
            <button v-if="userName !== 'Invitado'" @click="bookingStep = 1; activeTab = 'historial'" class="btn-primary px-6 py-2.5 text-[10px] font-black uppercase italic tracking-tighter cursor-pointer">Ver mi Historial</button>
            <button v-else @click="resetReserva" class="btn-primary px-6 py-2.5 text-[10px] font-black uppercase italic tracking-tighter cursor-pointer">Volver al Inicio</button>
          </div>
        </div>

        <div v-if="activeTab === 'historial'" class="max-w-4xl mx-auto space-y-6 animate-in fade-in duration-500">
          <div class="flex items-center justify-between"><h2 class="text-xl font-black uppercase italic tracking-tighter">Mi Recorrido de Estilo</h2><div v-if="isVIP" class="flex items-center gap-2 bg-brand-primary/10 px-3 py-1.5 rounded-full border border-brand-primary/20"><Award class="w-4 h-4 text-brand-primary" /><span class="text-[8px] font-black text-brand-primary uppercase tracking-widest">ESTADO: VIP GOLD</span></div></div>
          <div v-if="historialCitas.length === 0" class="py-16 text-center border-2 border-dashed border-white/5 rounded-3xl text-white/10 italic text-sm">Empieza tu historia con nosotros hoy.</div>
          <div v-else class="space-y-3"><div v-for="c in historialCitas" :key="c.id" class="bg-white/5 border border-white/5 p-4 rounded-2xl flex items-center justify-between group"><div class="flex items-center gap-4"><div class="w-8 h-8 bg-white/5 rounded-xl flex items-center justify-center"><Scissors class="w-4 h-4 text-white/20" /></div><div><h3 class="text-sm font-black uppercase italic tracking-tighter leading-none">{{ c.servicios?.nombre }}</h3><p class="text-[8px] text-white/30 font-bold uppercase tracking-widest mt-1">{{ formatFechaCita(c.fecha_hora) }} · {{ c.barberias?.nombre }}</p></div></div><div class="flex items-center gap-3"><span :class="['px-3 py-1 rounded-full text-[8px] font-black uppercase tracking-widest', c.estado === 'completada' ? 'bg-green-500/10 text-green-500' : 'bg-brand-primary/10 text-brand-primary']">{{ c.estado }}</span><button v-if="c.estado === 'completada'" @click="openResenaModal(c)" class="p-2 text-brand-primary hover:bg-brand-primary/10 rounded-lg transition-all cursor-pointer"><MessageSquare class="w-3.5 h-3.5" /></button></div></div></div>
        </div>
      </div>
    </main>

    <div v-if="showResenaModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[100] flex items-center justify-center p-4">
      <div class="w-full max-w-sm bg-brand-surface border border-white/10 p-8 rounded-[40px] shadow-2xl relative"><h2 class="text-xl font-black uppercase italic tracking-tighter mb-6 text-center">Califica tu Estilo</h2><div class="space-y-6"><div class="flex justify-center gap-2"><Star v-for="i in 5" :key="i" @click="resenaForm.calificacion = i" :class="['w-6 h-6 cursor-pointer transition-all', i <= resenaForm.calificacion ? 'text-brand-primary fill-current' : 'text-white/5']" /></div><textarea v-model="resenaForm.comentario" rows="3" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 outline-none focus:border-brand-primary text-[10px] italic font-medium" placeholder="¿Cómo te sentiste con el cambio?"></textarea><button @click="enviarResena" class="w-full btn-primary py-3 font-black uppercase italic tracking-tighter text-sm">Guardar Opinión</button></div></div>
    </div>
  </div>
</template>

<style scoped>
.custom-scrollbar::-webkit-scrollbar { width: 4px; }
.custom-scrollbar::-webkit-scrollbar-track { background: transparent; }
.custom-scrollbar::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, 0.05); border-radius: 10px; }
</style>
