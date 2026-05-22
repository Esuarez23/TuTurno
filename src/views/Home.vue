<script setup lang="ts">
import { Scissors, Calendar, ShieldCheck, Star } from 'lucide-vue-next'
import { useRouter } from 'vue-router'

const router = useRouter()
</script>

<template>
  <div class="min-h-screen bg-brand-dark overflow-x-hidden">
    <!-- Navbar -->
    <nav class="flex justify-between items-center px-8 py-6 border-b border-white/5">
      <div class="flex items-center gap-2">
        <div class="p-2 bg-brand-primary rounded-lg">
          <Scissors class="text-black w-6 h-6" />
        </div>
        <span class="text-2xl font-bold tracking-tighter">TuTurno</span>
      </div>
      
      <div class="flex gap-6 items-center">
        <a href="#" class="text-white/70 hover:text-white transition-colors cursor-pointer">Servicios</a>
        <a href="#" class="text-white/70 hover:text-white transition-colors cursor-pointer">Barberos</a>
        <button @click="router.push('/login')" class="btn-primary">Iniciar Sesión</button>
      </div>
    </nav>

    <!-- Hero Section -->
    <main class="max-w-7xl mx-auto px-8 py-20 lg:py-32 grid lg:grid-cols-2 gap-16 items-center">
      <div class="space-y-8 animate-in fade-in slide-in-from-left duration-1000">
        <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-brand-primary/10 border border-brand-primary/20 text-brand-primary text-sm font-medium">
          <Star class="w-4 h-4 fill-brand-primary" />
          <span>La mejor barbería de la ciudad</span>
        </div>
        
        <h1 class="text-6xl lg:text-8xl font-black leading-tight">
          Tu Estilo, <br />
          <span class="text-brand-primary">Tu Turno.</span>
        </h1>
        
        <p class="text-xl text-white/50 max-w-lg leading-relaxed">
          Gestiona tus citas con los mejores profesionales. Rapidez, comodidad y el mejor estilo en un solo lugar.
        </p>

        <div class="flex gap-4 pt-4">
          <button @click="router.push('/client-dashboard')" class="btn-primary flex items-center gap-2 cursor-pointer">
            <Calendar class="w-5 h-5" />
            Agenda ahora
          </button>
          <button class="btn-secondary">Conoce al equipo</button>
        </div>
      </div>

      <div class="relative group animate-in fade-in slide-in-from-right duration-1000">
        <div class="absolute -inset-4 bg-brand-primary/20 rounded-3xl blur-3xl group-hover:bg-brand-primary/30 transition-all duration-500"></div>
        <div class="relative card p-0 overflow-hidden border-white/10 aspect-square lg:aspect-video flex items-center justify-center">
           <img src="/barber_shop_hero_1776990375083.png" alt="Premium Barber Shop" class="w-full h-full object-cover opacity-80 group-hover:opacity-100 transition-opacity duration-500" />
           <div class="absolute inset-0 bg-gradient-to-t from-brand-dark via-transparent to-transparent"></div>
        </div>
      </div>
    </main>

    <!-- Features -->
    <section class="max-w-7xl mx-auto px-8 py-24 border-t border-white/5 grid md:grid-cols-3 gap-8">
      <div class="card space-y-4">
        <div class="w-12 h-12 bg-brand-primary/10 rounded-xl flex items-center justify-center text-brand-primary">
          <Calendar class="w-6 h-6" />
        </div>
        <h3 class="text-xl font-bold">Reserva Online</h3>
        <p class="text-white/50">Olvídate de las llamadas. Elige tu barbero y servicio en segundos.</p>
      </div>

      <div class="card space-y-4">
        <div class="w-12 h-12 bg-brand-primary/10 rounded-xl flex items-center justify-center text-brand-primary">
          <ShieldCheck class="w-6 h-6" />
        </div>
        <h3 class="text-xl font-bold">Garantía Elite</h3>
        <p class="text-white/50">Solo profesionales certificados para asegurar tu mejor versión.</p>
      </div>

      <div class="card space-y-4">
        <div class="w-12 h-12 bg-brand-primary/10 rounded-xl flex items-center justify-center text-brand-primary">
          <Star class="w-6 h-6" />
        </div>
        <h3 class="text-xl font-bold">Historial y Premios</h3>
        <p class="text-white/50">Consulta tus visitas anteriores y acumula puntos por fidelidad.</p>
      </div>
    </section>
  </div>
</template>
