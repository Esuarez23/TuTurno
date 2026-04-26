import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../lib/supabase'
import Home from '../views/Home.vue'

const routes = [
  { path: '/', component: Home },
  { path: '/login', component: () => import('../views/auth/Login.vue') },
  { path: '/register', component: () => import('../views/auth/Register.vue') },
  { 
    path: '/dashboard/cliente', 
    component: () => import('../views/dashboard/ClientDashboard.vue'),
    meta: { requiresAuth: true, role: 'cliente' }
  },
  { 
    path: '/dashboard/barbero', 
    component: () => import('../views/dashboard/BarberDashboard.vue'),
    meta: { requiresAuth: true, role: 'barbero' }
  },
  { 
    path: '/dashboard/owner', 
    component: () => import('../views/dashboard/OwnerDashboard.vue'),
    meta: { requiresAuth: true, role: 'dueño' }
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

router.beforeEach(async (to, from, next) => {
  const requiresAuth = to.matched.some(record => record.meta.requiresAuth)
  
  if (!requiresAuth) {
    return next()
  }

  const { data: { session } } = await supabase.auth.getSession()

  if (!session) {
    return next('/login')
  }

  // Verificar rol
  if (to.meta.role) {
    const { data: perfil, error } = await supabase
      .from('perfiles')
      .select('rol')
      .eq('id', session.user.id)
      .single()

    if (error || !perfil) {
      // Si no hay perfil, lo mandamos al index para evitar un bucle
      await supabase.auth.signOut()
      return next('/login')
    }

    if (perfil.rol !== to.meta.role) {
      // Redirigir al dashboard correcto según su rol real
      return next(`/dashboard/${perfil.rol === 'dueño' ? 'owner' : perfil.rol}`)
    }
  }

  next()
})

export default router
