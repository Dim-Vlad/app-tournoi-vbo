// Edge Function — create-referent
//
// Crée (par invitation e-mail) un compte référent VBO.
// Flux : l'admin (connecté) appelle cette fonction → on vérifie qu'il est bien
// admin → on envoie une INVITATION par e-mail au futur référent. Celui-ci reçoit
// un mail, clique sur le lien et choisit son propre mot de passe dans l'app.
//
// Le compte auth est créé avec user_metadata { app:'vbo', role:'referent',
// full_name }. Le déclencheur `vbo.handle_new_user` crée alors automatiquement
// le profil dans vbo.profiles (uniquement parce que app = 'vbo').
//
// Secrets à définir côté Supabase (jamais dans le dépôt) :
//   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxx
//   supabase secrets set APP_URL=https://dim-vlad.github.io/app-tournoi-vbo/
// (SUPABASE_URL et SUPABASE_ANON_KEY sont injectés automatiquement.)
//
// Déploiement :  supabase functions deploy create-referent
//
// ⚠️ L'envoi réel de l'e-mail suppose un SMTP configuré dans Supabase
//    (Authentication → Emails → SMTP Settings). Sans SMTP personnalisé,
//    l'e-mail intégré de Supabase est fortement limité (quelques envois/heure,
//    adresses restreintes) et ne convient pas en production.

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Méthode non autorisée" });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const appUrl =
      Deno.env.get("APP_URL") || "https://dim-vlad.github.io/app-tournoi-vbo/";

    if (!url || !anon || !service) {
      return json(500, {
        error: "Configuration serveur incomplète (secrets manquants).",
      });
    }

    // 1. Vérifier que l'appelant est un admin VBO authentifié.
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader) return json(401, { error: "Non authentifié." });

    const caller = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
      db: { schema: "vbo" },
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: userData, error: userErr } = await caller.auth.getUser();
    if (userErr || !userData?.user) {
      return json(401, { error: "Session invalide ou expirée." });
    }

    const { data: profile, error: profErr } = await caller
      .from("profiles")
      .select("role, status")
      .eq("id", userData.user.id)
      .maybeSingle();

    if (profErr) return json(500, { error: "Erreur de vérification du profil." });
    if (!profile || profile.role !== "admin" || profile.status !== "active") {
      return json(403, { error: "Action réservée à l'administrateur." });
    }

    // 2. Valider l'entrée.
    let payload: { name?: string; email?: string };
    try {
      payload = await req.json();
    } catch {
      return json(400, { error: "Requête invalide." });
    }
    const name = (payload.name || "").trim();
    const email = (payload.email || "").trim().toLowerCase();
    const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    if (!name) return json(400, { error: "Le nom du référent est requis." });
    if (!emailOk) return json(400, { error: "Adresse e-mail invalide." });

    // 3. Inviter l'utilisateur par e-mail (il choisira son mot de passe).
    const admin = createClient(url, service, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: invited, error: inviteErr } =
      await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo: appUrl,
        data: { app: "vbo", role: "referent", full_name: name },
      });

    if (inviteErr) {
      const msg = String(inviteErr.message || "");
      // Cas courant : l'adresse a déjà un compte.
      if (/already|registered|exists/i.test(msg)) {
        return json(409, {
          error: "Un compte existe déjà pour cette adresse e-mail.",
        });
      }
      return json(400, {
        error: "Échec de l'envoi de l'invitation : " + msg,
      });
    }

    return json(200, {
      ok: true,
      id: invited.user?.id ?? null,
      email,
      name,
      invited: true,
    });
  } catch (e) {
    return json(500, { error: "Erreur inattendue : " + String((e as Error)?.message || e) });
  }
});
