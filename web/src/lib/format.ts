/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

/** Fills `{name}` placeholders. Unknown ones stay as they are. */
export function fill(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (match, key: string) => (key in values ? String(values[key]) : match));
}

/** A `YYYY-MM-DD` date in the player's language, read as a calendar day. */
export function formatBirthDate(value: string, locale: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);

  if (!match) {
    return value;
  }

  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));

  return safeFormat(date, locale, { dateStyle: "long", timeZone: "UTC" });
}

/** Unix seconds as a short date. */
export function formatPlayed(seconds: number, locale: string): string {
  return safeFormat(new Date(seconds * 1000), locale, { dateStyle: "medium" });
}

function safeFormat(date: Date, locale: string, options: Intl.DateTimeFormatOptions): string {
  try {
    return new Intl.DateTimeFormat(locale, options).format(date);
  } catch {
    return new Intl.DateTimeFormat("en", options).format(date);
  }
}

/** Up to two initials for a card. */
export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
}

/** The label key for an error code from the server. */
export function resultLabel(error: string | undefined): string {
  switch (error) {
    case "invalid_args":
      return "resultInvalid";
    case "no_permission":
      return "resultDenied";
    case "rate_limited":
      return "resultWait";
    default:
      return "resultFailed";
  }
}
