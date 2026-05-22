import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../lib/supabase'
import Home from '../views/Home.vue'

const routes = [
  { path: '/', component: Home },
  { path: '/login', component: () => import('../views/auth/Login.vue') },
  { path: '/register', component: () => import('../views/auth/Register.vue') },
  { path: '/reset-password', component: () => import('../views/auth/ResetPassword.vue') },
  { 
    path: '/client-dashboard', 
    component: () => import('../views/dashboard/ClientDashboard.vue'),
    meta: { requiresAuth: false }
  },
  { 
    path: '/barber-dashboard', 
    component: () => import('../views/dashboard/BarberDashboard.vue'),
    meta: { requiresAuth: true, role: 'barbero' }
  },
  { 
    path: '/owner-dashboard', 
    component: () => import('../views/dashboard/OwnerDashboard.vue'),
    meta: { requiresAuth: true, roles: ['dueno', 'dueño'] }
  },
  { 
    path: '/super-admin', 
    component: () => import('../views/dashboard/SuperAdminDashboard.vue'),
    meta: { requiresAuth: true, role: 'superadmin' }
  },
  { path: '/:pathMatch(.*)*', redirect: '/' }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

router.beforeEach(async (to, _from, next) => {
  const { data: { session } } = await supabase.auth.getSession()
  const requiresAuth = to.matched.some(record => record.meta.requiresAuth)

  if (requiresAuth && !session) {
    return next('/login')
  }

  let rolReal: string | null = null
  if (session) {
    try {
      // Consultar el rol en tiempo real en la base de datos para máxima consistencia y seguridad
      let { data: perfil, error: perfilError } = await supabase
        .from('perfiles')
        .select('rol')
        .eq('id', session.user.id)
        .maybeSingle()
      
      if (perfil) {
        rolReal = perfil.rol
      } else if (!perfil && !perfilError) {
        // Autorreparación usando RPC del servidor (bypasea RLS)
        console.info('Perfil faltante detectado en router. Invocando sync_user_profile RPC...')
        const { data: syncResult, error: syncError } = await supabase.rpc('sync_user_profile')

        if (!syncError && syncResult?.success) {
          rolReal = syncResult.rol
          console.info('Perfil autorreparado con éxito en el router via RPC.')
        } else {
          console.error('No se pudo autorreparar el perfil en el router:', syncError || syncResult?.error)
          console.warn('Sesión huérfana detectada en LocalStorage. Cerrando sesión local...')
          await supabase.auth.signOut()
          return next('/login')
        }
      } else {
        console.error('Error al obtener perfil en el router:', perfilError)
      }
    } catch (e) {
      console.error('Error al obtener el rol del perfil autenticado:', e)
    }

    // Fallback seguro a los metadatos de sesión
    if (!rolReal) {
      rolReal = (session.user.user_metadata?.rol as string) || 'cliente'
    }
  }

  // Redirección inteligente al dashboard correspondiente si ya está autenticado e intenta ir a rutas de login/registro/home
  if (session && rolReal && (to.path === '/' || to.path === '/login' || to.path === '/register')) {
    return next(obtenerRutaPorRol(rolReal))
  }

  // Protección estricta de rutas basada en roles de perfil validados en tiempo real
  if (requiresAuth && session && rolReal) {
    const routeRole = to.meta.role as string
    const routeRoles = to.meta.roles as string[]

    if (routeRole && routeRole !== rolReal) {
      return next(obtenerRutaPorRol(rolReal))
    }
    
    if (routeRoles && !routeRoles.includes(rolReal)) {
      return next(obtenerRutaPorRol(rolReal))
    }
  }

  next()
})

function obtenerRutaPorRol(rol: string): string {
  if (rol === 'superadmin') return '/super-admin'
  if (rol === 'dueno' || rol === 'dueño') return '/owner-dashboard'
  if (rol === 'barbero') return '/barber-dashboard'
  return '/client-dashboard'
}

export default router
