import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase, supabaseConfigurationError } from "./lib/supabase";
import Login from "./pages/Login";
import Productos from "./pages/Productos";
import Compras from "./pages/Compras";
import "./App.css";
import Ventas from "./pages/Ventas";
import Dashboard from "./pages/Dashboard";

type Profile = { nombre: string; activo: boolean; rol: string };

function SignedIn({ session }: { session: Session }) {
  const [tab, setTab] = useState("productos");
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
    onClick={() => setTab("productos")}
  >
    Productos
  </button>

  {(profile.rol === "ADMINISTRADOR" ||
    profile.rol === "INVENTARIO") && (
    <button
      type="button"
      className={tab === "compras" ? "selected" : "secondary"}
      onClick={() => setTab("compras")}
    >
      Compras
    </button>
  )}

  {(profile.rol === "ADMINISTRADOR" ||
    profile.rol === "CAJERO") && (
    <button
      type="button"
      className={tab === "ventas" ? "selected" : "secondary"}
      onClick={() => setTab("ventas")}
    >
      Ventas
    </button>
  )}
  {profile.rol === "ADMINISTRADOR" && (
  <button
    type="button"
    className={tab === "dashboard" ? "selected" : "secondary"}
    onClick={() => setTab("dashboard")}
  >
    Resumen
  </button>
)}
</nav>

{/* Las pantallas van fuera del nav */}
<div hidden={tab !== "productos"}>
  <Productos
    key={catalogVersion}
    canManage={
      profile.rol === "ADMINISTRADOR" ||
      profile.rol === "INVENTARIO"
    }
  />
</div>
{profile.rol === "ADMINISTRADOR" && (
  <div hidden={tab !== "dashboard"}>
    <Dashboard
      activo={tab === "dashboard"}
      revision={catalogVersion}
    />
  </div>
)}
{(profile.rol === "ADMINISTRADOR" ||
  profile.rol === "INVENTARIO") && (
  <div hidden={tab !== "compras"}>
    <Compras
      onRegistered={() =>
        setCatalogVersion((value) => value + 1)
      }
    />
  </div>
)}

{(profile.rol === "ADMINISTRADOR" ||
  profile.rol === "CAJERO") && (
  <div hidden={tab !== "ventas"}>
    <Ventas
      userId={session.user.id}
      onRegistered={() =>
        setCatalogVersion((value) => value + 1)
      }
    />
  </div>
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
          servidor de desarrollo.
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
