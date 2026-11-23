import { loadEnv } from "vite";

// VITE_* se incluye en los archivos públicos. Validar antes de compilar.
const env = loadEnv("production", process.cwd(), "VITE_");
const url = env.VITE_SUPABASE_URL?.trim();
const key = (env.VITE_SUPABASE_PUBLISHABLE_KEY || env.VITE_SUPABASE_ANON_KEY)?.trim();
function fail(message) {
  console.error(`No se puede preparar la publicación: ${message}`);
  process.exit(1);
}
if (!url || !key) fail("configura VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY en las variables de compilación.");
try {
  if (new URL(url).origin !== "https://ytzybvbeleuuoduitckq.supabase.co")
    fail("la URL no corresponde al proyecto de esta tienda. Revisa también public/_headers si cambias de proyecto.");
} catch { fail("la URL de Supabase no es válida."); }
if (Object.keys(env).some(name => /SECRET|PASSWORD|SERVICE_ROLE|DATABASE_URL/.test(name)))
  fail("hay una variable VITE_* reservada para información privada. Retírala de la compilación.");
if (!key.startsWith("sb_publishable_") || key.includes("REEMPLAZA")) {
  try {
    if (JSON.parse(Buffer.from(key.split(".")[1], "base64url").toString()).role !== "anon")
      fail("usa únicamente la clave publicable o anon; nunca service_role ni sb_secret.");
  } catch { fail("la clave debe ser publicable o anon válida; nunca una clave privada."); }
}
console.log("Configuración pública comprobada. No se muestran las claves.");
