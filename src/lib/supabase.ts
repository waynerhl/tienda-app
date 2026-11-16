import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL?.trim();
const key = (
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY
)?.trim();

function configurationError(): string | null {
  if (!url || !key)
    return "Falta configurar la URL y la clave pública de Supabase en .env.local.";
  try {
    if (new URL(url).protocol !== "https:")
      return "La URL de Supabase debe comenzar con https://.";
  } catch {
    return "La URL de Supabase no tiene un formato válido.";
  }
  if (key.startsWith("sb_secret_"))
    return "Usa una clave publicable de Supabase para esta aplicación.";
  if (!key.startsWith("sb_publishable_")) {
    try {
      const payload = JSON.parse(
        atob(key.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
      );
      if (payload.role !== "anon")
        return "Usa una clave publicable o anon de Supabase.";
    } catch {
      return "La clave pública de Supabase no tiene un formato válido.";
    }
  }
  return null;
}

export const supabaseConfigurationError = configurationError();
export const supabase = supabaseConfigurationError
  ? null
  : createClient(url!, key!);
