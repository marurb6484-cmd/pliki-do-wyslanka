interface PlayerAttachment {
  playerId: string;
  playerName: string;
  joinedAt: number;
  messagesInWindow: number;
  windowStartedAt: number;
  ready: boolean;
  robotName: string;
  ovr: number;
}

interface ClientMessage {
  type?: string;
  seq?: number;
  x?: number;
  y?: number;
  rotation?: number;
  throttle?: number;
  steer?: number;
  brake?: boolean;
  ready?: boolean;
  ai_count?: number;
  states?: Array<Record<string, unknown>>;
  z?: number;
  yaw?: number;
  vx?: number;
  vz?: number;
}

const MAX_PLAYERS = 6;
const MAX_MESSAGE_BYTES = 4096;
const MAX_MESSAGES_PER_SECOND = 40;

interface Env {
  ROOM_DIRECTORY: DurableObjectNamespace;
}

export class RaceRoom {
  private readonly state: DurableObjectState;
  private readonly env: Env;
  private roomCode = "";

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket upgrade required", { status: 426 });
    }

    const current = this.state.getWebSockets();
    this.roomCode = (new URL(request.url).searchParams.get("room_code") ?? "").toUpperCase();
    if (current.length >= MAX_PLAYERS) {
      return new Response(JSON.stringify({ error: "ROOM_FULL" }), {
        status: 409,
        headers: { "content-type": "application/json" },
      });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const playerName = (new URL(request.url).searchParams.get("player") ?? "Robot")
      .replace(/[\u0000-\u001f<>]/g, "")
      .trim()
      .slice(0, 20) || "Robot";
    const params = new URL(request.url).searchParams;
    const robotName = (params.get("robot") ?? "Robot").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, 28) || "Robot";
    const requestedOvr = Number(params.get("ovr") ?? 1);
    const ovr = Number.isFinite(requestedOvr) ? Math.max(1, Math.min(100, Math.round(requestedOvr))) : 1;
    const attachment: PlayerAttachment = {
      playerId: crypto.randomUUID(),
      playerName,
      joinedAt: Date.now(),
      messagesInWindow: 0,
      windowStartedAt: Date.now(),
      ready: false,
      robotName,
      ovr,
    };

    this.state.acceptWebSocket(server);
    server.serializeAttachment(attachment);

    server.send(JSON.stringify({
      type: "welcome",
      player_id: attachment.playerId,
      player_name: playerName,
      robot_name: robotName,
      ovr,
      max_players: MAX_PLAYERS,
      players: this.listPlayers(),
      host_id: this.getHostId(),
      server_time: Date.now(),
    }));
    this.broadcastLobby();
    void this.syncDirectory();

    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): void {
    const attachment = ws.deserializeAttachment() as PlayerAttachment | null;
    if (!attachment) return;

    const now = Date.now();
    if (now - attachment.windowStartedAt >= 1000) {
      attachment.windowStartedAt = now;
      attachment.messagesInWindow = 0;
    }
    attachment.messagesInWindow += 1;
    ws.serializeAttachment(attachment);
    if (attachment.messagesInWindow > MAX_MESSAGES_PER_SECOND) {
      ws.close(1008, "Rate limit exceeded");
      return;
    }

    const raw = typeof message === "string" ? message : new TextDecoder().decode(message);
    if (new TextEncoder().encode(raw).length > MAX_MESSAGE_BYTES) {
      ws.close(1009, "Message too large");
      return;
    }

    let data: ClientMessage;
    try {
      data = JSON.parse(raw) as ClientMessage;
    } catch {
      ws.send(JSON.stringify({ type: "error", code: "BAD_JSON" }));
      return;
    }

    // MVP relay: only compact driving-input packets are forwarded. The server does
    // not yet validate race progress or award results; that is a later milestone.
    if (data.type === "input") {
      const safe = {
        type: "input",
        player_id: attachment.playerId,
        seq: Number.isSafeInteger(data.seq) ? data.seq : 0,
        x: this.clampNumber(data.x, -100000, 100000),
        y: this.clampNumber(data.y, -100000, 100000),
        rotation: this.clampNumber(data.rotation, -1000, 1000),
        throttle: this.clampNumber(data.throttle, -1, 1),
        steer: this.clampNumber(data.steer, -1, 1),
        brake: data.brake === true,
        server_time: now,
      };
      this.broadcast(safe, ws);
      return;
    }

    if (data.type === "ai_state") {
      if (attachment.playerId !== this.getHostId()) {
        ws.send(JSON.stringify({ type: "error", code: "HOST_ONLY" }));
        return;
      }
      const states = Array.isArray(data.states) ? data.states.slice(0, 3).map((item, index) => {
        const state = item && typeof item === "object" ? item as Record<string, unknown> : {};
        return {
          slot: index,
          x: this.clampNumber(state.x, -5000, 5000),
          y: this.clampNumber(state.y, -100, 100),
          z: this.clampNumber(state.z, -5000, 5000),
          yaw: this.clampNumber(state.yaw, -1000, 1000),
          vx: this.clampNumber(state.vx, -100, 100),
          vz: this.clampNumber(state.vz, -100, 100),
        };
      }) : [];
      this.broadcast({ type: "ai_state", states, server_time: now }, ws);
      return;
    }

    if (data.type === "race_state") {
      const safe = {
        type: "race_state",
        player_id: attachment.playerId,
        seq: Number.isSafeInteger(data.seq) ? data.seq : 0,
        x: this.clampNumber(data.x, -5000, 5000),
        y: this.clampNumber(data.y, -100, 100),
        z: this.clampNumber(data.z, -5000, 5000),
        yaw: this.clampNumber(data.yaw, -1000, 1000),
        vx: this.clampNumber(data.vx, -100, 100),
        vz: this.clampNumber(data.vz, -100, 100),
        server_time: now,
      };
      this.broadcast(safe, ws);
      return;
    }

    if (data.type === "ready") {
      attachment.ready = data.ready === true;
      ws.serializeAttachment(attachment);
      this.broadcastLobby();
      return;
    }

    if (data.type === "start_race") {
      if (attachment.playerId !== this.getHostId()) {
        ws.send(JSON.stringify({ type: "error", code: "HOST_ONLY" }));
        return;
      }
      const sockets = this.state.getWebSockets();
      if (sockets.length < 2) {
        ws.send(JSON.stringify({ type: "error", code: "NEED_MORE_PLAYERS" }));
        return;
      }
      const allReady = sockets.every((socket) => {
        const player = socket.deserializeAttachment() as PlayerAttachment | null;
        return player !== null && player.ready;
      });
      if (!allReady) {
        ws.send(JSON.stringify({ type: "error", code: "PLAYERS_NOT_READY" }));
        return;
      }
      const aiCount = Number.isInteger(data.ai_count) ? Math.max(0, Math.min(3, data.ai_count as number)) : 0;
      this.broadcast({ type: "race_starting", start_at: now + 5000, host_id: attachment.playerId, ai_count: aiCount });
      return;
    }

    if (data.type === "ping") {
      ws.send(JSON.stringify({ type: "pong", client_time: data.seq ?? 0, server_time: now }));
      return;
    }

    ws.send(JSON.stringify({ type: "error", code: "UNKNOWN_MESSAGE_TYPE" }));
  }

  webSocketClose(ws: WebSocket, code: number, reason: string): void {
    const attachment = ws.deserializeAttachment() as PlayerAttachment | null;
    try { ws.close(code, reason); } catch { /* already closed */ }
    if (attachment) {
      this.broadcast({ type: "player_left", player_id: attachment.playerId, player_name: attachment.playerName });
      this.broadcastLobby();
      void this.syncDirectory();
    }
  }

  webSocketError(ws: WebSocket): void {
    try { ws.close(1011, "WebSocket error"); } catch { /* ignore */ }
  }

  private listPlayers(): Array<{ player_id: string; player_name: string; robot_name: string; ovr: number; ready: boolean }> {
    return this.state.getWebSockets().map((socket) => {
      const item = socket.deserializeAttachment() as PlayerAttachment | null;
      return item ? { player_id: item.playerId, player_name: item.playerName, robot_name: item.robotName, ovr: item.ovr, ready: item.ready } : null;
    }).filter((item): item is { player_id: string; player_name: string; robot_name: string; ovr: number; ready: boolean } => item !== null);
  }

  private getHostId(): string {
    const players = this.state.getWebSockets().map((socket) => socket.deserializeAttachment() as PlayerAttachment | null)
      .filter((item): item is PlayerAttachment => item !== null)
      .sort((a, b) => a.joinedAt - b.joinedAt);
    return players.length > 0 ? players[0].playerId : "";
  }

  private broadcastLobby(): void {
    this.broadcast({ type: "lobby_update", players: this.listPlayers(), host_id: this.getHostId() });
  }

  private async syncDirectory(): Promise<void> {
    if (!this.roomCode) return;
    const directory = this.env.ROOM_DIRECTORY.get(this.env.ROOM_DIRECTORY.idFromName("global"));
    await directory.fetch("https://directory.internal/upsert", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ room_code: this.roomCode, players: this.listPlayers() }),
    });
  }

  private broadcast(data: unknown, except?: WebSocket): void {
    const payload = JSON.stringify(data);
    for (const socket of this.state.getWebSockets()) {
      if (socket === except) continue;
      try { socket.send(payload); } catch { /* stale socket is cleaned up by close event */ }
    }
  }

  private clampNumber(value: unknown, min: number, max: number): number {
    const number = typeof value === "number" && Number.isFinite(value) ? value : 0;
    return Math.max(min, Math.min(max, number));
  }
}
