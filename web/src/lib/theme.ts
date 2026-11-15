/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The owner's ug-lib theme, applied to this page too, so every UgCore screen looks the same. Same rules as ug-lib.

import type { ThemeConfig } from "@/types/protocol";

/** Theme tokens owners MAY override, mapped to their CSS variable. */
const THEME_TOKENS: Record<string, string> = {
  background: "--ug-background",
  foreground: "--ug-foreground",
  card: "--ug-card",
  cardForeground: "--ug-card-foreground",
  popover: "--ug-popover",
  popoverForeground: "--ug-popover-foreground",
  primary: "--ug-primary",
  primaryForeground: "--ug-primary-foreground",
  secondary: "--ug-secondary",
  secondaryForeground: "--ug-secondary-foreground",
  muted: "--ug-muted",
  mutedForeground: "--ug-muted-foreground",
  accent: "--ug-accent",
  accentForeground: "--ug-accent-foreground",
  destructive: "--ug-destructive",
  destructiveForeground: "--ug-destructive-foreground",
  success: "--ug-success",
  successForeground: "--ug-success-foreground",
  warning: "--ug-warning",
  warningForeground: "--ug-warning-foreground",
  border: "--ug-border",
  input: "--ug-input",
  ring: "--ug-ring",
};

/** Accent colors owners MAY recolor. Each one sets the 500 shade; the others follow from it. */
export const TONE_TOKENS = ["violet", "indigo", "blue", "sky", "emerald", "amber", "rose", "fuchsia", "teal"] as const;

/** The shades the page uses, from one HSL triplet: lighter for text and borders, darker for gradient ends. */
export function toneShades(base: string): Record<300 | 400 | 500 | 600, string> {
  const [hue, saturation, lightness] = base.split(" ").map((part) => parseFloat(part));
  const l = lightness ?? 50;
  const at = (value: number) => `${hue} ${saturation}% ${value}%`;

  return { 300: at(Math.min(l + 18, 88)), 400: at(Math.min(l + 8, 80)), 500: base, 600: at(Math.max(l - 8, 10)) };
}

const HSL_TRIPLET = /^\d+(\.\d+)? \d+(\.\d+)?% \d+(\.\d+)?%$/;
const SIZE = /^\d*\.?\d+(rem|px)$/;
const FONTS: Record<string, string> = {
  Inter: '"Inter Variable", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
};

/** Applies theme values to `<html>`. Lua checked them; they are checked again before reaching CSS. */
export function applyTheme(theme: ThemeConfig | undefined): void {
  const root = document.documentElement;

  root.classList.toggle("dark", theme?.mode !== "light");

  for (const [token, cssVar] of Object.entries(THEME_TOKENS)) {
    const value = theme?.colors?.[token];

    if (typeof value === "string" && HSL_TRIPLET.test(value)) {
      root.style.setProperty(cssVar, value);
    } else {
      root.style.removeProperty(cssVar);
    }
  }

  for (const tone of TONE_TOKENS) {
    const value = theme?.colors?.[tone];
    const shades = typeof value === "string" && HSL_TRIPLET.test(value) ? toneShades(value) : null;

    for (const shade of [300, 400, 500, 600] as const) {
      const name = `--ug-tone-${tone}-${shade}`;

      if (shades) {
        root.style.setProperty(name, shades[shade]);
      } else {
        root.style.removeProperty(name);
      }
    }
  }

  if (theme && SIZE.test(theme.radius)) {
    root.style.setProperty("--ug-radius", theme.radius);
  }

  const font = theme ? FONTS[theme.font] : undefined;

  if (font) {
    root.style.setProperty("--ug-font-sans", font);
  }

  const scale = theme && Number.isFinite(theme.scale) ? Math.min(Math.max(theme.scale, 0.75), 1.5) : 1;

  root.style.setProperty("--ug-scale", String(scale));
}
