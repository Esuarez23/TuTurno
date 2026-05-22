<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { 
  LogOut, LayoutDashboard, Users, Scissors, Calendar, 
  Activity, Shield, ToggleLeft, ToggleRight, Plus, 
  TrendingUp, DollarSign,
  Search, RefreshCw
} from 'lucide-vue-next'
import { useNotifications } from '../../composables/useNotifications'
import { useConfirm } from '../../composables/useConfirm'

const router = useRouter()
const notify = useNotifications()
const { confirm } = useConfirm()

const activeTab = ref('resumen')
const adminName = ref('')
const loading = ref(false)
const searchQuery = ref('')

// Estadísticas globales
const stats = ref({
  totalUsuarios: 0,
  totalBarberias: 0,
  totalCitasMes: 0,
  ingresosMes: 0,
  usuariosHoy: 0,
  barberiaActivas: 0
})

// Datos de tablas
const usuarios = ref<any[]>([])
const barberias = ref<any[]>([])
const citas = ref<any[]>([])
const logs = ref<any[]>([])
const loadingData = ref(false)

// Filtros
const filtroRol = ref('todos')
const filtroEstado = ref('todos')

// Modal crear dueño + barbería
const showCreateOwnerModal = ref(false)
const newOwner = ref({ nombre: '', email: '', password: '' })
const newBarberiaManual = ref({ nombre: '', direccion: '', telefono: '' })

onMounted(async () => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) { router.push('/login'); return }
  
  // Verificar que es superadmin
  const { data: perfil } = await supabase.from('perfiles').select('rol, nombre').eq('id', session.user.id).single()
  if (!perfil || perfil.rol !== 'superadmin') { router.push('/'); return }
  
  adminName.value = perfil.nombre || session.user.email || 'Super Admin'
  await cargarTodo()
})

const cargarTodo = async () => {
  loadingData.value = true
  await Promise.all([fetchStats(), fetchUsuarios(), fetchBarberias(), fetchCitas(), fetchLogs()])
  loadingData.value = false
}

const fetchStats = async () => {
  const hoyInicio = new Date(); hoyInicio.setHours(0,0,0,0)
  const inicioMes = new Date(); inicioMes.setDate(1); inicioMes.setHours(0,0,0,0)

  const [
    { count: totalUsuarios },
    { count: totalBarberias },
    { count: barberiaActivas },
    { count: totalCitasMes },
    { count: usuariosHoy },
    { data: citasMes }
  ] = await Promise.all([
    supabase.from('perfiles').select('*', { count: 'exact', head: true }),
    supabase.from('barberias').select('*', { count: 'exact', head: true }),
    supabase.from('barberias').select('*', { count: 'exact', head: true }).eq('activo', true),
    supabase.from('citas').select('*', { count: 'exact', head: true }).gte('created_at', inicioMes.toISOString()),
    supabase.from('perfiles').select('*', { count: 'exact', head: true }).gte('created_at', hoyInicio.toISOString()),
    supabase.from('citas').select('precio_final').eq('estado', 'completada').gte('created_at', inicioMes.toISOString())
  ])

  stats.value = {
    totalUsuarios: totalUsuarios || 0,
    totalBarberias: totalBarberias || 0,
    barberiaActivas: barberiaActivas || 0,
    totalCitasMes: totalCitasMes || 0,
    usuariosHoy: usuariosHoy || 0,
    ingresosMes: (citasMes || []).reduce((acc, c) => acc + (Number(c.precio_final) || 0), 0)
  }
}

const fetchUsuarios = async () => {
  const { data } = await supabase.from('perfiles').select('*').order('created_at', { ascending: false })
  usuarios.value = data || []
}

const fetchBarberias = async () => {
  const { data } = await supabase.from('barberias').select('*, dueno:perfiles!dueno_id(nombre, email)').order('created_at', { ascending: false })
  barberias.value = data || []
}

const fetchCitas = async () => {
  const { data } = await supabase
    .from('citas')
    .select('*, barberia:barberias(nombre), barbero:perfiles!barbero_id(nombre), servicio:servicios(nombre)')
    .order('created_at', { ascending: false })
    .limit(100)
  citas.value = data || []
}

const fetchLogs = async () => {
  const { data } = await supabase.from('logs_actividad').select('*, usuario:perfiles(nombre, email)').order('created_at', { ascending: false }).limit(100)
  logs.value = data || []
}

// Activar/desactivar usuario
const toggleUsuario = async (usuario: any) => {
  const nuevoEstado = !usuario.activo
  const accion = nuevoEstado ? 'activar' : 'desactivar'
  const ok = await confirm({ title: `¿${accion.charAt(0).toUpperCase() + accion.slice(1)} usuario?`, message: `¿Confirmas que deseas ${accion} a ${usuario.nombre}?`, type: nuevoEstado ? 'info' : 'warning', confirmText: accion.charAt(0).toUpperCase() + accion.slice(1) })
  if (!ok) return
  const { error } = await supabase.from('perfiles').update({ activo: nuevoEstado }).eq('id', usuario.id)
  if (!error) { notify.success(`Usuario ${accion === 'activar' ? 'activado' : 'desactivado'}`); fetchUsuarios() }
}

// Cambiar rol de usuario
const cambiarRol = async (usuario: any, nuevoRol: string) => {
  const { error } = await supabase.from('perfiles').update({ rol: nuevoRol }).eq('id', usuario.id)
  if (!error) { notify.success('Rol actualizado'); fetchUsuarios() }
  else notify.error('Error al cambiar el rol')
}

// Activar/desactivar barbería
const toggleBarberia = async (b: any) => {
  const nuevoEstado = !b.activo
  const { error } = await supabase.from('barberias').update({ activo: nuevoEstado }).eq('id', b.id)
  if (!error) { notify.success(`Barbería ${nuevoEstado ? 'activada' : 'desactivada'}`); fetchBarberias(); fetchStats() }
}

// Eliminar barbería (con confirmación)
const eliminarBarberia = async (b: any) => {
  const ok = await confirm({ title: '¿Eliminar Barbería?', message: `Esto eliminará "${b.nombre}" y todos sus datos. Esta acción es irreversible.`, type: 'danger', confirmText: 'Sí, Eliminar' })
  if (!ok) return
  const { error } = await supabase.from('barberias').delete().eq('id', b.id)
  if (!error) { notify.success('Barbería eliminada'); fetchBarberias(); fetchStats() }
}

// Crear dueño y barbería manualmente
const crearDuenoBarberia = async () => {
  if (!newOwner.value.nombre || !newOwner.value.email || !newOwner.value.password) return notify.error('Completa todos los campos del dueño')
  loading.value = true
  try {
    // Crear usuario con email/password
    const { data, error: authError } = await supabase.auth.admin.createUser({
      email: newOwner.value.email,
      password: newOwner.value.password,
      user_metadata: { nombre: newOwner.value.nombre, rol: 'dueño' },
      email_confirm: true
    })
    if (authError) throw authError

    if (data.user && newBarberiaManual.value.nombre) {
      await supabase.from('barberias').insert([{
        dueno_id: data.user.id,
        nombre: newBarberiaManual.value.nombre,
        direccion: newBarberiaManual.value.direccion,
        telefono: newBarberiaManual.value.telefono,
      }])
    }
    notify.success(`Dueño ${newOwner.value.nombre} creado exitosamente`)
    showCreateOwnerModal.value = false
    newOwner.value = { nombre: '', email: '', password: '' }
    newBarberiaManual.value = { nombre: '', direccion: '', telefono: '' }
    cargarTodo()
  } catch (e: any) {
    notify.error(e.message || 'Error al crear el dueño')
  }
  loading.value = false
}

// Filtros computados
const usuariosFiltrados = computed(() => {
  return usuarios.value.filter(u => {
    const coincideRol = filtroRol.value === 'todos' || u.rol === filtroRol.value
    const coincideBusqueda = !searchQuery.value || 
      u.nombre?.toLowerCase().includes(searchQuery.value.toLowerCase()) ||
      u.email?.toLowerCase().includes(searchQuery.value.toLowerCase())
    return coincideRol && coincideBusqueda
  })
})

const barberiasFiltradas = computed(() => {
  return barberias.value.filter(b => {
    const coincideEstado = filtroEstado.value === 'todos' || (filtroEstado.value === 'activa' ? b.activo : !b.activo)
    const coincideBusqueda = !searchQuery.value || b.nombre?.toLowerCase().includes(searchQuery.value.toLowerCase())
    return coincideEstado && coincideBusqueda
  })
})

const rolColor = (rol: string) => {
  if (rol === 'superadmin') return 'text-purple-400 bg-purple-400/10 border-purple-400/20'
  if (rol === 'dueño' || rol === 'dueno') return 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20'
  if (rol === 'barbero') return 'text-blue-400 bg-blue-400/10 border-blue-400/20'
  return 'text-green-400 bg-green-400/10 border-green-400/20'
}

const estadoCitaColor = (estado: string) => {
  if (estado === 'completada') return 'text-green-400'
  if (estado === 'confirmada') return 'text-blue-400'
  if (estado === 'cancelada') return 'text-red-400'
  return 'text-yellow-400'
}

const formatFecha = (fecha: string) => new Date(fecha).toLocaleDateString('es-CO', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })

const handleLogout = async () => { await supabase.auth.signOut(); router.push('/') }
</script>

<template>
  <div class="min-h-screen bg-[#0A0A0A] text-white flex flex-col md:flex-row font-sans">

    <!-- Sidebar -->
    <aside class="w-full md:w-60 bg-[#111111] border-r border-white/5 flex flex-col shrink-0">
      <!-- Logo -->
      <div class="p-6 border-b border-white/5">
        <div class="flex items-center gap-3">
          <div class="w-9 h-9 bg-purple-500 rounded-xl flex items-center justify-center shadow-lg shadow-purple-500/30">
            <Shield class="w-5 h-5 text-white" />
          </div>
          <div>
            <p class="font-black text-sm tracking-tight">SUPER ADMIN</p>
            <p class="text-[10px] text-white/30 uppercase tracking-widest">TuTurno Platform</p>
          </div>
        </div>
      </div>

      <!-- Perfil admin -->
      <div class="px-4 py-3 border-b border-white/5">
        <p class="text-xs text-white/40">Sesión como</p>
        <p class="text-sm font-bold truncate text-purple-300">{{ adminName }}</p>
      </div>

      <!-- Navegación -->
      <nav class="flex-1 p-3 space-y-1">
        <button v-for="tab in [
          { id: 'resumen', label: 'Resumen', icon: LayoutDashboard },
          { id: 'usuarios', label: 'Usuarios', icon: Users },
          { id: 'barberias', label: 'Barberías', icon: Scissors },
          { id: 'citas', label: 'Todas las Citas', icon: Calendar },
          { id: 'logs', label: 'Logs de Actividad', icon: Activity }
        ]" :key="tab.id"
          @click="activeTab = tab.id; searchQuery = ''"
          :class="['w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all cursor-pointer',
            activeTab === tab.id 
              ? 'bg-purple-500/15 text-purple-300 border border-purple-500/20' 
              : 'text-white/40 hover:bg-white/5 hover:text-white/70']">
          <component :is="tab.icon" class="w-4 h-4 shrink-0" />
          {{ tab.label }}
        </button>
      </nav>

      <!-- Logout -->
      <div class="p-3 border-t border-white/5">
        <button @click="handleLogout" class="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm text-white/30 hover:text-red-400 hover:bg-red-400/5 transition-all cursor-pointer">
          <LogOut class="w-4 h-4" />
          Cerrar Sesión
        </button>
      </div>
    </aside>

    <!-- Contenido Principal -->
    <main class="flex-1 overflow-y-auto">
      <!-- Header -->
      <div class="sticky top-0 z-10 bg-[#0A0A0A]/90 backdrop-blur-sm border-b border-white/5 px-6 py-4 flex items-center justify-between">
        <div>
          <h1 class="text-lg font-black tracking-tight">
            {{ activeTab === 'resumen' ? 'Panel de Control' :
               activeTab === 'usuarios' ? 'Gestión de Usuarios' :
               activeTab === 'barberias' ? 'Gestión de Barberías' :
               activeTab === 'citas' ? 'Historial Global de Citas' : 'Logs de Actividad' }}
          </h1>
          <p class="text-xs text-white/30">Administración total de la plataforma</p>
        </div>
        <button @click="cargarTodo" :disabled="loadingData" class="flex items-center gap-2 px-4 py-2 bg-white/5 hover:bg-white/10 text-white/60 rounded-xl text-sm transition-all cursor-pointer border border-white/10">
          <RefreshCw class="w-4 h-4" :class="{ 'animate-spin': loadingData }" />
          Actualizar
        </button>
      </div>

      <div class="p-6 space-y-6">

        <!-- ======================== RESUMEN ======================== -->
        <div v-if="activeTab === 'resumen'" class="space-y-6">
          <!-- KPI Cards -->
          <div class="grid grid-cols-2 lg:grid-cols-3 gap-4">
            <div v-for="kpi in [
              { label: 'Total Usuarios', value: stats.totalUsuarios, icon: Users, color: 'purple', sub: `+${stats.usuariosHoy} hoy` },
              { label: 'Barberías Activas', value: stats.barberiaActivas, icon: Scissors, color: 'yellow', sub: `de ${stats.totalBarberias} totales` },
              { label: 'Citas este Mes', value: stats.totalCitasMes, icon: Calendar, color: 'blue', sub: 'total de citas' },
              { label: 'Ingresos del Mes', value: `$${stats.ingresosMes.toLocaleString()}`, icon: DollarSign, color: 'green', sub: 'solo completadas' },
              { label: 'Nuevos Hoy', value: stats.usuariosHoy, icon: TrendingUp, color: 'pink', sub: 'usuarios registrados' },
              { label: 'Total Barberías', value: stats.totalBarberias, icon: Activity, color: 'orange', sub: 'en la plataforma' }
            ]" :key="kpi.label"
              class="bg-[#111111] border border-white/5 rounded-2xl p-5 hover:border-white/10 transition-colors">
              <div class="flex items-start justify-between mb-4">
                <div :class="`w-10 h-10 rounded-xl flex items-center justify-center bg-${kpi.color}-500/10`">
                  <component :is="kpi.icon" :class="`w-5 h-5 text-${kpi.color}-400`" />
                </div>
              </div>
              <p class="text-2xl font-black tracking-tight">{{ kpi.value }}</p>
              <p class="text-xs text-white/40 mt-1">{{ kpi.label }}</p>
              <p class="text-[10px] text-white/20 mt-0.5">{{ kpi.sub }}</p>
            </div>
          </div>

          <!-- Últimas barberías registradas -->
          <div class="bg-[#111111] border border-white/5 rounded-2xl p-5">
            <h3 class="text-sm font-bold mb-4 flex items-center gap-2">
              <Scissors class="w-4 h-4 text-yellow-400" />
              Últimas Barberías Registradas
            </h3>
            <div class="space-y-2">
              <div v-for="b in barberias.slice(0, 5)" :key="b.id" class="flex items-center justify-between p-3 bg-white/3 rounded-xl">
                <div class="flex items-center gap-3">
                  <div class="w-8 h-8 bg-yellow-500/10 rounded-lg flex items-center justify-center">
                    <Scissors class="w-4 h-4 text-yellow-400" />
                  </div>
                  <div>
                    <p class="text-sm font-medium">{{ b.nombre }}</p>
                    <p class="text-xs text-white/30">{{ b.direccion || 'Sin dirección' }}</p>
                  </div>
                </div>
                <div :class="['text-xs px-2 py-1 rounded-lg border', b.activo ? 'text-green-400 bg-green-400/10 border-green-400/20' : 'text-red-400 bg-red-400/10 border-red-400/20']">
                  {{ b.activo ? 'Activa' : 'Inactiva' }}
                </div>
              </div>
              <p v-if="!barberias.length" class="text-center text-white/20 py-4 text-sm">Sin barberías registradas</p>
            </div>
          </div>

          <!-- Últimos logs -->
          <div class="bg-[#111111] border border-white/5 rounded-2xl p-5">
            <h3 class="text-sm font-bold mb-4 flex items-center gap-2">
              <Activity class="w-4 h-4 text-blue-400" />
              Actividad Reciente
            </h3>
            <div class="space-y-2">
              <div v-for="log in logs.slice(0, 6)" :key="log.id" class="flex items-start gap-3 p-3 bg-white/3 rounded-xl">
                <div class="w-2 h-2 rounded-full bg-purple-400 mt-1.5 shrink-0"></div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm text-white/70">{{ log.descripcion }}</p>
                  <p class="text-xs text-white/20 mt-0.5">{{ formatFecha(log.created_at) }}</p>
                </div>
              </div>
              <p v-if="!logs.length" class="text-center text-white/20 py-4 text-sm">Sin actividad registrada</p>
            </div>
          </div>
        </div>

        <!-- ======================== USUARIOS ======================== -->
        <div v-if="activeTab === 'usuarios'" class="space-y-4">
          <!-- Toolbar -->
          <div class="flex flex-col sm:flex-row gap-3">
            <div class="relative flex-1">
              <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-white/30" />
              <input v-model="searchQuery" placeholder="Buscar por nombre o email..." class="w-full pl-10 pr-4 py-2.5 bg-[#111111] border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
            </div>
            <select v-model="filtroRol" class="px-4 py-2.5 bg-[#111111] border border-white/10 rounded-xl text-sm text-white/70 focus:outline-none focus:border-purple-500/50 cursor-pointer">
              <option value="todos">Todos los roles</option>
              <option value="cliente">Cliente</option>
              <option value="barbero">Barbero</option>
              <option value="dueño">Dueño</option>
              <option value="superadmin">Super Admin</option>
            </select>
          </div>

          <!-- Tabla de usuarios -->
          <div class="bg-[#111111] border border-white/5 rounded-2xl overflow-hidden">
            <div class="p-4 border-b border-white/5 flex items-center justify-between">
              <p class="text-sm font-bold">{{ usuariosFiltrados.length }} usuarios</p>
            </div>
            <div class="divide-y divide-white/5">
              <div v-for="u in usuariosFiltrados" :key="u.id" class="flex items-center gap-4 px-5 py-4 hover:bg-white/3 transition-colors">
                <!-- Avatar -->
                <div class="w-9 h-9 rounded-xl bg-gradient-to-br from-purple-500/20 to-blue-500/20 flex items-center justify-center text-sm font-black text-white/60 shrink-0">
                  {{ (u.nombre || '?')[0].toUpperCase() }}
                </div>
                <!-- Info -->
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 flex-wrap">
                    <p class="text-sm font-medium">{{ u.nombre || 'Sin nombre' }}</p>
                    <span :class="['text-[10px] px-2 py-0.5 rounded-full border font-medium', rolColor(u.rol)]">
                      {{ u.rol }}
                    </span>
                    <span v-if="!u.activo" class="text-[10px] px-2 py-0.5 rounded-full border text-red-400 bg-red-400/10 border-red-400/20">
                      Desactivado
                    </span>
                  </div>
                  <p class="text-xs text-white/30 mt-0.5 truncate">{{ u.email }}</p>
                </div>
                <!-- Fecha -->
                <p class="text-xs text-white/20 hidden lg:block shrink-0">{{ new Date(u.created_at).toLocaleDateString('es-CO') }}</p>
                <!-- Acciones -->
                <div class="flex items-center gap-2 shrink-0">
                  <!-- Cambiar rol -->
                  <select :value="u.rol" @change="cambiarRol(u, ($event.target as HTMLSelectElement).value)"
                    class="text-xs px-2 py-1.5 bg-white/5 border border-white/10 rounded-lg text-white/60 focus:outline-none cursor-pointer hidden sm:block">
                    <option value="cliente">Cliente</option>
                    <option value="barbero">Barbero</option>
                    <option value="dueño">Dueño</option>
                    <option value="superadmin">Super Admin</option>
                  </select>
                  <!-- Toggle activo/inactivo -->
                  <button @click="toggleUsuario(u)" :title="u.activo ? 'Desactivar' : 'Activar'"
                    :class="['p-1.5 rounded-lg border transition-all cursor-pointer', u.activo ? 'text-green-400 border-green-400/20 hover:bg-red-400/10 hover:text-red-400 hover:border-red-400/20' : 'text-red-400 border-red-400/20 hover:bg-green-400/10 hover:text-green-400 hover:border-green-400/20']">
                    <component :is="u.activo ? ToggleRight : ToggleLeft" class="w-4 h-4" />
                  </button>
                </div>
              </div>
              <div v-if="!usuariosFiltrados.length" class="py-12 text-center text-white/20 text-sm">
                No se encontraron usuarios con ese filtro
              </div>
            </div>
          </div>
        </div>

        <!-- ======================== BARBERÍAS ======================== -->
        <div v-if="activeTab === 'barberias'" class="space-y-4">
          <!-- Toolbar -->
          <div class="flex flex-col sm:flex-row gap-3">
            <div class="relative flex-1">
              <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-white/30" />
              <input v-model="searchQuery" placeholder="Buscar barbería..." class="w-full pl-10 pr-4 py-2.5 bg-[#111111] border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
            </div>
            <select v-model="filtroEstado" class="px-4 py-2.5 bg-[#111111] border border-white/10 rounded-xl text-sm text-white/70 focus:outline-none cursor-pointer">
              <option value="todos">Todas</option>
              <option value="activa">Activas</option>
              <option value="inactiva">Inactivas</option>
            </select>
            <button @click="showCreateOwnerModal = true" class="flex items-center gap-2 px-4 py-2.5 bg-purple-500 hover:bg-purple-600 text-white rounded-xl text-sm font-bold transition-all cursor-pointer shrink-0">
              <Plus class="w-4 h-4" />
              Crear Dueño
            </button>
          </div>

          <!-- Cards de barberías -->
          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <div v-for="b in barberiasFiltradas" :key="b.id"
              class="bg-[#111111] border border-white/5 rounded-2xl p-5 hover:border-white/10 transition-all space-y-4">
              <!-- Header -->
              <div class="flex items-start justify-between">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 bg-yellow-500/10 rounded-xl flex items-center justify-center">
                    <Scissors class="w-5 h-5 text-yellow-400" />
                  </div>
                  <div>
                    <p class="font-bold text-sm">{{ b.nombre }}</p>
                    <p class="text-xs text-white/30">{{ b.direccion || 'Sin dirección' }}</p>
                  </div>
                </div>
                <div :class="['text-[10px] px-2 py-1 rounded-full border font-medium shrink-0', b.activo ? 'text-green-400 bg-green-400/10 border-green-400/20' : 'text-red-400 bg-red-400/10 border-red-400/20']">
                  {{ b.activo ? 'Activa' : 'Inactiva' }}
                </div>
              </div>
              <!-- Dueño -->
              <div class="flex items-center gap-2 text-xs text-white/40">
                <Shield class="w-3.5 h-3.5" />
                Dueño: <span class="text-white/60 font-medium">{{ (b.dueno as any)?.nombre || 'Sin asignar' }}</span>
              </div>
              <!-- Fecha -->
              <p class="text-xs text-white/20">Registrada: {{ new Date(b.created_at).toLocaleDateString('es-CO') }}</p>
              <!-- Acciones -->
              <div class="flex gap-2 pt-1">
                <button @click="toggleBarberia(b)" :class="['flex-1 py-2 rounded-xl text-xs font-bold border transition-all cursor-pointer', b.activo ? 'border-red-400/20 text-red-400 hover:bg-red-400/10' : 'border-green-400/20 text-green-400 hover:bg-green-400/10']">
                  {{ b.activo ? 'Desactivar' : 'Activar' }}
                </button>
                <button @click="eliminarBarberia(b)" class="flex-1 py-2 rounded-xl text-xs font-bold border border-red-500/30 text-red-500 hover:bg-red-500/10 transition-all cursor-pointer">
                  Eliminar
                </button>
              </div>
            </div>
            <div v-if="!barberiasFiltradas.length" class="col-span-full py-12 text-center text-white/20 text-sm">
              No se encontraron barberías
            </div>
          </div>
        </div>

        <!-- ======================== CITAS ======================== -->
        <div v-if="activeTab === 'citas'" class="space-y-4">
          <div class="relative">
            <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-white/30" />
            <input v-model="searchQuery" placeholder="Buscar por barbería..." class="w-full pl-10 pr-4 py-2.5 bg-[#111111] border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
          </div>

          <div class="bg-[#111111] border border-white/5 rounded-2xl overflow-hidden">
            <div class="divide-y divide-white/5">
              <div v-for="c in citas.filter(c => !searchQuery || (c.barberia as any)?.nombre?.toLowerCase().includes(searchQuery.toLowerCase()))" :key="c.id"
                class="flex items-center gap-4 px-5 py-4 hover:bg-white/3 transition-colors">
                <div class="w-2 h-2 rounded-full shrink-0" :class="c.estado === 'completada' ? 'bg-green-400' : c.estado === 'cancelada' ? 'bg-red-400' : 'bg-yellow-400'"></div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium">{{ (c.barberia as any)?.nombre || 'Sin barbería' }}</p>
                  <p class="text-xs text-white/30 truncate">
                    Barbero: {{ (c.barbero as any)?.nombre || 'Manual' }} · Servicio: {{ (c.servicio as any)?.nombre || '-' }}
                  </p>
                </div>
                <div class="text-right shrink-0">
                  <p :class="['text-xs font-medium', estadoCitaColor(c.estado)]">{{ c.estado }}</p>
                  <p class="text-xs text-white/20">{{ formatFecha(c.fecha_hora) }}</p>
                </div>
              </div>
              <div v-if="!citas.length" class="py-12 text-center text-white/20 text-sm">Sin citas registradas</div>
            </div>
          </div>
        </div>

        <!-- ======================== LOGS ======================== -->
        <div v-if="activeTab === 'logs'" class="space-y-4">
          <div class="bg-[#111111] border border-white/5 rounded-2xl overflow-hidden">
            <div class="p-4 border-b border-white/5">
              <p class="text-sm font-bold flex items-center gap-2"><Activity class="w-4 h-4 text-blue-400" /> Últimas 100 acciones</p>
            </div>
            <div class="divide-y divide-white/5 max-h-[600px] overflow-y-auto">
              <div v-for="log in logs" :key="log.id" class="flex items-start gap-4 px-5 py-3.5 hover:bg-white/3 transition-colors">
                <div class="w-2 h-2 rounded-full bg-purple-400 mt-1.5 shrink-0"></div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm text-white/70">{{ log.descripcion }}</p>
                  <p class="text-xs text-white/20 mt-0.5">{{ (log.usuario as any)?.nombre || 'Sistema' }} · {{ formatFecha(log.created_at) }}</p>
                </div>
                <span class="text-[10px] px-2 py-0.5 bg-white/5 rounded-full text-white/30 shrink-0">{{ log.tipo }}</span>
              </div>
              <div v-if="!logs.length" class="py-12 text-center text-white/20 text-sm">Sin logs registrados aún</div>
            </div>
          </div>
        </div>

      </div>
    </main>

    <!-- Modal: Crear Dueño + Barbería -->
    <div v-if="showCreateOwnerModal" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <div class="w-full max-w-md bg-[#111111] border border-white/10 rounded-3xl p-7 shadow-2xl space-y-5">
        <div class="flex items-center gap-3 mb-2">
          <div class="w-10 h-10 bg-purple-500/10 rounded-xl flex items-center justify-center">
            <Plus class="w-5 h-5 text-purple-400" />
          </div>
          <div>
            <h3 class="text-lg font-black">Crear Dueño de Barbería</h3>
            <p class="text-xs text-white/30">El usuario se creará con rol "dueño"</p>
          </div>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-white/50 font-medium">Nombre completo *</label>
          <input v-model="newOwner.nombre" type="text" placeholder="Nombre del dueño" class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
        </div>
        <div class="space-y-1">
          <label class="text-xs text-white/50 font-medium">Email *</label>
          <input v-model="newOwner.email" type="email" placeholder="email@ejemplo.com" class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
        </div>
        <div class="space-y-1">
          <label class="text-xs text-white/50 font-medium">Contraseña temporal *</label>
          <input v-model="newOwner.password" type="password" placeholder="••••••••" class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
        </div>

        <div class="border-t border-white/5 pt-4 space-y-3">
          <p class="text-xs text-white/40 font-medium uppercase tracking-widest">Barbería (opcional)</p>
          <input v-model="newBarberiaManual.nombre" type="text" placeholder="Nombre de la barbería" class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
          <input v-model="newBarberiaManual.direccion" type="text" placeholder="Dirección" class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
          <input v-model="newBarberiaManual.telefono" type="text" placeholder="Teléfono" class="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-sm text-white placeholder-white/20 focus:outline-none focus:border-purple-500/50" />
        </div>

        <div class="flex gap-3 pt-2">
          <button @click="showCreateOwnerModal = false" class="flex-1 py-3 rounded-2xl border border-white/10 text-white/40 hover:text-white/70 text-sm font-bold transition-all cursor-pointer">
            Cancelar
          </button>
          <button @click="crearDuenoBarberia" :disabled="loading" class="flex-1 py-3 rounded-2xl bg-purple-500 hover:bg-purple-600 text-white text-sm font-bold transition-all cursor-pointer disabled:opacity-50">
            {{ loading ? 'Creando...' : 'Crear Dueño' }}
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
