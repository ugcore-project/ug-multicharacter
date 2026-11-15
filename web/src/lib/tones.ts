/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Accent colors that tell slots, details and spawn points apart. The brand gradient follows the ug-core logo:
// violet to indigo to blue. Class names are written out in full so Tailwind finds them.

export interface ToneClasses {
  /** Icon chip: tinted background and text. */
  chip: string;
  /** Text and icon color alone. */
  text: string;
  /** Border of a selected card. */
  border: string;
  /** Solid gradient fill, for avatars. */
  fill: string;
}

export const TONES = {
  violet: { chip: "bg-violet-500/15 text-violet-300", text: "text-violet-300", border: "border-violet-400", fill: "bg-gradient-to-br from-violet-400 to-violet-600" },
  sky: { chip: "bg-sky-500/15 text-sky-300", text: "text-sky-300", border: "border-sky-400", fill: "bg-gradient-to-br from-sky-400 to-sky-600" },
  emerald: { chip: "bg-emerald-500/15 text-emerald-300", text: "text-emerald-300", border: "border-emerald-400", fill: "bg-gradient-to-br from-emerald-400 to-emerald-600" },
  amber: { chip: "bg-amber-500/15 text-amber-300", text: "text-amber-300", border: "border-amber-400", fill: "bg-gradient-to-br from-amber-400 to-amber-600" },
  rose: { chip: "bg-rose-500/15 text-rose-300", text: "text-rose-300", border: "border-rose-400", fill: "bg-gradient-to-br from-rose-400 to-rose-600" },
  fuchsia: { chip: "bg-fuchsia-500/15 text-fuchsia-300", text: "text-fuchsia-300", border: "border-fuchsia-400", fill: "bg-gradient-to-br from-fuchsia-400 to-fuchsia-600" },
  teal: { chip: "bg-teal-500/15 text-teal-300", text: "text-teal-300", border: "border-teal-400", fill: "bg-gradient-to-br from-teal-400 to-teal-600" },
  indigo: { chip: "bg-indigo-500/15 text-indigo-300", text: "text-indigo-300", border: "border-indigo-400", fill: "bg-gradient-to-br from-indigo-400 to-indigo-600" },
} as const satisfies Record<string, ToneClasses>;

const ORDER: ToneClasses[] = [TONES.violet, TONES.sky, TONES.emerald, TONES.amber, TONES.rose, TONES.fuchsia, TONES.teal, TONES.indigo];

/** A color per position, so slots and list entries keep theirs. `index` is 1-based or 0-based, it only has to be stable. */
export function toneAt(index: number): ToneClasses {
  return ORDER[((index % ORDER.length) + ORDER.length) % ORDER.length] ?? TONES.violet;
}

/** The ug-core logo gradient. */
export const BRAND_BAR = "h-1 bg-gradient-to-r from-violet-500 via-indigo-500 to-blue-500";
export const BRAND_FILL = "bg-gradient-to-r from-violet-500 via-indigo-500 to-blue-500 text-white hover:brightness-110";
