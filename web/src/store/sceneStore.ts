/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { create } from "zustand";
import { applyTheme } from "@/lib/theme";
import {
  DeathState,
  Detail,
  Place,
  Side,
  type PanelLayout,
  FieldType,
  NuiAction,
  ResultKind,
  Screen,
  type ActionResult,
  type FormConfig,
  type FormField,
  type NuiMessage,
  type PageConfig,
  type SlotView,
  type SpawnOption,
} from "@/types/protocol";

interface SceneState {
  config: PageConfig;
  slots: SlotView[];
  focus: number;
  screen: Screen | null;
  title: { text: string; visible: boolean };
  /** The UI follows the world fades. */
  visible: boolean;
  form: FormConfig;
  /** The last create or delete outcome, until the next action. */
  result: ActionResult | null;
  /** A dialog holds the keyboard: the selection ignores keys. */
  dialogOpen: boolean;
  spawns: SpawnOption[];
  spawnFocus: string | null;
  setFocus: (index: number) => void;
}

/** English labels until Lua sends the configured language. */
export const DEFAULT_LABELS: Record<string, string> = {
  play: "Play",
  create: "Create character",
  empty: "Empty slot",
  born: "Born",
  lastPlayed: "Last played",
  location: "Last location",
  never: "Never",
  downed: "Downed",
  dead: "Dead",
  skip: "Press Enter to skip",
  slot: "Slot {index} of {count}",
  hint: "← → to choose · Enter to play",
  createTitle: "New character",
  back: "Back",
  submit: "Create",
  model: "Body",
  modelMale: "Male",
  modelFemale: "Female",
  delete: "Delete",
  deleteTitle: "Delete {name}?",
  deleteHint: "Type {name} to confirm. This cannot be undone.",
  cancel: "Cancel",
  errorRequired: "Required",
  errorLength: "{min} to {max} characters",
  errorSymbols: "Letters only, no digits or symbols",
  errorSpaces: "No extra spaces",
  errorDate: "Use a real date",
  errorAge: "Age {min} to {max}",
  errorOption: "Pick one",
  resultInvalid: "Some details were not accepted.",
  resultDenied: "This is not allowed.",
  resultWait: "Wait a moment and try again.",
  resultFailed: "Something went wrong. Try again.",
  spawnTitle: "Where to?",
  spawnHint: "↑ ↓ to choose · Enter to go",
  spawnGo: "Spawn here",
  lastLocation: "Last location",
  firstLocation: "Arrival point",
};

export const DEFAULT_LAYOUT: PanelLayout = {
  side: Side.Left,
  slots: Place.Bottom,
  hint: true,
  initials: true,
  keyboard: true,
  animations: true,
};

const DEFAULT_DETAILS: Detail[] = [Detail.Born, Detail.LastPlayed, Detail.Location];

/** The owner layout, field by field. Lua checked it; anything off falls back to the default. */
export function readLayout(value: unknown): PanelLayout {
  const raw = typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
  const flag = (key: keyof PanelLayout) => (typeof raw[key] === "boolean" ? (raw[key] as boolean) : (DEFAULT_LAYOUT[key] as boolean));
  const sides: readonly unknown[] = Object.values(Side);
  const places: readonly unknown[] = Object.values(Place);

  return {
    side: sides.includes(raw.side) ? (raw.side as Side) : DEFAULT_LAYOUT.side,
    slots: places.includes(raw.slots) ? (raw.slots as Place) : DEFAULT_LAYOUT.slots,
    hint: flag("hint"),
    initials: flag("initials"),
    keyboard: flag("keyboard"),
    animations: flag("animations"),
  };
}

/** The details in the owner's order, without unknown or repeated ones. Not a list means the default ones. */
export function readDetails(value: unknown): Detail[] {
  if (!Array.isArray(value)) {
    return DEFAULT_DETAILS;
  }

  const known: readonly unknown[] = Object.values(Detail);

  return [...new Set(value.filter((entry): entry is Detail => known.includes(entry)))];
}

/** The page config until Lua sends its own. */
export const DEFAULT_CONFIG: PageConfig = { labels: DEFAULT_LABELS, locale: "en", layout: DEFAULT_LAYOUT, details: DEFAULT_DETAILS, skippable: true };

const EMPTY_FORM: FormConfig = { fields: [], ageRange: { min: 18, max: 90 }, models: [], allowDelete: false };

const MAX_SLOTS = 32;
const MAX_TEXT = 128;

export const useSceneStore = create<SceneState>((set) => ({
  config: DEFAULT_CONFIG,
  slots: [],
  focus: 1,
  screen: null,
  title: { text: "", visible: false },
  visible: false,
  form: EMPTY_FORM,
  result: null,
  dialogOpen: false,
  spawns: [],
  spawnFocus: null,
  setFocus: (index) => set({ focus: index }),
}));

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value.slice(0, MAX_TEXT) : undefined;
}

/** Rebuilds slots from known fields only. */
export function readSlots(value: unknown): SlotView[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.slice(0, MAX_SLOTS).map((entry: unknown, position) => {
    const slot: SlotView = { index: position + 1 };
    const character = isRecord(entry) && isRecord(entry.character) ? entry.character : undefined;
    const name = character && text(character.name);

    if (character && name) {
      const deathState = Object.values(DeathState).find((state) => state === character.deathState) ?? DeathState.Alive;
      const birthDate = text(character.birthDate);
      const street = text(character.street);
      const lastPlayed = typeof character.lastPlayed === "number" && Number.isFinite(character.lastPlayed) ? character.lastPlayed : undefined;

      slot.character = {
        name,
        deathState,
        ...(birthDate ? { birthDate } : {}),
        ...(street ? { street } : {}),
        ...(lastPlayed !== undefined ? { lastPlayed } : {}),
      };
    }

    return slot;
  });
}

function count(value: unknown, min: number, max: number): number | undefined {
  return typeof value === "number" && Number.isInteger(value) && value >= min && value <= max ? value : undefined;
}

/** Rebuilds the form config from known fields only. */
export function readForm(value: unknown): FormConfig {
  if (!isRecord(value)) {
    return EMPTY_FORM;
  }

  const fields: FormField[] = [];

  for (const entry of Array.isArray(value.fields) ? value.fields.slice(0, 12) : []) {
    const type = isRecord(entry) ? Object.values(FieldType).find((kind) => kind === entry.type) : undefined;
    const name = isRecord(entry) ? text(entry.name) : undefined;
    const label = isRecord(entry) ? text(entry.label) : undefined;

    if (!isRecord(entry) || !type || !name || !label) {
      continue;
    }

    const field: FormField = { name, type, label };
    const min = count(entry.min, 0, 64);
    const max = count(entry.max, 1, 64);

    if (min !== undefined) {
      field.min = min;
    }

    if (max !== undefined) {
      field.max = max;
    }

    if (Array.isArray(entry.options)) {
      field.options = entry.options.slice(0, 50).flatMap((option: unknown) => {
        const optionValue = isRecord(option) ? text(option.value) : undefined;
        const optionLabel = isRecord(option) ? text(option.label) : undefined;

        return optionValue && optionLabel ? [{ value: optionValue, label: optionLabel }] : [];
      });
    }

    fields.push(field);
  }

  const range = isRecord(value.ageRange) ? value.ageRange : {};
  const models = Array.isArray(value.models) ? value.models.slice(0, 20).flatMap((model: unknown) => (text(model) ? [text(model) as string] : [])) : [];

  return {
    fields,
    ageRange: { min: count(range.min, 0, 150) ?? EMPTY_FORM.ageRange.min, max: count(range.max, 0, 150) ?? EMPTY_FORM.ageRange.max },
    models,
    allowDelete: value.allowDelete === true,
  };
}

/** Rebuilds spawn options from known fields only. */
export function readSpawns(value: unknown): SpawnOption[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.slice(0, 51).flatMap((entry: unknown) => {
    const id = isRecord(entry) ? text(entry.id) : undefined;
    const label = isRecord(entry) ? text(entry.label) : undefined;
    const street = isRecord(entry) ? text(entry.street) : undefined;

    return id && label ? [{ id, label, ...(street ? { street } : {}) }] : [];
  });
}

function readLabels(value: unknown): Record<string, string> {
  const labels = { ...DEFAULT_LABELS };

  if (isRecord(value)) {
    for (const key of Object.keys(DEFAULT_LABELS)) {
      const label = text(value[key]);

      if (label) {
        labels[key] = label;
      }
    }
  }

  return labels;
}

/** Applies one message from Lua. Unknown actions and malformed payloads are ignored. */
export function handleMessage(message: unknown): void {
  if (!isRecord(message) || typeof message.action !== "string") {
    return;
  }

  const { action, payload } = message as unknown as NuiMessage;
  const data = isRecord(payload) ? payload : {};

  switch (action) {
    case NuiAction.Config: {
      const theme = isRecord(data.theme) ? (data.theme as unknown as PageConfig["theme"]) : undefined;

      applyTheme(theme);
      useSceneStore.setState({
        config: {
          labels: readLabels(data.labels),
          locale: text(data.locale) ?? "en",
          ...(theme ? { theme } : {}),
          layout: readLayout(data.layout),
          details: readDetails(data.details),
          skippable: data.skippable !== false,
        },
      });
      break;
    }
    case NuiAction.Open: {
      const slots = readSlots(data.slots);

      useSceneStore.setState({ slots, focus: 1 });
      break;
    }
    case NuiAction.Focus: {
      const { slots } = useSceneStore.getState();

      if (typeof data.index === "number" && Number.isInteger(data.index) && data.index >= 1 && data.index <= slots.length) {
        useSceneStore.setState({ focus: data.index });
      }

      break;
    }
    case NuiAction.Screen: {
      const screen = Object.values(Screen).find((value) => value === data.screen);

      useSceneStore.setState({ screen: screen ?? null, result: null });
      break;
    }
    case NuiAction.Title:
      useSceneStore.setState({ title: { text: text(data.text) ?? "", visible: data.visible === true } });
      break;
    case NuiAction.Visible:
      useSceneStore.setState({ visible: data.visible === true });
      break;
    case NuiAction.Spawns: {
      const spawns = readSpawns(data.options);
      const focus = text(data.focus);

      useSceneStore.setState({ spawns, spawnFocus: spawns.some((option) => option.id === focus) ? (focus ?? null) : (spawns[0]?.id ?? null) });
      break;
    }
    case NuiAction.Form:
      useSceneStore.setState({ form: readForm(data) });
      break;
    case NuiAction.Result:
      const kind = Object.values(ResultKind).find((value) => value === data.kind);

      if (kind && typeof data.ok === "boolean") {
        const error = text(data.error);

        useSceneStore.setState({ result: { kind, ok: data.ok, ...(error ? { error } : {}) } });
      }

      break;
    case NuiAction.Close:
      useSceneStore.setState({ slots: [], screen: null, visible: false, title: { text: "", visible: false }, result: null, dialogOpen: false });
      break;
  }
}

/** Listens to messages from Lua. Returns the remover. */
export function installMessages(): () => void {
  const listener = (event: MessageEvent) => handleMessage(event.data);

  window.addEventListener("message", listener);

  return () => window.removeEventListener("message", listener);
}
