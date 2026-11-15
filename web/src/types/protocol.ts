/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Mirrors `UgMc.Enums.NuiAction`, `NuiCallback` and `Screen` in shared/enums.lua. tests/nui.lua checks both sides match.

/** Messages Lua sends: `{ action, payload }`. */
export const NuiAction = {
  Config: "config",
  Open: "open",
  Focus: "focus",
  Screen: "screen",
  Title: "title",
  Visible: "visible",
  Close: "close",
  Form: "form",
  Result: "result",
  Spawns: "spawns",
} as const;

export type NuiAction = (typeof NuiAction)[keyof typeof NuiAction];

/** Callbacks the page posts. Lua checks every body. */
export const NuiCallback = {
  Ready: "ready",
  Hover: "hover",
  Select: "select",
  Skip: "skip",
  Model: "model",
  Submit: "submit",
  Cancel: "cancel",
  Delete: "delete",
  SpawnHover: "spawnHover",
  SpawnChoose: "spawnChoose",
} as const;

export type NuiCallback = (typeof NuiCallback)[keyof typeof NuiCallback];

/** What the page shows. */
export const Screen = {
  Intro: "intro",
  Select: "select",
  Create: "create",
  Spawn: "spawn",
  Busy: "busy",
} as const;

export type Screen = (typeof Screen)[keyof typeof Screen];

export const DeathState = {
  Alive: "Alive",
  Downed: "Downed",
  Dead: "Dead",
} as const;

export type DeathState = (typeof DeathState)[keyof typeof DeathState];

/** One slot of the lineup, as Lua builds it. Lua sends only what the card shows. */
export interface SlotView {
  index: number;
  character?: {
    name: string;
    birthDate?: string;
    /** Unix seconds. */
    lastPlayed?: number;
    street?: string;
    deathState: DeathState;
  };
}

export const FieldType = {
  Text: "text",
  Date: "date",
  Select: "select",
} as const;

export type FieldType = (typeof FieldType)[keyof typeof FieldType];

/** A creation field from the owner's config. The server checks the same rules again. */
export interface FormField {
  name: string;
  type: FieldType;
  label: string;
  min?: number;
  max?: number;
  options?: { value: string; label: string }[];
}

export interface FormConfig {
  fields: FormField[];
  ageRange: { min: number; max: number };
  models: string[];
  allowDelete: boolean;
}

export const ResultKind = {
  Create: "create",
  Delete: "delete",
} as const;

export type ResultKind = (typeof ResultKind)[keyof typeof ResultKind];

/** The outcome of a create or a delete. */
export interface ActionResult {
  kind: ResultKind;
  ok: boolean;
  error?: string;
}

/** A place the chosen character MAY spawn. Lua sends ids and labels only, never coordinates. */
export interface SpawnOption {
  id: string;
  label: string;
  /** The street of the last location. */
  street?: string;
}

export const Side = {
  Left: "left",
  Right: "right",
} as const;

export type Side = (typeof Side)[keyof typeof Side];

export const Place = {
  Top: "top",
  Bottom: "bottom",
} as const;

export type Place = (typeof Place)[keyof typeof Place];

export const Detail = {
  Born: "born",
  LastPlayed: "lastPlayed",
  Location: "location",
} as const;

export type Detail = (typeof Detail)[keyof typeof Detail];

/** The owner's selection screen, from config.lua `layout`. */
export interface PanelLayout {
  side: Side;
  slots: Place;
  hint: boolean;
  initials: boolean;
  keyboard: boolean;
  animations: boolean;
}

export interface ThemeConfig {
  mode: string;
  colors: Record<string, string>;
  radius: string;
  font: string;
  scale: number;
}

export interface PageConfig {
  theme?: ThemeConfig;
  labels: Record<string, string>;
  locale: string;
  layout: PanelLayout;
  details: Detail[];
  /** The intro MAY be skipped. */
  skippable: boolean;
}

export interface NuiMessage {
  action: NuiAction;
  payload?: unknown;
}
