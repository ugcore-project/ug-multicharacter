/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The only file that calls `fetch`. NUI callbacks are POSTs to `https://<resource>/<callback>`.

import { NuiCallback } from "@/types/protocol";

declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
}

/** True in a normal browser (`npm run dev`), where no NUI callback endpoint exists. */
export function isEnvBrowser(): boolean {
  return typeof window.GetParentResourceName !== "function";
}

function resourceName(): string {
  return window.GetParentResourceName?.() ?? "ug-multicharacter";
}

/** Sent requests in a browser, for the dev preview and tests. */
export const browserLog: { callback: string; data: unknown }[] = [];

export async function postNui(callback: NuiCallback, data: unknown): Promise<boolean> {
  if (isEnvBrowser()) {
    browserLog.push({ callback, data });

    return true;
  }

  try {
    const response = await fetch(`https://${resourceName()}/${callback}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    });
    const reply = (await response.json()) as { ok?: unknown };

    return reply.ok === true;
  } catch {
    return false;
  }
}

/** The page is mounted. Lua sends the config, then the scene. */
export function sendReady(): Promise<boolean> {
  return postNui(NuiCallback.Ready, {});
}

/** The pointer or the arrow keys moved to a slot. The camera follows. */
export function sendHover(index: number): Promise<boolean> {
  return postNui(NuiCallback.Hover, { index });
}

/** Play the slot's character. */
export function sendSelect(index: number): Promise<boolean> {
  return postNui(NuiCallback.Select, { index });
}

/** Shows a model on the new character's slot. */
export function sendModel(model: string): Promise<boolean> {
  return postNui(NuiCallback.Model, { model });
}

/** Creates the character. Lua and the server check every value. */
export function sendSubmit(fields: Record<string, string>, model: string): Promise<boolean> {
  return postNui(NuiCallback.Submit, { fields, model });
}

/** Leaves the creation screen. */
export function sendCancel(): Promise<boolean> {
  return postNui(NuiCallback.Cancel, {});
}

/** Deletes the slot's character, after the player typed its name. */
export function sendDelete(index: number): Promise<boolean> {
  return postNui(NuiCallback.Delete, { index });
}

/** The camera flies over a spawn place. */
export function sendSpawnHover(id: string): Promise<boolean> {
  return postNui(NuiCallback.SpawnHover, { id });
}

/** Spawn there. The server decides the final destination. */
export function sendSpawnChoose(id: string): Promise<boolean> {
  return postNui(NuiCallback.SpawnChoose, { id });
}

/** Skip the intro. */
export function sendSkip(): Promise<boolean> {
  return postNui(NuiCallback.Skip, {});
}
