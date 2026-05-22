-- ============================================================================
-- TuTurno - Esquema Completo de la Base de Datos (Consolidado)
-- Ejecutar en: Supabase Dashboard -> SQL Editor (Instalación limpia)
-- ============================================================================

-- ============================================================
-- 1. TABLA: perfiles
-- ============================================================
CREATE TABLE IF NOT EXISTS public.perfiles (
  id UUID PRIMARY KEY, -- Sin FK directa a auth.users para soportar el flujo de clientes invitados (Guest Booking)
  nombre TEXT NOT NULL DEFAULT '',
  email TEXT,
  rol TEXT NOT NULL DEFAULT 'cliente' CHECK (rol IN ('cliente', 'barbero', 'dueño', 'dueno', 'superadmin')),
  estado_vinculacion TEXT DEFAULT 'pendiente', -- 'pendiente', 'aprobado', 'rechazado'
  modelo_pago TEXT DEFAULT 'porcentaje',        -- 'porcentaje', 'fijo_servicio', 'salario_fijo'
  pago_valor DECIMAL(10,2) DEFAULT 50.00,
  activo BOOLEAN DEFAULT TRUE,
  telefono TEXT,
  es_barbero BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 2. TABLA: barberias
-- ============================================================
CREATE TABLE IF NOT EXISTS public.barberias (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dueno_id UUID REFERENCES public.perfiles(id) ON DELETE SET NULL,
  nombre TEXT NOT NULL,
  direccion TEXT,
  telefono TEXT,
  descripcion TEXT,
  logo_url TEXT,
  banner_url TEXT,
  foto_url TEXT,
  hora_apertura TIME DEFAULT '08:00',
  hora_cierre TIME DEFAULT '20:00',
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Vincular perfiles -> barberias de forma segura (evita referencias circulares al crear tablas)
ALTER TABLE public.perfiles 
  ADD COLUMN IF NOT EXISTS barberia_id UUID REFERENCES public.barberias(id) ON DELETE SET NULL;

-- ============================================================
-- 3. TABLA: servicios
-- ============================================================
CREATE TABLE IF NOT EXISTS public.servicios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barberia_id UUID REFERENCES public.barberias(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  precio DECIMAL(10,2) NOT NULL DEFAULT 0,
  duracion_minutos INTEGER DEFAULT 30,
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 4. TABLA: citas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.citas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barberia_id UUID REFERENCES public.barberias(id) ON DELETE CASCADE,
  barbero_id UUID REFERENCES public.perfiles(id) ON DELETE SET NULL,
  cliente_id UUID REFERENCES public.perfiles(id) ON DELETE SET NULL,
  servicio_id UUID REFERENCES public.servicios(id) ON DELETE SET NULL,
  nombre_cliente_manual TEXT,       -- Para clientes invitados/sin registro
  fecha_hora TIMESTAMP WITH TIME ZONE NOT NULL,
  estado TEXT DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'confirmada', 'en_espera', 'completada', 'cancelada')),
  tipo TEXT DEFAULT 'agendado' CHECK (tipo IN ('agendado', 'espera')),
  precio_final DECIMAL(10,2),
  notas TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 5. TABLA: resenas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.resenas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cita_id UUID REFERENCES public.citas(id) ON DELETE CASCADE,
  barberia_id UUID REFERENCES public.barberias(id) ON DELETE CASCADE,
  barbero_id UUID REFERENCES public.perfiles(id) ON DELETE SET NULL,
  cliente_id UUID REFERENCES public.perfiles(id) ON DELETE SET NULL,
  calificacion INTEGER CHECK (calificacion BETWEEN 1 AND 5),
  comentario TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 6. TABLA: pagos_nomina
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pagos_nomina (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barbero_id UUID REFERENCES public.perfiles(id) ON DELETE CASCADE,
  monto_pagado DECIMAL(10,2),
  servicios_contados INTEGER,
  periodo_desde TIMESTAMP WITH TIME ZONE,
  periodo_hasta TIMESTAMP WITH TIME ZONE,
  fecha_pago TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 7. TABLA: logs_actividad (Auditoría para el Super Admin)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.logs_actividad (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo TEXT NOT NULL,              -- 'nuevo_usuario', 'cita_completada', etc.
  descripcion TEXT,
  usuario_id UUID REFERENCES public.perfiles(id) ON DELETE SET NULL,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 8. TABLA INTERMEDIA: barbero_servicios (Asignaciones)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.barbero_servicios (
  barbero_id UUID REFERENCES public.perfiles(id) ON DELETE CASCADE,
  servicio_id UUID REFERENCES public.servicios(id) ON DELETE CASCADE,
  PRIMARY KEY (barbero_id, servicio_id)
);

-- ============================================================
-- 9. FUNCIONES RPC Y TRIGGERS DE SEGURIDAD
-- ============================================================

-- A. Función RPC: Sincronización ininterrumpida y robusta de perfiles (Fusión de Huérfanos)
CREATE OR REPLACE FUNCTION public.sync_user_profile()
RETURNS json AS $$
DECLARE
  v_user_id UUID;
  v_email TEXT;
  v_nombre TEXT;
  v_rol TEXT;
  v_old_id UUID;
  v_old_rol TEXT;
  -- Arrays para rastrear filas afectadas
  v_barb_ids UUID[];
  v_citas_cli UUID[];
  v_citas_bar UUID[];
  v_res_cli UUID[];
  v_res_bar UUID[];
  v_pagos_ids UUID[];
  v_logs_ids UUID[];
  v_bs_serv_ids UUID[];
  v_result json;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No hay sesión autenticada');
  END IF;

  SELECT email,
         COALESCE(raw_user_meta_data->>'nombre', 'Usuario'),
         COALESCE(raw_user_meta_data->>'rol', 'cliente')
  INTO v_email, v_nombre, v_rol
  FROM auth.users WHERE id = v_user_id;

  IF v_rol = 'superadmin' THEN v_rol := 'cliente'; END IF;

  IF EXISTS (SELECT 1 FROM public.perfiles WHERE id = v_user_id) THEN
    SELECT json_build_object('success', true, 'rol', p.rol)
    INTO v_result FROM public.perfiles p WHERE p.id = v_user_id;
    RETURN v_result;
  END IF;

  SELECT id, rol INTO v_old_id, v_old_rol
  FROM public.perfiles WHERE email = v_email AND id <> v_user_id LIMIT 1;

  IF v_old_id IS NOT NULL THEN
    IF v_old_rol IS NOT NULL AND v_old_rol <> 'superadmin' THEN
      v_rol := v_old_rol;
    END IF;

    -- Respaldar referencias
    SELECT COALESCE(array_agg(id), '{}') INTO v_barb_ids FROM public.barberias WHERE dueno_id = v_old_id;
    SELECT COALESCE(array_agg(id), '{}') INTO v_citas_cli FROM public.citas WHERE cliente_id = v_old_id;
    SELECT COALESCE(array_agg(id), '{}') INTO v_citas_bar FROM public.citas WHERE barbero_id = v_old_id;
    SELECT COALESCE(array_agg(id), '{}') INTO v_res_cli FROM public.resenas WHERE cliente_id = v_old_id;
    SELECT COALESCE(array_agg(id), '{}') INTO v_res_bar FROM public.resenas WHERE barbero_id = v_old_id;
    SELECT COALESCE(array_agg(id), '{}') INTO v_pagos_ids FROM public.pagos_nomina WHERE barbero_id = v_old_id;
    SELECT COALESCE(array_agg(id), '{}') INTO v_logs_ids FROM public.logs_actividad WHERE usuario_id = v_old_id;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'barbero_servicios') THEN
      SELECT COALESCE(array_agg(servicio_id), '{}') INTO v_bs_serv_ids FROM public.barbero_servicios WHERE barbero_id = v_old_id;
      DELETE FROM public.barbero_servicios WHERE barbero_id = v_old_id;
    END IF;

    -- Desconectar
    UPDATE public.barberias SET dueno_id = NULL WHERE id = ANY(v_barb_ids);
    UPDATE public.citas SET cliente_id = NULL WHERE id = ANY(v_citas_cli);
    UPDATE public.citas SET barbero_id = NULL WHERE id = ANY(v_citas_bar);
    UPDATE public.resenas SET cliente_id = NULL WHERE id = ANY(v_res_cli);
    UPDATE public.resenas SET barbero_id = NULL WHERE id = ANY(v_res_bar);
    UPDATE public.pagos_nomina SET barbero_id = NULL WHERE id = ANY(v_pagos_ids);
    UPDATE public.logs_actividad SET usuario_id = NULL WHERE id = ANY(v_logs_ids);

    DELETE FROM public.perfiles WHERE id = v_old_id;

    INSERT INTO public.perfiles (id, nombre, email, rol, activo, created_at)
    VALUES (v_user_id, v_nombre, v_email, v_rol, TRUE, now());

    -- Reconectar
    UPDATE public.barberias SET dueno_id = v_user_id WHERE id = ANY(v_barb_ids);
    UPDATE public.citas SET cliente_id = v_user_id WHERE id = ANY(v_citas_cli);
    UPDATE public.citas SET barbero_id = v_user_id WHERE id = ANY(v_citas_bar);
    UPDATE public.resenas SET cliente_id = v_user_id WHERE id = ANY(v_res_cli);
    UPDATE public.resenas SET barbero_id = v_user_id WHERE id = ANY(v_res_bar);
    UPDATE public.pagos_nomina SET barbero_id = v_user_id WHERE id = ANY(v_pagos_ids);
    UPDATE public.logs_actividad SET usuario_id = v_user_id WHERE id = ANY(v_logs_ids);

    IF v_bs_serv_ids IS NOT NULL AND array_length(v_bs_serv_ids, 1) > 0 THEN
      INSERT INTO public.barbero_servicios (barbero_id, servicio_id)
      SELECT v_user_id, unnest(v_bs_serv_ids) ON CONFLICT DO NOTHING;
    END IF;
  ELSE
    INSERT INTO public.perfiles (id, nombre, email, rol, activo, created_at)
    VALUES (v_user_id, v_nombre, v_email, v_rol, TRUE, now())
    ON CONFLICT (id) DO UPDATE
    SET nombre = EXCLUDED.nombre, email = EXCLUDED.email, rol = EXCLUDED.rol;
  END IF;

  SELECT json_build_object('success', true, 'rol', p.rol)
  INTO v_result FROM public.perfiles p WHERE p.id = v_user_id;

  RETURN COALESCE(v_result, json_build_object('success', false, 'error', 'No se pudo sincronizar el perfil'));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- B. Trigger Trigger: handle_new_user() para sincronización automática
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  rol_filtrado TEXT;
  id_viejo UUID;
  t_barb UUID[]; t_cc UUID[]; t_cb UUID[];
  t_rc UUID[]; t_rb UUID[]; t_p UUID[]; t_l UUID[]; t_bs UUID[];
BEGIN
  rol_filtrado := COALESCE(NEW.raw_user_meta_data->>'rol', 'cliente');
  IF rol_filtrado = 'superadmin' THEN rol_filtrado := 'cliente'; END IF;

  SELECT id INTO id_viejo FROM public.perfiles WHERE email = NEW.email AND id <> NEW.id LIMIT 1;

  IF id_viejo IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(array_agg(id), '{}') INTO t_barb FROM public.barberias WHERE dueno_id = id_viejo;
      SELECT COALESCE(array_agg(id), '{}') INTO t_cc FROM public.citas WHERE cliente_id = id_viejo;
      SELECT COALESCE(array_agg(id), '{}') INTO t_cb FROM public.citas WHERE barbero_id = id_viejo;
      SELECT COALESCE(array_agg(id), '{}') INTO t_rc FROM public.resenas WHERE cliente_id = id_viejo;
      SELECT COALESCE(array_agg(id), '{}') INTO t_rb FROM public.resenas WHERE barbero_id = id_viejo;
      SELECT COALESCE(array_agg(id), '{}') INTO t_p FROM public.pagos_nomina WHERE barbero_id = id_viejo;
      SELECT COALESCE(array_agg(id), '{}') INTO t_l FROM public.logs_actividad WHERE usuario_id = id_viejo;

      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'barbero_servicios') THEN
        SELECT COALESCE(array_agg(servicio_id), '{}') INTO t_bs FROM public.barbero_servicios WHERE barbero_id = id_viejo;
        DELETE FROM public.barbero_servicios WHERE barbero_id = id_viejo;
      END IF;

      -- Desconectar
      UPDATE public.barberias SET dueno_id = NULL WHERE id = ANY(t_barb);
      UPDATE public.citas SET cliente_id = NULL WHERE id = ANY(t_cc);
      UPDATE public.citas SET barbero_id = NULL WHERE id = ANY(t_cb);
      UPDATE public.resenas SET cliente_id = NULL WHERE id = ANY(t_rc);
      UPDATE public.resenas SET barbero_id = NULL WHERE id = ANY(t_rb);
      UPDATE public.pagos_nomina SET barbero_id = NULL WHERE id = ANY(t_p);
      UPDATE public.logs_actividad SET usuario_id = NULL WHERE id = ANY(t_l);

      DELETE FROM public.perfiles WHERE id = id_viejo;

      INSERT INTO public.perfiles (id, nombre, email, rol, activo, created_at)
      VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'nombre', 'Usuario'), NEW.email, rol_filtrado, TRUE, now())
      ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, email = EXCLUDED.email, rol = EXCLUDED.rol;

      -- Reconectar
      UPDATE public.barberias SET dueno_id = NEW.id WHERE id = ANY(t_barb);
      UPDATE public.citas SET cliente_id = NEW.id WHERE id = ANY(t_cc);
      UPDATE public.citas SET barbero_id = NEW.id WHERE id = ANY(t_cb);
      UPDATE public.resenas SET cliente_id = NEW.id WHERE id = ANY(t_rc);
      UPDATE public.resenas SET barbero_id = NEW.id WHERE id = ANY(t_rb);
      UPDATE public.pagos_nomina SET barbero_id = NEW.id WHERE id = ANY(t_p);
      UPDATE public.logs_actividad SET usuario_id = NEW.id WHERE id = ANY(t_l);

      IF t_bs IS NOT NULL AND array_length(t_bs, 1) > 0 THEN
        INSERT INTO public.barbero_servicios (barbero_id, servicio_id)
        SELECT NEW.id, unnest(t_bs) ON CONFLICT DO NOTHING;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'handle_new_user: fallo al migrar % -> %: %', id_viejo, NEW.id, SQLERRM;
    END;
  ELSE
    BEGIN
      INSERT INTO public.perfiles (id, nombre, email, rol, activo, created_at)
      VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'nombre', 'Usuario'), NEW.email, rol_filtrado, TRUE, now())
      ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, email = EXCLUDED.email, rol = EXCLUDED.rol;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'handle_new_user: error perfil %: %', NEW.id, SQLERRM;
    END;
  END IF;

  BEGIN
    INSERT INTO public.logs_actividad (tipo, descripcion, usuario_id, metadata)
    VALUES ('nuevo_usuario', 'Nuevo usuario registrado: ' || COALESCE(NEW.raw_user_meta_data->>'nombre', NEW.email), NEW.id, jsonb_build_object('rol', rol_filtrado, 'email', NEW.email));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'handle_new_user: error log %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Enlazar trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 10. CONFIGURACIÓN DE SEGURIDAD RLS (Row Level Security)
-- ============================================================

-- Activar RLS en todas las tablas
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.barberias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.servicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.citas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resenas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagos_nomina ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logs_actividad ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.barbero_servicios ENABLE ROW LEVEL SECURITY;

-- Políticas de perfiles
DROP POLICY IF EXISTS "perfiles_select" ON public.perfiles;
CREATE POLICY "perfiles_select" ON public.perfiles
  FOR SELECT USING (
    auth.uid() = id
    OR (auth.jwt()->'user_metadata'->>'rol') = 'superadmin'
    OR rol = 'barbero'
    OR rol = 'cliente'
    OR EXISTS (
      SELECT 1 FROM public.perfiles admin
      WHERE admin.id = auth.uid() AND (admin.rol = 'dueño' OR admin.rol = 'dueno' OR admin.rol = 'superadmin')
    )
  );

DROP POLICY IF EXISTS "perfiles_insert" ON public.perfiles;
CREATE POLICY "perfiles_insert" ON public.perfiles
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "perfiles_update" ON public.perfiles;
CREATE POLICY "perfiles_update" ON public.perfiles
  FOR UPDATE USING (
    auth.uid() = id
    OR EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'superadmin')
  );

-- Políticas de barberias
DROP POLICY IF EXISTS "barberias_select" ON public.barberias;
CREATE POLICY "barberias_select" ON public.barberias
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "barberias_insert" ON public.barberias;
CREATE POLICY "barberias_insert" ON public.barberias
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL AND (
      auth.uid() = dueno_id
      OR EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'superadmin')
    )
  );

DROP POLICY IF EXISTS "barberias_update" ON public.barberias;
CREATE POLICY "barberias_update" ON public.barberias
  FOR UPDATE USING (
    auth.uid() = dueno_id
    OR EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'superadmin')
  );

-- Políticas de servicios
DROP POLICY IF EXISTS "servicios_select" ON public.servicios;
CREATE POLICY "servicios_select" ON public.servicios
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "servicios_insert_update_delete" ON public.servicios;
CREATE POLICY "servicios_insert_update_delete" ON public.servicios
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.barberias b
      WHERE b.id = servicios.barberia_id AND (
        b.dueno_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'superadmin')
      )
    )
  );

-- Políticas de citas (Desbloqueadas para soportar reservas con invitados)
DROP POLICY IF EXISTS "citas_select" ON public.citas;
CREATE POLICY "citas_select" ON public.citas
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "citas_insert" ON public.citas;
CREATE POLICY "citas_insert" ON public.citas
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "citas_update" ON public.citas;
CREATE POLICY "citas_update" ON public.citas
  FOR UPDATE USING (true);

-- Políticas de reseñas
DROP POLICY IF EXISTS "resenas_select" ON public.resenas;
CREATE POLICY "resenas_select" ON public.resenas
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "resenas_insert" ON public.resenas;
CREATE POLICY "resenas_insert" ON public.resenas
  FOR INSERT WITH CHECK (auth.uid() = cliente_id);

-- Políticas de pagos de nómina
DROP POLICY IF EXISTS "pagos_select" ON public.pagos_nomina;
CREATE POLICY "pagos_select" ON public.pagos_nomina
  FOR SELECT USING (
    auth.uid() = barbero_id
    OR EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND (p.rol = 'dueño' OR p.rol = 'dueno' OR p.rol = 'superadmin'))
  );

DROP POLICY IF EXISTS "pagos_insert" ON public.pagos_nomina;
CREATE POLICY "pagos_insert" ON public.pagos_nomina
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND (p.rol = 'dueño' OR p.rol = 'dueno' OR p.rol = 'superadmin'))
  );

-- Políticas de logs de actividad
DROP POLICY IF EXISTS "logs_select" ON public.logs_actividad;
CREATE POLICY "logs_select" ON public.logs_actividad
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid() AND p.rol = 'superadmin')
  );

DROP POLICY IF EXISTS "logs_insert" ON public.logs_actividad;
CREATE POLICY "logs_insert" ON public.logs_actividad
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Políticas de barbero_servicios
DROP POLICY IF EXISTS "barbero_servicios_select" ON public.barbero_servicios;
CREATE POLICY "barbero_servicios_select" ON public.barbero_servicios
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "barbero_servicios_insert" ON public.barbero_servicios;
CREATE POLICY "barbero_servicios_insert" ON public.barbero_servicios
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.perfiles p
      JOIN public.barberias b ON b.id = p.barberia_id
      WHERE p.id = barbero_servicios.barbero_id AND (
        b.dueno_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.perfiles sa WHERE sa.id = auth.uid() AND sa.rol = 'superadmin')
      )
    )
  );

DROP POLICY IF EXISTS "barbero_servicios_delete" ON public.barbero_servicios;
CREATE POLICY "barbero_servicios_delete" ON public.barbero_servicios
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.perfiles p
      JOIN public.barberias b ON b.id = p.barberia_id
      WHERE p.id = barbero_servicios.barbero_id AND (
        b.dueno_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.perfiles sa WHERE sa.id = auth.uid() AND sa.rol = 'superadmin')
      )
    )
  );

-- ============================================================
-- 11. HABILITAR PUBLICACIÓN REALTIME Y REPLICA IDENTITY
-- ============================================================

-- Habilitar tiempo real de forma condicional para evitar errores
DO $$
BEGIN
  -- Agregar public.citas si no está en la publicación
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'citas'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.citas;
  END IF;

  -- Agregar public.perfiles si no está en la publicación
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'perfiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.perfiles;
  END IF;

  -- Agregar public.resenas si no está en la publicación
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'resenas'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.resenas;
  END IF;
END $$;

-- Replica Identity FULL (Indispensable para filtrado robusto en tiempo real)
ALTER TABLE public.citas REPLICA IDENTITY FULL;
ALTER TABLE public.perfiles REPLICA IDENTITY FULL;
ALTER TABLE public.resenas REPLICA IDENTITY FULL;
