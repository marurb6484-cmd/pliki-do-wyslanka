
import { RaceRoom } from "./room";
import { RoomDirectory } from "./directory";

export { RaceRoom, RoomDirectory };

interface Env {
  RACE_ROOMS: DurableObjectNamespace;
  ROOM_DIRECTORY: DurableObjectNamespace;
  DB: D1Database;
  GOOGLE_CLIENT_ID?: string;
}

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" };
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
const encoder = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const unb64 = (value: string) => Uint8Array.from(atob(value), c => c.charCodeAt(0));
const hex = (bytes: Uint8Array) => Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");

function validRoomCode(value: string): boolean { return /^[A-F0-9]{8}$/.test(value); }
function cleanEmail(value: unknown): string { return typeof value === "string" ? value.trim().toLowerCase().slice(0, 254) : ""; }
function validEmail(value: string): boolean { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value); }
function cleanName(value: unknown): string { return (typeof value === "string" ? value : "Robot").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, 28) || "Robot"; }

async function body(request: Request): Promise<any> {
  const text = await request.text();
  if (text.length > 300_000) throw new Error("BODY_TOO_LARGE");
  return JSON.parse(text || "{}");
}

async function digest(value: string): Promise<string> {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
}

async function passwordHash(password: string, salt: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 210000 }, key, 256);
  return b64(new Uint8Array(bits));
}

async function issueSession(env: Env, userId: string): Promise<string> {
  const token = b64(crypto.getRandomValues(new Uint8Array(32))).replace(/=+$/g, "");
  const tokenHash = await digest(token);
  const expires = Date.now() + 30 * 24 * 60 * 60 * 1000;
  await env.DB.prepare("INSERT INTO sessions (token_hash,user_id,expires_at,created_at) VALUES (?,?,?,?)")
    .bind(tokenHash, userId, expires, Date.now()).run();
  return token;
}

async function authenticatedUser(request: Request, env: Env): Promise<any | null> {
  const auth = request.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const tokenHash = await digest(auth.slice(7));
  return await env.DB.prepare("SELECT u.id,u.email,u.display_name FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? LIMIT 1")
    .bind(tokenHash, Date.now()).first();
}

async function register(request: Request, env: Env): Promise<Response> {
  const data = await body(request);
  const email = cleanEmail(data.email);
  const password = typeof data.password === "string" ? data.password : "";
  if (!validEmail(email) || password.length < 10 || password.length > 128) return json({ ok:false, error:"INVALID_CREDENTIALS_FORMAT", message:"Use a valid email and a password of 10–128 characters." }, 400);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await passwordHash(password, salt);
  const id = crypto.randomUUID();
  const name = cleanName(data.display_name);
  try {
    await env.DB.prepare("INSERT INTO users (id,email,display_name,password_salt,password_hash,created_at) VALUES (?,?,?,?,?,?)")
      .bind(id,email,name,b64(salt),hash,Date.now()).run();
  } catch {
    return json({ ok:false,error:"EMAIL_ALREADY_REGISTERED" },409);
  }
  return json({ ok:true,token:await issueSession(env,id),user:{id,email,display_name:name} },201);
}

async function login(request: Request, env: Env): Promise<Response> {
  const data = await body(request);
  const email = cleanEmail(data.email);
  const password = typeof data.password === "string" ? data.password : "";
  const user: any = await env.DB.prepare("SELECT id,email,display_name,password_salt,password_hash FROM users WHERE email=? LIMIT 1").bind(email).first();
  if (!user || !password || await passwordHash(password,unb64(user.password_salt)) !== user.password_hash) return json({ok:false,error:"INVALID_LOGIN"},401);
  return json({ok:true,token:await issueSession(env,user.id),user:{id:user.id,email:user.email,display_name:user.display_name}});
}

async function logout(request: Request, env: Env): Promise<Response> {
  const auth = request.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ok:false,error:"UNAUTHORIZED"},401);
  const tokenHash = await digest(auth.slice(7));
  await env.DB.prepare("DELETE FROM sessions WHERE token_hash=?").bind(tokenHash).run();
  return json({ok:true});
}

async function googleLogin(request: Request, env: Env): Promise<Response> {
  if (!env.GOOGLE_CLIENT_ID) return json({ok:false,error:"GOOGLE_LOGIN_NOT_CONFIGURED"},503);
  const data = await body(request);
  const idToken = typeof data.id_token === "string" ? data.id_token : "";
  if (!idToken || idToken.length > 10000) return json({ok:false,error:"INVALID_GOOGLE_TOKEN"},400);
  const response = await fetch("https://oauth2.googleapis.com/tokeninfo?id_token=" + encodeURIComponent(idToken));
  if (!response.ok) return json({ok:false,error:"GOOGLE_TOKEN_REJECTED"},401);
  const claims: any = await response.json();
  if (claims.aud !== env.GOOGLE_CLIENT_ID || !["accounts.google.com","https://accounts.google.com"].includes(claims.iss) || Number(claims.exp) * 1000 <= Date.now() || claims.email_verified !== "true") return json({ok:false,error:"GOOGLE_TOKEN_INVALID"},401);
  const email = cleanEmail(claims.email);
  if (!validEmail(email)) return json({ok:false,error:"GOOGLE_EMAIL_INVALID"},401);
  let user: any = await env.DB.prepare("SELECT id,email,display_name FROM users WHERE email=? LIMIT 1").bind(email).first();
  if (!user) {
    const id=crypto.randomUUID();
    const name=cleanName(claims.name || email.split("@")[0]);
    await env.DB.prepare("INSERT INTO users (id,email,display_name,created_at) VALUES (?,?,?,?)").bind(id,email,name,Date.now()).run();
    user={id,email,display_name:name};
  }
  return json({ok:true,token:await issueSession(env,user.id),user});
}

async function getSave(request: Request, env: Env): Promise<Response> {
  const user = await authenticatedUser(request,env);
  if (!user) return json({ok:false,error:"UNAUTHORIZED"},401);
  const save: any = await env.DB.prepare("SELECT revision,payload,updated_at FROM saves WHERE user_id=?").bind(user.id).first();
  return json({ok:true,save:save ? {revision:save.revision,payload:save.payload,updated_at:save.updated_at} : null});
}

async function putSave(request: Request, env: Env): Promise<Response> {
  const user = await authenticatedUser(request,env);
  if (!user) return json({ok:false,error:"UNAUTHORIZED"},401);
  const data=await body(request);
  const payload=typeof data.payload === "string" ? data.payload : "";
  const expected=Number.isInteger(data.expected_revision) ? Number(data.expected_revision) : 0;
  if (!payload || payload.length > 250_000 || !payload.includes("[robot_racing_backup]")) return json({ok:false,error:"INVALID_SAVE_PAYLOAD"},400);
  const current: any = await env.DB.prepare("SELECT revision,payload,updated_at FROM saves WHERE user_id=?").bind(user.id).first();
  const currentRevision = current ? Number(current.revision) : 0;
  if (expected !== currentRevision) return json({ok:false,error:"SAVE_CONFLICT",cloud_save:current ? {revision:current.revision,payload:current.payload,updated_at:current.updated_at} : null},409);
  const next=currentRevision+1;
  const now=Date.now();
  if (current) await env.DB.prepare("INSERT INTO save_history (user_id,revision,payload,created_at) VALUES (?,?,?,?)").bind(user.id,currentRevision,current.payload,now).run();
  const result = await env.DB.prepare("INSERT INTO saves (user_id,revision,payload,updated_at) VALUES (?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload,updated_at=excluded.updated_at WHERE saves.revision=?")
    .bind(user.id,next,payload,now,currentRevision).run();
  if ((result.meta?.changes ?? 0) !== 1) {
    const latest: any = await env.DB.prepare("SELECT revision,payload,updated_at FROM saves WHERE user_id=?").bind(user.id).first();
    return json({ok:false,error:"SAVE_CONFLICT",cloud_save:latest ? {revision:latest.revision,payload:latest.payload,updated_at:latest.updated_at} : null},409);
  }
  return json({ok:true,revision:next,updated_at:now});
}

async function getProfile(request: Request, env: Env): Promise<Response> {
  const user = await authenticatedUser(request,env);
  if (!user) return json({ok:false,error:"UNAUTHORIZED"},401);
  const profile: any = await env.DB.prepare("SELECT public_name,country_code,selected_robot_id,updated_at FROM user_profiles WHERE user_id=?").bind(user.id).first();
  return json({ok:true,profile:profile ?? {public_name:user.display_name,country_code:"",selected_robot_id:"",updated_at:null}});
}

async function updateProfile(request: Request, env: Env): Promise<Response> {
  const user = await authenticatedUser(request,env);
  if (!user) return json({ok:false,error:"UNAUTHORIZED"},401);
  const data = await body(request);
  const previous: any = await env.DB.prepare("SELECT public_name,country_code,selected_robot_id FROM user_profiles WHERE user_id=?").bind(user.id).first();
  const publicName = cleanName(data.public_name ?? previous?.public_name ?? user.display_name);
  const requestedCountry = typeof data.country_code === "string" ? data.country_code.toUpperCase() : "";
  const country = /^[A-Z]{2}$/.test(requestedCountry) ? requestedCountry : (previous?.country_code ?? "");
  const robot = typeof data.selected_robot_id === "string" ? data.selected_robot_id.replace(/[^a-zA-Z0-9_-]/g,"").slice(0,64) : (previous?.selected_robot_id ?? "");
  const now = Date.now();
  await env.DB.prepare("INSERT INTO user_profiles (user_id,public_name,country_code,selected_robot_id,updated_at) VALUES (?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET public_name=excluded.public_name,country_code=excluded.country_code,selected_robot_id=excluded.selected_robot_id,updated_at=excluded.updated_at")
    .bind(user.id,publicName,country,robot,now).run();
  await env.DB.prepare("UPDATE users SET display_name=? WHERE id=?").bind(publicName,user.id).run();
  return json({ok:true,profile:{public_name:publicName,country_code:country,selected_robot_id:robot,updated_at:now}});
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({
        ok:true,
        service:"robot-racing-multiplayer",
        protocol:1,
        cloud_accounts:true,
        cloud_assets:false,
        cloud_profiles:true
      });
    }

    if (url.pathname === "/api/assets" || url.pathname.startsWith("/api/assets/")) {
      return json({ok:false,error:"CLOUD_ASSETS_DISABLED"},410);
    }

    if (request.method === "POST" && url.pathname === "/api/auth/register") return register(request,env);
    if (request.method === "POST" && url.pathname === "/api/auth/login") return login(request,env);
    if (request.method === "POST" && url.pathname === "/api/auth/google") return googleLogin(request,env);
    if (request.method === "POST" && url.pathname === "/api/auth/logout") return logout(request,env);
    if (request.method === "GET" && url.pathname === "/api/save") return getSave(request,env);
    if (request.method === "PUT" && url.pathname === "/api/save") return putSave(request,env);
    if (request.method === "GET" && url.pathname === "/api/profile") return getProfile(request,env);
    if (request.method === "PUT" && url.pathname === "/api/profile") return updateProfile(request,env);

    if (request.method === "GET" && url.pathname === "/api/rooms") {
      const directory=env.ROOM_DIRECTORY.get(env.ROOM_DIRECTORY.idFromName("global"));
      return directory.fetch("https://directory.internal/list");
    }

    if (request.method === "POST" && url.pathname === "/api/rooms") {
      const roomCode=crypto.randomUUID().replace(/-/g,"").slice(0,8).toUpperCase();
      return json({ok:true,room_code:roomCode,max_players:6,protocol:1},201);
    }

    if (request.method === "GET" && url.pathname === "/ws") {
      const roomCode=(url.searchParams.get("room")??"").toUpperCase();
      const playerName=cleanName(url.searchParams.get("player"));
      if (!validRoomCode(roomCode)) return json({ok:false,error:"INVALID_ROOM_CODE"},400);
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return json({ok:false,error:"WEBSOCKET_REQUIRED"},426);
      const room=env.RACE_ROOMS.get(env.RACE_ROOMS.idFromName(roomCode));
      const forwarded=new URL("https://room.internal/connect");
      forwarded.searchParams.set("player",playerName);
      forwarded.searchParams.set("room_code",roomCode);
      forwarded.searchParams.set("robot",cleanName(url.searchParams.get("robot")));
      forwarded.searchParams.set("ovr",url.searchParams.get("ovr")??"1");
      return room.fetch(new Request(forwarded,request));
    }

    return json({ok:false,error:"NOT_FOUND"},404);
  },
};

