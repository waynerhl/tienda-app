import { useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";

export default function Login() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase || busy) return;
    setBusy(true);
    setError("");
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (error)
        setError(
          error.code === "invalid_credentials"
            ? "El correo o la contraseña no son correctos."
            : error.code === "email_not_confirmed"
              ? "Confirma tu correo antes de ingresar."
              : "No pudimos iniciar sesión. Comprueba tu conexión e inténtalo de nuevo.",
        );
    } catch {
      setError("No pudimos conectar con Supabase. Inténtalo de nuevo.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-shell">
      <section className="login-intro">
        <span className="brand-mark" aria-hidden="true">
          T
        </span>
        <p className="eyebrow">TU TIENDA, EN ORDEN</p>
        <h1>Todo empieza con un buen control.</h1>
        <p>Consulta tus productos y sus existencias desde un solo lugar.</p>
        <div className="intro-note">
          Inventario claro. Decisiones informadas.
        </div>
      </section>
      <section className="login-card" aria-labelledby="login-title">
        <p className="eyebrow">BIENVENIDO</p>
        <h2 id="login-title">Ingresa a tu tienda</h2>
        <p className="muted">Usa tu cuenta de la aplicación.</p>
        <form onSubmit={signIn}>
          <label htmlFor="email">Correo electrónico</label>
          <input
            id="email"
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            disabled={busy}
          />
          <label htmlFor="password">Contraseña</label>
          <input
            id="password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            disabled={busy}
          />
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <button type="submit" disabled={busy}>
            {busy ? "Ingresando…" : "Ingresar"}
          </button>
        </form>
        <p className="footnote">
          El acceso se administra con las cuentas autorizadas de la tienda.
        </p>
      </section>
    </main>
  );
}
