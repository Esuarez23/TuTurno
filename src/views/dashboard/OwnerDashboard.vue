<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { LogOut, Scissors, LayoutDashboard, Briefcase, Users, Plus, Trash2, Edit2, UserCheck, UserX, Clock, Calendar, DollarSign, MapPin, Star, MessageSquare, Settings, TrendingUp, Award, UserPlus, Heart, Image as ImageIcon, Wallet, CreditCard, Zap, X } from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'
import { useConfirm } from '../../composables/useConfirm'
import Tooltip from '../../components/Tooltip.vue'

const router = useRouter()
const notify = useNotifications()
const { confirm } = useConfirm()
const loading = ref(false)

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
const activeTab = ref('resumen')
const ownerName = ref('')
const barberia = ref<any>(null)
const loadingBarberia = ref(true)

// Nómina
const nominaData = ref<any[]>([])
const loadingNomina = ref(false)
const showConfigPagoModal = ref(false)
const barberoAConfigurar = ref<any>(null)
const configPago = ref({ modelo: 'porcentaje', valor: 50 })

// Métricas
const ingresosMes = ref(0)
const citasHoyCount = ref(0)
const productividadEquipo = ref<any[]>([])
const topServicios = ref<any[]>([])

// Citas
const todasLasCitas = ref<any[]>([])
const showManualCitaModal = ref(false)
const manualCita = ref({ barbero_id: '', servicio_id: '', cliente_nombre: '', fecha: getLocalDateString(), hora: '09:00' })

// Clientes VIP
const clientesData = ref<any[]>([])
const loadingClientes = ref(false)

// Reseñas
const todasLasResenas = ref<any[]>([])

// Barbería
const showBarberiaModal = ref(false)
const newBarberia = ref({ nombre: '', direccion: '', foto_url: '', logo_url: '', banner_url: '', hora_apertura: '08:00', hora_cierre: '20:00' })

// Servicios
const servicios = ref<any[]>([])
const showServicioModal = ref(false)
const newServicio = ref({ nombre: '', precio: '', duracion_minutos: 30 })

// Equipo
const barberosActivos = ref<any[]>([])
const solicitudesPendientes = ref<any[]>([])

// Rol Híbrido (Dueño-Barbero)
const currentUserProfile = ref<any>(null)
const personalCitasAgendadas = ref<any[]>([])
const personalCitasEspera = ref<any[]>([])
const showEsperaModalOwner = ref(false)
const newEsperaOwner = ref({ nombre_cliente: '', servicio_id: '' })

// Asignación de Servicios
const showServiciosBarberoModal = ref(false)
const barberoSeleccionado = ref<any>(null)
const serviciosAsignados = ref<string[]>([])
const loadingAsignaciones = ref(false)

// Pestañas dinámicas basadas en si es barbero o no
const sidebarTabs = computed(() => {
  const base = [
    {id:'resumen', icon: LayoutDashboard, label: 'Resumen'},
    {id:'nomina', icon: Wallet, label: 'Nómina'},
  ]
  if (currentUserProfile.value?.es_barbero) {
    base.push({id:'mi_agenda', icon: Zap, label: 'Mi Agenda'})
  }
  base.push(
    {id:'citas', icon: Calendar, label: 'Citas'},
    {id:'clientes', icon: Heart, label: 'Clientes VIP'},
    {id:'resenas', icon: MessageSquare, label: 'Reseñas'},
    {id:'servicios', icon: Briefcase, label: 'Servicios'},
    {id:'equipo', icon: Users, label: 'Equipo'},
    {id:'config', icon: Settings, label: 'Ajustes'}
  )
  return base
})

// Selector de barberos que incluye al dueño si trabaja como barbero
const todosLosBarberosActivosYOwner = computed(() => {
  const list = [...barberosActivos.value]
  if (currentUserProfile.value?.es_barbero) {
    if (!list.some(b => b.id === currentUserProfile.value.id)) {
      list.unshift({
        id: currentUserProfile.value.id,
        nombre: currentUserProfile.value.nombre + ' (TÚ)'
      })
    }
  }
  return list
})

onMounted(async () => {
  const { data: { session } } = await supabase.auth.getSession()
  if (session) {
    const { data: profile } = await supabase.from('perfiles').select('*').eq('id', session.user.id).maybeSingle()
    if (profile) {
      currentUserProfile.value = profile
      ownerName.value = profile.nombre
      if (profile.es_barbero) {
        fetchPersonalAgenda()
      }
    } else if (session.user.user_metadata?.nombre) {
      ownerName.value = session.user.user_metadata.nombre
    }
  }
  await fetchBarberia()
  setupRealtimeSubscription()
})

const setupRealtimeSubscription = () => {
  supabase.channel('cambios-dueno')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'citas' }, () => { 
      fetchMetricas(); 
      fetchTodasLasCitas(); 
      fetchClientes(); 
      fetchNomina();
      if (currentUserProfile.value?.es_barbero) {
        fetchPersonalAgenda()
      }
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'perfiles' }, () => { fetchBarberos(); fetchNomina() })
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'resenas' }, () => { fetchResenas() })
    .subscribe()
}

const fetchBarberia = async () => {
  loadingBarberia.value = true
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return
  const { data } = await supabase.from('barberias').select('*').eq('dueno_id', session.user.id).maybeSingle()
  if (data) {
    barberia.value = data
    newBarberia.value = { ...data }
    fetchServicios(); fetchBarberos(); fetchMetricas(); fetchTodasLasCitas(); fetchResenas(); fetchClientes(); fetchNomina()
    if (currentUserProfile.value?.es_barbero) {
      fetchPersonalAgenda()
    }
  } else {
    showBarberiaModal.value = true
  }
  loadingBarberia.value = false
}

const fetchNomina = async () => {
  if (!barberia.value) return
  loadingNomina.value = true
  const inicioMes = new Date(); inicioMes.setDate(1); inicioMes.setHours(0,0,0,0)
  
  // Fetch all perfiles associated with the barbershop (hired barbers OR owner)
  const { data: todosLosPerfiles } = await supabase.from('perfiles').select('*').eq('barberia_id', barberia.value.id)
  
  const activeBarbers = (todosLosPerfiles || []).filter(b => 
    (b.rol === 'barbero' && b.estado_vinculacion === 'aprobado') ||
    ((b.rol === 'dueño' || b.rol === 'dueno') && b.es_barbero)
  )
  
  const { data: citas } = await supabase.from('citas').select('*, servicios(precio)').eq('barberia_id', barberia.value.id).eq('estado', 'completada').gte('fecha_hora', inicioMes.toISOString())
  if (activeBarbers) {
    nominaData.value = activeBarbers.map(b => {
      const citasBarbero = citas?.filter(c => c.barbero_id === b.id) || []
      const totalIngresos = citasBarbero.reduce((acc, c) => acc + (Number(c.servicios?.precio) || 0), 0)
      let aPagar = 0
      if (b.modelo_pago === 'porcentaje') aPagar = totalIngresos * ((b.pago_valor || 50) / 100)
      else if (b.modelo_pago === 'fijo_servicio') aPagar = citasBarbero.length * (b.pago_valor || 10)
      else aPagar = b.pago_valor || 0
      return { ...b, citasCount: citasBarbero.length, totalIngresos, aPagar }
    })
  }
  loadingNomina.value = false
}

// Métodos de Dueño-Barbero (Híbrido)
const toggleTrabajarComoBarbero = async () => {
  if (!currentUserProfile.value) return
  loading.value = true
  const newVal = !currentUserProfile.value.es_barbero
  
  const { error } = await supabase
    .from('perfiles')
    .update({ 
      es_barbero: newVal, 
      barberia_id: newVal ? barberia.value.id : currentUserProfile.value.barberia_id 
    })
    .eq('id', currentUserProfile.value.id)
    
  if (!error) {
    currentUserProfile.value.es_barbero = newVal
    if (newVal) {
      currentUserProfile.value.barberia_id = barberia.value.id
      fetchPersonalAgenda()
    } else {
      personalCitasAgendadas.value = []
      personalCitasEspera.value = []
      activeTab.value = 'resumen'
    }
    notify.success(newVal ? "¡Ahora apareces como Barbero!" : "Ya no apareces en la agenda")
    fetchNomina()
  } else {
    notify.error("Error al actualizar estado")
  }
  loading.value = false
}

const guardarConfigComisionOwner = async () => {
  if (!currentUserProfile.value) return
  loading.value = true
  const { error } = await supabase
    .from('perfiles')
    .update({ 
      modelo_pago: currentUserProfile.value.modelo_pago, 
      pago_valor: currentUserProfile.value.pago_valor 
    })
    .eq('id', currentUserProfile.value.id)
    
  if (!error) {
    notify.success("Configuración de comisión guardada")
    fetchNomina()
  } else {
    notify.error("Error al guardar comisiones")
  }
  loading.value = false
}

const fetchPersonalAgenda = async () => {
  if (!currentUserProfile.value) return
  const hoy = getLocalDateString()
  const offset = getTimezoneOffsetString()
  const { data } = await supabase
    .from('citas')
    .select('*, servicios(nombre, precio), cliente:perfiles!cliente_id(nombre)')
    .eq('barbero_id', currentUserProfile.value.id)
    .eq('estado', 'confirmada')
    .gte('fecha_hora', hoy + 'T00:00:00' + offset)
    .lte('fecha_hora', hoy + 'T23:59:59' + offset)
    .order('fecha_hora', { ascending: true })
  
  if (data) {
    personalCitasAgendadas.value = data.filter(c => c.tipo === 'agendado')
    personalCitasEspera.value = data.filter(c => c.tipo === 'espera')
  }
}

const completarCitaPersonal = async (id: string) => {
  const ok = await confirm({
    title: '¿Finalizar Servicio?',
    message: 'Esta cita se registrará como completada y sumará a tus ingresos.',
    confirmText: 'Completar',
    type: 'info'
  })
  if (!ok) return
  const { error } = await supabase.from('citas').update({ estado: 'completada' }).eq('id', id)
  if (error) {
    notify.error("Error al finalizar servicio: " + error.message)
  } else {
    notify.success("¡Servicio finalizado!")
    fetchPersonalAgenda()
    fetchMetricas()
    fetchNomina()
  }
}

const cancelarCitaPersonal = async (id: string) => {
  const ok = await confirm({
    title: '¿Cancelar Turno?',
    message: '¿Estás seguro de que deseas cancelar este turno? Esta acción no se puede deshacer.',
    confirmText: 'Sí, Cancelar',
    type: 'danger'
  })
  if (!ok) return
  const { error } = await supabase.from('citas').update({ estado: 'cancelada' }).eq('id', id)
  if (error) {
    notify.error("Error al cancelar turno: " + error.message)
  } else {
    notify.success("Turno cancelado")
    fetchPersonalAgenda()
  }
}

const agregarAListaEsperaOwner = async () => {
  if (!newEsperaOwner.value.nombre_cliente || !newEsperaOwner.value.servicio_id) return
  if (!barberia.value?.id) return notify.error("No se ha cargado la barbería activa")
  if (!currentUserProfile.value?.id) return notify.error("No se ha cargado el perfil de usuario actual")
  
  loading.value = true
  const servicio = servicios.value.find(s => s.id === newEsperaOwner.value.servicio_id)
  
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
    barbero_id: currentUserProfile.value.id,
    servicio_id: newEsperaOwner.value.servicio_id,
    nombre_cliente_manual: newEsperaOwner.value.nombre_cliente,
    tipo: 'espera',
    estado: 'confirmada',
    fecha_hora: fechaHoraLocalConOffset,
    precio_final: servicio?.precio || 0
  }])
  if (!error) {
    showEsperaModalOwner.value = false
    newEsperaOwner.value = { nombre_cliente: '', servicio_id: '' }
    fetchPersonalAgenda()
    notify.success("Agregado a la lista de espera con éxito")
  } else {
    notify.error("Error al agregar a la lista: " + error.message)
  }
  loading.value = false
}

// Métodos de Asignación de Servicios (Badges interactivos)
const abrirServiciosBarberoModal = async (barbero: any) => {
  barberoSeleccionado.value = barbero
  showServiciosBarberoModal.value = true
  loadingAsignaciones.value = true
  
  const { data, error } = await supabase
    .from('barbero_servicios')
    .select('servicio_id')
    .eq('barbero_id', barbero.id)
    
  if (!error && data) {
    serviciosAsignados.value = data.map(m => m.servicio_id)
  } else {
    serviciosAsignados.value = []
  }
  loadingAsignaciones.value = false
}

const toggleServicioAsignado = (servicioId: string) => {
  const idx = serviciosAsignados.value.indexOf(servicioId)
  if (idx > -1) {
    serviciosAsignados.value.splice(idx, 1)
  } else {
    serviciosAsignados.value.push(servicioId)
  }
}

const guardarServiciosBarbero = async () => {
  if (!barberoSeleccionado.value) return
  loading.value = true
  
  const { error: deleteError } = await supabase
    .from('barbero_servicios')
    .delete()
    .eq('barbero_id', barberoSeleccionado.value.id)
    
  if (!deleteError) {
    if (serviciosAsignados.value.length > 0) {
      const inserts = serviciosAsignados.value.map(srvId => ({
        barbero_id: barberoSeleccionado.value.id,
        servicio_id: srvId
      }))
      const { error: insertError } = await supabase
        .from('barbero_servicios')
        .insert(inserts)
        
      if (insertError) {
        notify.error("Error al guardar servicios")
      } else {
        notify.success("Servicios asignados correctamente")
        showServiciosBarberoModal.value = false
      }
    } else {
      notify.success("El barbero realizará todos los servicios")
      showServiciosBarberoModal.value = false
    }
  } else {
    notify.error("Error al actualizar servicios")
  }
  loading.value = false
}

const openConfigPago = (barbero: any) => {
  barberoAConfigurar.value = barbero
  configPago.value = { modelo: barbero.modelo_pago || 'porcentaje', valor: barbero.pago_valor || 50 }
  showConfigPagoModal.value = true
}

const guardarConfigPago = async () => {
  loading.value = true
  const { error } = await supabase.from('perfiles').update({ modelo_pago: configPago.value.modelo, pago_valor: configPago.value.valor }).eq('id', barberoAConfigurar.value.id)
  if (!error) { notify.success("Configuración actualizada"); showConfigPagoModal.value = false; fetchNomina() }
  loading.value = false
}

const registrarPago = async (barbero: any) => {
  const ok = await confirm({
    title: 'Confirmar Pago',
    message: `¿Confirmas que has pagado $${barbero.aPagar.toLocaleString()} a ${barbero.nombre}?`,
    confirmText: 'Sí, Pagado',
    type: 'info'
  })
  if (!ok) return
  loading.value = true
  const { error } = await supabase.from('pagos_nomina').insert([{ barbero_id: barbero.id, monto_pagado: barbero.aPagar, servicios_contados: barbero.citasCount, periodo_desde: new Date(new Date().setDate(1)).toISOString(), periodo_hasta: new Date().toISOString() }])
  if (!error) { notify.success("Pago registrado con éxito"); fetchNomina() }
  loading.value = false
}

const totalNominaPagar = computed(() => nominaData.value.reduce((acc, b) => acc + b.aPagar, 0))

const fetchMetricas = async () => {
  if (!barberia.value) return
  const hoy = getLocalDateString()
  const offset = getTimezoneOffsetString()
  const inicioMes = new Date(); inicioMes.setDate(1); inicioMes.setHours(0,0,0,0)
  const { count } = await supabase.from('citas').select('*', { count: 'exact', head: true }).eq('barberia_id', barberia.value.id).gte('fecha_hora', hoy + 'T00:00:00' + offset).lte('fecha_hora', hoy + 'T23:59:59' + offset)
  citasHoyCount.value = count || 0
  const { data: citasMes } = await supabase.from('citas').select('precio_final, barbero_id, barbero:perfiles!barbero_id(nombre), servicios(nombre)').eq('barberia_id', barberia.value.id).eq('estado', 'completada').gte('fecha_hora', inicioMes.toISOString())
  if (citasMes) {
    ingresosMes.value = citasMes.reduce((acc, c) => acc + (Number(c.precio_final) || 0), 0)
    const prodMap: any = {}; citasMes.forEach(c => { const n = (c.barbero as any)?.nombre || 'Manual'; prodMap[n] = (prodMap[n] || 0) + (Number(c.precio_final) || 0) })
    productividadEquipo.value = Object.entries(prodMap).map(([nombre, total]) => ({ nombre, total: total as number })).sort((a: any, b: any) => b.total - a.total)
    const servMap: any = {}; citasMes.forEach(c => { const n = (c.servicios as any)?.nombre || 'Desconocido'; servMap[n] = (servMap[n] || 0) + 1 })
    topServicios.value = Object.entries(servMap).map(([nombre, count]) => ({ nombre, count: count as number })).sort((a: any, b: any) => b.count - a.count).slice(0, 3)
  }
}

const fetchClientes = async () => {
  if (!barberia.value) return
  loadingClientes.value = true
  const { data: citas } = await supabase.from('citas').select('cliente_id, nombre_cliente_manual, cliente:perfiles!cliente_id(nombre, email)').eq('barberia_id', barberia.value.id)
  if (citas) {
    const map: any = {}
    citas.forEach(c => {
      const id = c.cliente_id || c.nombre_cliente_manual
      if (!map[id]) { map[id] = { nombre: (c.cliente as any)?.nombre || c.nombre_cliente_manual, email: (c.cliente as any)?.email || 'Manual', visitas: 0 } }
      map[id].visitas++
    })
    clientesData.value = Object.values(map).sort((a: any, b: any) => b.visitas - a.visitas)
  }
  loadingClientes.value = false
}

const agendarManual = async () => {
  if (!manualCita.value.barbero_id || !manualCita.value.servicio_id || !manualCita.value.cliente_nombre) return notify.error("Completa todos los campos")
  if (!barberia.value?.id) return notify.error("No se ha cargado la barbería activa")
  
  loading.value = true
  const servicio = servicios.value.find(s => s.id === manualCita.value.servicio_id)
  const offset = getTimezoneOffsetString()
  
  const { error } = await supabase.from('citas').insert([{
    barberia_id: barberia.value.id,
    barbero_id: manualCita.value.barbero_id,
    servicio_id: manualCita.value.servicio_id,
    nombre_cliente_manual: manualCita.value.cliente_nombre,
    fecha_hora: `${manualCita.value.fecha}T${manualCita.value.hora}:00${offset}`,
    estado: 'confirmada',
    tipo: 'agendado',
    precio_final: servicio?.precio || 0
  }])
  
  if (error) {
    notify.error("Error al agendar: " + error.message)
  } else {
    showManualCitaModal.value = false
    fetchTodasLasCitas()
    notify.success("Cita agendada con éxito")
  }
  loading.value = false
}

const saveBarberiaConfig = async () => {
  if (!newBarberia.value.nombre || !newBarberia.value.direccion) {
    return notify.error("El nombre y la dirección son obligatorios")
  }
  loading.value = true
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return
  
  if (barberia.value) {
    // Actualizar barbería existente
    const { error } = await supabase.from('barberias').update({ 
      nombre: newBarberia.value.nombre, 
      direccion: newBarberia.value.direccion, 
      logo_url: newBarberia.value.logo_url, 
      banner_url: newBarberia.value.banner_url, 
      hora_apertura: newBarberia.value.hora_apertura, 
      hora_cierre: newBarberia.value.hora_cierre 
    }).eq('id', barberia.value.id)
    
    if (!error) { 
      barberia.value = { ...newBarberia.value }
      notify.success("Marca actualizada")
      showBarberiaModal.value = false
      activeTab.value = 'resumen' 
    } else {
      notify.error("Error al actualizar la marca")
    }
  } else {
    // Registro inicial de barbería
    const { data, error } = await supabase.from('barberias').insert([{ 
      dueno_id: session.user.id,
      nombre: newBarberia.value.nombre, 
      direccion: newBarberia.value.direccion, 
      logo_url: newBarberia.value.logo_url, 
      banner_url: newBarberia.value.banner_url, 
      hora_apertura: newBarberia.value.hora_apertura, 
      hora_cierre: newBarberia.value.hora_cierre 
    }]).select().single()
    
    if (!error && data) {
      barberia.value = data
      newBarberia.value = { ...data }
      showBarberiaModal.value = false
      notify.success("¡Barbería registrada con éxito!")
      fetchServicios(); fetchBarberos(); fetchMetricas(); fetchTodasLasCitas(); fetchResenas(); fetchClientes(); fetchNomina()
    } else {
      notify.error("Error al crear la barbería")
    }
  }
  loading.value = false
}

const abrirNuevoServicioModal = () => {
  newServicio.value = { nombre: '', precio: '', duracion_minutos: 30 }
  showServicioModal.value = true
}

const abrirManualCitaModal = () => {
  manualCita.value = { 
    barbero_id: '', 
    servicio_id: '', 
    cliente_nombre: '', 
    fecha: getLocalDateString(), 
    hora: '09:00' 
  }
  showManualCitaModal.value = true
}

const fetchServicios = async () => { if (barberia.value) { const { data } = await supabase.from('servicios').select('*').eq('barberia_id', barberia.value.id); servicios.value = data || [] } }
const saveServicio = async () => {
  const { error } = await supabase.from('servicios').insert([{ ...newServicio.value, barberia_id: barberia.value.id }])
  if (!error) { showServicioModal.value = false; fetchServicios(); notify.success("Servicio agregado") }
}
const deleteServicio = async (id: string) => {
  const ok = await confirm({
    title: '¿Eliminar Servicio?',
    message: 'Esta acción no se puede deshacer y el servicio dejará de estar disponible.',
    confirmText: 'Eliminar',
    type: 'danger'
  })
  if (!ok) return
  await supabase.from('servicios').delete().eq('id', id)
  fetchServicios()
}

const fetchBarberos = async () => {
  if (!barberia.value) return
  const { data } = await supabase.from('perfiles').select('*').eq('barberia_id', barberia.value.id).eq('rol', 'barbero')
  if (data) {
    barberosActivos.value = data.filter(b => b.estado_vinculacion === 'aprobado')
    solicitudesPendientes.value = data.filter(b => b.estado_vinculacion === 'pendiente')
  }
}

const gestionarSolicitud = async (id: string, st: string) => {
  await supabase.from('perfiles').update({ estado_vinculacion: st, barberia_id: st === 'aprobado' ? barberia.value.id : null }).eq('id', id)
  fetchBarberos()
}

const fetchTodasLasCitas = async () => {
  if (barberia.value) {
    const { data } = await supabase.from('citas').select('*, barbero:perfiles!barbero_id(nombre), servicios(nombre, precio)').eq('barberia_id', barberia.value.id).order('fecha_hora', { ascending: false }).limit(50)
    todasLasCitas.value = data || []
  }
}

const fetchResenas = async () => {
  if (barberia.value) {
    const { data } = await supabase.from('resenas').select('*, cliente:perfiles!cliente_id(nombre), barbero:perfiles!barbero_id(nombre)').order('created_at', { ascending: false })
    todasLasResenas.value = data || []
  }
}

const handleLogout = async () => { await supabase.auth.signOut(); router.push('/') }
</script>

<template>
  <div class="min-h-screen bg-brand-dark text-white flex flex-col md:flex-row font-sans">
    <!-- Sidebar -->
    <aside class="w-full md:w-56 bg-brand-surface border-r border-white/5 flex flex-col">
      <div class="p-6 border-b border-white/5 flex items-center gap-2">
        <div class="w-8 h-8 bg-brand-primary rounded-lg flex items-center justify-center text-black shadow-lg shadow-brand-primary/20">
          <Scissors class="w-5 h-5" />
        </div>
        <span class="font-black text-xl uppercase italic tracking-tighter">TuTurno</span>
      </div>
      
      <nav class="flex-1 p-3 space-y-1 py-6">
        <button v-for="tab in sidebarTabs" :key="tab.id" @click="activeTab = tab.id" 
        :class="['w-full flex items-center gap-3 px-4 py-3 rounded-xl font-bold uppercase italic tracking-tighter transition-all cursor-pointer text-xs', activeTab === tab.id ? 'bg-brand-primary text-black' : 'text-white/30 hover:bg-white/5 hover:text-white']">
          <component :is="tab.icon" class="w-4 h-4" /> {{ tab.label }}
        </button>
      </nav>

      <div class="p-4 border-t border-white/5">
        <button @click="handleLogout" class="w-full flex items-center gap-3 px-4 py-3 text-red-400 hover:bg-red-400/10 rounded-xl transition-all font-bold uppercase italic tracking-tighter text-xs cursor-pointer">
          <LogOut class="w-4 h-4" /> Salir
        </button>
      </div>
    </aside>

    <main class="flex-1 flex flex-col overflow-hidden">
      <!-- Header -->
      <header class="px-8 py-6 flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-white/5 bg-white/[0.01]">
        <div class="flex items-center gap-4">
          <div v-if="barberia?.logo_url" class="w-10 h-10 rounded-full border border-brand-primary/30 overflow-hidden bg-white/5"><img :src="barberia.logo_url" class="w-full h-full object-cover" /></div>
          <div><h1 class="text-2xl font-black uppercase italic tracking-tighter leading-none mb-1">Hola, {{ ownerName.split(' ')[0] }}</h1><p class="text-white/20 font-bold uppercase tracking-widest text-[9px] flex items-center gap-1.5"><MapPin class="w-3 h-3 text-brand-primary" /> {{ barberia?.nombre || 'Administración' }}</p></div>
        </div>
        <div class="flex items-center gap-3">
          <button v-if="activeTab === 'mi_agenda'" @click="showEsperaModalOwner = true" class="btn-primary px-5 py-2.5 text-xs flex items-center gap-2 font-black uppercase italic tracking-tighter shadow-lg shadow-brand-primary/10 cursor-pointer"><Plus class="w-4 h-4" /> Cliente en Local</button>
          <button v-if="activeTab === 'servicios'" @click="abrirNuevoServicioModal" class="btn-primary px-5 py-2.5 text-xs flex items-center gap-2 font-black uppercase italic tracking-tighter shadow-lg shadow-brand-primary/10 cursor-pointer"><Plus class="w-4 h-4" /> Nuevo Servicio</button>
          <button v-if="activeTab === 'citas'" @click="abrirManualCitaModal" class="btn-primary px-5 py-2.5 text-xs flex items-center gap-2 font-black uppercase italic tracking-tighter shadow-lg shadow-brand-primary/10 cursor-pointer"><UserPlus class="w-4 h-4" /> Cita Manual</button>
        </div>
      </header>

      <div v-if="loadingBarberia" class="flex-1 flex flex-col items-center justify-center text-white/10"><div class="w-8 h-8 border-2 border-brand-primary/20 border-t-brand-primary rounded-full animate-spin mb-3"></div><p class="text-[8px] font-black uppercase tracking-widest">Cargando...</p></div>

      <div v-else class="flex-1 overflow-y-auto px-8 py-8 custom-scrollbar">
        
        <!-- Tab: Mi Agenda (Para Dueño que también es Barbero) -->
        <div v-if="activeTab === 'mi_agenda'" class="space-y-8 animate-in fade-in duration-500">
          <section class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="bg-white/5 border border-white/10 p-6 rounded-[30px] relative overflow-hidden group">
              <p class="text-white/20 text-[8px] font-black uppercase tracking-widest mb-1">Cortes de Hoy (Tus ingresos)</p>
              <p class="text-3xl font-black italic tracking-tighter text-brand-primary">
                {{ personalCitasAgendadas.length + personalCitasEspera.length }}
              </p>
            </div>
            <div class="bg-gradient-to-br from-brand-primary to-yellow-600 p-6 rounded-[30px] text-black shadow-xl shadow-brand-primary/10 relative overflow-hidden">
               <Zap class="absolute -right-2 -bottom-2 w-20 h-20 opacity-10" />
               <p class="text-[8px] font-black uppercase tracking-widest mb-1 opacity-60">Siguiente Turno</p>
               <p class="text-2xl font-black italic tracking-tighter uppercase leading-none truncate">
                 {{ [...personalCitasAgendadas, ...personalCitasEspera][0]?.nombre_cliente_manual || [...personalCitasAgendadas, ...personalCitasEspera][0]?.cliente?.nombre || 'LIBRE' }}
               </p>
            </div>
          </section>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 pb-10">
            <!-- Turnos de Hoy -->
            <div class="space-y-4">
              <h3 class="text-sm font-black uppercase italic tracking-tighter flex items-center gap-2 px-2 text-white/40">
                <Calendar class="w-4 h-4 text-brand-primary" /> Turnos de Hoy
              </h3>
              <div v-if="personalCitasAgendadas.length === 0" class="py-12 text-center border border-dashed border-white/5 rounded-3xl text-white/5 italic text-xs">
                Agenda libre.
              </div>
              <div v-for="cita in personalCitasAgendadas" :key="cita.id" class="bg-white/[0.02] border border-white/5 p-4 rounded-3xl flex items-center gap-4 hover:border-brand-primary/20 transition-all group">
                <div class="w-14 h-14 bg-brand-primary text-black rounded-2xl flex flex-col items-center justify-center shrink-0 shadow-lg border border-brand-primary/20">
                  <span class="text-[7px] font-black uppercase tracking-widest mb-0.5 leading-none">Hora</span>
                  <span class="text-lg font-black italic leading-none">
                    {{ new Date(cita.fecha_hora).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }) }}
                  </span>
                </div>
                <div class="flex-1 min-w-0">
                  <h4 class="text-base font-black uppercase italic tracking-tighter truncate">{{ cita.nombre_cliente_manual || cita.cliente?.nombre || 'Cliente' }}</h4>
                  <p class="text-white/30 text-[8px] font-black uppercase tracking-widest mt-1 flex items-center gap-1.5"><Scissors class="w-3.5 h-3.5 text-brand-primary" /> {{ cita.servicios?.nombre }}</p>
                </div>
                <div class="flex gap-2">
                  <button @click="cancelarCitaPersonal(cita.id)" class="w-10 h-10 flex items-center justify-center rounded-xl bg-white/5 text-white/20 hover:text-red-500 cursor-pointer transition-colors"><X class="w-4 h-4" /></button>
                  <button @click="completarCitaPersonal(cita.id)" class="w-10 h-10 flex items-center justify-center rounded-xl bg-brand-primary text-black shadow-lg cursor-pointer hover:scale-[1.05] duration-300 transition-transform"><UserCheck class="w-5 h-5" /></button>
                </div>
              </div>
            </div>

            <!-- Lista de Espera -->
            <div class="space-y-4">
              <h3 class="text-sm font-black uppercase italic tracking-tighter flex items-center gap-2 px-2 text-white/40">
                <Users class="w-4 h-4 text-white/30" /> Lista de Espera
              </h3>
              <div v-if="personalCitasEspera.length === 0" class="py-12 text-center border border-dashed border-white/5 rounded-3xl text-white/5 italic text-xs">
                Sin clientes en espera.
              </div>
              <div v-for="(espera, index) in personalCitasEspera" :key="espera.id" class="bg-white/[0.02] border border-white/5 p-4 rounded-3xl flex items-center gap-4 hover:border-brand-primary/20 transition-all group">
                <div class="w-12 h-12 bg-white/5 border border-white/10 rounded-2xl flex flex-col items-center justify-center shrink-0">
                  <span class="text-[7px] font-black text-white/20 uppercase mb-0.5">POS.</span>
                  <span class="text-xl font-black italic leading-none text-brand-primary">#{{ index + 1 }}</span>
                </div>
                <div class="flex-1 min-w-0">
                  <h4 class="text-base font-black uppercase italic tracking-tighter text-white/80 truncate">{{ espera.nombre_cliente_manual }}</h4>
                  <p class="text-brand-primary/50 text-[8px] font-black uppercase tracking-widest mt-1 flex items-center gap-1.5"><Scissors class="w-3.5 h-3.5" /> {{ espera.servicios?.nombre }}</p>
                </div>
                <button @click="completarCitaPersonal(espera.id)" class="px-6 h-12 bg-white/5 hover:bg-brand-primary hover:text-black border border-white/5 hover:border-brand-primary rounded-2xl text-[9px] font-black uppercase italic tracking-tighter transition-all cursor-pointer">FINALIZAR</button>
              </div>
            </div>
          </div>
        </div>

        <!-- Tab: Nómina -->
        <div v-if="activeTab === 'nomina'" class="space-y-8 animate-in fade-in duration-500">
           <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div class="bg-white/5 border border-white/10 p-6 rounded-3xl group relative overflow-hidden"><p class="text-white/20 text-[8px] font-black uppercase tracking-widest mb-1">Ingresos Totales (Mes)</p><p class="text-3xl font-black italic tracking-tighter leading-none text-white">${{ ingresosMes.toLocaleString() }}</p></div>
              <div class="bg-brand-primary p-6 rounded-3xl text-black shadow-xl shadow-brand-primary/20 group relative overflow-hidden"><DollarSign class="absolute -right-2 -bottom-2 w-20 h-20 opacity-10" /><p class="text-[8px] font-black uppercase tracking-widest mb-1 opacity-60">Total Nómina a Pagar</p><p class="text-3xl font-black italic tracking-tighter leading-none">${{ totalNominaPagar.toLocaleString() }}</p></div>
           </div>
           <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div v-for="b in nominaData" :key="b.id" class="bg-white/5 border border-white/10 p-6 rounded-[30px] space-y-6 hover:border-brand-primary/30 transition-all group">
                 <div class="flex items-center justify-between">
                   <div class="flex items-center gap-4">
                     <div class="w-12 h-12 bg-white/10 rounded-2xl flex items-center justify-center font-black text-xl italic text-brand-primary">{{ b.nombre[0] }}</div>
                     <div>
                       <h4 class="text-xl font-black uppercase italic tracking-tighter leading-none">{{ b.nombre }}</h4>
                       <span class="px-2 py-0.5 bg-white/10 text-white/40 text-[7px] font-black uppercase tracking-widest rounded-full mt-2 inline-block">Modelo: {{ b.modelo_pago || 'Porcentaje' }}</span>
                     </div>
                   </div>
                   <Tooltip text="CONFIGURAR MODELO Y MONTO DE PAGO PARA ESTE BARBERO" position="left">
                     <button @click="openConfigPago(b)" class="p-2 text-white/20 hover:text-brand-primary hover:bg-brand-primary/10 rounded-xl transition-all cursor-pointer"><Settings class="w-5 h-5" /></button>
                   </Tooltip>
                 </div>
                 <div class="grid grid-cols-3 gap-4 border-y border-white/5 py-4"><div class="text-center"><p class="text-[7px] font-black text-white/20 uppercase tracking-widest mb-1">Servicios</p><p class="text-lg font-black italic text-white">{{ b.citasCount }}</p></div><div class="text-center border-x border-white/5"><p class="text-[7px] font-black text-white/20 uppercase tracking-widest mb-1">Generado</p><p class="text-lg font-black italic text-white">${{ b.totalIngresos.toLocaleString() }}</p></div><div class="text-center"><p class="text-[7px] font-black text-brand-primary uppercase tracking-widest mb-1">Su Pago</p><p class="text-lg font-black italic text-brand-primary">${{ b.aPagar.toLocaleString() }}</p></div></div>
                 <Tooltip text="REGISTRAR PAGO REALIZADO Y REINICIAR ACUMULADO MENSUAL" position="top" class="w-full">
                   <button @click="registrarPago(b)" class="w-full bg-white/5 hover:bg-brand-primary hover:text-black py-3 rounded-2xl text-[10px] font-black uppercase tracking-widest transition-all cursor-pointer flex items-center justify-center gap-2"><CreditCard class="w-4 h-4" /> Marcar como Pagado</button>
                 </Tooltip>
              </div>
           </div>
        </div>

        <!-- Tab: Clientes VIP -->
        <div v-if="activeTab === 'clientes'" class="space-y-6 animate-in fade-in duration-500">
           <div class="flex items-center justify-between"><h2 class="text-2xl font-black uppercase italic tracking-tighter">Fidelidad de Clientes</h2><p class="text-white/20 text-[10px] font-bold uppercase tracking-widest">{{ clientesData.length }} clientes únicos</p></div>
           <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"><div v-for="c in clientesData" :key="c.nombre" class="bg-white/5 border border-white/5 p-6 rounded-3xl flex items-center justify-between group hover:border-brand-primary/30 transition-all"><div class="flex items-center gap-4"><div class="w-10 h-10 bg-white/5 rounded-xl flex items-center justify-center text-white/20 group-hover:text-brand-primary transition-colors"><Users class="w-5 h-5" /></div><div><h4 class="text-base font-black uppercase italic tracking-tighter leading-none">{{ c.nombre }}</h4><p class="text-white/10 text-[8px] font-black uppercase tracking-widest mt-1">{{ c.email }}</p></div></div><div class="text-right"><div class="flex items-baseline gap-1 justify-end"><span class="text-2xl font-black italic tracking-tighter text-brand-primary">{{ c.visitas }}</span><span class="text-[8px] font-black text-white/20 uppercase tracking-widest">Visitas</span></div><span v-if="c.visitas >= 3" class="px-2 py-0.5 bg-brand-primary text-black text-[7px] font-black uppercase tracking-widest rounded-full">CLIENTE VIP</span></div></div></div>
        </div>

        <!-- Tab: Resumen -->
        <div v-if="activeTab === 'resumen'" class="space-y-8 animate-in fade-in duration-500">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div class="bg-gradient-to-br from-brand-primary to-yellow-600 p-6 rounded-3xl text-black shadow-xl shadow-brand-primary/10 relative overflow-hidden group"><DollarSign class="absolute -right-2 -bottom-2 w-20 h-20 opacity-10" /><p class="text-[8px] font-black uppercase tracking-widest mb-1 opacity-60">Ingresos Mes</p><p class="text-3xl font-black italic tracking-tighter leading-none">${{ ingresosMes.toLocaleString() }}</p></div>
            <div class="bg-white/5 border border-white/10 p-6 rounded-3xl group relative overflow-hidden"><Users class="absolute -right-2 -bottom-2 w-20 h-20 opacity-5" /><p class="text-white/20 text-[8px] font-black uppercase tracking-widest mb-1">Equipo</p><p class="text-3xl font-black italic tracking-tighter leading-none">{{ barberosActivos.length }}</p></div>
            <div class="bg-white/5 border border-white/10 p-6 rounded-3xl group relative overflow-hidden"><Calendar class="absolute -right-2 -bottom-2 w-20 h-20 opacity-5" /><p class="text-white/20 text-[8px] font-black uppercase tracking-widest mb-1">Hoy</p><p class="text-3xl font-black italic tracking-tighter leading-none text-brand-primary">{{ citasHoyCount }}</p></div>
          </div>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8"><div class="card p-6 bg-white/[0.02] border border-white/5 rounded-3xl"><h3 class="text-sm font-black uppercase italic tracking-tighter mb-6 flex items-center gap-2"><TrendingUp class="w-4 h-4 text-brand-primary" /> Productividad Equipo</h3><div v-if="productividadEquipo.length === 0" class="py-6 text-center text-white/5 italic text-xs">Sin datos...</div><div v-else class="space-y-4"><div v-for="p in productividadEquipo" :key="p.nombre" class="flex items-center gap-4 p-4 bg-white/5 rounded-2xl border border-white/5 group"><div class="flex-1"><p class="font-black uppercase italic tracking-tighter text-sm">{{ p.nombre }}</p><div class="w-full bg-white/5 h-1.5 rounded-full mt-2 overflow-hidden"><div class="bg-brand-primary h-full transition-all duration-1000" :style="{ width: (p.total / (ingresosMes || 1) * 100) + '%' }"></div></div></div><p class="text-lg font-black italic tracking-tighter text-brand-primary">${{ p.total.toLocaleString() }}</p></div></div></div><div class="card p-6 bg-white/[0.02] border border-white/5 rounded-3xl"><h3 class="text-sm font-black uppercase italic tracking-tighter mb-6 flex items-center gap-2"><Award class="w-4 h-4 text-brand-primary" /> Servicios Estrella</h3><div v-if="topServicios.length === 0" class="py-6 text-center text-white/5 italic text-xs">Sin datos...</div><div v-else class="space-y-3"><div v-for="s in topServicios" :key="s.nombre" class="flex items-center justify-between p-4 bg-brand-primary/5 rounded-2xl border border-brand-primary/10"><p class="font-black uppercase italic tracking-tighter text-sm">{{ s.nombre }}</p><div class="flex items-center gap-1.5"><span class="text-xl font-black italic tracking-tighter text-white">{{ s.count }}</span><span class="text-[8px] font-black text-white/30 uppercase tracking-widest italic">Citas</span></div></div></div></div></div>
        </div>

        <!-- Tab: Citas -->
        <div v-if="activeTab === 'citas'" class="animate-in fade-in duration-500">
           <div class="overflow-hidden border border-white/5 rounded-3xl bg-white/[0.02]"><table class="w-full text-left border-collapse"><thead><tr class="bg-white/5 text-white/20 text-[9px] font-black uppercase tracking-widest"><th class="px-6 py-4">Fecha & Hora</th><th class="px-6 py-4">Barbero</th><th class="px-6 py-4">Cliente</th><th class="px-6 py-4">Estado</th><th class="px-6 py-4 text-right">Precio</th></tr></thead><tbody class="divide-y divide-white/5"><tr v-for="c in todasLasCitas" :key="c.id" class="hover:bg-white/[0.02] transition-colors"><td class="px-6 py-4"><p class="font-black text-base uppercase italic tracking-tighter leading-none">{{ new Date(c.fecha_hora).toLocaleDateString([], { day: 'numeric', month: 'short' }) }}</p><p class="text-[9px] text-white/20 font-bold uppercase tracking-widest">{{ new Date(c.fecha_hora).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }}</p></td><td class="px-6 py-4"><p class="font-black uppercase italic tracking-tighter text-white/80 text-sm">{{ c.barbero?.nombre || 'Manual' }}</p></td><td class="px-6 py-4 text-xs font-bold uppercase text-white/30 tracking-widest">{{ c.nombre_cliente_manual || 'App User' }}</td><td class="px-6 py-4"><span :class="['px-3 py-1 rounded-full text-[8px] font-black uppercase tracking-widest', c.estado === 'completada' ? 'bg-green-500/10 text-green-500' : 'bg-brand-primary/10 text-brand-primary']">{{ c.estado }}</span></td><td class="px-6 py-4 text-right font-black text-xl italic tracking-tighter text-white">${{ c.servicios?.precio }}</td></tr></tbody></table></div>
        </div>

        <!-- Tab: Ajustes -->
        <div v-if="activeTab === 'config'" class="animate-in fade-in duration-500 max-w-lg mx-auto py-6 space-y-6">
           <div class="bg-white/5 border border-white/10 rounded-[40px] p-8 space-y-8 relative overflow-hidden">
             <h3 class="text-2xl font-black uppercase italic tracking-tighter leading-none flex items-center gap-3"><Settings class="w-6 h-6 text-brand-primary" /> Identidad de Marca</h3>
             <div class="space-y-6">
               <div>
                 <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2">Nombre Comercial</label>
                 <input v-model="newBarberia.nombre" type="text" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 outline-none focus:border-brand-primary font-black uppercase italic tracking-tighter text-lg" />
               </div>
               <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                 <div>
                   <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2 flex items-center gap-1"><ImageIcon class="w-3 h-3" /> URL Logo</label>
                   <input v-model="newBarberia.logo_url" type="text" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 outline-none focus:border-brand-primary text-xs font-medium" placeholder="https://...png" />
                 </div>
                 <div>
                   <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2 flex items-center gap-1"><ImageIcon class="w-3 h-3" /> URL Banner</label>
                   <input v-model="newBarberia.banner_url" type="text" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 outline-none focus:border-brand-primary text-xs font-medium" placeholder="https://...jpg" />
                 </div>
               </div>
               <div class="grid grid-cols-2 gap-4">
                 <div>
                   <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2 text-brand-primary">Apertura</label>
                   <input v-model="newBarberia.hora_apertura" type="time" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 outline-none focus:border-brand-primary font-black text-lg" />
                 </div>
                 <div>
                   <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2 text-brand-primary">Cierre</label>
                   <input v-model="newBarberia.hora_cierre" type="time" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 outline-none focus:border-brand-primary font-black text-lg" />
                 </div>
               </div>
               <button @click="saveBarberiaConfig" :disabled="loading" class="w-full btn-primary py-5 text-xl font-black uppercase italic tracking-tighter shadow-xl shadow-brand-primary/20 cursor-pointer">{{ loading ? 'GUARDANDO...' : 'GUARDAR CAMBIOS' }}</button>
             </div>
           </div>

           <!-- Panel Rol Híbrido (Dueño-Barbero) -->
           <div class="bg-white/5 border border-white/10 rounded-[40px] p-8 space-y-6 relative overflow-hidden">
             <div class="flex items-center justify-between">
               <div>
                 <h4 class="text-lg font-black uppercase italic tracking-tighter leading-none mb-1 flex items-center gap-2">
                   <Scissors class="w-5 h-5 text-brand-primary" /> ¿También trabajas como barbero?
                 </h4>
                 <p class="text-white/30 text-[8px] font-bold uppercase tracking-widest mt-1">Actívalo para aparecer disponible en la agenda de reservas</p>
               </div>
               <button @click="toggleTrabajarComoBarbero" :disabled="loading" class="w-12 h-6 rounded-full p-1 transition-colors duration-300 relative cursor-pointer outline-none border border-white/5" :class="currentUserProfile?.es_barbero ? 'bg-brand-primary' : 'bg-white/10'">
                 <div class="w-4 h-4 bg-black rounded-full transition-transform duration-300" :class="currentUserProfile?.es_barbero ? 'translate-x-6' : 'translate-x-0'"></div>
               </button>
             </div>

             <!-- Configuración de Comisión del Dueño si es Barbero -->
             <div v-if="currentUserProfile?.es_barbero" class="border-t border-white/5 pt-6 space-y-6 animate-in slide-in-from-top-4 duration-300">
               <h5 class="text-[9px] font-black uppercase tracking-widest text-brand-primary">Tus Ganancias Personales</h5>
               <div class="grid grid-cols-2 gap-4">
                 <div>
                   <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Modelo de Pago</label>
                   <select v-model="currentUserProfile.modelo_pago" class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3 outline-none focus:border-brand-primary font-black uppercase italic text-xs text-white cursor-pointer">
                     <option value="porcentaje" class="bg-brand-dark">Porcentaje (%)</option>
                     <option value="fijo_servicio" class="bg-brand-dark">Fijo por Servicio ($)</option>
                     <option value="salario_fijo" class="bg-brand-dark">Salario Fijo ($)</option>
                   </select>
                 </div>
                 <div>
                   <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">
                     {{ currentUserProfile.modelo_pago === 'porcentaje' ? 'Porcentaje (%)' : 'Monto ($)' }}
                   </label>
                   <input v-model.number="currentUserProfile.pago_valor" type="number" class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3 outline-none focus:border-brand-primary font-black text-base text-white" />
                 </div>
               </div>
               <button @click="guardarConfigComisionOwner" :disabled="loading" class="w-full bg-white/5 hover:bg-brand-primary hover:text-black border border-white/5 hover:border-brand-primary py-4 rounded-2xl text-[10px] font-black uppercase tracking-widest transition-all cursor-pointer flex items-center justify-center gap-2">
                 <DollarSign class="w-4 h-4" /> Guardar Comisión Personal
               </button>
             </div>
           </div>
        </div>

        <!-- Feedback -->
        <div v-if="activeTab === 'resenas'" class="space-y-6 animate-in fade-in duration-500"><div class="flex items-center justify-between"><h2 class="text-xl font-black uppercase italic tracking-tighter">Feedback</h2><p class="text-white/20 text-[9px] font-bold uppercase tracking-widest">{{ todasLasResenas.length }} opiniones</p></div><div v-if="todasLasResenas.length === 0" class="py-12 text-center border-2 border-dashed border-white/5 rounded-3xl text-white/10 italic text-xs">Sin reseñas.</div><div v-else class="grid grid-cols-1 lg:grid-cols-2 gap-4"><div v-for="r in todasLasResenas" :key="r.id" class="bg-white/5 border border-white/5 p-6 rounded-3xl hover:border-brand-primary/20 transition-all"><div class="flex items-center justify-between mb-4"><div class="flex items-center gap-3"><div class="w-10 h-10 bg-white/10 rounded-xl flex items-center justify-center font-black uppercase italic text-brand-primary text-sm">{{ r.cliente?.nombre?.[0] }}</div><div><h4 class="font-black uppercase italic tracking-tighter text-sm">{{ r.cliente?.nombre }}</h4><p class="text-[8px] font-black text-white/20 uppercase tracking-widest">Atendido por: {{ r.barbero?.nombre }}</p></div></div><div class="flex items-center gap-1 bg-brand-primary text-black px-2 py-0.5 rounded-full text-[10px] font-black"><Star class="w-2.5 h-2.5 fill-current" />{{ r.calificacion }}</div></div><p class="text-white/70 italic text-xs leading-relaxed font-medium">"{{ r.comentario || 'Sin comentario' }}"</p></div></div></div>

        <!-- Servicios -->
        <div v-if="activeTab === 'servicios'" class="grid grid-cols-1 md:grid-cols-3 gap-6 animate-in fade-in duration-500"><div v-for="servicio in servicios" :key="servicio.id" class="bg-white/5 border border-white/5 p-6 rounded-3xl hover:border-brand-primary/30 group relative transition-all"><div class="flex justify-between items-start mb-4"><div class="w-8 h-8 bg-brand-primary/10 rounded-lg flex items-center justify-center text-brand-primary"><Scissors class="w-4 h-4" /></div><button @click="deleteServicio(servicio.id)" class="opacity-0 group-hover:opacity-100 p-2 text-red-500 hover:bg-red-500/10 rounded-lg transition-all cursor-pointer"><Trash2 class="w-4 h-4" /></button></div><h4 class="text-lg font-black uppercase italic tracking-tighter mb-1">{{ servicio.nombre }}</h4><p class="text-white/20 text-[9px] font-black uppercase tracking-widest mb-4 flex items-center gap-1.5"><Clock class="w-3 h-3" /> {{ servicio.duracion_minutos }} MIN</p><div class="flex items-end justify-between"><p class="text-2xl font-black italic tracking-tighter text-brand-primary leading-none">${{ servicio.precio }}</p><button class="p-2 bg-white/5 rounded-lg opacity-20 hover:opacity-100 cursor-pointer"><Edit2 class="w-3 h-3" /></button></div></div></div>

        <!-- Equipo -->
        <div v-if="activeTab === 'equipo'" class="space-y-8 animate-in fade-in duration-500">
          <div v-if="solicitudesPendientes.length > 0" class="space-y-4">
            <h3 class="text-sm font-black uppercase italic tracking-tighter text-brand-primary flex items-center gap-2"><UserCheck class="w-4 h-4" /> Pendientes</h3>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div v-for="s in solicitudesPendientes" :key="s.id" class="bg-brand-primary/5 border border-brand-primary/20 p-5 rounded-2xl flex items-center justify-between">
                <div class="flex items-center gap-4">
                  <div class="w-10 h-10 bg-brand-primary/20 rounded-xl flex items-center justify-center text-brand-primary"><Users class="w-5 h-5" /></div>
                  <div>
                    <h4 class="text-lg font-black uppercase italic tracking-tighter leading-none mb-1">{{ s.nombre }}</h4>
                    <p class="text-brand-primary/50 text-[8px] font-black uppercase tracking-widest">{{ s.email }}</p>
                  </div>
                </div>
                <div class="flex gap-2">
                  <Tooltip text="RECHAZAR SOLICITUD" position="top">
                    <button @click="gestionarSolicitud(s.id, 'ninguno')" class="w-8 h-8 flex items-center justify-center rounded-lg bg-red-500/10 text-red-500 cursor-pointer"><UserX class="w-4 h-4" /></button>
                  </Tooltip>
                  <Tooltip text="APROBAR E INTEGRAR AL EQUIPO" position="top">
                    <button @click="gestionarSolicitud(s.id, 'aprobado')" class="w-8 h-8 flex items-center justify-center rounded-lg bg-brand-primary text-black cursor-pointer"><UserCheck class="w-4 h-4" /></button>
                  </Tooltip>
                </div>
              </div>
            </div>
          </div>
          <div class="space-y-4">
            <h3 class="text-sm font-black uppercase italic tracking-tighter text-white/20 flex items-center gap-2"><Briefcase class="w-4 h-4" /> Equipo Oficial</h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div v-for="b in barberosActivos" :key="b.id" class="bg-white/5 border border-white/5 p-6 rounded-3xl flex flex-col items-center text-center group transition-all relative overflow-hidden">
                <div class="absolute -right-6 -bottom-6 w-16 h-16 bg-brand-primary/5 rounded-full blur-xl group-hover:bg-brand-primary/10 transition-colors"></div>
                <div class="w-12 h-12 bg-white/5 rounded-xl flex items-center justify-center mb-4 border border-white/10 group-hover:bg-brand-primary/10 transition-all"><Users class="w-6 h-6 text-white/10 group-hover:text-brand-primary" /></div>
                <h4 class="text-xl font-black uppercase italic tracking-tighter leading-none mb-1">{{ b.nombre }}</h4>
                <div class="flex items-center gap-2 mb-4">
                  <div class="flex items-center gap-1 bg-brand-primary text-black px-1.5 py-0.5 rounded text-[8px] font-black"><Star class="w-2.5 h-2.5 fill-current" />{{ b.rating > 0 ? b.rating.toFixed(1) : '0.0' }}</div>
                  <p class="text-white/20 text-[8px] font-black uppercase tracking-widest italic">{{ b.totalResenas }} OPINIONES</p>
                </div>
                <div class="flex gap-2 w-full mt-auto">
                  <button @click="abrirServiciosBarberoModal(b)" class="flex-1 py-2.5 bg-white/5 text-white/40 hover:bg-brand-primary hover:text-black border border-white/5 hover:border-brand-primary text-[8px] font-black uppercase tracking-widest rounded-full transition-all cursor-pointer">Servicios</button>
                  <button @click="gestionarSolicitud(b.id, 'ninguno')" class="flex-1 py-2.5 bg-red-500/5 text-red-500/40 hover:bg-red-500/20 hover:text-red-500 text-[8px] font-black uppercase tracking-widest rounded-full transition-all cursor-pointer">Revocar</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>

    <!-- Modales -->
    <div v-if="showConfigPagoModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[110] flex items-center justify-center p-4"><div class="w-full max-w-sm bg-brand-surface border border-white/10 p-8 rounded-[40px] shadow-2xl relative animate-in zoom-in-95"><h2 class="text-2xl font-black uppercase italic tracking-tighter mb-8">Configurar Pago: {{ barberoAConfigurar?.nombre }}</h2><div class="space-y-6"><div><label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2">Modelo de Pago</label><select v-model="configPago.modelo" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 outline-none focus:border-brand-primary font-black uppercase italic tracking-tighter text-white"><option value="porcentaje">Porcentaje (%)</option><option value="fijo_servicio">Fijo por Servicio ($)</option><option value="salario_fijo">Salario Fijo ($)</option></select></div><div><label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2">{{ configPago.modelo === 'porcentaje' ? 'Porcentaje (%)' : 'Monto ($)' }}</label><input v-model="configPago.valor" type="number" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 outline-none focus:border-brand-primary font-black text-xl" /></div><div class="flex gap-4 pt-4"><button @click="showConfigPagoModal = false" class="flex-1 py-4 text-white/20 font-black uppercase text-[10px] tracking-widest cursor-pointer">Cancelar</button><button @click="guardarConfigPago" :disabled="loading" class="flex-[2] btn-primary py-4 font-black uppercase italic tracking-tighter text-xl">Guardar</button></div></div></div></div>

    <!-- Modal Registro/Configuración de Barbería -->
    <div v-if="showBarberiaModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[105] flex items-center justify-center p-4">
      <div class="w-full max-w-md bg-brand-surface border border-brand-primary/20 p-8 rounded-[40px] shadow-2xl relative animate-in zoom-in-95">
        <h2 class="text-2xl font-black uppercase italic tracking-tighter mb-6 text-brand-primary">
          {{ barberia ? 'Editar Identidad de Marca' : 'Registra tu Barbería' }}
        </h2>
        <p class="text-white/40 text-xs font-medium mb-6 italic leading-relaxed">
          {{ barberia ? 'Modifica los datos comerciales de tu marca.' : 'Para comenzar a administrar, registra los datos principales de tu barbería.' }}
        </p>
        
        <div class="space-y-4">
          <div>
            <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Nombre Comercial</label>
            <input v-model="newBarberia.nombre" type="text" placeholder="Ej. Barbieri Luxury" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary font-black uppercase italic tracking-tighter text-base" />
          </div>
          
          <div>
            <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Dirección Física</label>
            <input v-model="newBarberia.direccion" type="text" placeholder="Ej. Av. Central #123" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary text-xs font-semibold" />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Apertura</label>
              <input v-model="newBarberia.hora_apertura" type="time" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary font-black text-base" />
            </div>
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Cierre</label>
              <input v-model="newBarberia.hora_cierre" type="time" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary font-black text-base" />
            </div>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Logo URL (Opcional)</label>
              <input v-model="newBarberia.logo_url" type="text" placeholder="https://..." class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3 outline-none focus:border-brand-primary text-[10px] font-medium" />
            </div>
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Banner URL (Opcional)</label>
              <input v-model="newBarberia.banner_url" type="text" placeholder="https://..." class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3 outline-none focus:border-brand-primary text-[10px] font-medium" />
            </div>
          </div>

          <div class="flex gap-4 pt-6">
            <button v-if="barberia" @click="showBarberiaModal = false" class="flex-1 py-4 text-white/20 font-black uppercase text-[10px] tracking-widest cursor-pointer hover:text-white transition-colors">
              Cancelar
            </button>
            <button @click="saveBarberiaConfig" :disabled="loading" class="flex-[2] btn-primary py-4 font-black uppercase italic tracking-tighter text-lg cursor-pointer">
              {{ loading ? 'Guardando...' : 'Guardar Barbería' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal Crear/Añadir Servicio -->
    <div v-if="showServicioModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[105] flex items-center justify-center p-4">
      <div class="w-full max-w-sm bg-brand-surface border border-white/10 p-8 rounded-[40px] shadow-2xl relative animate-in zoom-in-95">
        <h2 class="text-2xl font-black uppercase italic tracking-tighter mb-6 text-brand-primary">Nuevo Servicio</h2>
        <p class="text-white/40 text-xs italic mb-6 leading-relaxed">
          Añade un nuevo servicio al catálogo para que tus clientes y barberos puedan agendarlo.
        </p>
        
        <div class="space-y-4">
          <div>
            <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Nombre del Servicio</label>
            <input v-model="newServicio.nombre" type="text" placeholder="Ej. Corte Elite + Barba" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary font-black uppercase italic tracking-tighter text-base" />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Precio ($)</label>
              <input v-model="newServicio.precio" type="number" placeholder="Ej. 25" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary font-black text-lg" />
            </div>
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Duración (Minutos)</label>
              <input v-model="newServicio.duracion_minutos" type="number" placeholder="Ej. 30" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary font-black text-lg" />
            </div>
          </div>

          <div class="flex gap-4 pt-6">
            <button @click="showServicioModal = false" class="flex-1 py-4 text-white/20 font-black uppercase text-[10px] tracking-widest cursor-pointer hover:text-white transition-colors">
              Cancelar
            </button>
            <button @click="saveServicio" :disabled="!newServicio.nombre || !newServicio.precio" class="flex-[2] btn-primary py-4 font-black uppercase italic tracking-tighter text-lg cursor-pointer">
              Guardar Servicio
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal Registrar Cita Manual -->
    <div v-if="showManualCitaModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[105] flex items-center justify-center p-4">
      <div class="w-full max-w-md bg-brand-surface border border-white/10 p-8 rounded-[40px] shadow-2xl relative animate-in zoom-in-95">
        <h2 class="text-2xl font-black uppercase italic tracking-tighter mb-6 text-brand-primary flex items-center gap-2">
          <UserPlus class="w-6 h-6 text-brand-primary" /> Cita Manual
        </h2>
        <p class="text-white/40 text-xs italic mb-6 leading-relaxed">
          Agenda turnos presenciales de clientes que se encuentren físicamente en el local.
        </p>
        
        <div class="space-y-4">
          <div>
            <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Nombre del Cliente</label>
            <input v-model="manualCita.cliente_nombre" type="text" placeholder="Ej. Carlos Pérez" class="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-3.5 outline-none focus:border-brand-primary font-black uppercase italic tracking-tighter text-base" />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Asignar Barbero</label>
              <select v-model="manualCita.barbero_id" class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3.5 outline-none focus:border-brand-primary font-black uppercase italic text-sm text-white cursor-pointer">
                <option value="" disabled class="bg-brand-dark">Seleccionar...</option>
                <option v-for="b in todosLosBarberosActivosYOwner" :key="b.id" :value="b.id" class="bg-brand-dark">
                  {{ b.nombre.toUpperCase() }}
                </option>
              </select>
            </div>
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Servicio Requerido</label>
              <select v-model="manualCita.servicio_id" class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3.5 outline-none focus:border-brand-primary font-black uppercase italic text-sm text-white cursor-pointer">
                <option value="" disabled class="bg-brand-dark">Seleccionar...</option>
                <option v-for="s in servicios" :key="s.id" :value="s.id" class="bg-brand-dark">
                  {{ s.nombre.toUpperCase() }} (${{ s.precio }})
                </option>
              </select>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Fecha del Turno</label>
              <input v-model="manualCita.fecha" type="date" class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3.5 outline-none focus:border-brand-primary font-black text-sm text-white cursor-pointer" :min="getLocalDateString()" />
            </div>
            <div>
              <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-1.5 px-2">Hora de la Cita</label>
              <input v-model="manualCita.hora" type="time" class="w-full bg-white/5 border border-white/10 rounded-2xl px-4 py-3.5 outline-none focus:border-brand-primary font-black text-sm text-white cursor-pointer" />
            </div>
          </div>

          <div class="flex gap-4 pt-6">
            <button @click="showManualCitaModal = false" class="flex-1 py-4 text-white/20 font-black uppercase text-[10px] tracking-widest cursor-pointer hover:text-white transition-colors">
              Cancelar
            </button>
            <button @click="agendarManual" :disabled="loading || !manualCita.cliente_nombre || !manualCita.barbero_id || !manualCita.servicio_id" class="flex-[2] btn-primary py-4 font-black uppercase italic tracking-tighter text-lg cursor-pointer">
              {{ loading ? 'Agendando...' : 'Agendar Turno' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Modal Configurar Servicios de Barbero (Badges Interactivos) -->
  <div v-if="showServiciosBarberoModal" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[115] flex items-center justify-center p-4">
    <div class="w-full max-w-md bg-brand-surface border border-white/10 p-8 rounded-[40px] shadow-2xl relative animate-in zoom-in-95">
      <button @click="showServiciosBarberoModal = false" class="absolute top-6 right-6 text-white/20 hover:text-white cursor-pointer"><X class="w-5 h-5" /></button>
      <h2 class="text-2xl font-black uppercase italic tracking-tighter mb-2 text-brand-primary">Asignar Servicios</h2>
      <p class="text-white/40 text-xs italic mb-6 leading-relaxed">
        Selecciona qué servicios puede realizar <span class="text-white font-bold">{{ barberoSeleccionado?.nombre }}</span>. Si no seleccionas ninguno, podrá realizar todos por defecto.
      </p>

      <div v-if="loadingAsignaciones" class="py-12 text-center animate-pulse text-white/10 text-xs">Cargando asignaciones...</div>
      
      <div v-else class="space-y-6">
        <div class="flex flex-wrap gap-2 max-h-[40vh] overflow-y-auto pr-2 custom-scrollbar">
          <button v-for="s in servicios" :key="s.id" @click="toggleServicioAsignado(s.id)" :class="['px-4 py-2.5 rounded-2xl text-[10px] font-black uppercase tracking-widest transition-all cursor-pointer flex items-center gap-1.5 border', serviciosAsignados.includes(s.id) ? 'bg-brand-primary text-black border-brand-primary shadow-lg shadow-brand-primary/10' : 'bg-white/5 text-white/40 border-white/5 hover:border-white/15 hover:text-white']">
            <span class="w-1.5 h-1.5 rounded-full shrink-0" :class="serviciosAsignados.includes(s.id) ? 'bg-black' : 'bg-white/20'"></span>
            {{ s.nombre }}
          </button>
        </div>

        <div class="flex gap-4 pt-4">
          <button @click="showServiciosBarberoModal = false" class="flex-1 py-4 text-white/20 font-black uppercase text-[10px] tracking-widest cursor-pointer hover:text-white transition-colors">Cancelar</button>
          <button @click="guardarServiciosBarbero" :disabled="loading" class="flex-[2] btn-primary py-4 font-black uppercase italic tracking-tighter text-base cursor-pointer">
            {{ loading ? 'Guardando...' : 'Guardar Servicios' }}
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Modal Agregar Cliente a Lista de Espera del Dueño -->
  <div v-if="showEsperaModalOwner" class="fixed inset-0 bg-black/95 backdrop-blur-xl z-[115] flex items-center justify-center p-4">
    <div class="w-full max-w-sm bg-brand-surface border border-white/10 rounded-[40px] p-8 shadow-2xl relative animate-in zoom-in-95">
      <button @click="showEsperaModalOwner = false" class="absolute top-6 right-6 text-white/20 hover:text-white cursor-pointer"><X class="w-5 h-5" /></button>
      <h2 class="text-2xl font-black uppercase italic tracking-tighter mb-8 flex items-center gap-3">
        <UserPlus class="text-brand-primary w-6 h-6" /> Nuevo Cliente
      </h2>
      <div class="space-y-4">
        <div>
          <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2">Nombre Cliente</label>
          <input v-model="newEsperaOwner.nombre_cliente" type="text" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 focus:border-brand-primary outline-none font-black uppercase italic tracking-tighter text-base" />
        </div>
        <div>
          <label class="block text-[8px] font-black text-white/20 uppercase tracking-widest mb-2 px-2">Servicio</label>
          <select v-model="newEsperaOwner.servicio_id" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 focus:border-brand-primary outline-none font-black uppercase italic text-white cursor-pointer">
            <option value="" class="bg-brand-dark">SELECCIONAR...</option>
            <option v-for="s in servicios" :key="s.id" :value="s.id" class="bg-brand-dark">{{ s.nombre.toUpperCase() }}</option>
          </select>
        </div>
        <div class="flex gap-4 pt-6">
          <button @click="showEsperaModalOwner = false" class="flex-1 py-4 text-white/20 font-black uppercase italic text-[10px] tracking-widest cursor-pointer hover:text-white transition-colors">Cerrar</button>
          <button @click="agregarAListaEsperaOwner" :disabled="loading" class="flex-[2] btn-primary py-4 font-black uppercase italic tracking-tighter text-xl cursor-pointer">Agregar</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.custom-scrollbar::-webkit-scrollbar { width: 4px; }
.custom-scrollbar::-webkit-scrollbar-track { background: transparent; }
.custom-scrollbar::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, 0.05); border-radius: 10px; }
</style>
