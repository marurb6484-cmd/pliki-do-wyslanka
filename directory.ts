interface RoomSummary {
  room_code: string;
  players: Array<{ player_id: string; player_name: string; ready: boolean }>;
  players_count: number;
  max_players: number;
  updated_at: number;
}

export class RoomDirectory {
  private readonly state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/upsert") {
      const body = await request.json() as RoomSummary;
      const code = String(body.room_code ?? "").toUpperCase();
      if (!/^[A-F0-9]{8}$/.test(code)) return Response.json({ ok: false }, { status: 400 });
      const players = Array.isArray(body.players) ? body.players.slice(0, 6) : [];
      if (players.length === 0) {
        await this.state.storage.delete(`room:${code}`);
      } else {
        const room: RoomSummary = {
          room_code: code,
          players,
          players_count: players.length,
          max_players: 6,
          updated_at: Date.now(),
        };
        await this.state.storage.put(`room:${code}`, room);
      }
      return Response.json({ ok: true });
    }

    if (request.method === "GET" && url.pathname === "/list") {
      const stored = await this.state.storage.list<RoomSummary>({ prefix: "room:" });
      const now = Date.now();
      const rooms: RoomSummary[] = [];
      for (const [key, room] of stored) {
        if (now - room.updated_at > 120000 || room.players_count <= 0) {
          await this.state.storage.delete(key);
        } else {
          rooms.push(room);
        }
      }
      rooms.sort((a, b) => b.updated_at - a.updated_at);
      return Response.json({ ok: true, rooms });
    }
    return Response.json({ ok: false, error: "NOT_FOUND" }, { status: 404 });
  }
}
