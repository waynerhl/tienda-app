import { lazy, Suspense, useEffect, useState } from "react";
import type { ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase, supabaseConfigurationError } from "./lib/supabase";
import Login from "./pages/Login";
import "./App.css";
const Productos = lazy(() => import("./pages/Productos"));
const Compras = lazy(() => import("./pages/Compras"));
const Ventas = lazy(() => import("./pages/Ventas"));
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Clientes = lazy(() => import("./pages/Clientes"));
const Proveedores = lazy(() => import("./pages/Proveedores"));
const Efectivo = lazy(() => import("./pages/Efectivo"));
const Reserva = lazy(() => import("./pages/Reserva"));
const Caja = lazy(() => import("./pages/Caja"));
const Inicial = lazy(() => import("./pages/Inicial"));
const Inventario = lazy(() => import("./pages/Inventario"));
const Reportes = lazy(() => import("./pages/Reportes"));
const Rotacion = lazy(() => import("./pages/Rotacion"));
const ListaCompras = lazy(() => import("./pages/ListaCompras"));

// Una pantalla se monta al abrirla y conserva su estado al cambiar de pestaña.
function ModulePanel({ active, visited, children }: {
  active: boolean;
  visited: boolean;
  children: ReactNode;
}) {
  if (!visited) return null;
  return (
    <div hidden={!active}>
      <Suspense fallback={<p className="state" role="status">Preparando módulo…</p>}>
        {children}
      </Suspense>
    </div>
  );
}

type Profile = { nombre: string; activo: boolean; rol: string };

function SignedIn({ session }: { session: Session }) {
  const [tab, setTab] = useState("productos");
  const [visitedTabs, setVisitedTabs] = useState(() => new Set(["productos"]));

  function selectTab(next: string) {
    setVisitedTabs(previous => previous.has(next) ? previous : new Set([...previous, next]));
    setTab(next);
  }
  const [catalogVersion, setCatalogVersion] = useState(0);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  const [signingOut, setSigningOut] = useState(false);
  const [signOutError, setSignOutError] = useState("");

  useEffect(() => {
    const controller = new AbortController();
    async function loadProfile() {
      if (!supabase) return;
      setLoading(true);
      setError("");
      try {
        const { data, error } = await supabase
          .from("usuarios")
          .select("nombre,activo,rol_id")
          .eq("id_usuario", session.user.id)
          .abortSignal(controller.signal)
          .maybeSingle();
        if (controller.signal.aborted) return;
        if (error) throw error;
        if (data?.activo) {
          const { data: role, error: roleError } = await supabase
            .from("roles")
            .select("nombre")
            .eq("id_rol", data.rol_id)
            .abortSignal(controller.signal)
            .single();
          if (controller.signal.aborted) return;
          if (roleError) throw roleError;
          setProfile({
            nombre: data.nombre,
            activo: data.activo,
            rol: role.nombre,
          });
        } else {
          setProfile(
            data ? { nombre: data.nombre, activo: false, rol: "" } : null,
          );
        }
      } catch {
        if (!controller.signal.aborted)
          setError(
            "No pudimos verificar tu perfil. Comprueba la conexión y vuelve a intentar.",
          );
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }
    void loadProfile();
    return () => controller.abort();
  }, [session.user.id, retry]);

  async function signOut() {
    if (!supabase) return;
    setSigningOut(true);
    setSignOutError("");
    try {
      const { error } = await supabase.auth.signOut({ scope: "local" });
      if (error) throw error;
    } catch {
      setSignOutError("No pudimos cerrar la sesión. Inténtalo de nuevo.");
    } finally {
      setSigningOut(false);
    }
  }

  return (
    <div className="app-shell">
      <header className="app-header">
        <a className="brand" href="/">
          <span className="brand-mark" aria-hidden="true">
            T
          </span>{" "}
          Mi tienda
        </a>
        <div className="account">
          <span>{profile?.nombre || session.user.email}</span>
          <button className="secondary" disabled={signingOut} onClick={signOut}>
            {signingOut ? "Saliendo…" : "Cerrar sesión"}
          </button>
        </div>
      </header>
      <main className="workspace">
        {signOutError && (
          <p className="error" role="alert">
            {signOutError}
          </p>
        )}
        {loading ? (
          <p className="state" role="status">
            Verificando tu acceso…
          </p>
        ) : error ? (
          <div className="state">
            <p className="error" role="alert">
              {error}
            </p>
            <button onClick={() => setRetry((v) => v + 1)}>Reintentar</button>
          </div>
        ) : !profile || !profile.activo ? (
          <section className="catalog-card state">
            <h1>Acceso pendiente</h1>
            <p>
              Tu cuenta necesita un perfil activo autorizado por el
              administrador de la tienda.
            </p>
          </section>
        ) : (
          <>
            <nav className="module-nav" aria-label="Módulos de la tienda">
  <button
    type="button"
    className={tab === "productos" ? "selected" : "secondary"}
    onClick={() => selectTab("productos")}
  >
    Productos
  </button>

  {(profile.rol === "ADMINISTRADOR" ||
    profile.rol === "INVENTARIO") && (
    <button
      type="button"
      className={tab === "compras" ? "selected" : "secondary"}
      onClick={() => selectTab("compras")}
    >
      Compras
    </button>
  )}

  {(profile.rol === "ADMINISTRADOR" ||
    profile.rol === "CAJERO") && (
    <button
      type="button"
      className={tab === "ventas" ? "selected" : "secondary"}
      onClick={() => selectTab("ventas")}
    >
      Ventas
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && (
  <button
    type="button"
    className={tab === "dashboard" ? "selected" : "secondary"}
    onClick={() => selectTab("dashboard")}
  >
    Resumen
  </button>
)}
  {(profile.rol === "ADMINISTRADOR" || profile.rol === "CAJERO") && (
    <button
      type="button"
      className={tab === "clientes" ? "selected" : "secondary"}
      aria-current={tab === "clientes" ? "page" : undefined}
      onClick={() => selectTab("clientes")}
    >
      Clientes y cobros
    </button>
  )}
  {(profile.rol === "ADMINISTRADOR" || profile.rol === "INVENTARIO") && (
    <button
      type="button"
      className={tab === "proveedores" ? "selected" : "secondary"}
      aria-current={tab === "proveedores" ? "page" : undefined}
      onClick={() => selectTab("proveedores")}
    >
      Proveedores y pagos
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && (
    <button
      type="button"
      className={tab === "efectivo" ? "selected" : "secondary"}
      aria-current={tab === "efectivo" ? "page" : undefined}
      onClick={() => selectTab("efectivo")}
    >
      Efectivo
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && (
    <button
      type="button"
      className={tab === "caja" ? "selected" : "secondary"}
      aria-current={tab === "caja" ? "page" : undefined}
      onClick={() => selectTab("caja")}
    >
      Caja
    </button>
  )}
  {(profile.rol === "ADMINISTRADOR" || profile.rol === "INVENTARIO") && (
    <button
      type="button"
      className={tab === "inventario" ? "selected" : "secondary"}
      aria-current={tab === "inventario" ? "page" : undefined}
      onClick={() => selectTab("inventario")}
    >
      Inventario
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && (
    <button
      type="button"
      className={tab === "reportes" ? "selected" : "secondary"}
      aria-current={tab === "reportes" ? "page" : undefined}
      onClick={() => selectTab("reportes")}
    >
      Reportes
    </button>
  )}
  {(profile.rol === "ADMINISTRADOR" || profile.rol === "INVENTARIO") && (
    <button
      type="button"
      className={tab === "lista-compras" ? "selected" : "secondary"}
      aria-current={tab === "lista-compras" ? "page" : undefined}
      onClick={() => selectTab("lista-compras")}
    >
      Lista de compras
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && (
    <button type="button" className={tab === "rotacion" ? "selected" : "secondary"}
      aria-current={tab === "rotacion" ? "page" : undefined} onClick={() => selectTab("rotacion")}>
      Rotación
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && (
    <button type="button" className={tab === "inicial" ? "selected" : "secondary"}
      aria-current={tab === "inicial" ? "page" : undefined} onClick={() => selectTab("inicial")}>
      Inventario inicial
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && <button type="button" className={tab === "reserva" ? "selected" : "secondary"} aria-current={tab === "reserva" ? "page" : undefined} onClick={() => selectTab("reserva")}>Reserva</button>}
</nav>
{profile.rol === "ADMINISTRADOR" && <ModulePanel active={tab === "reserva"} visited={visitedTabs.has("reserva")}><Reserva activo={tab === "reserva"} revision={catalogVersion} userId={session.user.id} onChanged={() => setCatalogVersion(v => v + 1)} /></ModulePanel>}
{profile.rol === "ADMINISTRADOR" && (
  <ModulePanel active={tab === "inicial"} visited={visitedTabs.has("inicial")}>
    <Inicial activo={tab === "inicial"} revision={catalogVersion} userId={session.user.id} onChanged={() => setCatalogVersion(v => v + 1)} />
  </ModulePanel>
)}

{profile.rol === "ADMINISTRADOR" && (
  <ModulePanel active={tab === "rotacion"} visited={visitedTabs.has("rotacion")}>
    <Rotacion activo={tab === "rotacion"} revision={catalogVersion} />
  </ModulePanel>
)}

{(profile.rol === "ADMINISTRADOR" || profile.rol === "INVENTARIO") && (
  <ModulePanel active={tab === "lista-compras"} visited={visitedTabs.has("lista-compras")}>
    <Suspense fallback={<p className="state" role="status">Preparando lista…</p>}>
      <ListaCompras activo={tab === "lista-compras"} revision={catalogVersion} userId={session.user.id} onChanged={() => setCatalogVersion(value => value + 1)} />
    </Suspense>
  </ModulePanel>
)}

{profile.rol === "ADMINISTRADOR" && (
  <ModulePanel active={tab === "reportes"} visited={visitedTabs.has("reportes")}>
    <Suspense fallback={<p className="state" role="status">Preparando reportes…</p>}>
      <Reportes activo={tab === "reportes"} revision={catalogVersion} />
    </Suspense>
  </ModulePanel>
)}

{(profile.rol === "ADMINISTRADOR" || profile.rol === "INVENTARIO") && (
  <ModulePanel active={tab === "inventario"} visited={visitedTabs.has("inventario")}>
    <Suspense fallback={<p className="state" role="status">Preparando inventario…</p>}>
      <Inventario activo={tab === "inventario"} revision={catalogVersion} userId={session.user.id} onChanged={() => setCatalogVersion(value => value + 1)} />
    </Suspense>
  </ModulePanel>
)}

{profile.rol === "ADMINISTRADOR" && (
  <ModulePanel active={tab === "caja"} visited={visitedTabs.has("caja")}>
    <Suspense fallback={<p className="state" role="status">Preparando caja…</p>}>
      <Caja activo={tab === "caja"} revision={catalogVersion} userId={session.user.id} onChanged={() => setCatalogVersion(value => value + 1)} />
    </Suspense>
  </ModulePanel>
)}

{profile.rol === "ADMINISTRADOR" && (
  <ModulePanel active={tab === "efectivo"} visited={visitedTabs.has("efectivo")}>
    <Suspense fallback={<p className="state" role="status">Preparando efectivo…</p>}>
      <Efectivo activo={tab === "efectivo"} revision={catalogVersion} />
    </Suspense>
  </ModulePanel>
)}

{(profile.rol === "ADMINISTRADOR" || profile.rol === "INVENTARIO") && (
  <ModulePanel active={tab === "proveedores"} visited={visitedTabs.has("proveedores")}>
    <Proveedores
      userId={session.user.id}
      activo={tab === "proveedores"}
      revision={catalogVersion}
      onChanged={() => setCatalogVersion(value => value + 1)}
    />
  </ModulePanel>
)}

{(profile.rol === "ADMINISTRADOR" || profile.rol === "CAJERO") && (
  <ModulePanel active={tab === "clientes"} visited={visitedTabs.has("clientes")}>
    <Clientes
      userId={session.user.id}
      activo={tab === "clientes"}
      revision={catalogVersion}
      onChanged={() => setCatalogVersion(value => value + 1)}
    />
  </ModulePanel>
)}

{/* Las pantallas van fuera del nav */}
<ModulePanel active={tab === "productos"} visited={visitedTabs.has("productos")}>
  <Productos
    key={catalogVersion}
    canManage={
      profile.rol === "ADMINISTRADOR" ||
      profile.rol === "INVENTARIO"
    }
  />
</ModulePanel>
{profile.rol === "ADMINISTRADOR" && (
  <ModulePanel active={tab === "dashboard"} visited={visitedTabs.has("dashboard")}>
    <Dashboard
      activo={tab === "dashboard"}
      revision={catalogVersion}
    />
  </ModulePanel>
)}
{(profile.rol === "ADMINISTRADOR" ||
  profile.rol === "INVENTARIO") && (
  <ModulePanel active={tab === "compras"} visited={visitedTabs.has("compras")}>
    <Compras
      revisionExterna={catalogVersion}
      onRegistered={() =>
        setCatalogVersion((value) => value + 1)
      }
    />
  </ModulePanel>
)}

{(profile.rol === "ADMINISTRADOR" ||
  profile.rol === "CAJERO") && (
  <ModulePanel active={tab === "ventas"} visited={visitedTabs.has("ventas")}>
    <Ventas
      userId={session.user.id}
      revisionExterna={catalogVersion}
      onRegistered={() =>
        setCatalogVersion((value) => value + 1)
      }
    />
  </ModulePanel>
)}
          </>
        )}
      </main>
      <footer className="app-footer">Mi tienda · Control de inventario</footer>
    </div>
  );
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!supabase) return;
    // INITIAL_SESSION restaura la sesión; la suscripción también recibe login y logout.
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      setLoading(false);
      setError("");
    });
    let active = true;
    void supabase.auth
      .getSession()
      .then(({ data, error }) => {
        if (!active) return;
        if (error)
          setError(
            "No pudimos recuperar tu sesión. Recarga la página para intentarlo de nuevo.",
          );
        else setSession(data.session);
        setLoading(false);
      })
      .catch(() => {
        if (active) {
          setError(
            "No pudimos recuperar tu sesión. Recarga la página para intentarlo de nuevo.",
          );
          setLoading(false);
        }
      });
    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);

  if (supabaseConfigurationError)
    return (
      <main className="setup-card">
        <p className="eyebrow">CONFIGURACIÓN INICIAL</p>
        <h1>Conecta tu tienda</h1>
        <p role="alert">{supabaseConfigurationError}</p>
        <p className="muted">
          Completa las variables de .env.local siguiendo el README y reinicia el
          servidor de desarrollo. Si estás publicando, configura las variables
          de compilación del alojamiento y vuelve a desplegar.
        </p>
      </main>
    );
  if (loading)
    return (
      <main className="state" role="status">
        Preparando tu tienda…
      </main>
    );
  if (error)
    return (
      <main className="setup-card">
        <p className="error" role="alert">
          {error}
        </p>
        <button onClick={() => window.location.reload()}>Reintentar</button>
      </main>
    );
  return session ? (
    <SignedIn key={session.user.id} session={session} />
  ) : (
    <Login />
  );
}
