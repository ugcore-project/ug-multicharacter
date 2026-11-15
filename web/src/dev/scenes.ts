/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Showcase scenes: what the page shows for the README. The preview plays them, and `npm run capture` saves each one
// to .github/assets/<id>.webp, animated when `animated` is set. Add a scene for every screen worth showing.

import { NuiAction, Screen, type NuiMessage } from "@/types/protocol";

/** One step: a message as Lua would send it, or a click on an element, then a pause. */
export interface SceneStep {
  send?: NuiMessage;
  /** CSS selector of the element to click. */
  click?: string;
  /** Milliseconds before the next step. */
  wait?: number;
}

export interface Scene {
  /** File name of the capture: lowercase, digits and dashes. */
  id: string;
  title: string;
  steps: SceneStep[];
  /** Captured as an animated image of the whole run, instead of a still of the end. */
  animated?: boolean;
  /** CSS selector of the element the capture is cropped to, with a margin. The whole screen when unset. */
  crop?: string;
}

/** A screen area in CSS pixels. */
export interface Area {
  x: number;
  y: number;
  width: number;
  height: number;
}

const SLOTS = [
  { character: { name: "Ana Silva", birthDate: "1995-04-12", lastPlayed: 1_791_400_000, street: "Vespucci Boulevard", deathState: "Alive" } },
  { character: { name: "João O'Neil-Costa", birthDate: "2000-02-29", lastPlayed: 1_790_000_000, street: "Route 68", deathState: "Downed" } },
  {},
  {},
];

/** The default form, as Lua sends it. */
export const FORM: NuiMessage = {
  action: NuiAction.Form,
  payload: {
    fields: [
      { name: "firstName", type: "text", label: "First name", min: 2, max: 24 },
      { name: "lastName", type: "text", label: "Last name", min: 2, max: 24 },
      { name: "birthDate", type: "date", label: "Birth date" },
      { name: "sex", type: "select", label: "Sex", options: [{ value: "male", label: "Male" }, { value: "female", label: "Female" }] },
    ],
    ageRange: { min: 18, max: 90 },
    models: ["mp_m_freemode_01", "mp_f_freemode_01"],
    allowDelete: true,
  },
};

const SELECT: SceneStep[] = [
  { send: { action: NuiAction.Open, payload: { slots: SLOTS } } },
  { send: { action: NuiAction.Screen, payload: { screen: Screen.Select } } },
  { send: { action: NuiAction.Visible, payload: { visible: true } }, wait: 1000 },
];

const SPAWNS: NuiMessage = {
  action: NuiAction.Spawns,
  payload: {
    options: [
      { id: "last", label: "Last location", street: "Vespucci Boulevard" },
      { id: "legion", label: "Legion Square" },
      { id: "sandy", label: "Sandy Shores" },
      { id: "paleto", label: "Paleto Bay" },
    ],
    focus: "last",
  },
};

export const SCENES: Scene[] = [
  { id: "character-selection", title: "Selection", steps: SELECT },
  {
    id: "character-create",
    title: "Creation form",
    steps: [
      { send: { action: NuiAction.Screen, payload: { screen: Screen.Create } } },
      { send: { action: NuiAction.Visible, payload: { visible: true } }, wait: 1000 },
    ],
  },
  {
    id: "spawn-picker",
    title: "Spawn picker",
    steps: [
      { send: SPAWNS },
      { send: { action: NuiAction.Screen, payload: { screen: Screen.Spawn } } },
      { send: { action: NuiAction.Visible, payload: { visible: true } }, wait: 1000 },
    ],
  },
  {
    id: "intro",
    title: "Intro and title card",
    animated: true,
    steps: [
      { send: { action: NuiAction.Open, payload: { slots: SLOTS } } },
      { send: { action: NuiAction.Screen, payload: { screen: Screen.Intro } } },
      { send: { action: NuiAction.Visible, payload: { visible: false } }, wait: 500 },
      { send: { action: NuiAction.Title, payload: { text: "Los Santos RP", visible: true } }, wait: 3200 },
      { send: { action: NuiAction.Title, payload: { text: "Los Santos RP", visible: false } }, wait: 1000 },
      ...SELECT,
      { wait: 600 },
    ],
  },
];


/**
 * Plays a scene through `send`. Resolves after the last step's pause, with the area the crop element covered after
 * any step, or null without a crop or when it never showed.
 */
export async function playScene(scene: Scene, send: (message: NuiMessage) => void): Promise<Area | null> {
  let area: Area | null = null;

  for (const step of scene.steps) {
    if (step.send) {
      send(step.send);
    }

    if (step.click) {
      document.querySelector<HTMLElement>(step.click)?.click();
    }

    await new Promise((resolve) => setTimeout(resolve, step.wait ?? 0));

    const box = scene.crop ? document.querySelector(scene.crop)?.getBoundingClientRect() : undefined;

    if (box && box.width > 0) {
      const left = Math.min(area?.x ?? box.left, box.left);
      const top = Math.min(area?.y ?? box.top, box.top);
      const right = Math.max(area ? area.x + area.width : box.right, box.right);
      const bottom = Math.max(area ? area.y + area.height : box.bottom, box.bottom);

      area = { x: left, y: top, width: right - left, height: bottom - top };
    }
  }

  return area;
}
